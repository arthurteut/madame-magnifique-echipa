-- Jurnalul de croissant (0018): patiseria și șefii citesc și scriu, restul nu. Rulează după 0018.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'jurnal.' || k || '@x' from (values ('b1'), ('b2'), ('b3'), ('b4'), ('b5')) v (k)
on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'jurnal.' || k, n, r from (values
  ('b1', 'Pati PPT', 'PPT'), ('b2', 'Sef SP', 'SP'), ('b3', 'Vali V', 'V'), ('b4', 'Paul PP+B', 'PP + B'), ('b5', 'Ada AE', 'AE')) v (k, n, r)
on conflict do nothing;
delete from public.croissant_batches;
create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create temp table rez (test text, ok boolean);
grant all on rez to authenticated, anon;
set role authenticated;

select pg_temp.ca('b1');
insert into public.croissant_batches (name, score, data) values ('Batch #1', 7, '{"flourType": "T65"}');
insert into rez select 'PPT scrie un batch', count(*) = 1 from public.croissant_batches;
insert into rez select 'Autorul e cel logat', created_by = '00000000-0000-0000-0000-0000000000b1' from public.croissant_batches;
select pg_temp.ca('b2');
update public.croissant_batches set score = 8, created_by = null;
insert into rez select 'SP modifică, dar autorul rămâne', score = 8 and created_by = '00000000-0000-0000-0000-0000000000b1'
  and updated_by = '00000000-0000-0000-0000-0000000000b2' from public.croissant_batches;
delete from public.croissant_batches;
insert into rez select 'SP nu șterge batch-ul altcuiva', count(*) = 1 from public.croissant_batches;
insert into rez select 'Autorii se văd cu numele', array_agg(full_name order by full_name) = array['Pati PPT', 'Sef SP'] from public.autori_jurnal();
select pg_temp.ca('b4');
insert into rez select 'PP + B vede jurnalul', count(*) = 1 from public.croissant_batches;
select pg_temp.ca('b5');
insert into rez select 'AE vede jurnalul', count(*) = 1 from public.croissant_batches;
select pg_temp.ca('b3');
insert into rez select 'Vânzătorul nu vede jurnalul', count(*) = 0 from public.croissant_batches;
do $$ begin
  insert into public.croissant_batches (name) values ('intrus');
  insert into rez values ('Vânzătorul nu scrie', false);
exception when others then insert into rez values ('Vânzătorul nu scrie', true); end $$;
insert into rez select 'Vânzătorul nu vede autorii', count(*) = 0 from public.autori_jurnal();
select pg_temp.ca('b1');
delete from public.croissant_batches;
insert into rez select 'Autorul își șterge batch-ul', count(*) = 0 from public.croissant_batches;
set role anon;
do $$ begin perform 1 from public.croissant_batches; insert into rez values ('Anonimul nu citește', false);
exception when others then insert into rez values ('Anonimul nu citește', true); end $$;
reset role;
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
