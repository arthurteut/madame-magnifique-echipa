-- Jocul echipei (0020): puncte din clock-in, fișe și probleme rezolvate; cine vede ce. Rulează după 0020.
-- Conturi proprii testului (…00000000d1 …), șterse la final.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'joc.' || k || '@x' from (values ('d1'), ('d2'), ('d3'), ('d4')) v (k)
on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'joc.' || k, n, r from (values
  ('d1', 'Vera V', 'V'), ('d2', 'Rita RL', 'RL'), ('d3', 'Gelu GM', 'GM'), ('d4', 'Fănel V', 'V')) v (k, n, r)
on conflict do nothing;
insert into public.profile_spaces (user_id, space_id) values
  ('00000000-0000-0000-0000-0000000000d1', 'porumbescu'), ('00000000-0000-0000-0000-0000000000d2', 'porumbescu'),
  ('00000000-0000-0000-0000-0000000000d4', 'fructus')
on conflict do nothing;
delete from public.notifications; delete from public.clockings; delete from public.shifts; delete from public.checklist_runs;
create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create or replace function pg_temp.u(k text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || k)::uuid $$;
create temp table rez (test text, ok boolean);
create temp table cod as select token from public.space_qr where space_id = 'porumbescu';
grant all on rez, cod to authenticated, anon;
set role authenticated;

-- RL-ul programează tura, vânzătoarea vine la timp
select pg_temp.ca('d2');
insert into public.shifts (user_id, space_id, day, starts, ends, opens)
select pg_temp.u('d1'), 'porumbescu', (n at time zone 'Europe/Bucharest')::date, (n at time zone 'Europe/Bucharest')::time,
       ((n + interval '6 hours') at time zone 'Europe/Bucharest')::time, true
from (select now() - interval '2 minutes' as n) x;
select pg_temp.ca('d1');
select public.pontaj_intrare('porumbescu', (select token from cod));
insert into rez select 'Clock-in la timp: +10 XP', (public.joc_eu() ->> 'xp')::int = 10;

-- Fișa: 2 pași făcuți, unul nefăcut cu notă, apoi o observație
insert into public.checklist_runs (cheie, title, space_id, steps)
values ('doc:test-joc', 'Deschiderea', 'porumbescu', '[{"t":"Unu"},{"t":"Doi"},{"t":"Frigiderul"}]');
insert into public.checklist_marks (run_id, idx, status) select id, 0, 'facut' from public.checklist_runs;
insert into public.checklist_marks (run_id, idx, status) select id, 1, 'facut' from public.checklist_runs;
insert into public.checklist_marks (run_id, idx, status, note) select id, 2, 'nefacut', 'Nu pornește' from public.checklist_runs;
-- 10 + 2×2 pași + 15 fișa la termen + 5 problemă semnalată (fără bonusul „fără cusur”)
insert into rez select 'Fișa terminată: pași, fișă, problemă semnalată', (public.joc_eu() ->> 'xp')::int = 34;
update public.checklist_runs set note = 'Lipsește laptele';
insert into rez select 'Observația îi poartă numele', note_by = pg_temp.u('d1') from public.checklist_runs;
insert into rez select 'Observația: +5 XP', (public.joc_eu() ->> 'xp')::int = 39;
do $$ begin
  insert into public.probleme_rezolvate (run_id, idx) select id, 2 from public.checklist_runs;
  insert into rez values ('Vânzătoarea nu-și rezolvă singură problema', false);
exception when others then insert into rez values ('Vânzătoarea nu-și rezolvă singură problema', true); end $$;
do $$ begin
  perform public.joc_echipa('porumbescu');
  insert into rez values ('Vânzătoarea nu vede tabloul echipei', false);
exception when others then insert into rez values ('Vânzătoarea nu vede tabloul echipei', true); end $$;
do $$ begin
  perform public.joc_locatii();
  insert into rez values ('Vânzătoarea nu vede clasamentul magazinelor', false);
exception when others then insert into rez values ('Vânzătoarea nu vede clasamentul magazinelor', true); end $$;

-- RL-ul rezolvă problema
select pg_temp.ca('d2');
insert into public.probleme_rezolvate (run_id, idx) select id, 2 from public.checklist_runs;
insert into rez select 'RL-ul rezolvă problema', count(*) = 1 and bool_and(resolved_by = pg_temp.u('d2')) from public.probleme_rezolvate;
do $$ begin
  insert into public.probleme_rezolvate (run_id, idx) select id, 2 from public.checklist_runs;
  insert into rez values ('O problemă se rezolvă o singură dată', false);
