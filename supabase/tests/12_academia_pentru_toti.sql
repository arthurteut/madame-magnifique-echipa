-- Academia pentru toată echipa (0012). Rulează după 05 (cursurile de test A–D), 0008 și 0012.
-- Testele 05, 07 și 08 descriu accesul de dinainte de 0012 (se rulează înainte de 0012).
\set ON_ERROR_STOP off
\pset footer off
create temp table rez (test text, ok boolean);
grant all on rez to authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000007', false);
insert into rez select 'V vede toate cursurile publicate, nu ciorna', count(*) = 3 and not bool_or(not published) from public.courses;
insert into rez select 'V citește ghidul brutarului', count(*) > 0 from public.handbook_chapters;
insert into rez select 'V nu vede răspunsurile', count(*) = 0 from public.quiz_answers;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000015', false);
insert into rez select 'BRT vede cursurile publicate', count(*) = 3 from public.courses;
insert into rez select 'BRT tot nu vede spații', count(*) = 0 from public.spaces;
insert into rez select 'BRT tot nu vede proceduri', count(*) = 0 from public.procedures;
reset role;
insert into rez select 'Toate rolurile au Academia', (select count(*) from public.roles) * 2 =
  (select count(*) from public.role_section_access where section in ('cursuri', 'brutar'));
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
