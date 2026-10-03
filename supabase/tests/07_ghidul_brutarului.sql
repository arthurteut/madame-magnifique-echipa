-- Ghidul brutarului (0007): cine citește capitolele. Rulează după 02, 0004 și 0007.
-- Conturi: GM = ...000000, DP = ...000001, V = ...000007; AE = ...000014 (din 05).
\set ON_ERROR_STOP off
\pset footer off
create or replace function pg_temp.ca(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-' || u, false); end $$;
insert into public.handbook_chapters (slug, position, title, body) values ('test01', 99, 'Test', 'x')
on conflict (slug) do nothing;
create temp table rez (test text, ok boolean);
grant all on rez to authenticated, anon;
set role authenticated;
select pg_temp.ca('000000000001');
insert into rez select 'DP citește ghidul', count(*) >= 1 from public.handbook_chapters where slug = 'test01';
select pg_temp.ca('000000000007');
insert into rez select 'V nu citește ghidul', count(*) = 0 from public.handbook_chapters;
select pg_temp.ca('000000000014');
insert into rez select 'AE citește ghidul', count(*) >= 1 from public.handbook_chapters where slug = 'test01';
select pg_temp.ca('000000000000');
insert into rez select 'GM citește ghidul', count(*) >= 1 from public.handbook_chapters where slug = 'test01';
select pg_temp.ca('000000000001');
update public.handbook_chapters set body = 'hack' where slug = 'test01';
reset role;
insert into rez select 'DP nu modifică', body = 'x' from public.handbook_chapters where slug = 'test01';
insert into rez select 'Pagina brutar: DP, SP, GD, GM, AE (+ rolurile din 0008–0011)', array_agg(role_code order by role_code) @> array['AE', 'DP', 'GD', 'GM', 'SP']
  and not 'V' = any (array_agg(role_code))
  from public.role_section_access where section = 'brutar';
set role anon;
do $$ begin perform 1 from public.handbook_chapters; insert into rez values ('Anonimul nu citește', false);
exception when others then insert into rez values ('Anonimul nu citește', true); end $$;
reset role;
delete from public.handbook_chapters where slug = 'test01';
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