exception when others then insert into rez values ('O problemă se rezolvă o singură dată', true); end $$;
insert into rez select 'RL-ul: +5 XP pentru rezolvare', (public.joc_eu() ->> 'xp')::int = 5;
insert into rez select 'Tabloul Porumbescu: Vera are 49 XP', (o ->> 'xp')::int = 49
  from jsonb_array_elements(public.joc_echipa('porumbescu') -> 'oameni') o where o ->> 'nume' = 'Vera V';
insert into rez select 'Scorul săptămânii: 2 din 3 pași, 1 din 2 probleme rezolvate',
  (s ->> 'pasi_facuti')::int = 2 and (s ->> 'pasi')::int = 3 and (s ->> 'rezolvate')::int = 1 and (s ->> 'probleme')::int = 2
  and (s ->> 'scor')::int = 58
  from (select public.joc_echipa('porumbescu') -> 'saptamana' as s) x;
insert into rez select 'Feed-ul zilei are ce s-a întâmplat', jsonb_array_length(public.joc_echipa('porumbescu') -> 'azi') >= 6;
do $$ begin
  perform public.joc_echipa('fructus');
  insert into rez values ('RL-ul de Porumbescu nu vede tabloul Fructus', false);
exception when others then insert into rez values ('RL-ul de Porumbescu nu vede tabloul Fructus', true); end $$;
insert into rez select 'RL-ul vede clasamentul magazinelor', jsonb_array_length(public.joc_locatii()) = 3;
reset role;
insert into public.shifts (user_id, space_id, day, starts, ends) values (pg_temp.u('d4'), 'fructus', current_date + 2, '08:00', '16:00');
set role authenticated;
select pg_temp.ca('d2');
insert into rez select 'RL-ul de Porumbescu nu vede programul de la Fructus', count(*) = 0 from public.shifts where space_id = 'fructus';
insert into rez select 'RL-ul își vede programul de la Porumbescu', count(*) = 1 from public.shifts where space_id = 'porumbescu';

select pg_temp.ca('d1');
insert into rez select 'Rezolvarea: +10 XP celui care a semnalat', (public.joc_eu() ->> 'xp')::int = 49;
insert into rez select 'Contoarele insignelor', (c ->> 'fise_terminate')::int = 1 and (c ->> 'clockin_la_timp')::int = 1
  and (c ->> 'probleme_rezolvate')::int = 1 and (c ->> 'fara_cusur')::int = 0
  from (select public.joc_eu() -> 'contoare' as c) x;
insert into rez select 'Vânzătoarea vede scorul echipei ei', public.joc_eu() -> 'echipa' -> 'saptamana' ? 'scor'
  and public.joc_eu() ->> 'locatie' = 'porumbescu';
select pg_temp.ca('d4');
insert into rez select 'Altă locație nu vede rezolvările de la Porumbescu', count(*) = 0 from public.probleme_rezolvate;
select pg_temp.ca('d3');
insert into rez select 'GM-ul vede tabloul oricărei locații', public.joc_echipa('fructus') ? 'saptamana';

-- Seria: trei ture trecute, prima cu întârziere, ultimele două la timp
reset role;
insert into rez select 'Notificarea „problema ta e rezolvată” ajunge la Vera', count(*) = 1 from public.notifications
  where kind = 'problema_rezolvata' and user_id = pg_temp.u('d1');
with t as (
  insert into public.shifts (user_id, space_id, day, starts, ends)
  select pg_temp.u('d4'), 'fructus', current_date - k, '08:00', '16:00' from generate_series(1, 3) k returning *
)
insert into public.clockings (user_id, space_id, shift_id, clock_in, clock_out)
select user_id, space_id, id, public.tura_start(t) + case when day = current_date - 3 then interval '30 minutes' else interval '1 minute' end,
       public.tura_sfarsit(t) from t;
insert into rez select 'Seria: 2 ture la timp acum, maximum 2', curenta = 2 and maxima = 2 from public.serie_punctualitate(pg_temp.u('d4'));

set role anon;
do $$ begin perform public.joc_eu(); insert into rez values ('Anonimul nu are joc', false);
exception when others then insert into rez values ('Anonimul nu are joc', true); end $$;
reset role;
-- conturile testului dispar, ca să nu schimbe numărătorile celorlalte teste
delete from public.checklist_runs where cheie = 'doc:test-joc';
delete from public.notifications; delete from public.shifts where user_id::text like '00000000-0000-0000-0000-0000000000d%';
delete from public.profiles where user_id::text like '00000000-0000-0000-0000-0000000000d%';
delete from auth.users where id::text like '00000000-0000-0000-0000-0000000000d%';
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
