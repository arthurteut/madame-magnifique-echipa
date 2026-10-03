-- Rolurile de producție (0009): ce vede fiecare. Rulează după 02 și 0009.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000016', 'ppt@x'), ('00000000-0000-0000-0000-000000000017', 'pcf@x'),
  ('00000000-0000-0000-0000-000000000018', 'pbr@x') on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code) values
  ('00000000-0000-0000-0000-000000000016', 'test.ppt', 'Test PPT', 'PPT'),
  ('00000000-0000-0000-0000-000000000017', 'test.pcf', 'Test PCF', 'PCF'),
  ('00000000-0000-0000-0000-000000000018', 'test.pbr', 'Test PBR', 'PBR') on conflict do nothing;
create or replace function pg_temp.ca(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-' || u, false); end $$;
create temp table rez (test text, ok boolean);
grant all on rez to authenticated;
set role authenticated;
select pg_temp.ca('000000000016');
insert into rez select 'PPT: Peciu Nou și Laboratorul Fructus', array_agg(id order by id) = array['laborator-fructus', 'peciu-nou'] from public.spaces;
insert into rez select 'PPT nu are ghidul brutarului', count(*) = 0 from public.handbook_chapters;
insert into rez select 'PPT: roluri, proceduri, cursuri, ghid', array_agg(section order by section) = array['cursuri', 'ghid', 'proceduri', 'roluri'] from public.role_section_access;
select pg_temp.ca('000000000017');
insert into rez select 'PCF: doar Laboratorul Fructus', array_agg(id) = array['laborator-fructus'] from public.spaces;
select pg_temp.ca('000000000018');
insert into rez select 'PBR: doar Peciu Nou', array_agg(id) = array['peciu-nou'] from public.spaces;
insert into rez select 'PBR citește ghidul brutarului', count(*) > 0 from public.handbook_chapters;
insert into rez select 'PBR nu vede magazinele', not exists (select 1 from public.spaces where type = 'magazin');
select pg_temp.ca('000000000001');
insert into rez select 'DP vede rolurile noi', count(*) = 3 from public.roles where code in ('PPT', 'PCF', 'PBR');
select pg_temp.ca('000000000002');
insert into rez select 'SP vede rolurile noi', count(*) = 3 from public.roles where code in ('PPT', 'PCF', 'PBR');
select pg_temp.ca('000000000007');
insert into rez select 'V nu vede rolurile noi', count(*) = 0 from public.roles where code in ('PPT', 'PCF', 'PBR');
reset role;
insert into rez select 'Laboratoarele: „Cine lucrează aici”', count(*) = 4 from public.space_roles where role_code in ('PPT', 'PCF', 'PBR');
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
