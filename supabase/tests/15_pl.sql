-- P&L (0015): doar GM, AE, EC și ADM văd și completează. Rulează după 02, 0004 și 0015.
-- Conturi: GM = ...000000, RL = ...000005, V = ...000007, ADM = ...000011,
-- EC = ...000012, AE = ...000014.
\set ON_ERROR_STOP off
\pset footer off
create or replace function pg_temp.ca(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-' || u, false); end $$;
insert into public.pl_books (name, year) values ('Test P&L', 2099) on conflict (name, year) do nothing;
insert into public.pl_guide (slug, title, body) values ('test', 'Test', 'x') on conflict (slug) do nothing;
create temp table rez (test text, ok boolean);
grant all on rez to authenticated, anon;
set role authenticated;

select pg_temp.ca('000000000012');
insert into rez select 'EC vede P&L-ul', count(*) = 1 from public.pl_books where name = 'Test P&L';
insert into public.pl_months (book_id, month, data)
  select id, 1, '{"bauturi": 62000}' from public.pl_books where name = 'Test P&L';
insert into rez select 'EC completează o lună', count(*) = 1 from public.pl_months m join public.pl_books b on b.id = m.book_id
  where b.name = 'Test P&L' and m.month = 1;
insert into rez select 'EC citește ghidul', count(*) = 1 from public.pl_guide where slug = 'test';
delete from public.pl_books where name = 'Test P&L';

select pg_temp.ca('000000000011');
update public.pl_months set data = '{"bauturi": 63000}'
  where book_id = (select id from public.pl_books where name = 'Test P&L') and month = 1;
insert into rez select 'ADM modifică luna', (data->>'bauturi')::int = 63000 from public.pl_months m
  join public.pl_books b on b.id = m.book_id where b.name = 'Test P&L' and m.month = 1;
insert into rez select 'ADM apare ca ultimul care a modificat',
  m.updated_by = '00000000-0000-0000-0000-000000000011' from public.pl_months m
  join public.pl_books b on b.id = m.book_id where b.name = 'Test P&L' and m.month = 1;

select pg_temp.ca('000000000014');
update public.pl_books set settings = '{"curs": 5.1}' where name = 'Test P&L';
insert into rez select 'AE schimbă setările', (settings->>'curs')::numeric = 5.1 from public.pl_books where name = 'Test P&L';

select pg_temp.ca('000000000005');
insert into rez select 'RL nu vede P&L-ul', count(*) = 0 from public.pl_books;
insert into rez select 'RL nu vede lunile', count(*) = 0 from public.pl_months;
insert into rez select 'RL nu citește ghidul', count(*) = 0 from public.pl_guide;
do $$ begin
  insert into public.pl_books (name, year) values ('Intrus', 2099);
  insert into rez values ('RL nu adaugă un P&L', false);
exception when others then insert into rez values ('RL nu adaugă un P&L', true); end $$;
update public.pl_months set data = '{}';

select pg_temp.ca('000000000007');
insert into rez select 'V nu vede P&L-ul', count(*) = 0 from public.pl_books;

reset role;
insert into rez select 'Nimeni din afară nu a schimbat luna', (data->>'bauturi')::int = 63000 from public.pl_months m
  join public.pl_books b on b.id = m.book_id where b.name = 'Test P&L' and m.month = 1;
insert into rez select 'EC nu poate șterge un P&L întreg', count(*) = 1 from public.pl_books where name = 'Test P&L';

-- Chiar dacă adminul bifează pagina pentru RL, datele nu ajung la el.
insert into public.role_section_access (role_code, section) values ('RL', 'pl') on conflict do nothing;
set role authenticated;
select pg_temp.ca('000000000005');
insert into rez select 'RL cu pagina bifată tot nu vede', count(*) = 0 from public.pl_books;
-- Fără pagina „pl”, nici ADM nu mai vede.
reset role;
delete from public.role_section_access where role_code = 'RL' and section = 'pl';
delete from public.role_section_access where role_code = 'ADM' and section = 'pl';
set role authenticated;
select pg_temp.ca('000000000011');
insert into rez select 'ADM fără pagină nu vede', count(*) = 0 from public.pl_books;

select pg_temp.ca('000000000000');
insert into rez select 'GM vede P&L-ul', count(*) = 1 from public.pl_books where name = 'Test P&L';
delete from public.pl_books where name = 'Test P&L';
insert into rez select 'GM șterge un P&L', count(*) = 0 from public.pl_books where name = 'Test P&L';
reset role;
insert into rez select 'Lunile se șterg odată cu P&L-ul', count(*) = 0 from public.pl_months m
  where not exists (select 1 from public.pl_books b where b.id = m.book_id);
insert into public.role_section_access (role_code, section) values ('ADM', 'pl') on conflict do nothing;
insert into rez select 'Pagina pl: exact GM, AE, EC, ADM',
  array_agg(role_code order by role_code) = array['ADM', 'AE', 'EC', 'GM']
  from public.role_section_access where section = 'pl';

set role anon;
do $$ begin perform 1 from public.pl_books; insert into rez values ('Anonimul nu citește', false);
exception when others then insert into rez values ('Anonimul nu citește', true); end $$;
reset role;
delete from public.pl_guide where slug = 'test';
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
