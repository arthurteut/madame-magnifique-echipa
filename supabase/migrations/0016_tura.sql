-- =============================================================================
-- Ghidul echipei Madame Magnifique · Tura: program, clock-in cu QR, fișe bifate, notificări
--
-- Se rulează după 0015, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
--   role_parents          organigrama: cine e deasupra cui (notificările urcă pe toată linia)
--   space_hours           orele magazinelor (termenul fișei de deschidere / închidere)
--   space_qr              codul QR al fiecărei locații (îl vede doar adminul, îl printează din Admin)
--   shifts                programul pe ture: cine, unde, când, cine deschide / închide
--   clockings             pontajul: clock-in / clock-out, doar prin QR (funcțiile pontaj_*)
--   checklist_runs        o fișă bifată într-o zi, la o locație (comună echipei de acolo)
--   checklist_marks       pașii bifați: făcut / nefăcut, valoare, notă, cine și când
--   notifications         notificările din aplicație; fiecare pleacă și ca push pe telefon
--   push_subscriptions    telefoanele pe care s-au activat notificările
--   push_config           cheile push și secretul funcției trimite-push (doar service_role)
--
-- Verificările de la 5 minute (mementouri, întârzieri) rulează cu pg_cron; push-ul pleacă
-- prin pg_net către funcția trimite-push. Ambele extensii se activează mai jos.
-- =============================================================================

do $$ begin
  create extension if not exists pg_net;
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_net / pg_cron nu sunt disponibile aici: %', sqlerrm;   -- în Supabase există amândouă
end $$;

-- ---------------------------------------------------------------------------
-- Organigrama
-- ---------------------------------------------------------------------------
create table if not exists public.role_parents (
  role_code   text primary key references public.roles (code) on update cascade on delete cascade,
  parent_code text not null references public.roles (code) on update cascade on delete cascade,
  check (role_code <> parent_code)
);
insert into public.role_parents (role_code, parent_code)
select r, p from (values
  ('V', 'VT'), ('BAR', 'VT'), ('PP + B', 'VT'), ('VT', 'RL'), ('RL', 'GM'),
  ('PBR', 'PBP'), ('PPT', 'PBP'), ('PCF', 'PBP'), ('BRT', 'PBP'), ('GD', 'PBP'),
  ('PBP', 'SP'), ('SP', 'DP'), ('DP', 'GM')
) v (r, p)
where exists (select 1 from public.roles where code = r) and exists (select 1 from public.roles where code = p)
on conflict (role_code) do nothing;
alter table public.role_parents enable row level security;
revoke all on public.role_parents from anon, authenticated;
grant select on public.role_parents to authenticated;
grant all on public.role_parents to service_role;
drop policy if exists "organigrama o vede echipa" on public.role_parents;
create policy "organigrama o vede echipa" on public.role_parents for select to authenticated using (public.is_member());
drop policy if exists "adminul schimbă organigrama" on public.role_parents;
create policy "adminul schimbă organigrama" on public.role_parents for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Toți cei de deasupra unui rol (șeful, șeful șefului …).
create or replace function public.sefii(r text)
returns setof text language sql stable security definer set search_path = public as $$
  with recursive sus (cod, adancime) as (
    select parent_code, 1 from public.role_parents where role_code = r
    union
    select p.parent_code, s.adancime + 1 from public.role_parents p join sus s on p.role_code = s.cod where s.adancime < 10
  ) select distinct cod from sus
$$;
-- Toate rolurile de sub un rol.
create or replace function public.subordonatii(r text)
returns setof text language sql stable security definer set search_path = public as $$
  with recursive jos (cod, adancime) as (
    select role_code, 1 from public.role_parents where parent_code = r
    union
    select p.role_code, j.adancime + 1 from public.role_parents p join jos j on p.parent_code = j.cod where j.adancime < 10
  ) select distinct cod from jos
$$;
-- Poate planifica / urmări omul ăsta: adminul și cei de deasupra rolului lui.
create or replace function public.poate_conduce(u uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.is_admin() or exists (
    select 1 from public.profiles p where p.user_id = u and p.role_code in (select public.subordonatii(public.my_role()))))
