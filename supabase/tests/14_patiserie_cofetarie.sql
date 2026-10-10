-- Patiseria și cofetăria separate (0014). Rulează după 0014. Fiecare rând trebuie să aibă ok = t.
\set ON_ERROR_STOP off
\pset footer off
create temp table rez (test text, ok boolean);
insert into public.courses (title, published, category) values ('T14 patiserie', true, 'patiserie'), ('T14 cofetărie', true, 'cofetarie'), ('T14 comun', true, 'patiserie-cofetarie');
insert into rez select 'Cele trei categorii noi sunt acceptate', count(*) = 3 from public.courses where title like 'T14%';
do $$ begin insert into public.courses (title, category) values ('T14 rău', 'cofetărie'); insert into rez values ('Categorie scrisă greșit refuzată', false);
exception when check_violation then insert into rez values ('Categorie scrisă greșit refuzată', true); end $$;
delete from public.courses where title like 'T14%';
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
