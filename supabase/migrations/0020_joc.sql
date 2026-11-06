-- =============================================================================
-- Ghidul echipei Madame Magnifique · Jocul echipei: puncte (XP), niveluri, serii, scoruri
--
-- Se rulează după 0019, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Punctele se calculează din ce se întâmplă deja în aplicație (nu se introduc de mână):
--   punctualitate   clock-in la timp +10 (≤ 5 min după începutul turei), +3 (≤ 15 min), fără program +2
--   fișe            pas făcut +2; fișă terminată +15 la termen / +5 după; +10 dacă niciun pas nefăcut
--   academia        lecție parcursă +5; test trecut (prima dată) +30
--   probleme        pas nefăcut sau observație semnalată +5; rezolvată: +10 celui care a semnalat-o,
--                   +5 celui care a rezolvat-o (RL / șeful, din Echipa → Azi)
-- Fiecare își vede punctele lui și scorul echipei; RL-ul (pentru locația lui), GM și AE văd tot.
-- Tot aici: șefii văd programul și pontajul colegilor doar la locațiile lor.
-- =============================================================================

-- Cine a scris observația fișei (pentru punctele de la „probleme”).
alter table public.checklist_runs add column if not exists note_by uuid references public.profiles (user_id) on delete set null;
create or replace function public.fisa_protejata()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and current_user = 'authenticated' then
    new.cheie := old.cheie; new.doc_id := old.doc_id; new.title := old.title; new.space_id := old.space_id;
    new.day := old.day; new.steps := old.steps; new.due_at := old.due_at; new.started_by := old.started_by;
    new.started_at := old.started_at; new.finished_at := old.finished_at; new.finished_by := old.finished_by;
    new.note_by := case when new.note is distinct from old.note then auth.uid() else old.note_by end;
  end if;
  return new;
end $$;

-- Programul și pontajul colegilor: șeful le vede doar la locațiile lui (un RL legat de Porumbescu nu vede alte magazine).
drop policy if exists "îmi văd turele, șefii le văd pe ale echipei" on public.shifts;
create policy "îmi văd turele, șefii le văd pe ale echipei" on public.shifts for select to authenticated
  using (public.is_member() and (user_id = auth.uid() or public.sees_all()
         or (public.poate_conduce(user_id) and public.can_see_space(space_id)) or public.am_tura(space_id, day)));
drop policy if exists "pontajul: al meu, al echipei pentru șefi" on public.clockings;
create policy "pontajul: al meu, al echipei pentru șefi" on public.clockings for select to authenticated
  using (public.is_member() and (user_id = auth.uid() or public.sees_all()
         or (public.poate_conduce(user_id) and public.can_see_space(space_id)) or public.in_tura(space_id)));

-- ---------------------------------------------------------------------------
-- Problemele rezolvate (din „De rezolvat”)
-- ---------------------------------------------------------------------------
create table if not exists public.probleme_rezolvate (
  id          bigint generated always as identity primary key,
  run_id      bigint not null references public.checklist_runs (id) on delete cascade,
  idx         int,                                    -- pasul; gol = observația fișei
  resolved_by uuid default auth.uid() references public.profiles (user_id) on delete set null,
  resolved_at timestamptz not null default now(),
  note        text not null default ''
);
create unique index if not exists probleme_rezolvate_una on public.probleme_rezolvate (run_id, coalesce(idx, -1));
alter table public.probleme_rezolvate enable row level security;
revoke all on public.probleme_rezolvate from anon, authenticated;
grant select, insert, delete on public.probleme_rezolvate to authenticated;
grant all on public.probleme_rezolvate to service_role;
drop policy if exists "rezolvările: echipa locației" on public.probleme_rezolvate;
drop policy if exists "rezolvă șeful care vede locația" on public.probleme_rezolvate;
drop policy if exists "anulează șeful care vede locația" on public.probleme_rezolvate;
create policy "rezolvările: echipa locației" on public.probleme_rezolvate for select to authenticated
  using (exists (select 1 from public.checklist_runs r where r.id = run_id and public.is_member()
                 and (public.can_see_space(r.space_id) or public.sees_all())));