$$;
-- Vede panoul „Echipa azi”: cine are subordonați, adminul și cine vede tot (AE).
create or replace function public.vede_echipa()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.sees_all() or exists (select 1 from public.subordonatii(public.my_role())))
$$;
revoke all on function public.sefii(text), public.subordonatii(text), public.poate_conduce(uuid), public.vede_echipa() from public, anon;
grant execute on function public.sefii(text), public.subordonatii(text), public.poate_conduce(uuid), public.vede_echipa() to authenticated;

-- Oamenii pe care îi văd în program și în panou (profilurile nu sunt publice în echipă).
create or replace function public.echipa_mea()
returns table (user_id uuid, full_name text, role_code text, active boolean)
language sql stable security definer set search_path = public as $$
  select p.user_id, p.full_name, p.role_code, p.active from public.profiles p
  where public.is_member() and (p.user_id = auth.uid() or public.sees_all()
     or p.role_code in (select public.subordonatii(public.my_role())))
  order by p.full_name
$$;
revoke all on function public.echipa_mea() from public, anon;
grant execute on function public.echipa_mea() to authenticated;

-- ---------------------------------------------------------------------------
-- Orele magazinelor (1 = luni … 7 = duminică; fără rând = închis)
-- ---------------------------------------------------------------------------
create table if not exists public.space_hours (
  space_id text not null references public.spaces (id) on delete cascade,
  weekday  int not null check (weekday between 1 and 7),
  opens    time not null,
  closes   time not null,
  primary key (space_id, weekday)
);
insert into public.space_hours (space_id, weekday, opens, closes)
select s, d, o::time, c::time from (values
  ('porumbescu', '08:00', '19:30', '09:00', '16:00'),
  ('dumbravita', '08:30', '20:00', '09:00', '18:00'),
  ('fructus',    '08:30', '20:00', '09:00', '17:00')
) v (s, o_lv, c_lv, o_s, c_s)
cross join lateral (values (1, o_lv, c_lv), (2, o_lv, c_lv), (3, o_lv, c_lv), (4, o_lv, c_lv), (5, o_lv, c_lv), (6, o_s, c_s)) z (d, o, c)
where exists (select 1 from public.spaces where id = s)
on conflict do nothing;
alter table public.space_hours enable row level security;
revoke all on public.space_hours from anon, authenticated;
grant select on public.space_hours to authenticated;
grant all on public.space_hours to service_role;
drop policy if exists "orele le vede echipa" on public.space_hours;
create policy "orele le vede echipa" on public.space_hours for select to authenticated using (public.is_member());
drop policy if exists "adminul schimbă orele" on public.space_hours;
create policy "adminul schimbă orele" on public.space_hours for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- Codurile QR ale locațiilor
-- ---------------------------------------------------------------------------
create table if not exists public.space_qr (
  space_id text primary key references public.spaces (id) on delete cascade,
  token    text not null default replace(gen_random_uuid()::text, '-', ''),
  updated_at timestamptz not null default now()
);
insert into public.space_qr (space_id) select id from public.spaces where type in ('magazin', 'productie')
on conflict do nothing;
alter table public.space_qr enable row level security;
revoke all on public.space_qr from anon, authenticated;
grant select, update on public.space_qr to authenticated;
grant all on public.space_qr to service_role;
drop policy if exists "doar adminul vede codurile" on public.space_qr;
create policy "doar adminul vede codurile" on public.space_qr for select to authenticated using (public.is_admin());
drop policy if exists "doar adminul schimbă codurile" on public.space_qr;
create policy "doar adminul schimbă codurile" on public.space_qr for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- Programul pe ture
-- ---------------------------------------------------------------------------
create table if not exists public.shifts (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (user_id) on delete cascade,
  space_id   text not null references public.spaces (id) on delete cascade,
  day        date not null,
  starts     time not null,
  ends       time not null,                          -- dacă e ≤ starts, tura se termină a doua zi
  opens      boolean not null default false,         -- deschide locația / departamentul
  closes     boolean not null default false,         -- închide
  note       text not null default '',
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists shifts_zi on public.shifts (day, space_id);
create index if not exists shifts_om on public.shifts (user_id, day);

-- Începutul și sfârșitul turei, ca momente (ora României).
create or replace function public.tura_start(s public.shifts)
returns timestamptz language sql stable as $$ select (s.day + s.starts) at time zone 'Europe/Bucharest' $$;
create or replace function public.tura_sfarsit(s public.shifts)
returns timestamptz language sql stable as $$
  select (s.day + s.ends + case when s.ends <= s.starts then interval '1 day' else interval '0' end) at time zone 'Europe/Bucharest' $$;

-- Am și eu tură la locația asta în ziua asta? (security definer: fără recursivitate în politica de mai jos)
create or replace function public.am_tura(s text, d date)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.shifts where user_id = auth.uid() and space_id = s and day = d)
$$;
revoke all on function public.am_tura(text, date) from public, anon;
grant execute on function public.am_tura(text, date) to authenticated;

