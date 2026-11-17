-- =============================================================================
-- Ghidul echipei Madame Magnifique · Comunicarea în aplicație și punctajul transparent
--
-- Se rulează după 0020, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- 1. Semnalări: problemele de lucru (lipsă marfă, echipament defect, client…) se trimit din aplicație,
--    le vede echipa locației și șefii; șeful le preia, le rezolvă sau spune de ce nu se confirmă.
-- 2. Anunțuri: conducerea scrie pentru o locație sau pentru toată firma; fiecare confirmă cu „Am citit”.
-- 3. Feedback: șeful direct și cei de deasupra trimit unui om o apreciere (0, +5, +10, +20 XP) sau un
--    „de îmbunătățit” (0, −5, −10 XP), mereu cu text; omul îl vede, confirmă și poate răspunde.
-- 4. Punctele se pot și pierde, mereu cu motiv:
--      clock-in cu peste 15 min întârziere                          −5
--      fișa de deschidere / închidere nefăcută până la sfârșitul zilei   −10 (celui programat)
--      anunț neconfirmat în 24 de ore                               −2
--      „de îmbunătățit” de la șef                                   −5 / −10
--    Orice pierdere poate fi contestată; dacă șeful o admite, punctele se dau înapoi.
-- 5. Raportul lunar: punctele câștigate, pierdute și nete ale fiecărui om; GM sau AE închide luna,
--    iar cifrele rămân înghețate (pentru bonus).
-- Tot aici: problema semnalată nu mai aduce puncte la trimitere (se putea abuza), ci doar când e
-- rezolvată (+10, primele 3 pe zi); clock-in-ul se punctează o singură dată pe tură.
-- =============================================================================