create policy "rezolvă șeful care vede locația" on public.probleme_rezolvate for insert to authenticated
  with check (resolved_by = auth.uid() and public.vede_echipa() and exists (select 1 from public.checklist_runs r
              where r.id = run_id and (public.can_see_space(r.space_id) or public.sees_all())));
create policy "anulează șeful care vede locația" on public.probleme_rezolvate for delete to authenticated
  using (public.vede_echipa() and exists (select 1 from public.checklist_runs r
         where r.id = run_id and (public.can_see_space(r.space_id) or public.sees_all())));

-- Cine a semnalat problema află că s-a rezolvat.
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
      'Problema semnalată de tine e rezolvată · +10 XP', coalesce(pas, '') || ' · ' || coalesce(public.nume_om(new.resolved_by), ''),
      '#/tura', r.space_id);
  end if;
  return new;
end $$;
drop trigger if exists problema_rezolvata on public.probleme_rezolvate;
create trigger problema_rezolvata after insert on public.probleme_rezolvate for each row execute function public.problema_rezolvata();

-- ---------------------------------------------------------------------------
-- Punctele
-- ---------------------------------------------------------------------------
-- Locația „de acasă” a omului: cea din Admin, altfel ultima la care a făcut clock-in.
create or replace function public.locatia_omului(u uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select space_id from public.profile_spaces where user_id = u order by space_id limit 1),
                  (select space_id from public.clockings where user_id = u order by clock_in desc limit 1))
$$;
revoke all on function public.locatia_omului(uuid) from public, anon, authenticated;

create or replace function public.xp_evenimente(p_de date, p_pana date)
returns table (user_id uuid, space_id text, zi date, sursa text, puncte int, detaliu text, la timestamptz)
language sql stable security definer set search_path = public as $$
  -- clock-in
  select c.user_id, c.space_id, (c.clock_in at time zone 'Europe/Bucharest')::date, 'punctualitate',
         case when s.id is null then 2
              when c.clock_in <= public.tura_start(s) + interval '5 minutes' then 10
              when c.clock_in <= public.tura_start(s) + interval '15 minutes' then 3 else 0 end,
         case when s.id is null then 'Clock-in fără program'
              when c.clock_in <= public.tura_start(s) + interval '5 minutes' then 'Clock-in la timp'
              else 'Clock-in cu întârziere' end, c.clock_in
  from public.clockings c left join public.shifts s on s.id = c.shift_id
  where (c.clock_in at time zone 'Europe/Bucharest')::date between p_de and p_pana
  union all
  -- pași făcuți
  select m.marked_by, r.space_id, r.day, 'fise', 2, 'Pas făcut · ' || r.title, m.at
  from public.checklist_marks m join public.checklist_runs r on r.id = m.run_id
  where m.status = 'facut' and m.marked_by is not null and r.day between p_de and p_pana
  union all
  -- fișe terminate
  select r.finished_by, r.space_id, r.day, 'fise',
         (case when r.due_at is null or r.finished_at <= r.due_at then 15 else 5 end)
         + (case when not exists (select 1 from public.checklist_marks m where m.run_id = r.id and m.status = 'nefacut') then 10 else 0 end),
         r.title || case when r.due_at is null or r.finished_at <= r.due_at then ' · gata la termen' else ' · gata după termen' end, r.finished_at
  from public.checklist_runs r
  where r.finished_at is not null and r.finished_by is not null and r.day between p_de and p_pana
  union all
  -- Academia: lecții
  select lp.user_id, public.locatia_omului(lp.user_id), (lp.done_at at time zone 'Europe/Bucharest')::date, 'academia', 5, 'Lecție parcursă', lp.done_at
  from public.lesson_progress lp
  where (lp.done_at at time zone 'Europe/Bucharest')::date between p_de and p_pana
  union all
  -- Academia: primul test trecut la fiecare curs
  select q.user_id, public.locatia_omului(q.user_id), (q.created_at at time zone 'Europe/Bucharest')::date, 'academia', 30, 'Test trecut · ' || c.title, q.created_at
  from (select distinct on (a.user_id, a.course_id) a.* from public.quiz_attempts a where a.passed order by a.user_id, a.course_id, a.created_at) q
  join public.courses c on c.id = q.course_id
  where (q.created_at at time zone 'Europe/Bucharest')::date between p_de and p_pana
  union all
  -- probleme semnalate: pas nefăcut sau notă
  select m.marked_by, r.space_id, r.day, 'probleme', 5, 'Problemă semnalată · ' || r.title, m.at
  from public.checklist_marks m join public.checklist_runs r on r.id = m.run_id
  where (m.status = 'nefacut' or m.note <> '') and m.marked_by is not null and r.day between p_de and p_pana
  union all
  -- observații trimise din fișă
  select r.note_by, r.space_id, r.day, 'probleme', 5, 'Observație trimisă · ' || r.title, coalesce(r.finished_at, r.started_at)
  from public.checklist_runs r
  where r.note <> '' and r.note_by is not null and r.day between p_de and p_pana
  union all
  -- problemă rezolvată: celui care a semnalat-o
  select coalesce(m.marked_by, r.note_by), r.space_id, (pr.resolved_at at time zone 'Europe/Bucharest')::date, 'probleme', 10,
         'Problema ta a fost rezolvată · ' || r.title, pr.resolved_at
  from public.probleme_rezolvate pr join public.checklist_runs r on r.id = pr.run_id
  left join public.checklist_marks m on m.run_id = pr.run_id and m.idx = pr.idx
  where coalesce(m.marked_by, r.note_by) is not null and (pr.resolved_at at time zone 'Europe/Bucharest')::date between p_de and p_pana
  union all
  -- problemă rezolvată: celui care a rezolvat-o
  select pr.resolved_by, r.space_id, (pr.resolved_at at time zone 'Europe/Bucharest')::date, 'probleme', 5,
         'Ai rezolvat o problemă · ' || r.title, pr.resolved_at
  from public.probleme_rezolvate pr join public.checklist_runs r on r.id = pr.run_id
  where pr.resolved_by is not null and (pr.resolved_at at time zone 'Europe/Bucharest')::date between p_de and p_pana