alter table public.shifts enable row level security;
revoke all on public.shifts from anon, authenticated;
grant select, insert, update, delete on public.shifts to authenticated;
grant all on public.shifts to service_role;
drop policy if exists "îmi văd turele, șefii le văd pe ale echipei" on public.shifts;
create policy "îmi văd turele, șefii le văd pe ale echipei" on public.shifts for select to authenticated
  using (public.is_member() and (user_id = auth.uid() or public.sees_all() or public.poate_conduce(user_id)
    -- colegii de la aceeași locație, în aceeași zi (cine mai e în tură)
    or public.am_tura(space_id, day)));
drop policy if exists "șefii fac programul" on public.shifts;
create policy "șefii fac programul" on public.shifts for all to authenticated
  using (public.poate_conduce(user_id) and (public.is_admin() or public.can_see_space(space_id)))
  with check (public.poate_conduce(user_id) and (public.is_admin() or public.can_see_space(space_id)));

-- ---------------------------------------------------------------------------
-- Pontajul
-- ---------------------------------------------------------------------------
create table if not exists public.clockings (
  id        bigint generated always as identity primary key,
  user_id   uuid not null references public.profiles (user_id) on delete cascade,
  space_id  text not null references public.spaces (id) on delete cascade,
  shift_id  bigint references public.shifts (id) on delete set null,
  clock_in  timestamptz not null default now(),
  clock_out timestamptz
);
create index if not exists clockings_om on public.clockings (user_id, clock_in desc);
create index if not exists clockings_loc on public.clockings (space_id, clock_in desc);
-- Sunt în tură la locația asta (clock-in făcut, fără clock-out)?
create or replace function public.in_tura(s text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clockings where user_id = auth.uid() and space_id = s and clock_out is null)
$$;
revoke all on function public.in_tura(text) from public, anon;
grant execute on function public.in_tura(text) to authenticated;
alter table public.clockings enable row level security;
revoke all on public.clockings from anon, authenticated;
grant select on public.clockings to authenticated;
grant all on public.clockings to service_role;
drop policy if exists "pontajul: al meu, al echipei pentru șefi" on public.clockings;
create policy "pontajul: al meu, al echipei pentru șefi" on public.clockings for select to authenticated
  using (public.is_member() and (user_id = auth.uid() or public.sees_all() or public.poate_conduce(user_id)
    or public.in_tura(space_id)));