-- Pot conduce omul ăsta? (sunt deasupra lui în organigramă și avem o locație comună; GM și AE: pe oricine)
create or replace function public.conduce_omul(u uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and u is distinct from auth.uid() and (public.sees_all() or (public.poate_conduce(u)
    and exists (select 1 from public.spaces s where public.vede_locatia(u, s.id) and public.vede_locatia(auth.uid(), s.id))))
$$;
revoke all on function public.conduce_omul(uuid) from public, anon;
grant execute on function public.conduce_omul(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Semnalări
-- ---------------------------------------------------------------------------
create table if not exists public.semnalari (
  id          bigint generated always as identity primary key,
  space_id    text not null references public.spaces (id) on delete cascade,
  user_id     uuid not null default auth.uid() references public.profiles (user_id) on delete cascade,
  categorie   text not null default 'altele' check (categorie in ('marfa', 'echipament', 'client', 'echipa', 'curatenie', 'altele')),
  text        text not null check (length(trim(text)) between 3 and 2000),
  urgent      boolean not null default false,
  privata     boolean not null default false,              -- „doar pentru șefi”
  status      text not null default 'deschisa' check (status in ('deschisa', 'in_lucru', 'rezolvata', 'respinsa')),
  raspuns     text not null default '' check (length(raspuns) <= 2000),
  preluat_de  uuid references public.profiles (user_id) on delete set null,
  rezolvat_de uuid references public.profiles (user_id) on delete set null,
  rezolvat_la timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists semnalari_loc on public.semnalari (space_id, created_at desc);
create index if not exists semnalari_om on public.semnalari (user_id, created_at desc);

create or replace function public.semnalare_protejata()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user <> 'authenticated' then return new; end if;
  if tg_op = 'INSERT' then
    new.user_id := auth.uid(); new.status := 'deschisa'; new.raspuns := ''; new.preluat_de := null;
    new.rezolvat_de := null; new.rezolvat_la := null; new.created_at := now(); new.updated_at := now();
    return new;
  end if;
  new.space_id := old.space_id; new.user_id := old.user_id; new.categorie := old.categorie; new.text := old.text;
  new.urgent := old.urgent; new.privata := old.privata; new.created_at := old.created_at; new.updated_at := now();
  new.preluat_de := old.preluat_de; new.rezolvat_de := old.rezolvat_de; new.rezolvat_la := old.rezolvat_la;
  if new.status is distinct from old.status then
    if new.status = 'respinsa' and length(trim(new.raspuns)) < 3 then raise exception 'Scrie pe scurt de ce nu se confirmă.'; end if;
    if new.status in ('rezolvata', 'respinsa') then new.rezolvat_de := auth.uid(); new.rezolvat_la := now();
    else new.rezolvat_de := null; new.rezolvat_la := null; end if;
    if new.status = 'in_lucru' then new.preluat_de := auth.uid(); end if;
    if new.status = 'deschisa' then new.preluat_de := null; end if;
  end if;
  return new;
end $$;
drop trigger if exists semnalare_protejata on public.semnalari;
create trigger semnalare_protejata before insert or update on public.semnalari for each row execute function public.semnalare_protejata();

create or replace function public.semnalare_anunta()
returns trigger language plpgsql security definer set search_path = public as $$
declare et text;
begin
  et := case new.categorie when 'marfa' then 'lipsă marfă' when 'echipament' then 'echipament defect' when 'client' then 'client'
        when 'echipa' then 'echipă și program' when 'curatenie' then 'curățenie și igienă' else 'altceva' end;
  if tg_op = 'INSERT' then
    perform public.notifica_sefii(new.user_id, new.space_id, 'semnalare',
      public.nume_loc(new.space_id) || ': ' || case when new.urgent then 'URGENT · ' else '' end || 'semnalare · ' || et,
      left(new.text, 160) || ' · ' || coalesce(public.nume_om(new.user_id), ''), '#/semnalari');
  elsif new.status is distinct from old.status and new.user_id is distinct from auth.uid() then
    insert into public.notifications (user_id, kind, title, body, url, space_id) values (new.user_id, 'semnalare',
      case new.status when 'in_lucru' then 'Semnalarea ta e în lucru' when 'rezolvata' then 'Semnalarea ta e rezolvată'
           when 'respinsa' then 'Semnalarea ta nu s-a confirmat' else 'Semnalarea ta a fost redeschisă' end,
      left(new.text, 80) || case when new.raspuns <> '' then ' — „' || left(new.raspuns, 160) || '”' else '' end
        || ' · ' || coalesce(public.nume_om(auth.uid()), ''), '#/semnalari', new.space_id);
  end if;
  return new;
end $$;
drop trigger if exists semnalare_anunta on public.semnalari;
create trigger semnalare_anunta after insert or update on public.semnalari for each row execute function public.semnalare_anunta();

alter table public.semnalari enable row level security;
revoke all on public.semnalari from anon, authenticated;
grant select, insert, delete on public.semnalari to authenticated;
grant update (status, raspuns) on public.semnalari to authenticated;
grant all on public.semnalari to service_role;
drop policy if exists "semnalările: echipa locației și șefii" on public.semnalari;
drop policy if exists "semnalează cine vede locația" on public.semnalari;
drop policy if exists "șeful preia și rezolvă" on public.semnalari;
drop policy if exists "îmi retrag semnalarea deschisă" on public.semnalari;
create policy "semnalările: echipa locației și șefii" on public.semnalari for select to authenticated
  using (public.is_member() and (user_id = auth.uid() or public.sees_all()
         or (public.can_see_space(space_id) and (not privata or public.vede_echipa()))));
create policy "semnalează cine vede locația" on public.semnalari for insert to authenticated
  with check (public.is_member() and user_id = auth.uid() and public.can_see_space(space_id));
create policy "șeful preia și rezolvă" on public.semnalari for update to authenticated
  using (public.sees_all() or (public.vede_echipa() and public.can_see_space(space_id)))
  with check (public.sees_all() or (public.vede_echipa() and public.can_see_space(space_id)));
create policy "îmi retrag semnalarea deschisă" on public.semnalari for delete to authenticated
  using (user_id = auth.uid() and status = 'deschisa');

-- ---------------------------------------------------------------------------
-- 2. Anunțuri (cu „Am citit”)
-- ---------------------------------------------------------------------------
create table if not exists public.anunturi (
  id         bigint generated always as identity primary key,
  from_user  uuid default auth.uid() references public.profiles (user_id) on delete set null,
  space_id   text references public.spaces (id) on delete cascade,      -- gol = toată firma
  title      text not null check (length(trim(title)) between 3 and 140),
  body       text not null default '' check (length(body) <= 4000),
  created_at timestamptz not null default now()
);
create index if not exists anunturi_data on public.anunturi (created_at desc);
-- Destinatarii se fixează la trimitere (cine era atunci în echipa locației); read_at gol = necitit.
create table if not exists public.anunturi_citiri (
  anunt_id bigint not null references public.anunturi (id) on delete cascade,
  user_id  uuid not null references public.profiles (user_id) on delete cascade,
  read_at  timestamptz,
  primary key (anunt_id, user_id)
);
create index if not exists anunturi_citiri_om on public.anunturi_citiri (user_id) where read_at is null;

create or replace function public.anunt_protejat()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then new.from_user := auth.uid(); new.created_at := now(); end if;
  return new;
end $$;
drop trigger if exists anunt_protejat on public.anunturi;
create trigger anunt_protejat before insert on public.anunturi for each row execute function public.anunt_protejat();

create or replace function public.anunt_trimis()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.anunturi_citiri (anunt_id, user_id)
  select new.id, p.user_id from public.profiles p join public.roles r on r.code = p.role_code
  where p.active and p.user_id is distinct from new.from_user and not (r.is_admin or r.sees_all)
    and (new.space_id is null or (public.vede_locatia(p.user_id, new.space_id)
         and exists (select 1 from public.space_roles sr where sr.space_id = new.space_id and sr.role_code = p.role_code)));
  insert into public.notifications (user_id, kind, title, body, url, space_id)
  select c.user_id, 'anunt', 'Anunț: ' || new.title,
         case when new.body <> '' then left(new.body, 140) || ' · ' else '' end || coalesce(public.nume_om(new.from_user), '')
           || ' · confirmă cu „Am citit” în 24 de ore', '#/mesaje', new.space_id
  from public.anunturi_citiri c where c.anunt_id = new.id;
  return new;
end $$;
drop trigger if exists anunt_trimis on public.anunturi;
create trigger anunt_trimis after insert on public.anunturi for each row execute function public.anunt_trimis();

create or replace function public.citire_protejata()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.anunt_id := old.anunt_id; new.user_id := old.user_id; new.read_at := coalesce(old.read_at, now());
  end if;
  return new;
end $$;
drop trigger if exists citire_protejata on public.anunturi_citiri;
create trigger citire_protejata before update on public.anunturi_citiri for each row execute function public.citire_protejata();

alter table public.anunturi enable row level security;
alter table public.anunturi_citiri enable row level security;
revoke all on public.anunturi, public.anunturi_citiri from anon, authenticated;
grant select, insert, delete on public.anunturi to authenticated;
grant select on public.anunturi_citiri to authenticated;
grant update (read_at) on public.anunturi_citiri to authenticated;
grant all on public.anunturi, public.anunturi_citiri to service_role;
drop policy if exists "anunțurile locațiilor mele și ale firmei" on public.anunturi;
drop policy if exists "anunță șefii" on public.anunturi;
drop policy if exists "îmi retrag anunțul" on public.anunturi;
create policy "anunțurile locațiilor mele și ale firmei" on public.anunturi for select to authenticated
  using (public.is_member() and (space_id is null or from_user = auth.uid() or public.can_see_space(space_id)));
create policy "anunță șefii" on public.anunturi for insert to authenticated
  with check (from_user = auth.uid() and public.vede_echipa()
              and ((space_id is null and public.sees_all()) or (space_id is not null and public.can_see_space(space_id))));
create policy "îmi retrag anunțul" on public.anunturi for delete to authenticated
  using (from_user = auth.uid() or public.is_admin());
drop policy if exists "citirile: ale mele, iar șefii pe ale echipei" on public.anunturi_citiri;
drop policy if exists "confirm că am citit" on public.anunturi_citiri;
create policy "citirile: ale mele, iar șefii pe ale echipei" on public.anunturi_citiri for select to authenticated
  using (user_id = auth.uid() or public.sees_all() or exists (select 1 from public.anunturi a where a.id = anunt_id
         and (a.from_user = auth.uid() or (public.vede_echipa() and a.space_id is not null and public.can_see_space(a.space_id)))));
create policy "confirm că am citit" on public.anunturi_citiri for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3. Feedback de la șefi (apreciere / de îmbunătățit), cu sau fără puncte
-- ---------------------------------------------------------------------------
create table if not exists public.feedback (
  id         bigint generated always as identity primary key,
  to_user    uuid not null references public.profiles (user_id) on delete cascade,
  from_user  uuid default auth.uid() references public.profiles (user_id) on delete set null,
  fel        text not null check (fel in ('apreciere', 'imbunatatire')),
  text       text not null check (length(trim(text)) between 5 and 2000),
  puncte     int not null default 0,
  created_at timestamptz not null default now(),
  read_at    timestamptz,
  raspuns    text not null default '' check (length(raspuns) <= 2000),
  constraint feedback_puncte check ((fel = 'apreciere' and puncte in (0, 5, 10, 20)) or (fel = 'imbunatatire' and puncte in (0, -5, -10)))
);
create index if not exists feedback_om on public.feedback (to_user, created_at desc);

-- Lunile închise (cifrele pentru bonus nu se mai schimbă) și fotografia punctelor fiecărui om.
create table if not exists public.luni_inchise (
  luna      date primary key check (luna = date_trunc('month', luna)::date),
  inchis_de uuid references public.profiles (user_id) on delete set null,
  inchis_la timestamptz not null default now()
);
create table if not exists public.puncte_luna (
  luna     date not null references public.luni_inchise (luna) on delete cascade,
  user_id  uuid not null,                    -- fără legătură la profil: cifra rămâne și dacă pleacă omul
  nume     text not null,
  rol      text not null default '',
  locatie  text,
  castigat int not null,
  pierdut  int not null,
  net      int not null,
  surse    jsonb not null default '{}',      -- {"fise": {"plus": 120, "minus": 10}, …}
  pierderi jsonb not null default '[]',      -- [{"zi": "…", "puncte": -5, "detaliu": "…"}]
  ture     int not null default 0,           -- turele din program ale lunii și câte au început la timp
  ture_la_timp int not null default 0,
  primary key (luna, user_id)
);
create or replace function public.luna_inchisa(d date)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.luni_inchise where luna = date_trunc('month', d)::date)
$$;
revoke all on function public.luna_inchisa(date) from public, anon;
grant execute on function public.luna_inchisa(date) to authenticated;

create or replace function public.feedback_protejat()
returns trigger language plpgsql set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; s int;
begin
  if current_user <> 'authenticated' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    if public.luna_inchisa((old.created_at at time zone 'Europe/Bucharest')::date) then
      raise exception 'Luna e închisă; feedbackul nu se mai șterge.';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    new.from_user := auth.uid(); new.created_at := now(); new.read_at := null; new.raspuns := '';
    if new.puncte <> 0 then
      select coalesce(sum(f.puncte), 0) into s from public.feedback f
      where f.to_user = new.to_user and (f.created_at at time zone 'Europe/Bucharest')::date = azi and sign(f.puncte) = sign(new.puncte);
      if new.puncte > 0 and s + new.puncte > 20 then
        raise exception 'Azi a primit deja % XP din aprecieri. Plafonul e de 20 pe zi.', s; end if;
      if new.puncte < 0 and s + new.puncte < -10 then
        raise exception 'Azi a pierdut deja % XP din observații. Plafonul e de 10 pe zi.', -s; end if;
    end if;
    return new;
  end if;
  -- UPDATE: doar cel care l-a primit, doar confirmarea de citire și răspunsul (o singură dată)
  new.to_user := old.to_user; new.from_user := old.from_user; new.fel := old.fel; new.text := old.text;
  new.puncte := old.puncte; new.created_at := old.created_at; new.read_at := coalesce(old.read_at, now());
  if old.raspuns <> '' then new.raspuns := old.raspuns; end if;
  return new;
end $$;
drop trigger if exists feedback_protejat on public.feedback;
create trigger feedback_protejat before insert or update or delete on public.feedback for each row execute function public.feedback_protejat();

create or replace function public.feedback_anunta()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, kind, title, body, url) values (new.to_user, 'feedback',
      case new.fel when 'apreciere' then 'Apreciere de la ' else 'De îmbunătățit, de la ' end || coalesce(public.nume_om(new.from_user), 'conducere')
        || case when new.puncte > 0 then ' · +' || new.puncte || ' XP' when new.puncte < 0 then ' · −' || abs(new.puncte) || ' XP' else '' end,
      left(new.text, 200), '#/mesaje');
  elsif new.raspuns <> '' and old.raspuns = '' and new.from_user is not null then
    insert into public.notifications (user_id, kind, title, body, url) values (new.from_user, 'feedback',
      coalesce(public.nume_om(new.to_user), 'Colegul') || ' a răspuns la feedback', left(new.raspuns, 200), '#/mesaje');
  end if;
  return new;
end $$;
drop trigger if exists feedback_anunta on public.feedback;
create trigger feedback_anunta after insert or update on public.feedback for each row execute function public.feedback_anunta();

alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;
grant select, insert, delete on public.feedback to authenticated;
grant update (read_at, raspuns) on public.feedback to authenticated;
grant all on public.feedback to service_role;
drop policy if exists "feedbackul: al meu, dat de mine sau al oamenilor mei" on public.feedback;
drop policy if exists "dau feedback oamenilor mei" on public.feedback;
drop policy if exists "confirm și răspund la feedbackul meu" on public.feedback;
drop policy if exists "îmi retrag feedbackul" on public.feedback;
create policy "feedbackul: al meu, dat de mine sau al oamenilor mei" on public.feedback for select to authenticated
  using (to_user = auth.uid() or from_user = auth.uid() or public.conduce_omul(to_user));
create policy "dau feedback oamenilor mei" on public.feedback for insert to authenticated
  with check (from_user = auth.uid() and public.conduce_omul(to_user));
create policy "confirm și răspund la feedbackul meu" on public.feedback for update to authenticated
  using (to_user = auth.uid()) with check (to_user = auth.uid());
create policy "îmi retrag feedbackul" on public.feedback for delete to authenticated
  using (from_user = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------------------
-- 4. Contestații (se trimit și se decid doar prin funcțiile de mai jos)
-- ---------------------------------------------------------------------------
create table if not exists public.contestatii (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (user_id) on delete cascade,
  cheie      text not null,                               -- evenimentul contestat (ex.: „pontaj:123”)
  zi         date not null,
  puncte     int not null,
  detaliu    text not null default '',
  motiv      text not null check (length(trim(motiv)) between 5 and 2000),
  status     text not null default 'deschisa' check (status in ('deschisa', 'admisa', 'respinsa')),
  raspuns    text not null default '',
  decis_de   uuid references public.profiles (user_id) on delete set null,
  decis_la   timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, cheie)
);
alter table public.contestatii enable row level security;
alter table public.luni_inchise enable row level security;
alter table public.puncte_luna enable row level security;
revoke all on public.contestatii, public.luni_inchise, public.puncte_luna from anon, authenticated;
grant select on public.contestatii, public.luni_inchise, public.puncte_luna to authenticated;
grant all on public.contestatii, public.luni_inchise, public.puncte_luna to service_role;
drop policy if exists "contestațiile: ale mele sau ale oamenilor mei" on public.contestatii;
create policy "contestațiile: ale mele sau ale oamenilor mei" on public.contestatii for select to authenticated
  using (user_id = auth.uid() or public.conduce_omul(user_id));
drop policy if exists "lunile închise le vede echipa" on public.luni_inchise;
create policy "lunile închise le vede echipa" on public.luni_inchise for select to authenticated using (public.is_member());
drop policy if exists "punctele lunii: ale mele sau ale oamenilor mei" on public.puncte_luna;
create policy "punctele lunii: ale mele sau ale oamenilor mei" on public.puncte_luna for select to authenticated
  using (user_id = auth.uid() or public.conduce_omul(user_id));

-- Notificarea de la 0020 promitea „+10 XP”; acum punctele au plafon pe zi, deci textul rămâne fără cifră.
create or replace function public.problema_rezolvata()
returns trigger language plpgsql security definer set search_path = public as $$
declare r public.checklist_runs; cine uuid; pas text;
begin
  select * into r from public.checklist_runs where id = new.run_id;
  if new.idx is null then cine := r.note_by; pas := r.note;
  else select marked_by into cine from public.checklist_marks where run_id = new.run_id and idx = new.idx;
       pas := r.steps -> new.idx ->> 't'; end if;
  if cine is not null and cine <> new.resolved_by then
    insert into public.notifications (user_id, kind, title, body, url, space_id) values (cine, 'problema_rezolvata',
      'Problema semnalată de tine e rezolvată', coalesce(pas, '') || ' · ' || coalesce(public.nume_om(new.resolved_by), ''),
      '#/progres', r.space_id);
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Punctele: fiecare eveniment are cheie, motiv și semn
-- ---------------------------------------------------------------------------
drop function if exists public.xp_evenimente(date, date);
drop function if exists public.xp_evenimente(date, date, uuid);
create function public.xp_evenimente(p_de date, p_pana date, p_user uuid default null)
returns table (user_id uuid, space_id text, zi date, sursa text, puncte int, detaliu text, la timestamptz, cheie text)
language sql stable security definer set search_path = public as $$
  with brut as (
    -- clock-in: doar primul scan al turei (sau primul din zi, fără tură în program)
    select c.user_id, c.space_id, (c.clock_in at time zone 'Europe/Bucharest')::date as zi, 'punctualitate'::text as sursa,
           case when s.id is null then 2
                when c.clock_in <= public.tura_start(s) + interval '5 minutes' then 10
                when c.clock_in <= public.tura_start(s) + interval '15 minutes' then 3 else -5 end as puncte,
           case when s.id is null then 'Clock-in fără tură în program'
                when c.clock_in <= public.tura_start(s) + interval '5 minutes' then 'Clock-in la timp'
                else 'Clock-in cu ' || ceil(extract(epoch from c.clock_in - public.tura_start(s)) / 60)::int || ' min întârziere'
                     || case when c.clock_in > public.tura_start(s) + interval '15 minutes' then ' (peste 15)' else '' end end as detaliu,
           c.clock_in as la, 'pontaj:' || c.id as cheie, null::text as grup
    from (select k.*, row_number() over (partition by k.user_id,
                   coalesce('t' || k.shift_id, 'z' || (k.clock_in at time zone 'Europe/Bucharest')::date::text) order by k.clock_in) as nr
          from public.clockings k where p_user is null or k.user_id = p_user) c
    left join public.shifts s on s.id = c.shift_id
    where c.nr = 1 and (c.clock_in at time zone 'Europe/Bucharest')::date between p_de and p_pana
    union all
    -- pași făcuți
    select m.marked_by, r.space_id, r.day, 'fise', 2, 'Pas făcut · ' || r.title, m.at, 'pas:' || m.run_id || ':' || m.idx, null
    from public.checklist_marks m join public.checklist_runs r on r.id = m.run_id
    where m.status = 'facut' and m.marked_by is not null and r.day between p_de and p_pana and (p_user is null or m.marked_by = p_user)
    union all
    -- fișe terminate: +15 la termen (+5 după), +10 dacă niciun pas nu a rămas nefăcut
    select r.finished_by, r.space_id, r.day, 'fise',
           (case when r.due_at is null or r.finished_at <= r.due_at then 15 else 5 end)
           + (case when not exists (select 1 from public.checklist_marks m where m.run_id = r.id and m.status = 'nefacut') then 10 else 0 end),
           r.title || case when r.due_at is null or r.finished_at <= r.due_at then ' · gata la termen' else ' · gata după termen' end
             || case when not exists (select 1 from public.checklist_marks m where m.run_id = r.id and m.status = 'nefacut') then ', fără niciun pas nefăcut' else '' end,
           r.finished_at, 'fisa:' || r.id, null
    from public.checklist_runs r
    where r.finished_at is not null and r.finished_by is not null and r.day between p_de and p_pana and (p_user is null or r.finished_by = p_user)
    union all
    -- fișa de deschidere / închidere a locației, nefăcută până la 03:00 a doua zi: −10 celui programat să deschidă / să închidă
    select s.user_id, s.space_id, s.day, 'fise', -10,
           'Fișa de ' || case k.tip when 'deschidere' then 'deschidere' else 'închidere' end || ' nefăcută · ' || public.nume_loc(s.space_id),
           t.termen, 'fisa-lipsa:' || s.id || ':' || left(k.tip, 1), null
    from public.shifts s
    cross join (values ('deschidere'), ('inchidere')) k (tip)
    cross join lateral (select ((s.day + 1)::timestamp + interval '3 hours') at time zone 'Europe/Bucharest' as termen) t
    where ((k.tip = 'deschidere' and s.opens) or (k.tip = 'inchidere' and s.closes))
      and s.day between p_de and p_pana and (p_user is null or s.user_id = p_user) and now() > t.termen
      and exists (select 1 from public.procedure_docs d where d.space_id = s.space_id and d.procedure_code is null
                  and d.role_code is null and d.source_file ilike 'Procedura_' || k.tip || '%')
      and not exists (select 1 from public.checklist_runs r join public.procedure_docs d on d.id = r.doc_id
                      where r.space_id = s.space_id and r.day = s.day and r.finished_at <= t.termen
                        and d.procedure_code is null and d.role_code is null and d.source_file ilike 'Procedura_' || k.tip || '%')
    union all
    -- Academia: lecții
    select lp.user_id, public.locatia_omului(lp.user_id), (lp.done_at at time zone 'Europe/Bucharest')::date, 'academia', 5,
           'Lecție parcursă', lp.done_at, 'lectie:' || lp.lesson_id, null
    from public.lesson_progress lp
    where (lp.done_at at time zone 'Europe/Bucharest')::date between p_de and p_pana and (p_user is null or lp.user_id = p_user)
    union all
    -- Academia: primul test trecut la fiecare curs
    select q.user_id, public.locatia_omului(q.user_id), (q.created_at at time zone 'Europe/Bucharest')::date, 'academia', 30,
           'Test trecut · ' || c.title, q.created_at, 'test:' || q.course_id, null
    from (select distinct on (a.user_id, a.course_id) a.* from public.quiz_attempts a
          where a.passed and (p_user is null or a.user_id = p_user) order by a.user_id, a.course_id, a.created_at) q
    join public.courses c on c.id = q.course_id
    where (q.created_at at time zone 'Europe/Bucharest')::date between p_de and p_pana
    union all
    -- problemă din fișă, rezolvată de șef: +10 celui care a semnalat-o
    select coalesce(m.marked_by, r.note_by), r.space_id, (pr.resolved_at at time zone 'Europe/Bucharest')::date, 'probleme', 10,
           'Problema semnalată de tine a fost rezolvată · ' || r.title, pr.resolved_at, 'rezolvat:' || pr.id, 'semnalat'
    from public.probleme_rezolvate pr join public.checklist_runs r on r.id = pr.run_id
    left join public.checklist_marks m on m.run_id = pr.run_id and m.idx = pr.idx
    where coalesce(m.marked_by, r.note_by) is distinct from pr.resolved_by
      and (pr.resolved_at at time zone 'Europe/Bucharest')::date between p_de and p_pana
      and (p_user is null or coalesce(m.marked_by, r.note_by) = p_user)
    union all
    -- … și +5 celui care a rezolvat-o
    select pr.resolved_by, r.space_id, (pr.resolved_at at time zone 'Europe/Bucharest')::date, 'probleme', 5,
           'Ai rezolvat o problemă · ' || r.title, pr.resolved_at, 'rezolva:' || pr.id, 'rezolvat'
    from public.probleme_rezolvate pr join public.checklist_runs r on r.id = pr.run_id
    left join public.checklist_marks m on m.run_id = pr.run_id and m.idx = pr.idx
    where pr.resolved_by is distinct from coalesce(m.marked_by, r.note_by)
      and (pr.resolved_at at time zone 'Europe/Bucharest')::date between p_de and p_pana and (p_user is null or pr.resolved_by = p_user)
    union all
    -- semnalare rezolvată de șef: +10 celui care a trimis-o
    select g.user_id, g.space_id, (g.rezolvat_la at time zone 'Europe/Bucharest')::date, 'probleme', 10,
           'Semnalarea ta a fost rezolvată · ' || left(g.text, 60), g.rezolvat_la, 'semnalare:' || g.id, 'semnalat'
    from public.semnalari g
    where g.status = 'rezolvata' and g.rezolvat_la is not null and g.rezolvat_de is distinct from g.user_id
      and (g.rezolvat_la at time zone 'Europe/Bucharest')::date between p_de and p_pana and (p_user is null or g.user_id = p_user)
    union all
    -- … și +5 celui care a rezolvat-o
    select g.rezolvat_de, g.space_id, (g.rezolvat_la at time zone 'Europe/Bucharest')::date, 'probleme', 5,
           'Ai rezolvat o semnalare · ' || left(g.text, 60), g.rezolvat_la, 'semnalare-rez:' || g.id, 'rezolvat'
    from public.semnalari g
    where g.status = 'rezolvata' and g.rezolvat_la is not null and g.rezolvat_de is distinct from g.user_id
      and (g.rezolvat_la at time zone 'Europe/Bucharest')::date between p_de and p_pana and (p_user is null or g.rezolvat_de = p_user)
    union all
    -- feedback cu puncte, de la șefi
    select f.to_user, public.locatia_omului(f.to_user), (f.created_at at time zone 'Europe/Bucharest')::date, 'sefi', f.puncte,
           case f.fel when 'apreciere' then 'Apreciere de la ' else 'De îmbunătățit, de la ' end
             || coalesce(public.nume_om(f.from_user), 'conducere') || ': ' || left(f.text, 140), f.created_at, 'feedback:' || f.id, null
    from public.feedback f
    where f.puncte <> 0 and (f.created_at at time zone 'Europe/Bucharest')::date between p_de and p_pana and (p_user is null or f.to_user = p_user)
    union all
    -- anunț neconfirmat în 24 de ore
    select c.user_id, coalesce(a.space_id, public.locatia_omului(c.user_id)), ((a.created_at + interval '24 hours') at time zone 'Europe/Bucharest')::date,
           'anunturi', -2, 'Anunț neconfirmat în 24 de ore · ' || a.title, a.created_at + interval '24 hours', 'anunt:' || a.id, null
    from public.anunturi_citiri c join public.anunturi a on a.id = c.anunt_id
    where now() > a.created_at + interval '24 hours' and (c.read_at is null or c.read_at > a.created_at + interval '24 hours')
      and ((a.created_at + interval '24 hours') at time zone 'Europe/Bucharest')::date between p_de and p_pana and (p_user is null or c.user_id = p_user)
  ), numerotat as (
    select b.*, row_number() over (partition by b.user_id, b.zi, b.grup order by b.la, b.cheie) as nr from brut b where b.user_id is not null
  )
  select n.user_id, n.space_id, n.zi, n.sursa, n.puncte, n.detaliu, n.la, n.cheie from numerotat n
  where (n.grup is null or n.nr <= 3)        -- problemele rezolvate: primele 3 pe zi se punctează
    and not (n.puncte < 0 and exists (select 1 from public.contestatii c
                                      where c.user_id = n.user_id and c.cheie = n.cheie and c.status = 'admisa'))
$$;
revoke all on function public.xp_evenimente(date, date, uuid) from public, anon, authenticated;

-- Scorul unei locații: la „probleme” intră acum și semnalările (cele respinse nu se numără).
create or replace function public.scor_locatie(p_space text, p_de date, p_pana date)
returns jsonb language sql stable security definer set search_path = public as $$
  with ture as (
    select s.*, exists (select 1 from public.clockings c where c.shift_id = s.id
                        and c.clock_in <= public.tura_start(s) + interval '5 minutes') as la_timp
    from public.shifts s where s.space_id = p_space and s.day between p_de and p_pana
      and public.tura_start(s) < now() - interval '10 minutes'
  ), fise as (
    select r.* from public.checklist_runs r where r.space_id = p_space and r.day between p_de and p_pana
      and r.due_at is not null and (r.finished_at is not null or r.due_at < now())
  ), pasi as (
    select m.status from public.checklist_marks m join public.checklist_runs r on r.id = m.run_id
    where r.space_id = p_space and r.day between p_de and p_pana
  ), semnalate as (
    select r.id as run_id, m.idx from public.checklist_marks m join public.checklist_runs r on r.id = m.run_id
    where r.space_id = p_space and r.day between p_de and p_pana and (m.status = 'nefacut' or m.note <> '')
    union all
    select r.id, null::int from public.checklist_runs r where r.space_id = p_space and r.day between p_de and p_pana and r.note <> ''
  ), semn as (
    select g.status from public.semnalari g where g.space_id = p_space and g.status <> 'respinsa'
      and (g.created_at at time zone 'Europe/Bucharest')::date between p_de and p_pana
  ), c as (
    select (select count(*) from ture) as ture, (select count(*) filter (where la_timp) from ture) as ture_la_timp,
           (select count(*) from fise) as fise, (select count(*) filter (where finished_at <= due_at) from fise) as fise_la_termen,
           (select count(*) from pasi) as pasi, (select count(*) filter (where status = 'facut') from pasi) as pasi_facuti,
           (select count(*) from semnalate) + (select count(*) from semn) as probleme,
           (select count(*) from semnalate s where exists (select 1 from public.probleme_rezolvate pr
              where pr.run_id = s.run_id and coalesce(pr.idx, -1) = coalesce(s.idx, -1)))
             + (select count(*) from semn where status = 'rezolvata') as rezolvate,
           (select coalesce(sum(puncte), 0) from public.xp_evenimente(p_de, p_pana) e where e.space_id = p_space) as xp
  )
  select jsonb_build_object(
    'ture', ture, 'ture_la_timp', ture_la_timp, 'fise', fise, 'fise_la_termen', fise_la_termen,
    'pasi', pasi, 'pasi_facuti', pasi_facuti, 'probleme', probleme, 'rezolvate', rezolvate, 'xp', xp,
    'scor', (select round(avg(v)) from unnest(array[
        case when ture > 0 then 100.0 * ture_la_timp / ture end,
        case when fise > 0 then 100.0 * fise_la_termen / fise end,
        case when pasi > 0 then 100.0 * pasi_facuti / pasi end,
        case when probleme > 0 then 100.0 * rezolvate / probleme end]) v))
  from c
$$;
revoke all on function public.scor_locatie(text, date, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Ce vede fiecare
-- ---------------------------------------------------------------------------
-- Progresul unui om: al meu, sau al cuiva pe care îl conduc.
create or replace function public.joc_om(p_user uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid := coalesce(p_user, auth.uid()); azi date := (now() at time zone 'Europe/Bucharest')::date;
        luni date; luna date; loc text; om public.profiles; r jsonb;
begin
  if not public.is_member() then return null; end if;
  if u <> auth.uid() and not public.conduce_omul(u) then raise exception 'Nu vezi progresul acestui om.'; end if;
  select * into om from public.profiles where user_id = u;
  if not found then raise exception 'Contul nu există.'; end if;
  luni := public.luni_sapt(azi); luna := date_trunc('month', azi)::date; loc := public.locatia_omului(u);
  with ev as (select * from public.xp_evenimente('2000-01-01', azi, u))
  select jsonb_build_object(
    'user_id', u, 'nume', om.full_name, 'rol', om.role_code, 'eu', u = auth.uid(), 'acum', now(),
    'xp', (select coalesce(sum(puncte), 0) from ev),
    'xp_saptamana', (select coalesce(sum(puncte), 0) from ev where zi >= luni),
    'xp_azi', (select coalesce(sum(puncte), 0) from ev where zi = azi),
    'luna', (select jsonb_build_object('luna', luna, 'castigat', coalesce(sum(puncte) filter (where puncte > 0), 0),
               'pierdut', coalesce(-sum(puncte) filter (where puncte < 0), 0), 'net', coalesce(sum(puncte), 0)) from ev where zi >= luna),
    'surse', (select coalesce(jsonb_object_agg(sursa, p), '{}') from (select sursa, sum(puncte) p from ev where zi >= luni group by sursa) x),
    'ultimele', (select coalesce(jsonb_agg(x order by x.la desc), '[]') from (
                   select cheie, sursa, detaliu, puncte, la from ev where puncte <> 0 order by la desc limit 40) x),
    'serie', (select curenta from public.serie_punctualitate(u)),
    'serie_max', (select maxima from public.serie_punctualitate(u)),
    'contoare', jsonb_build_object(
      'fise_terminate', (select count(*) from public.checklist_runs where finished_by = u),
      'deschideri_la_timp', (select count(*) from public.checklist_runs where finished_by = u and title ilike 'deschidere%'
                              and (due_at is null or finished_at <= due_at)),
      'fara_cusur', (select count(*) from public.checklist_runs k where k.finished_by = u
                     and not exists (select 1 from public.checklist_marks m where m.run_id = k.id and m.status = 'nefacut')),
      'clockin_la_timp', (select count(*) from ev where sursa = 'punctualitate' and puncte = 10),
      'probleme_rezolvate', (select count(*) from ev where cheie like 'rezolvat:%' or cheie like 'semnalare:%'),
      'teste_trecute', (select count(*) from ev where cheie like 'test:%'),
      'lectii', (select count(*) from ev where cheie like 'lectie:%')),
    'locatie', loc,
    'echipa', case when loc is null then null else jsonb_build_object(
      'saptamana', public.scor_locatie(loc, luni, azi),
      'trecuta', public.scor_locatie(loc, luni - 7, luni - 1),
      'xp_total', (select coalesce(sum(puncte), 0) from public.xp_evenimente('2000-01-01', azi) e where e.space_id = loc)) end,
    'de_confirmat', case when u = auth.uid() then
        (select count(*) from public.anunturi_citiri c where c.user_id = u and c.read_at is null)
        + (select count(*) from public.feedback f where f.to_user = u and f.read_at is null) else 0 end,
    'contestatii', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
        select c.id, c.cheie, c.zi, c.puncte, c.detaliu, c.motiv, c.status, c.raspuns, c.created_at, c.decis_la,
               public.nume_om(c.decis_de) as decis_de
        from public.contestatii c where c.user_id = u order by c.created_at desc limit 20) x))
  into r;
  return r;
end $$;
revoke all on function public.joc_om(uuid) from public, anon;
grant execute on function public.joc_om(uuid) to authenticated;

create or replace function public.joc_eu()
returns jsonb language sql stable security definer set search_path = public as $$ select public.joc_om(null) $$;
revoke all on function public.joc_eu() from public, anon;
grant execute on function public.joc_eu() to authenticated;

-- Jurnalul punctelor pe o lună: fiecare eveniment, cu motiv și semn; pierderile arată și starea contestației.
create or replace function public.jurnal_puncte(p_user uuid default null, p_luna date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid := coalesce(p_user, auth.uid()); azi date := (now() at time zone 'Europe/Bucharest')::date;
        l date; sf date; inchisa boolean; r jsonb;
begin
  if not public.is_member() then return null; end if;
  if u <> auth.uid() and not public.conduce_omul(u) then raise exception 'Nu vezi punctele acestui om.'; end if;
  l := date_trunc('month', coalesce(p_luna, azi))::date; sf := (l + interval '1 month')::date - 1;
  inchisa := public.luna_inchisa(l);
  with ev as (select * from public.xp_evenimente(l, least(sf, azi), u)),
       luni as (select date_trunc('month', azi)::date - (k || ' months')::interval as m from generate_series(0, 5) k)
  select jsonb_build_object(
    'luna', l, 'inchisa', inchisa,
    'sumar', coalesce((select jsonb_build_object('castigat', castigat, 'pierdut', pierdut, 'net', net) from public.puncte_luna where luna = l and user_id = u),
               (select jsonb_build_object('castigat', coalesce(sum(puncte) filter (where puncte > 0), 0),
                  'pierdut', coalesce(-sum(puncte) filter (where puncte < 0), 0), 'net', coalesce(sum(puncte), 0)) from ev)),
    'surse', (select coalesce(jsonb_object_agg(sursa, jsonb_build_object('plus', plus, 'minus', minus)), '{}') from (
                select sursa, coalesce(sum(puncte) filter (where puncte > 0), 0) as plus, coalesce(-sum(puncte) filter (where puncte < 0), 0) as minus
                from ev group by sursa) x),
    'evenimente', (select coalesce(jsonb_agg(x order by x.la desc), '[]') from (
        select e.cheie, e.zi, e.la, e.sursa, e.puncte, e.detaliu, c.status as contestatie, c.raspuns
        from ev e left join public.contestatii c on c.user_id = u and c.cheie = e.cheie
        where e.puncte <> 0 order by e.la desc limit 800) x),
    'luni', (select jsonb_agg(jsonb_build_object('luna', m::date, 'inchisa', public.luna_inchisa(m::date)) order by m desc) from luni))
  into r;
  return r;
end $$;
revoke all on function public.jurnal_puncte(uuid, date) from public, anon;
grant execute on function public.jurnal_puncte(uuid, date) to authenticated;

-- Ce puncte au apărut de la ultima privire (pentru „+10 XP · Clock-in la timp” pe ecran).
create or replace function public.puncte_noi(p_dupa timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('acum', now(), 'evenimente', coalesce((select jsonb_agg(x order by x.la) from (
      select e.cheie, e.sursa, e.puncte, e.detaliu, e.la
      from public.xp_evenimente((p_dupa at time zone 'Europe/Bucharest')::date - 2, (now() at time zone 'Europe/Bucharest')::date, auth.uid()) e
      where p_dupa is not null and e.la > p_dupa and e.la <= now() and e.puncte <> 0 order by e.la desc limit 12) x), '[]'))
  where public.is_member()
$$;
revoke all on function public.puncte_noi(timestamptz) from public, anon;
grant execute on function public.puncte_noi(timestamptz) to authenticated;

-- Tabloul unei locații (ca în 0020; în „azi” apar acum și pierderile).
create or replace function public.joc_echipa(p_space text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; luni date; r jsonb;
begin
  if not (public.sees_all() or (public.vede_echipa() and public.can_see_space(p_space))) then
    raise exception 'Nu vezi echipa acestei locații.';
  end if;
  luni := public.luni_sapt(azi);
  with ev as (select * from public.xp_evenimente(azi - 60, azi)),
  toate as (select user_id, sum(puncte) as xp from public.xp_evenimente('2000-01-01', azi) group by user_id),
  oameni as (
    select distinct p.user_id, p.full_name, p.role_code from public.profiles p
    where p.active and (exists (select 1 from ev where ev.user_id = p.user_id and ev.space_id = p_space and ev.zi >= azi - 30)
       or exists (select 1 from public.shifts s where s.user_id = p.user_id and s.space_id = p_space and s.day between azi - 30 and azi + 7)
       or exists (select 1 from public.profile_spaces ps where ps.user_id = p.user_id and ps.space_id = p_space))
  )
  select jsonb_build_object(
    'saptamana', public.scor_locatie(p_space, luni, azi),
    'trecuta', public.scor_locatie(p_space, luni - 7, luni - 1),
    'luna', public.scor_locatie(p_space, date_trunc('month', azi)::date, azi),
    'xp_total', (select coalesce(sum(puncte), 0) from public.xp_evenimente('2000-01-01', azi) e where e.space_id = p_space),
    'oameni', (select coalesce(jsonb_agg(jsonb_build_object(
        'user_id', o.user_id, 'nume', o.full_name, 'rol', o.role_code,
        'xp', coalesce(t.xp, 0),
        'xp_saptamana', (select coalesce(sum(puncte), 0) from ev where ev.user_id = o.user_id and ev.zi >= luni),
        'xp_trecuta', (select coalesce(sum(puncte), 0) from ev where ev.user_id = o.user_id and ev.zi between luni - 7 and luni - 1),
        'serie', (select curenta from public.serie_punctualitate(o.user_id)),
        'il_conduc', public.conduce_omul(o.user_id)) order by o.full_name), '[]')
      from oameni o left join toate t on t.user_id = o.user_id),
    'azi', (select coalesce(jsonb_agg(x order by x.la desc), '[]') from (
        select e.user_id, p.full_name as nume, e.detaliu, e.puncte, e.la from ev e join public.profiles p on p.user_id = e.user_id
        where e.space_id = p_space and e.zi = azi and e.puncte <> 0 order by e.la desc limit 40) x),
    'semnalari_deschise', (select count(*) from public.semnalari g where g.space_id = p_space and g.status in ('deschisa', 'in_lucru')))
  into r;
  return r;
end $$;
revoke all on function public.joc_echipa(text) from public, anon;
grant execute on function public.joc_echipa(text) to authenticated;

-- Semnalările pe care le văd, cu numele oamenilor (profilurile nu sunt publice în echipă).
create or replace function public.semnalarile(p_space text default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by (x.status in ('deschisa', 'in_lucru')) desc, x.created_at desc), '[]') from (
    select g.id, g.space_id, g.categorie, g.text, g.urgent, g.privata, g.status, g.raspuns, g.created_at, g.updated_at, g.rezolvat_la,
           g.user_id = auth.uid() as a_mea, public.nume_om(g.user_id) as autor,
           public.nume_om(g.preluat_de) as preluat_de, public.nume_om(g.rezolvat_de) as rezolvat_de,
           (public.sees_all() or (public.vede_echipa() and public.can_see_space(g.space_id))) as pot_decide
    from public.semnalari g
    where public.is_member() and (p_space is null or g.space_id = p_space)
      and (g.user_id = auth.uid() or public.sees_all() or (public.can_see_space(g.space_id) and (not g.privata or public.vede_echipa())))
      and (g.status in ('deschisa', 'in_lucru') or g.created_at > now() - interval '45 days')
    order by g.created_at desc limit 200) x
$$;
revoke all on function public.semnalarile(text) from public, anon;
grant execute on function public.semnalarile(text) to authenticated;

-- Anunțurile și feedbackul meu; șefii văd și cine a citit ce au trimis.
create or replace function public.mesajele_mele()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'anunturi', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
        select a.id, a.title, a.body, a.space_id, a.created_at, a.created_at + interval '24 hours' as termen,
               public.nume_om(a.from_user) as de_la, a.from_user = auth.uid() as al_meu,
               c.user_id is not null as destinatar, c.read_at as citit_la,
               case when a.from_user = auth.uid() or public.sees_all()
                         or (public.vede_echipa() and a.space_id is not null and public.can_see_space(a.space_id)) then
                 (select jsonb_build_object('total', count(*), 'citite', count(*) filter (where k.read_at is not null),
                    'necitite', coalesce(jsonb_agg(public.nume_om(k.user_id) order by public.nume_om(k.user_id)) filter (where k.read_at is null), '[]'))
                  from public.anunturi_citiri k where k.anunt_id = a.id) end as stare
        from public.anunturi a left join public.anunturi_citiri c on c.anunt_id = a.id and c.user_id = auth.uid()
        where (a.space_id is null or a.from_user = auth.uid() or public.can_see_space(a.space_id))
          and (a.created_at > now() - interval '60 days' or (c.user_id is not null and c.read_at is null))
        order by a.created_at desc limit 80) x),
    'feedback', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
        select f.id, f.fel, f.text, f.puncte, f.created_at, f.read_at, f.raspuns, f.to_user,
               public.nume_om(f.from_user) as de_la, public.nume_om(f.to_user) as catre,
               f.to_user = auth.uid() as primit, f.from_user = auth.uid() as dat_de_mine
        from public.feedback f
        where (f.to_user = auth.uid() or f.from_user = auth.uid() or public.conduce_omul(f.to_user))
          and (f.created_at > now() - interval '90 days' or (f.to_user = auth.uid() and f.read_at is null))
        order by f.created_at desc limit 120) x),
    'de_confirmat', (select count(*) from public.anunturi_citiri c where c.user_id = auth.uid() and c.read_at is null)
                    + (select count(*) from public.feedback f where f.to_user = auth.uid() and f.read_at is null),
    'pot_anunta', public.vede_echipa(), 'pot_anunta_firma', public.sees_all())
  where public.is_member()
