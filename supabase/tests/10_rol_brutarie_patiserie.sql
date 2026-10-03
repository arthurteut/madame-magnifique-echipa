-- Rolul PBP (0010): vede ce văd PBR și PPT. Rulează după 0009 și 0010.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000019', 'pbp@x') on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
values ('00000000-0000-0000-0000-000000000019', 'test.pbp', 'Test PBP', 'PBP') on conflict do nothing;
create temp table rez (test text, ok boolean);
grant all on rez to authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000019', false);
insert into rez select 'PBP: ambele laboratoare', array_agg(id order by id) = array['laborator-fructus', 'peciu-nou'] from public.spaces;
insert into rez select 'PBP citește ghidul brutarului', count(*) > 0 from public.handbook_chapters;
insert into rez select 'PBP vede rolurile PBR și PPT', count(*) = 2 from public.roles where code in ('PBR', 'PPT');
insert into rez select 'PBP nu vede magazinele', not exists (select 1 from public.spaces where type = 'magazin');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
insert into rez select 'DP vede rolul PBP', count(*) = 1 from public.roles where code = 'PBP';
reset role;
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