-- ---------------------------------------------------------------------------
-- Fișele bifate
-- ---------------------------------------------------------------------------
create table if not exists public.checklist_runs (
  id          bigint generated always as identity primary key,
  cheie       text not null,                         -- „doc:123” (o fișă) sau „taskuri:V” (task-urile zilei ale rolului)
  doc_id      bigint references public.procedure_docs (id) on delete set null,
  title       text not null,
  space_id    text not null references public.spaces (id) on delete cascade,
  day         date not null default (now() at time zone 'Europe/Bucharest')::date,
  steps       jsonb not null check (jsonb_typeof(steps) = 'array'),   -- [{"t": "…", "sec": "…", "tip": "pas|valoare|dans"}]
  due_at      timestamptz,
  started_by  uuid default auth.uid(),
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  finished_by uuid,
  note        text not null default '',
  unique (space_id, day, cheie)
);
create table if not exists public.checklist_marks (
  run_id bigint not null references public.checklist_runs (id) on delete cascade,
  idx    int not null,
  status text not null check (status in ('facut', 'nefacut')),
  value  text not null default '',
  note   text not null default '',
  marked_by uuid default auth.uid(),
  at     timestamptz not null default now(),
  primary key (run_id, idx)
);
alter table public.checklist_runs enable row level security;
alter table public.checklist_marks enable row level security;
revoke all on public.checklist_runs, public.checklist_marks from anon, authenticated;
grant select, insert, update on public.checklist_runs to authenticated;
grant select, insert, update, delete on public.checklist_marks to authenticated;
grant all on public.checklist_runs, public.checklist_marks to service_role;
drop policy if exists "fișele: echipa locației și șefii" on public.checklist_runs;
create policy "fișele: echipa locației și șefii" on public.checklist_runs for select to authenticated
  using (public.is_member() and (public.can_see_space(space_id) or public.sees_all()));
drop policy if exists "fișa o pornește cine e în tură" on public.checklist_runs;
create policy "fișa o pornește cine e în tură" on public.checklist_runs for insert to authenticated
  with check (public.in_tura(space_id));
drop policy if exists "observațiile le scrie cine e în tură" on public.checklist_runs;
create policy "observațiile le scrie cine e în tură" on public.checklist_runs for update to authenticated
  using (public.in_tura(space_id)) with check (public.in_tura(space_id));
drop policy if exists "pașii: echipa locației și șefii" on public.checklist_marks;
create policy "pașii: echipa locației și șefii" on public.checklist_marks for select to authenticated
  using (exists (select 1 from public.checklist_runs r where r.id = run_id
                 and public.is_member() and (public.can_see_space(r.space_id) or public.sees_all())));
drop policy if exists "pașii îi bifează cine e în tură" on public.checklist_marks;
create policy "pașii îi bifează cine e în tură" on public.checklist_marks for all to authenticated
  using (exists (select 1 from public.checklist_runs r where r.id = run_id and public.in_tura(r.space_id) and r.finished_at is null))
  with check (exists (select 1 from public.checklist_runs r where r.id = run_id and public.in_tura(r.space_id) and r.finished_at is null)
              and marked_by = auth.uid());

-- Cine a pornit fișa și când se termină nu se schimbă din pagină.
create or replace function public.fisa_protejata()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and current_user = 'authenticated' then
    new.cheie := old.cheie; new.doc_id := old.doc_id; new.title := old.title; new.space_id := old.space_id;
    new.day := old.day; new.steps := old.steps; new.due_at := old.due_at; new.started_by := old.started_by;
    new.started_at := old.started_at; new.finished_at := old.finished_at; new.finished_by := old.finished_by;
  end if;
  return new;
end $$;
drop trigger if exists fisa_protejata on public.checklist_runs;
create trigger fisa_protejata before update on public.checklist_runs for each row execute function public.fisa_protejata();

