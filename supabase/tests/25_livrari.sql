-- Fișa de livrare (0025): livrările ies din comenzi, șoferul, dovada, ce vede fiecare.
-- Rulează după 0025. Date inventate. Conturi proprii (…0000000000b1 …), șterse la final.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'liv.' || k || '@x' from (values ('b1'), ('b2'), ('b3'), ('b4'), ('b5'), ('b6'), ('b7')) v (k)
on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'liv.' || k, n, r from (values
  ('b1', 'Nico Birou', 'CB2B'), ('b2', 'Zoli Sofer', 'LOG'), ('b3', 'Alex Sofer', 'LOG'), ('b4', 'Vera V', 'V'), ('b5', 'Fane V', 'V'),
  ('b6', 'Rica RL', 'RL'), ('b7', 'Marius Brutar', 'PBR')) v (k, n, r)
on conflict do nothing;
insert into public.profile_spaces (user_id, space_id) values
  ('00000000-0000-0000-0000-0000000000b4', 'porumbescu'), ('00000000-0000-0000-0000-0000000000b5', 'fructus'), ('00000000-0000-0000-0000-0000000000b6', 'porumbescu')
on conflict do nothing;
delete from public.livrari; delete from public.cmd_comenzi; delete from public.cmd_produse where nume like 'T25 %';
delete from public.notifications where kind in ('comanda', 'livrare');
update public.cmd_setari set ora_limita = '23:59';
insert into public.cmd_produse (nume, sectie, unitate) values ('T25 Croissant', 'patiserie', 'buc'), ('T25 Paine', 'brutarie', 'buc');
create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create or replace function pg_temp.u(k text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || k)::uuid $$;
create or replace function pg_temp.pica(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
create temp table rez (test text, ok boolean);
create temp table t as select (now() at time zone 'Europe/Bucharest')::date + 1 as maine, (now() at time zone 'Europe/Bucharest')::date as azi,
  (select id from public.cmd_produse where nume = 'T25 Croissant') as cro, (select id from public.cmd_produse where nume = 'T25 Paine') as pai;
create temp table k (nume text primary key, id bigint);
grant all on rez, t, k to authenticated, anon;
-- livrarea cu titlul dat, văzută de contul logat mâine
create or replace function pg_temp.l(titlu text) returns jsonb language sql as $$
  select x from jsonb_array_elements(public.liv_zi((select maine from t)) -> 'livrari') x where x ->> 'titlu' = titlu $$;
create or replace function pg_temp.lid(titlu text) returns bigint language sql as $$ select (pg_temp.l(titlu) ->> 'id')::bigint $$;

set role authenticated;
-- 1. O comandă B2B devine singură o livrare
select pg_temp.ca('b1');
insert into k select 'b2b', public.cmd_salveaza(jsonb_build_object('fel', 'b2b', 'client_nume', 'T25 Cafenea', 'zi', maine, 'livrare', 'Str. Test 1', 'ora', '08:00', 'linii', jsonb_build_array(
  jsonb_build_object('produs_id', cro, 'cantitate', 10), jsonb_build_object('produs_id', pai, 'cantitate', 4)))) from t;
insert into rez select 'Comanda B2B apare ca livrare, cu adresa, ora și produsele ei', pg_temp.l('T25 Cafenea') ->> 'unde' = 'Str. Test 1' and pg_temp.l('T25 Cafenea') ->> 'ora' = '08:00'
  and pg_temp.l('T25 Cafenea') ->> 'fel' = 'comanda' and jsonb_array_length(pg_temp.l('T25 Cafenea') -> 'continut') = 2 and pg_temp.l('T25 Cafenea') ->> 'stare' = 'de_facut';
insert into rez select 'Biroul primește lista șoferilor', (select count(*) from jsonb_array_elements(public.liv_zi((select maine from t)) -> 'soferi') s where s ->> 'nume' in ('Zoli Sofer', 'Alex Sofer')) = 2;
-- 2. Magazinul: o singură livrare pe zi și tură, cu tot ce a cerut
select pg_temp.ca('b4');
insert into k select 'nec', public.cmd_salveaza(jsonb_build_object('fel', 'magazin', 'space_id', 'porumbescu', 'zi', maine, 'linii', jsonb_build_array(jsonb_build_object('produs_id', pai, 'cantitate', 6)))) from t;
insert into k select 'cli', public.cmd_salveaza(jsonb_build_object('fel', 'client', 'space_id', 'porumbescu', 'zi', maine, 'client_nume', 'Dna Test', 'telefon', '0700', 'linii', jsonb_build_array(jsonb_build_object('produs_id', cro, 'cantitate', 3)))) from t;
insert into k select 'nec2', public.cmd_salveaza(jsonb_build_object('fel', 'magazin', 'space_id', 'porumbescu', 'zi', maine, 'tura', 2, 'linii', jsonb_build_array(jsonb_build_object('produs_id', pai, 'cantitate', 2)))) from t;
reset role;
insert into k select 'mag1', id from public.livrari where fel = 'magazin' and tura = 1;
insert into rez select 'Marfa magazinului: o livrare pentru tura 1 și una pentru tura 2', (select count(*) from public.livrari where fel = 'magazin' and space_id = 'porumbescu' and zi = (select maine from t)) = 2;
set role authenticated;
insert into rez select 'Livrarea magazinului adună necesarul și comanda clientului, cu numele lui',
  (select jsonb_array_length(x -> 'continut') = 2 and exists (select 1 from jsonb_array_elements(x -> 'continut') c where c ->> 'pentru' = 'Dna Test')
   from jsonb_array_elements(public.liv_zi((select maine from t)) -> 'livrari') x where x ->> 'fel' = 'magazin' and (x ->> 'tura')::int = 1);
insert into rez select 'Vânzătoarea vede marfa magazinului ei, nu și livrarea B2B', pg_temp.l('T25 Cafenea') is null and jsonb_array_length(public.liv_zi((select maine from t)) -> 'livrari') = 2;
insert into rez select 'Vânzătoarea nu pune șofer și nu schimbă starea', pg_temp.pica(format('select public.liv_pune_sofer(%s, null)', (select id from k where nume = 'mag1')))
  and pg_temp.pica(format('select public.liv_stare(%s, ''pe_drum'')', (select id from k where nume = 'mag1')));
insert into rez select 'Vânzătoarea nu scrie direct în tabel', pg_temp.pica($q$insert into public.livrari (zi, fel, titlu) values (current_date + 1, 'sarcina', 'x')$q$);
insert into rez select 'Vânzătoarea nu adaugă sarcini pentru șoferi', pg_temp.pica(format($q$select public.liv_adauga('{"zi":"%s","titlu":"Du ceva"}')$q$, maine)) from t;
select pg_temp.ca('b5');
insert into rez select 'Vânzătorul de la Fructus nu vede nimic din Porumbescu', jsonb_array_length(public.liv_zi((select maine from t)) -> 'livrari') = 0;

-- 3. Sarcini scrise de mână
select pg_temp.ca('b6');
insert into k select 'sarcina', public.liv_adauga(jsonb_build_object('zi', maine, 'titlu', 'T25 Termobox la Fructus', 'de_unde', 'Porumbescu', 'unde', 'Fructus', 'ora', '10:00')) from t;
insert into rez select 'Responsabila de magazin adaugă o sarcină', pg_temp.l('T25 Termobox la Fructus') ->> 'de_unde' = 'Porumbescu' and (pg_temp.l('T25 Termobox la Fructus') ->> 'pot_sterge')::boolean;
insert into rez select 'Responsabila nu alege ea șoferul', pg_temp.pica(format($q$select public.liv_adauga('{"zi":"%s","titlu":"T25 Alta","sofer":"%s"}')$q$, maine, pg_temp.u('b2'))) from t;
insert into rez select 'Sarcina fără text sau pe o zi trecută e refuzată', pg_temp.pica(format($q$select public.liv_adauga('{"zi":"%s","titlu":"x"}')$q$, maine)) and pg_temp.pica(format($q$select public.liv_adauga('{"zi":"%s","titlu":"T25 Veche"}')$q$, azi - 1)) from t;
reset role;
insert into rez select 'Sarcina fără șofer îi anunță pe toți șoferii', (select count(*) from public.notifications where kind = 'livrare' and title like 'Sarcină nouă%' and user_id in (pg_temp.u('b2'), pg_temp.u('b3'))) = 2;
delete from public.notifications where kind = 'livrare';
set role authenticated;

-- 4. Șoferul: biroul alege, șoferul preia
select pg_temp.ca('b1');
select public.liv_pune_sofer(pg_temp.lid('T25 Cafenea'), pg_temp.u('b2')) \g /dev/null
insert into rez select 'Biroul pune șoferul', pg_temp.l('T25 Cafenea') ->> 'sofer' = 'Zoli Sofer';
insert into rez select 'Biroul nu poate pune ca șofer pe cineva care nu e șofer', pg_temp.pica(format('select public.liv_pune_sofer(%s, %L)', pg_temp.lid('T25 Termobox la Fructus'), pg_temp.u('b4')));
reset role;
insert into rez select 'Șoferul ales e anunțat', exists (select 1 from public.notifications where user_id = pg_temp.u('b2') and title like 'Ai o livrare%' and body like 'T25 Cafenea%08:00');
set role authenticated;
select pg_temp.ca('b3');
insert into rez select 'Șoferul vede toate livrările zilei', jsonb_array_length(public.liv_zi((select maine from t)) -> 'livrari') = 4;
insert into rez select 'Un șofer nu ia livrarea altuia și nu-i schimbă starea', pg_temp.pica(format('select public.liv_pune_sofer(%s, %L)', pg_temp.lid('T25 Cafenea'), pg_temp.u('b3')))
  and pg_temp.pica(format('select public.liv_stare(%s, ''pe_drum'')', pg_temp.lid('T25 Cafenea')));
select public.liv_pune_sofer(pg_temp.lid('T25 Termobox la Fructus'), pg_temp.u('b3')) \g /dev/null
insert into rez select 'Șoferul preia o livrare liberă', (pg_temp.l('T25 Termobox la Fructus') ->> 'al_meu')::boolean;
select public.liv_pune_sofer(pg_temp.lid('T25 Termobox la Fructus'), null) \g /dev/null
insert into rez select 'Șoferul renunță la livrarea lui', pg_temp.l('T25 Termobox la Fructus') ->> 'sofer' is null;

-- 5. Dovada livrării
select pg_temp.ca('b2');
select public.liv_stare(pg_temp.lid('T25 Cafenea'), 'pe_drum') \g /dev/null
insert into rez select 'Șoferul marchează „am plecat”', pg_temp.l('T25 Cafenea') ->> 'stare' = 'pe_drum';
insert into rez select '„Livrat” fără cine a primit e refuzat', pg_temp.pica(format($q$select public.liv_stare(%s, 'livrat', '{"poza":"a.jpg"}')$q$, pg_temp.lid('T25 Cafenea')));
insert into rez select '„Livrat” fără poză și fără motiv e refuzat', pg_temp.pica(format($q$select public.liv_stare(%s, 'livrat', '{"primit_de":"Ana"}')$q$, pg_temp.lid('T25 Cafenea')));
select public.liv_stare(pg_temp.lid('T25 Cafenea'), 'livrat', '{"primit_de":"Ana de la bar","poza":"2026/x.jpg"}') \g /dev/null
insert into rez select 'Livrat: rămân cine a primit, poza, ora și șoferul', pg_temp.l('T25 Cafenea') ->> 'stare' = 'livrat' and pg_temp.l('T25 Cafenea') ->> 'primit_de' = 'Ana de la bar'
  and pg_temp.l('T25 Cafenea') ->> 'poza' = '2026/x.jpg' and pg_temp.l('T25 Cafenea') ->> 'facut_de' = 'Zoli Sofer' and pg_temp.l('T25 Cafenea') ->> 'facut_la' is not null;
insert into rez select 'Problema fără motiv e refuzată', pg_temp.pica(format($q$select public.liv_stare(%s, 'problema', '{}')$q$, pg_temp.lid('T25 Termobox la Fructus')));
select public.liv_stare(pg_temp.lid('T25 Termobox la Fructus'), 'problema', '{"problema":"Magazinul era închis"}') \g /dev/null
insert into rez select 'Șoferul care raportează o problemă la o livrare liberă devine șoferul ei', pg_temp.l('T25 Termobox la Fructus') ->> 'stare' = 'problema' and (pg_temp.l('T25 Termobox la Fructus') ->> 'al_meu')::boolean;
select public.liv_stare((select (x ->> 'id')::bigint from jsonb_array_elements(public.liv_zi((select maine from t)) -> 'livrari') x where x ->> 'fel' = 'magazin' and (x ->> 'tura')::int = 1), 'livrat', '{"primit_de":"Vera","fara_poza":"Telefonul nu are baterie"}') \g /dev/null
reset role;
insert into rez select 'Biroul află de livrare și de problemă; responsabila află de problema sarcinii ei și de marfa magazinului',
  exists (select 1 from public.notifications where user_id = pg_temp.u('b1') and title = 'Livrat · T25 Cafenea' and body = 'A primit Ana de la bar')
  and exists (select 1 from public.notifications where user_id = pg_temp.u('b1') and title like 'Problemă la livrare%' and body = 'Magazinul era închis')
  and exists (select 1 from public.notifications where user_id = pg_temp.u('b6') and title like 'Problemă la livrare%')
  and exists (select 1 from public.notifications where user_id = pg_temp.u('b6') and title like 'Livrat · %' and body like 'A primit Vera · fără poză: Telefonul%');
set role authenticated;

-- 6. Livrarea se ține după comandă
select pg_temp.ca('b1');
insert into k select 'b2b2', public.cmd_salveaza(jsonb_build_object('fel', 'b2b', 'client_nume', 'T25 Hotel', 'zi', maine, 'livrare', 'Hol', 'linii', jsonb_build_array(jsonb_build_object('produs_id', cro, 'cantitate', 5)))) from t;
reset role;
create temp table linii_b2b2 as select jsonb_agg(jsonb_build_object('id', li.id, 'produs_id', li.produs_id, 'cantitate', li.cantitate)) as j from public.cmd_linii li where li.comanda_id = (select id from k where nume = 'b2b2');
grant all on linii_b2b2 to authenticated;
set role authenticated;
select public.cmd_salveaza(jsonb_build_object('id', (select id from k where nume = 'b2b2'), 'client_nume', 'T25 Hotel', 'zi', maine + 1, 'livrare', 'Recepție', 'ora', '09:30',
  'linii', (select j from linii_b2b2))) from t \g /dev/null
insert into rez select 'Comanda mutată pe altă zi își mută și livrarea, cu adresa nouă', pg_temp.l('T25 Hotel') is null
  and (select x ->> 'unde' = 'Recepție' and x ->> 'ora' = '09:30' from jsonb_array_elements(public.liv_zi((select maine + 1 from t)) -> 'livrari') x where x ->> 'titlu' = 'T25 Hotel');
select public.cmd_anuleaza((select id from k where nume = 'b2b2'), 'Clientul a renunțat') \g /dev/null
insert into rez select 'Comanda anulată își anulează livrarea', (select x ->> 'stare' = 'anulata' from jsonb_array_elements(public.liv_zi((select maine + 1 from t)) -> 'livrari') x where x ->> 'titlu' = 'T25 Hotel');
reset role;
insert into rez select 'O comandă schimbată după livrare nu redeschide livrarea', (select stare from public.livrari where comanda_id = (select id from k where nume = 'b2b')) = 'livrat';
set role authenticated;
select pg_temp.ca('b4');
select public.cmd_anuleaza((select id from k where nume = 'nec2'), 'Nu mai trebuie') \g /dev/null
insert into rez select 'Marfa de tura 2 dispare din listă când nu mai are ce duce', not exists (select 1 from jsonb_array_elements(public.liv_zi((select maine from t)) -> 'livrari') x where (x ->> 'tura')::int = 2);

-- 7. Anularea sarcinii, rezumatul zilelor, anonimul
select pg_temp.ca('b6');
insert into k select 's2', public.liv_adauga(jsonb_build_object('zi', maine, 'titlu', 'T25 Apă de la Selgros')) from t;
select pg_temp.ca('b4');
insert into rez select 'Vânzătoarea nu anulează sarcina altcuiva', pg_temp.pica(format('select public.liv_anuleaza(%s)', (select id from k where nume = 's2')));
select pg_temp.ca('b6');
insert into rez select 'Livrarea unei comenzi nu se anulează de mână', pg_temp.pica(format('select public.liv_anuleaza(%s)', (select id from k where nume = 'mag1')));
select public.liv_anuleaza((select id from k where nume = 's2')) \g /dev/null
insert into rez select 'Responsabila își anulează sarcina', pg_temp.l('T25 Apă de la Selgros') ->> 'stare' = 'anulata';
select pg_temp.ca('b7');
insert into rez select 'Producția vede livrările zilei', jsonb_array_length(public.liv_zi((select maine from t)) -> 'livrari') >= 3;
select pg_temp.ca('b1');
insert into rez select 'Rezumatul zilei: câte sunt, câte au rămas, câte nu au șofer',
  (select (z ->> 'toate')::int = 3 and (z ->> 'ramase')::int = 0 and (z ->> 'fara_sofer')::int = 0 from jsonb_array_elements(public.liv_zile((select azi from t), (select maine from t))) z where (z ->> 'zi')::date = (select maine from t));
reset role;
select set_config('request.jwt.claim.sub', '', false) \g /dev/null
set role anon;
insert into rez select 'Anonimul nu are acces', pg_temp.pica('select public.liv_zi(current_date)');
reset role;

delete from public.livrari; delete from public.cmd_comenzi; delete from public.cmd_produse where nume like 'T25 %';
delete from public.notifications where kind in ('comanda', 'livrare');
delete from public.profile_spaces where user_id::text like '00000000-0000-0000-0000-0000000000b_';
delete from public.profiles where username like 'liv.%'; delete from auth.users where email like 'liv.%@x';
select test, ok from rez where not ok or ok is null;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
