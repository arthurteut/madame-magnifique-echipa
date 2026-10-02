-- Rolul Brutar (0008): vede doar ghidul brutarului. Rulează după 0008.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000015', 'test.brt@x') on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
values ('00000000-0000-0000-0000-000000000015', 'test.brt', 'Test Brutar', 'BRT') on conflict do nothing;
create temp table rez (test text, ok boolean);
grant all on rez to authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000015', false);
insert into rez select 'BRT citește ghidul brutarului', count(*) > 0 from public.handbook_chapters;
insert into rez select 'BRT citește rețetele casei', count(*) > 0 from public.bread_recipes;
insert into rez select 'BRT nu vede spații', count(*) = 0 from public.spaces;
insert into rez select 'BRT nu vede proceduri', count(*) = 0 from public.procedures;
insert into rez select 'BRT nu vede procedurile verificate', count(*) = 0 from public.procedure_docs;
insert into rez select 'BRT nu vede cursuri', count(*) = 0 from public.courses;
insert into rez select 'BRT nu vede „Cum funcționează”', count(*) = 0 from public.guide_sections;
insert into rez select 'BRT are doar pagina brutar', array_agg(section) = array['brutar'] from public.role_section_access;
reset role;
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