-- ---------------------------------------------------------------------------
-- Notificări
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (user_id) on delete cascade,
  kind       text not null,                          -- memento, clock_in, clock_out, fisa_gata, pas_nefacut, problema, intarziere
  title      text not null,
  body       text not null default '',
  url        text not null default '',
  space_id   text references public.spaces (id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists notifications_om on public.notifications (user_id, created_at desc);
alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;
grant select, update (read_at) on public.notifications to authenticated;
grant all on public.notifications to service_role;
drop policy if exists "notificările mele" on public.notifications;
create policy "notificările mele" on public.notifications for select to authenticated using (user_id = auth.uid());
drop policy if exists "le marchez citite" on public.notifications;
create policy "le marchez citite" on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.push_subscriptions (
  endpoint   text primary key,
  user_id    uuid not null default auth.uid() references public.profiles (user_id) on delete cascade,
  p256dh     text not null,
  auth       text not null,
  user_agent text not null default '',
  created_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon, authenticated;
grant select, insert, update, delete on public.push_subscriptions to authenticated;
grant all on public.push_subscriptions to service_role;
drop policy if exists "telefoanele mele" on public.push_subscriptions;
create policy "telefoanele mele" on public.push_subscriptions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_member());

-- Cheile push și adresa funcției. Fără politici: o citesc doar funcțiile de mai jos și service_role.
create table if not exists public.push_config (
  id            int primary key default 1 check (id = 1),
  function_url  text not null default '',
  anon_key      text not null default '',
  secret        text not null default replace(gen_random_uuid()::text, '-', ''),
  vapid_public  text not null default '',
  vapid_private text not null default ''
);
insert into public.push_config (id) values (1) on conflict do nothing;
alter table public.push_config enable row level security;
revoke all on public.push_config from anon, authenticated;
grant all on public.push_config to service_role;

create or replace function public.push_cheie_publica()
returns text language sql stable security definer set search_path = public as $$
  select nullif(vapid_public, '') from public.push_config where id = 1 and public.is_member()
$$;
revoke all on function public.push_cheie_publica() from public, anon;
grant execute on function public.push_cheie_publica() to authenticated;

-- Fiecare notificare nouă pleacă și ca push (dacă funcția e configurată și pg_net există).
create or replace function public.trimite_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare c public.push_config;
begin
  select * into c from public.push_config where id = 1;
  if c.function_url = '' or c.vapid_private = '' then return new; end if;
  begin
    perform net.http_post(
      url := c.function_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || c.anon_key, 'x-push-secret', c.secret),
      body := jsonb_build_object('id', new.id));
  exception when others then
    raise warning 'push: %', sqlerrm;                -- notificarea rămâne în aplicație chiar dacă push-ul nu pleacă
  end;
  return new;
end $$;
drop trigger if exists trimite_push on public.notifications;
create trigger trimite_push after insert on public.notifications for each row execute function public.trimite_push();