$$;
revoke all on function public.mesajele_mele() from public, anon;
grant execute on function public.mesajele_mele() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Contestația unei pierderi de puncte
-- ---------------------------------------------------------------------------
create or replace function public.contesta(p_cheie text, p_motiv text)
returns bigint language plpgsql security definer set search_path = public as $$
declare e record; n bigint; azi date := (now() at time zone 'Europe/Bucharest')::date;
begin
  if not public.is_member() then raise exception 'Contul nu e activ.'; end if;
  if length(trim(coalesce(p_motiv, ''))) < 5 then raise exception 'Scrie pe scurt de ce contești.'; end if;
  select * into e from public.xp_evenimente('2000-01-01', azi, auth.uid()) x where x.cheie = p_cheie and x.puncte < 0 limit 1;
  if not found then raise exception 'Nu am găsit pierderea de puncte.'; end if;
  if public.luna_inchisa(e.zi) then raise exception 'Luna e închisă; pierderea nu se mai poate contesta.'; end if;
  if exists (select 1 from public.contestatii where user_id = auth.uid() and cheie = p_cheie) then
    raise exception 'Ai contestat deja pierderea asta.'; end if;
  insert into public.contestatii (user_id, cheie, zi, puncte, detaliu, motiv)
  values (auth.uid(), p_cheie, e.zi, e.puncte, e.detaliu, trim(p_motiv)) returning id into n;
  perform public.notifica_sefii(auth.uid(), e.space_id, 'contestatie',
    coalesce(public.nume_om(auth.uid()), 'Un coleg') || ' contestă o pierdere de puncte',
    e.detaliu || ' (' || e.puncte || ' XP) — „' || left(trim(p_motiv), 160) || '”', '#/echipa?tab=oameni');
  return n;