$$;
revoke all on function public.xp_evenimente(date, date) from public, anon, authenticated;

-- Seria de ture la timp: cea de acum și cea mai lungă.
create or replace function public.serie_punctualitate(u uuid)
returns table (curenta int, maxima int)
language sql stable security definer set search_path = public as $$
  with t as (
    select s.id, row_number() over (order by public.tura_start(s)) as nr,
           exists (select 1 from public.clockings c where c.shift_id = s.id
                   and c.clock_in <= public.tura_start(s) + interval '5 minutes') as ok
    from public.shifts s where s.user_id = u and public.tura_start(s) < now() - interval '10 minutes'
  ), g as (
    select ok, nr - row_number() over (partition by ok order by nr) as grup, nr from t
  ), serii as (
    select grup, count(*) as lung, max(nr) as ultima from g where ok group by grup
  )
  select coalesce((select lung from serii where ultima = (select max(nr) from t)), 0)::int,
         coalesce((select max(lung) from serii), 0)::int
$$;
revoke all on function public.serie_punctualitate(uuid) from public, anon, authenticated;

-- Scorul unei locații pe o perioadă: componentele (în %) și media lor.
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
  ), c as (
    select (select count(*) from ture) as ture, (select count(*) filter (where la_timp) from ture) as ture_la_timp,
           (select count(*) from fise) as fise, (select count(*) filter (where finished_at <= due_at) from fise) as fise_la_termen,
           (select count(*) from pasi) as pasi, (select count(*) filter (where status = 'facut') from pasi) as pasi_facuti,
           (select count(*) from semnalate) as probleme,
           (select count(*) from semnalate s where exists (select 1 from public.probleme_rezolvate pr
              where pr.run_id = s.run_id and coalesce(pr.idx, -1) = coalesce(s.idx, -1))) as rezolvate,
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

create or replace function public.luni_sapt(d date)
returns date language sql immutable as $$ select d - (extract(isodow from d)::int - 1) $$;

-- ---------------------------------------------------------------------------
-- Ce vede fiecare
-- ---------------------------------------------------------------------------
-- Progresul meu: XP, serie, contoare pentru insigne și scorul echipei mele.
create or replace function public.joc_eu()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; luni date; loc text; r jsonb;
begin
  if not public.is_member() then return null; end if;
  luni := public.luni_sapt(azi); loc := public.locatia_omului(auth.uid());
  with ev as (select * from public.xp_evenimente('2000-01-01', azi) where user_id = auth.uid())
  select jsonb_build_object(
    'xp', (select coalesce(sum(puncte), 0) from ev),
    'xp_saptamana', (select coalesce(sum(puncte), 0) from ev where zi >= luni),
    'xp_azi', (select coalesce(sum(puncte), 0) from ev where zi = azi),
    'surse', (select coalesce(jsonb_object_agg(sursa, p), '{}') from (select sursa, sum(puncte) p from ev where zi >= luni group by sursa) x),
    'ultimele', (select coalesce(jsonb_agg(x order by x.la desc), '[]') from (select detaliu, puncte, la from ev where puncte > 0 order by la desc limit 40) x),
    'serie', (select curenta from public.serie_punctualitate(auth.uid())),
    'serie_max', (select maxima from public.serie_punctualitate(auth.uid())),
    'contoare', jsonb_build_object(
      'fise_terminate', (select count(*) from public.checklist_runs where finished_by = auth.uid()),
      'deschideri_la_timp', (select count(*) from public.checklist_runs where finished_by = auth.uid() and title ilike 'deschidere%'
                              and (due_at is null or finished_at <= due_at)),
      'fara_cusur', (select count(*) from public.checklist_runs r where r.finished_by = auth.uid()
                     and not exists (select 1 from public.checklist_marks m where m.run_id = r.id and m.status = 'nefacut')),
      'clockin_la_timp', (select count(*) from ev where sursa = 'punctualitate' and puncte = 10),
      'probleme_rezolvate', (select count(*) from ev where detaliu like 'Problema ta a fost rezolvată%'),
      'teste_trecute', (select count(*) from ev where detaliu like 'Test trecut%'),
      'lectii', (select count(*) from ev where detaliu = 'Lecție parcursă')),
    'locatie', loc,
    'echipa', case when loc is null then null else jsonb_build_object(
      'saptamana', public.scor_locatie(loc, luni, azi),
      'trecuta', public.scor_locatie(loc, luni - 7, luni - 1),
      'xp_total', (select coalesce(sum(puncte), 0) from public.xp_evenimente('2000-01-01', azi) e where e.space_id = loc)) end)
  into r;
  return r;
end $$;
revoke all on function public.joc_eu() from public, anon;
grant execute on function public.joc_eu() to authenticated;

-- Tabloul unei locații, pentru șefi: scorurile, oamenii (clasament), ce s-a întâmplat azi.
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
        'serie', (select curenta from public.serie_punctualitate(o.user_id))) order by o.full_name), '[]')
      from oameni o left join toate t on t.user_id = o.user_id),
    'azi', (select coalesce(jsonb_agg(x order by x.la desc), '[]') from (
        select e.user_id, p.full_name as nume, e.detaliu, e.puncte, e.la from ev e join public.profiles p on p.user_id = e.user_id
        where e.space_id = p_space and e.zi = azi and e.puncte > 0 order by e.la desc limit 30) x))
  into r;
  return r;
end $$;
revoke all on function public.joc_echipa(text) from public, anon;
grant execute on function public.joc_echipa(text) to authenticated;

-- Clasamentul magazinelor (RL-ii, GM, AE): scorul săptămânii, al celei trecute și al lunii.
create or replace function public.joc_locatii()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; luni date;
begin
  if not public.vede_echipa() then raise exception 'Clasamentul îl văd șefii.'; end if;
  luni := public.luni_sapt(azi);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'nume', s.name,
      'saptamana', public.scor_locatie(s.id, luni, azi),
      'trecuta', public.scor_locatie(s.id, luni - 7, luni - 1),
      'luna', public.scor_locatie(s.id, date_trunc('month', azi)::date, azi)) order by s.position), '[]')
    from public.spaces s where s.type = 'magazin');
end $$;
revoke all on function public.joc_locatii() from public, anon;
grant execute on function public.joc_locatii() to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.probleme_rezolvate;
exception when duplicate_object then null;
          when undefined_object then raise notice 'publicația supabase_realtime lipsește (mediu local)';
end $$;
