-- Categoriile din Academia (0013). Rulează după 0012. Fiecare rând trebuie să aibă ok = t.
\set ON_ERROR_STOP off
\pset footer off
create temp table rez (test text, ok boolean);
insert into public.courses (title, published) values ('T13 fără categorie', true);
insert into rez select 'Cursul nou e „general”', category = 'general' from public.courses where title = 'T13 fără categorie';
update public.courses set category = 'barista' where title = 'T13 fără categorie';
insert into rez select 'Se mută în Barista', category = 'barista' from public.courses where title = 'T13 fără categorie';
do $$ begin update public.courses set category = 'altceva' where title = 'T13 fără categorie'; insert into rez values ('Categorie necunoscută refuzată', false);
exception when check_violation then insert into rez values ('Categorie necunoscută refuzată', true); end $$;
delete from public.courses where title = 'T13 fără categorie';
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