end $$;
revoke all on function public.contesta(text, text) from public, anon;
grant execute on function public.contesta(text, text) to authenticated;

create or replace function public.decide_contestatie(p_id bigint, p_admisa boolean, p_raspuns text default '')
returns void language plpgsql security definer set search_path = public as $$
declare c public.contestatii;
begin
  select * into c from public.contestatii where id = p_id;
  if not found or c.status <> 'deschisa' then raise exception 'Contestația nu mai e deschisă.'; end if;
  if not public.conduce_omul(c.user_id) then raise exception 'Nu poți decide contestația acestui om.'; end if;
  -- o observație de la un șef o judecă cineva de deasupra lui (nu el însuși și nu cei de sub el)
  if c.cheie like 'feedback:%' and not public.is_admin() and exists (
       select 1 from public.feedback f where f.id = split_part(c.cheie, ':', 2)::bigint
         and f.from_user is not null and not public.conduce_omul(f.from_user)) then
    raise exception 'Contestația la o observație de la un șef o decide cineva de deasupra lui.';
  end if;
  if not p_admisa and length(trim(coalesce(p_raspuns, ''))) < 3 then raise exception 'Scrie pe scurt de ce o respingi.'; end if;
  if public.luna_inchisa(c.zi) then raise exception 'Luna e închisă.'; end if;
  update public.contestatii set status = case when p_admisa then 'admisa' else 'respinsa' end,
         raspuns = trim(coalesce(p_raspuns, '')), decis_de = auth.uid(), decis_la = now() where id = p_id;
  insert into public.notifications (user_id, kind, title, body, url) values (c.user_id, 'contestatie',
    case when p_admisa then 'Contestația ta a fost admisă · ' || abs(c.puncte) || ' XP înapoi' else 'Contestația ta a fost respinsă' end,
    c.detaliu || case when trim(coalesce(p_raspuns, '')) <> '' then ' — „' || left(trim(p_raspuns), 160) || '”' else '' end
      || ' · ' || coalesce(public.nume_om(auth.uid()), ''), '#/progres');