-- O notificare pentru toți cei de deasupra omului, care văd locația (GM, ca admin, vede tot).
create or replace function public.notifica_sefii(p_user uuid, p_space text, p_kind text, p_title text, p_body text, p_url text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.notifications (user_id, kind, title, body, url, space_id)
  select p.user_id, p_kind, p_title, p_body, p_url, p_space
  from public.profiles p join public.roles r on r.code = p.role_code
  where p.active and p.user_id <> p_user
    and p.role_code in (select public.sefii((select role_code from public.profiles where user_id = p_user)))
    and (r.is_admin or p_space is null
         or exists (select 1 from public.role_space_access a where a.role_code = p.role_code and a.space_id = p_space));
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.notifica_sefii(uuid, text, text, text, text, text) from public, anon, authenticated;

create or replace function public.nume_om(u uuid)
returns text language sql stable security definer set search_path = public as $$
  select full_name || ' (' || role_code || ')' from public.profiles where user_id = u
$$;
revoke all on function public.nume_om(uuid) from public, anon, authenticated;
create or replace function public.nume_loc(s text)
returns text language sql stable security definer set search_path = public as $$
  select case when type = 'magazin' then name else title end from public.spaces where id = s
$$;
revoke all on function public.nume_loc(text) from public, anon, authenticated;
create or replace function public.ora(t timestamptz)
returns text language sql stable as $$ select to_char(t at time zone 'Europe/Bucharest', 'HH24:MI') $$;

-- ---------------------------------------------------------------------------
-- Clock-in / clock-out (doar cu codul QR al locației)
-- ---------------------------------------------------------------------------
create or replace function public.pontaj_intrare(p_space text, p_token text)
returns public.clockings language plpgsql security definer set search_path = public as $$
declare c public.clockings; t public.shifts; deschis public.clockings;
begin
  if not public.is_member() then raise exception 'Contul nu e activ.'; end if;
  if not exists (select 1 from public.space_qr where space_id = p_space and token = p_token) then
    raise exception 'Codul QR nu e valid pentru locația asta. Scanează codul de la intrare.';
  end if;
  select * into deschis from public.clockings where user_id = auth.uid() and clock_out is null order by clock_in desc limit 1;
  if found then
    if deschis.space_id = p_space then return deschis; end if;
    raise exception 'Ai tura deschisă la %. Fă întâi clock-out acolo.', public.nume_loc(deschis.space_id);
  end if;
  -- tura din program cea mai apropiată de acum (azi sau o tură de noapte începută ieri)
  select * into t from public.shifts s
   where s.user_id = auth.uid() and s.space_id = p_space and s.day between current_date - 1 and current_date + 1
     and now() between public.tura_start(s) - interval '3 hours' and public.tura_sfarsit(s)
   order by abs(extract(epoch from now() - public.tura_start(s))) limit 1;
  insert into public.clockings (user_id, space_id, shift_id) values (auth.uid(), p_space, t.id) returning * into c;
  perform public.notifica_sefii(auth.uid(), p_space, 'clock_in',
    public.nume_loc(p_space) || ': ' || public.nume_om(auth.uid()) || ' a început tura',
    'Clock-in la ' || public.ora(c.clock_in) || coalesce(' · programat(ă) la ' || to_char(t.starts, 'HH24:MI'), ' · fără tură în program')
      || case when t.id is not null and c.clock_in > public.tura_start(t) + interval '5 minutes'
              then ' · întârziere ' || ceil(extract(epoch from c.clock_in - public.tura_start(t)) / 60)::int || ' min' else '' end,
    '#/echipa');
  return c;
end $$;

create or replace function public.pontaj_iesire(p_space text, p_token text)
returns public.clockings language plpgsql security definer set search_path = public as $$
declare c public.clockings; neterminate text;
begin
  if not public.is_member() then raise exception 'Contul nu e activ.'; end if;
  if not exists (select 1 from public.space_qr where space_id = p_space and token = p_token) then
    raise exception 'Codul QR nu e valid pentru locația asta. Scanează codul de la intrare.';
  end if;
  update public.clockings set clock_out = now()
   where id = (select id from public.clockings where user_id = auth.uid() and space_id = p_space and clock_out is null
               order by clock_in desc limit 1)
  returning * into c;
  if not found then raise exception 'Nu ai tura deschisă la %.', public.nume_loc(p_space); end if;
  -- fișele pornite azi la locație și neterminate
  select string_agg(title, ', ') into neterminate from public.checklist_runs
   where space_id = p_space and day = (c.clock_in at time zone 'Europe/Bucharest')::date and finished_at is null;
  perform public.notifica_sefii(auth.uid(), p_space, 'clock_out',
    public.nume_loc(p_space) || ': ' || public.nume_om(auth.uid()) || ' a încheiat tura',
    'Clock-out la ' || public.ora(c.clock_out) || ' · ' ||
      to_char(c.clock_out - c.clock_in, 'HH24"h"MI') || ' în tură' || coalesce(' · neterminate: ' || neterminate, ''),
    '#/echipa');
  return c;
end $$;
revoke all on function public.pontaj_intrare(text, text), public.pontaj_iesire(text, text) from public, anon;
grant execute on function public.pontaj_intrare(text, text), public.pontaj_iesire(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Pașii bifați: fișa gata, pas nefăcut, problemă notată
-- ---------------------------------------------------------------------------
create or replace function public.pas_bifat()
returns trigger language plpgsql security definer set search_path = public as $$
declare r public.checklist_runs; total int; facute int; nefacute int; pas text;
begin
  select * into r from public.checklist_runs where id = new.run_id;
  pas := r.steps -> new.idx ->> 't';
  if (new.status = 'nefacut' or new.note <> '')
     and (tg_op = 'INSERT' or old.status is distinct from new.status or old.note is distinct from new.note) then
    perform public.notifica_sefii(new.marked_by, r.space_id, case when new.status = 'nefacut' then 'pas_nefacut' else 'problema' end,
      public.nume_loc(r.space_id) || ': ' || case when new.status = 'nefacut' then 'pas nefăcut' else 'notă' end || ' · ' || r.title,
      coalesce(pas, '') || case when new.note <> '' then ' — „' || new.note || '”' else '' end || ' · ' || public.nume_om(new.marked_by),
      '#/echipa');
  end if;
  total := jsonb_array_length(r.steps);
  select count(*), count(*) filter (where status = 'nefacut') into facute, nefacute from public.checklist_marks where run_id = r.id;
  if r.finished_at is null and facute >= total then
    update public.checklist_runs set finished_at = now(), finished_by = new.marked_by where id = r.id;
    perform public.notifica_sefii(new.marked_by, r.space_id, 'fisa_gata',
      public.nume_loc(r.space_id) || ': ' || r.title || ' e gata',
      public.ora(now()) || ' · ' || public.nume_om(new.marked_by)
        || case when nefacute > 0 then ' · ' || nefacute || ' pași nefăcuți' else ' · toți pașii făcuți' end
        || case when r.due_at is not null and now() > r.due_at
                then ' · cu ' || ceil(extract(epoch from now() - r.due_at) / 60)::int || ' min după termen' else '' end,
      '#/echipa');
  end if;
  return new;
end $$;
drop trigger if exists pas_bifat on public.checklist_marks;
create trigger pas_bifat after insert or update on public.checklist_marks for each row execute function public.pas_bifat();

create or replace function public.observatie_fisa()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.note <> '' and new.note is distinct from old.note then
    perform public.notifica_sefii(auth.uid(), new.space_id, 'problema',
      public.nume_loc(new.space_id) || ': observație · ' || new.title,
      '„' || new.note || '” · ' || coalesce(public.nume_om(auth.uid()), ''), '#/echipa');
  end if;
  return new;
end $$;
drop trigger if exists observatie_fisa on public.checklist_runs;
create trigger observatie_fisa after update of note on public.checklist_runs for each row execute function public.observatie_fisa();

-- ---------------------------------------------------------------------------
-- Verificările de la 5 minute: mementouri și întârzieri
-- ---------------------------------------------------------------------------
create table if not exists public.notificari_trimise (
  cheie text primary key,
  at    timestamptz not null default now()
);
alter table public.notificari_trimise enable row level security;
revoke all on public.notificari_trimise from anon, authenticated;
grant all on public.notificari_trimise to service_role;

create or replace function public.o_data(k text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  insert into public.notificari_trimise (cheie) values (k);
  return true;
exception when unique_violation then
  return false;
end $$;
revoke all on function public.o_data(text) from public, anon, authenticated;

create or replace function public.verifica_ture()
returns void language plpgsql security definer set search_path = public as $$
declare s record; f record; acum timestamptz := now(); azi date := (now() at time zone 'Europe/Bucharest')::date;
begin
  for s in select t.*, public.tura_start(t) as st, public.tura_sfarsit(t) as sf from public.shifts t
            where t.day between azi - 1 and azi + 1 loop
    -- 1. cu 15 minute înainte de tură: memento să scaneze QR-ul la sosire
    if acum between s.st - interval '20 minutes' and s.st and public.o_data('memento-start:' || s.id) then
      insert into public.notifications (user_id, kind, title, body, url, space_id) values (s.user_id, 'memento',
        case when s.opens then 'Deschizi ' else 'Tura ta la ' end || public.nume_loc(s.space_id) || ' începe la ' || to_char(s.starts, 'HH24:MI'),
        'Când ajungi, scanează codul QR de la intrare (clock-in)'
          || case when s.opens then ', apoi deschide fișa de deschidere și bifează pașii.' else '.' end, '#/tura', s.space_id);
    end if;
    -- 2. la 10 minute după începutul turei, fără clock-in: anunță șefii
    if acum between s.st + interval '10 minutes' and s.sf
       and not exists (select 1 from public.clockings c where c.user_id = s.user_id and c.space_id = s.space_id
                       and c.clock_in > s.st - interval '3 hours')
       and public.o_data('fara-clock-in:' || s.id) then
      perform public.notifica_sefii(s.user_id, s.space_id, 'intarziere',
        public.nume_loc(s.space_id) || ': ' || public.nume_om(s.user_id) || ' nu a făcut clock-in',
        'Tura începea la ' || to_char(s.starts, 'HH24:MI') || case when s.opens then ' și deschide locația' else '' end || '.', '#/echipa');
    end if;
    -- 3. la sfârșitul turei: memento pentru clock-out (și pentru fișa de închidere, la cine închide)
    if acum between s.sf - interval '5 minutes' and s.sf + interval '15 minutes'
       and exists (select 1 from public.clockings c where c.user_id = s.user_id and c.space_id = s.space_id and c.clock_out is null)
       and public.o_data('memento-final:' || s.id) then
      insert into public.notifications (user_id, kind, title, body, url, space_id) values (s.user_id, 'memento',
        'Tura ta la ' || public.nume_loc(s.space_id) || ' se termină la ' || to_char(s.ends, 'HH24:MI'),
        case when s.closes then 'Termină fișa de închidere, apoi ' else '' end || 'scanează codul QR la plecare (clock-out).', '#/tura', s.space_id);
    end if;
  end loop;

  -- 4. fișele de deschidere / închidere neterminate la termen (doar la locațiile cu program și cu om programat să deschidă / închidă)
  for f in
    select h.space_id, k.tip, (azi + case when k.tip = 'deschidere' then h.opens else h.closes end) at time zone 'Europe/Bucharest'
             + case when k.tip = 'inchidere' then interval '60 minutes' else interval '0' end as termen
    from public.space_hours h cross join (values ('deschidere'), ('inchidere')) k (tip)
    where h.weekday = extract(isodow from azi)
  loop
    if acum between f.termen and f.termen + interval '3 hours'
       and exists (select 1 from public.shifts t where t.space_id = f.space_id and t.day = azi
                   and ((f.tip = 'deschidere' and t.opens) or (f.tip = 'inchidere' and t.closes)))
       and not exists (select 1 from public.checklist_runs r join public.procedure_docs d on d.id = r.doc_id
                       where r.space_id = f.space_id and r.day = azi and r.finished_at is not null
                         and d.procedure_code is null and d.role_code is null
                         and d.source_file ilike 'Procedura_' || f.tip || '%')
       and public.o_data('fisa-termen:' || f.tip || ':' || f.space_id || ':' || azi) then
      -- anunță șefii celor programați să deschidă / închidă (o singură dată pe șef)
      insert into public.notifications (user_id, kind, title, body, url, space_id)
      select distinct p.user_id, 'intarziere',
             public.nume_loc(f.space_id) || ': fișa de ' || case when f.tip = 'deschidere' then 'deschidere' else 'închidere' end || ' nu e gata',
             'Termenul era ' || public.ora(f.termen) || '.', '#/echipa', f.space_id
      from public.shifts t
      join public.profiles om on om.user_id = t.user_id
      join public.profiles p on p.active and p.role_code in (select public.sefii(om.role_code))
      join public.roles r on r.code = p.role_code
      where t.space_id = f.space_id and t.day = azi and ((f.tip = 'deschidere' and t.opens) or (f.tip = 'inchidere' and t.closes))
        and (r.is_admin or exists (select 1 from public.role_space_access a where a.role_code = p.role_code and a.space_id = f.space_id));
    end if;
  end loop;
  delete from public.notificari_trimise where at < now() - interval '3 days';
end $$;
revoke all on function public.verifica_ture() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('verifica-ture') where exists (select 1 from cron.job where jobname = 'verifica-ture');
  perform cron.schedule('verifica-ture', '*/5 * * * *', 'select public.verifica_ture()');
exception when undefined_table or undefined_function or invalid_schema_name then
  raise notice 'pg_cron nu e disponibil: verificările de la 5 minute nu rulează';
end $$;

-- ---------------------------------------------------------------------------
-- Timp real (panoul „Echipa azi”, fișele bifate de colegi, clopoțelul)
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['notifications', 'clockings', 'checklist_runs', 'checklist_marks', 'shifts'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
              when undefined_object then raise notice 'publicația supabase_realtime lipsește (mediu local)';
    end;
  end loop;
end $$;
