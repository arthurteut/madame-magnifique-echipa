-- Procedurile verificate (0006): cine vede ce document și ce PDF.
-- Rulează după 02 (conturile pe rol: GM = ...000000, VT = ...000006, V = ...000007,
-- BAR = ...000008, CB2B = ...000009) și 0006. Fiecare rând trebuie să aibă ok = t.
\set ON_ERROR_STOP off
\pset footer off
create or replace function pg_temp.ca(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-' || u, false); end $$;

delete from public.procedure_docs where source_file like 'test_%';
insert into public.procedure_docs (procedure_code, role_code, space_id, title, body, source_file, pdf_path) values
  ('PR-10.1', 'VT', null, 'Deschiderea casei', '1. Pas', 'test_vt.pdf', 'd/vt.pdf'),
  ('PR-04.1', 'V', null, 'Întâmpinarea', '1. Pas', 'test_v.pdf', 'd/v.pdf'),
  ('PR-05.4', 'BAR', 'fructus', 'Băuturi Fructus', '1. Pas', 'test_bar_fructus.pdf', 'd/bf.pdf'),
  (null, null, 'porumbescu', 'Deschidere Porumbescu', '1. Pas', 'test_fisa.pdf', 'd/fisa.pdf'),
  (null, 'RL', null, 'Fără cod', '1. Pas', 'test_rl.pdf', null);
delete from storage.objects where bucket_id = 'proceduri';
insert into storage.objects (bucket_id, name) values ('proceduri', 'd/vt.pdf'), ('proceduri', 'd/v.pdf'), ('proceduri', 'd/bf.pdf'), ('proceduri', 'd/fisa.pdf');

create temp table rez (test text, ok boolean);
grant all on rez to authenticated, anon;
set role authenticated;

select pg_temp.ca('000000000007');
insert into rez select 'V vede doar al lui și fișa locației', array_agg(source_file order by source_file) = array['test_fisa.pdf', 'test_v.pdf']
  from public.procedure_docs where source_file like 'test_%';
insert into rez select 'Storage: V descarcă doar PDF-urile lui', array_agg(name order by name) = array['d/fisa.pdf', 'd/v.pdf'] from storage.objects where bucket_id = 'proceduri';
select pg_temp.ca('000000000006');
insert into rez select 'VT vede VT, V, BAR și fișa (nu RL)',
  array_agg(source_file order by source_file) = array['test_bar_fructus.pdf', 'test_fisa.pdf', 'test_v.pdf', 'test_vt.pdf']
  from public.procedure_docs where source_file like 'test_%';
select pg_temp.ca('000000000008');
insert into rez select 'BAR vede barista Fructus și fișa', array_agg(source_file order by source_file) = array['test_bar_fructus.pdf', 'test_fisa.pdf']
  from public.procedure_docs where source_file like 'test_%';
select pg_temp.ca('000000000009');
insert into rez select 'CB2B nu vede nimic din magazine', count(*) = 0 from public.procedure_docs where source_file like 'test_%';
insert into rez select 'Storage: CB2B nu descarcă nimic', count(*) = 0 from storage.objects where bucket_id = 'proceduri';
-- scrieri refuzate
select pg_temp.ca('000000000006');
update public.procedure_docs set body = 'hack' where source_file = 'test_vt.pdf';
do $$ begin insert into public.procedure_docs (role_code, title, source_file) values ('VT', 'x', 'test_hack.pdf');
  insert into rez values ('VT nu adaugă documente', false);
exception when others then insert into rez values ('VT nu adaugă documente', true); end $$;
do $$ begin insert into storage.objects (bucket_id, name) values ('proceduri', 'd/hack.pdf'); insert into rez values ('VT nu încarcă PDF', false);
exception when others then insert into rez values ('VT nu încarcă PDF', true); end $$;
select pg_temp.ca('000000000000');
insert into rez select 'VT nu modifică textul', body = '1. Pas' from public.procedure_docs where source_file = 'test_vt.pdf';
insert into rez select 'GM vede toate', count(*) = 5 from public.procedure_docs where source_file like 'test_%';
update public.procedure_docs set pdf_path = 'd/rl.pdf' where source_file = 'test_rl.pdf';
insert into storage.objects (bucket_id, name) values ('proceduri', 'd/rl.pdf');
insert into rez select 'GM atașează PDF', pdf_path = 'd/rl.pdf' from public.procedure_docs where source_file = 'test_rl.pdf';
reset role;
set role anon;
do $$ begin perform 1 from public.procedure_docs; insert into rez values ('Anonimul nu citește', false);
exception when others then insert into rez values ('Anonimul nu citește', true); end $$;
reset role;
delete from public.procedure_docs where source_file like 'test_%';
delete from storage.objects where bucket_id = 'proceduri';

select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