end $$;
revoke all on function public.decide_contestatie(bigint, boolean, text) from public, anon;
grant execute on function public.decide_contestatie(bigint, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Raportul lunar (pentru bonus) și închiderea lunii
-- ---------------------------------------------------------------------------
create or replace function public.joc_raport(p_luna date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; l date; sf date; li public.luni_inchise; oameni jsonb; r jsonb;
begin
  if not public.vede_echipa() then raise exception 'Raportul îl văd șefii.'; end if;
  l := date_trunc('month', coalesce(p_luna, azi))::date; sf := (l + interval '1 month')::date - 1;
  select * into li from public.luni_inchise where luna = l;
  if li.luna is not null then
    select coalesce(jsonb_agg(jsonb_build_object('user_id', pl.user_id, 'nume', pl.nume, 'rol', pl.rol, 'locatie', pl.locatie,
             'castigat', pl.castigat, 'pierdut', pl.pierdut, 'net', pl.net, 'surse', pl.surse, 'pierderi', pl.pierderi,
             'ture', pl.ture, 'ture_la_timp', pl.ture_la_timp, 'il_conduc', pl.user_id <> auth.uid(),
             'xp_total', (select coalesce(sum(puncte), 0) from public.xp_evenimente('2000-01-01', azi, pl.user_id))) order by pl.net desc, pl.nume), '[]')
    into oameni from public.puncte_luna pl
    where pl.luna = l and (pl.user_id = auth.uid() or public.conduce_omul(pl.user_id));
  else
    with cine as (select p.user_id, p.full_name, p.role_code from public.profiles p
                  where p.active and (p.user_id = auth.uid() or public.conduce_omul(p.user_id))),
         ev as (select * from public.xp_evenimente(l, least(sf, azi))),
         toate as (select user_id, sum(puncte) as xp from public.xp_evenimente('2000-01-01', azi) group by user_id)
    select coalesce(jsonb_agg(x.j order by (x.j ->> 'net')::int desc, x.j ->> 'nume'), '[]') into oameni from (
      select jsonb_build_object('user_id', c.user_id, 'nume', c.full_name, 'rol', c.role_code, 'locatie', public.locatia_omului(c.user_id),
        'castigat', (select coalesce(sum(puncte) filter (where puncte > 0), 0) from ev where ev.user_id = c.user_id),
        'pierdut', (select coalesce(-sum(puncte) filter (where puncte < 0), 0) from ev where ev.user_id = c.user_id),
        'net', (select coalesce(sum(puncte), 0) from ev where ev.user_id = c.user_id),
        'surse', (select coalesce(jsonb_object_agg(sursa, jsonb_build_object('plus', plus, 'minus', minus)), '{}') from (
                    select sursa, coalesce(sum(puncte) filter (where puncte > 0), 0) as plus, coalesce(-sum(puncte) filter (where puncte < 0), 0) as minus
                    from ev where ev.user_id = c.user_id group by sursa) s),
        'pierderi', (select coalesce(jsonb_agg(jsonb_build_object('zi', zi, 'puncte', puncte, 'detaliu', detaliu) order by la), '[]')
                     from ev where ev.user_id = c.user_id and puncte < 0),
        'xp_total', coalesce((select xp from toate t where t.user_id = c.user_id), 0),
        'ture', (select count(*) from public.shifts s where s.user_id = c.user_id and s.day between l and least(sf, azi) and public.tura_start(s) < now() - interval '10 minutes'),
        'ture_la_timp', (select count(*) from public.shifts s where s.user_id = c.user_id and s.day between l and least(sf, azi)
                          and exists (select 1 from public.clockings k where k.shift_id = s.id and k.clock_in <= public.tura_start(s) + interval '5 minutes')),
        'il_conduc', c.user_id <> auth.uid()) as j
      from cine c) x;
  end if;
  select jsonb_build_object(
    'luna', l, 'inchisa', case when li.luna is null then null else
        jsonb_build_object('la', li.inchis_la, 'de', public.nume_om(li.inchis_de)) end,
    'pot_inchide', public.sees_all() and li.luna is null and now() >= ((sf + 1)::timestamp + interval '3 hours') at time zone 'Europe/Bucharest',
    'pot_redeschide', public.is_admin() and li.luna is not null,
    'oameni', oameni,
    'contestatii', (select coalesce(jsonb_agg(x order by x.created_at), '[]') from (
        select c.id, c.user_id, public.nume_om(c.user_id) as nume, c.cheie, c.zi, c.puncte, c.detaliu, c.motiv, c.created_at,
               not (c.cheie like 'feedback:%' and not public.is_admin() and exists (
                 select 1 from public.feedback f where f.id = split_part(c.cheie, ':', 2)::bigint
                   and f.from_user is not null and not public.conduce_omul(f.from_user))) as pot_decide
        from public.contestatii c where c.status = 'deschisa' and public.conduce_omul(c.user_id)) x),
    'luni', (select jsonb_agg(jsonb_build_object('luna', m::date, 'inchisa', public.luna_inchisa(m::date)) order by m desc)
             from (select date_trunc('month', azi)::date - (k || ' months')::interval as m from generate_series(0, 5) k) y))
  into r;
  return r;
end $$;
revoke all on function public.joc_raport(date) from public, anon;
grant execute on function public.joc_raport(date) to authenticated;

create or replace function public.inchide_luna(p_luna date)
returns int language plpgsql security definer set search_path = public as $$
declare l date := date_trunc('month', p_luna)::date; sf date; n int;
        nume_luna text[] := array['ianuarie','februarie','martie','aprilie','mai','iunie','iulie','august','septembrie','octombrie','noiembrie','decembrie'];
begin
  if not public.sees_all() then raise exception 'Luna o închide GM sau AE.'; end if;
  sf := (l + interval '1 month')::date - 1;
  if now() < ((sf + 1)::timestamp + interval '3 hours') at time zone 'Europe/Bucharest' then
    raise exception 'Luna se poate închide din % ora 03:00.', to_char(sf + 1, 'DD.MM.YYYY'); end if;
  if public.luna_inchisa(l) then raise exception 'Luna e deja închisă.'; end if;
  select count(*) into n from public.contestatii where status = 'deschisa' and zi between l and sf;
  if n > 0 then raise exception 'Mai sunt % contestații nedecise pentru luna asta. Decide-le întâi.', n; end if;
  insert into public.luni_inchise (luna, inchis_de) values (l, auth.uid());
  with ev as (select * from public.xp_evenimente(l, sf)),
       tot as (select user_id, coalesce(sum(puncte) filter (where puncte > 0), 0) as c,
                      coalesce(-sum(puncte) filter (where puncte < 0), 0) as p, coalesce(sum(puncte), 0) as net from ev group by user_id),
       srs as (select user_id, jsonb_object_agg(sursa, jsonb_build_object('plus', plus, 'minus', minus)) as j from (
                 select user_id, sursa, coalesce(sum(puncte) filter (where puncte > 0), 0) as plus,
                        coalesce(-sum(puncte) filter (where puncte < 0), 0) as minus from ev group by user_id, sursa) x group by user_id),
       prd as (select user_id, jsonb_agg(jsonb_build_object('zi', zi, 'puncte', puncte, 'detaliu', detaliu) order by la) as j
               from ev where puncte < 0 group by user_id)
  insert into public.puncte_luna (luna, user_id, nume, rol, locatie, castigat, pierdut, net, surse, pierderi, ture, ture_la_timp)
  select l, t.user_id, coalesce(pr.full_name, '—'), coalesce(pr.role_code, ''), public.locatia_omului(t.user_id),
         t.c, t.p, t.net, coalesce(s.j, '{}'), coalesce(d.j, '[]'),
         (select count(*) from public.shifts h where h.user_id = t.user_id and h.day between l and sf),
         (select count(*) from public.shifts h where h.user_id = t.user_id and h.day between l and sf
            and exists (select 1 from public.clockings k where k.shift_id = h.id and k.clock_in <= public.tura_start(h) + interval '5 minutes'))
  from tot t left join srs s on s.user_id = t.user_id left join prd d on d.user_id = t.user_id
  left join public.profiles pr on pr.user_id = t.user_id;
  get diagnostics n = row_count;
  insert into public.notifications (user_id, kind, title, body, url)
  select pl.user_id, 'luna', 'Luna ' || nume_luna[extract(month from l)::int] || ' s-a închis: ' || pl.net || ' XP',
         'Câștigate ' || pl.castigat || ', pierdute ' || pl.pierdut || '. Cifrele rămân așa pentru bonus.', '#/progres'
  from public.puncte_luna pl join public.profiles p on p.user_id = pl.user_id and p.active where pl.luna = l;
  return n;
end $$;
revoke all on function public.inchide_luna(date) from public, anon;
grant execute on function public.inchide_luna(date) to authenticated;

-- Redeschiderea (doar adminul, dacă s-a închis din greșeală): fotografia se șterge și se reface la următoarea închidere.
create or replace function public.redeschide_luna(p_luna date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Luna o redeschide doar adminul.'; end if;
  delete from public.luni_inchise where luna = date_trunc('month', p_luna)::date;
end $$;
revoke all on function public.redeschide_luna(date) from public, anon;
grant execute on function public.redeschide_luna(date) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Verificările de la 5 minute: omul e anunțat înainte să piardă puncte
-- ---------------------------------------------------------------------------
create or replace function public.verifica_ture()
returns void language plpgsql security definer set search_path = public as $$
declare s record; f record; a record; acum timestamptz := now(); azi date := (now() at time zone 'Europe/Bucharest')::date;
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
    -- 2. la 10 minute după începutul turei, fără clock-in: află șefii, iar omul e avertizat (peste 15 minute pierde 5 XP)
    if acum between s.st + interval '10 minutes' and s.sf
       and not exists (select 1 from public.clockings c where c.user_id = s.user_id and c.space_id = s.space_id
                       and c.clock_in > s.st - interval '3 hours')
       and public.o_data('fara-clock-in:' || s.id) then
      perform public.notifica_sefii(s.user_id, s.space_id, 'intarziere',
        public.nume_loc(s.space_id) || ': ' || public.nume_om(s.user_id) || ' nu a făcut clock-in',
        'Tura începea la ' || to_char(s.starts, 'HH24:MI') || case when s.opens then ' și deschide locația' else '' end || '.', '#/echipa');
      insert into public.notifications (user_id, kind, title, body, url, space_id) values (s.user_id, 'memento',
        'Nu ai făcut clock-in la ' || public.nume_loc(s.space_id),
        'Tura ta a început la ' || to_char(s.starts, 'HH24:MI') || '. Scanează acum codul QR: după 15 minute de întârziere pierzi 5 XP.',
        '#/tura', s.space_id);
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
      join public.roles r on true
      join public.profiles p on p.active and p.role_code = r.code and (r.code in (select public.sefii(om.role_code)) or r.sees_all)
      where t.space_id = f.space_id and t.day = azi and ((f.tip = 'deschidere' and t.opens) or (f.tip = 'inchidere' and t.closes))
        and (r.is_admin or r.sees_all or public.vede_locatia(p.user_id, f.space_id));
      -- … și pe cei programați: dacă fișa rămâne nefăcută până la sfârșitul zilei, pierd 10 XP
      insert into public.notifications (user_id, kind, title, body, url, space_id)
      select distinct t.user_id, 'memento',
             'Fișa de ' || case when f.tip = 'deschidere' then 'deschidere' else 'închidere' end || ' de la ' || public.nume_loc(f.space_id) || ' nu e gata',
             'Termenul era ' || public.ora(f.termen) || '. Termin-o azi: o fișă nefăcută până la sfârșitul zilei înseamnă −10 XP.', '#/tura', f.space_id
      from public.shifts t
      where t.space_id = f.space_id and t.day = azi and ((f.tip = 'deschidere' and t.opens) or (f.tip = 'inchidere' and t.closes));
    end if;
  end loop;

  -- 5. anunțurile neconfirmate: cu 4 ore înainte de termen, omul e avertizat (după 24 de ore pierde 2 XP)
  for a in
    select c.user_id, an.id, an.title, an.space_id from public.anunturi_citiri c join public.anunturi an on an.id = c.anunt_id
    where c.read_at is null and acum between an.created_at + interval '20 hours' and an.created_at + interval '24 hours'
  loop
    if public.o_data('anunt-memento:' || a.id || ':' || a.user_id) then
      insert into public.notifications (user_id, kind, title, body, url, space_id) values (a.user_id, 'memento',
        'Mai ai puțin timp să confirmi un anunț', '„' || a.title || '” · apasă „Am citit”; după 24 de ore neconfirmat pierzi 2 XP.',
        '#/mesaje', a.space_id);
    end if;
  end loop;
  delete from public.notificari_trimise where at < now() - interval '3 days';
end $$;
revoke all on function public.verifica_ture() from public, anon, authenticated;

do $$ declare t text; begin
  foreach t in array array['semnalari', 'anunturi', 'anunturi_citiri', 'feedback', 'contestatii'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
              when undefined_object then raise notice 'publicația supabase_realtime lipsește (mediu local)';
    end;
  end loop;
end $$;
