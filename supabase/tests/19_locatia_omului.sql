-- Locația fiecărui om (0019): un RL legat de Porumbescu vede și primește doar de acolo. Rulează după 0019.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'loc.' || k || '@x' from (values ('c1'), ('c2'), ('c3'), ('c4')) v (k)
on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'loc.' || k, n, r from (values
  ('c1', 'Estera RL', 'RL'), ('c2', 'Alt RL', 'RL'), ('c3', 'Vio V', 'V'), ('c4', 'Gabi GM', 'GM')) v (k, n, r)
on conflict do nothing;
delete from public.profile_spaces where user_id::text like '00000000-0000-0000-0000-0000000000c%';
delete from public.notifications; delete from public.clockings where user_id::text like '00000000-0000-0000-0000-0000000000c%';
create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create temp table rez (test text, ok boolean);
create temp table cod as select space_id, token from public.space_qr;
grant all on rez, cod to authenticated, anon;
set role authenticated;

select pg_temp.ca('c4');
insert into public.profile_spaces (user_id, space_id) values ('00000000-0000-0000-0000-0000000000c1', 'porumbescu');
insert into rez select 'Adminul leagă RL-ul de Porumbescu', count(*) = 1 from public.profile_spaces;
select pg_temp.ca('c1');
insert into rez select 'RL-ul legat vede doar Porumbescu', array_agg(id order by id) = array['porumbescu'] from public.spaces;
insert into rez select 'RL-ul legat își vede locația', count(*) = 1 from public.profile_spaces;
do $$ begin
  insert into public.profile_spaces (user_id, space_id) values ('00000000-0000-0000-0000-0000000000c1', 'fructus');
  insert into rez values ('RL-ul nu-și adaugă singur locații', false);
exception when others then insert into rez values ('RL-ul nu-și adaugă singur locații', true); end $$;
select pg_temp.ca('c2');
insert into rez select 'RL-ul fără locații vede toate magazinele', count(*) = 3 from public.spaces where type = 'magazin';
insert into rez select 'RL-ul nu vede legăturile altora', count(*) = 0 from public.profile_spaces;

-- Notificări: vânzătorul face clock-in la Fructus → RL-ul legat de Porumbescu nu află, celălalt RL da
select pg_temp.ca('c3');
select public.pontaj_intrare('fructus', (select token from cod where space_id = 'fructus'));
reset role;
insert into rez select 'Clock-in la Fructus: RL-ul de Porumbescu nu primește', not exists (select 1 from public.notifications
  where user_id = '00000000-0000-0000-0000-0000000000c1');
insert into rez select 'Clock-in la Fructus: RL-ul fără locații primește', exists (select 1 from public.notifications
  where user_id = '00000000-0000-0000-0000-0000000000c2');
set role authenticated;
select pg_temp.ca('c3');
select public.pontaj_iesire('fructus', (select token from cod where space_id = 'fructus'));
select public.pontaj_intrare('porumbescu', (select token from cod where space_id = 'porumbescu'));
reset role;
insert into rez select 'Clock-in la Porumbescu: RL-ul de Porumbescu primește', exists (select 1 from public.notifications
  where user_id = '00000000-0000-0000-0000-0000000000c1' and kind = 'clock_in');
reset role;
-- conturile testului dispar, ca să nu schimbe numărătorile celorlalte teste
delete from public.profiles where user_id::text like '00000000-0000-0000-0000-0000000000c%';
delete from auth.users where id::text like '00000000-0000-0000-0000-0000000000c%';
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
