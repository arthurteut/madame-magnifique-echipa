-- Comenzi către producție (0024): cine pune ce, ora-limită, confirmarea pe secții, schimbări, anulare, ce vede fiecare.
-- Rulează după 0024. Produse și clienți inventați. Conturi proprii (…000000000091 …), șterse la final.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'cmd.' || k || '@x' from (values ('91'), ('92'), ('93'), ('94'), ('95'), ('96'), ('97')) v (k)
on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'cmd.' || k, n, r from (values
  ('91', 'Nico Birou', 'CB2B'), ('92', 'Lili Patiserie', 'PPT'), ('93', 'Marius Brutar', 'PBR'), ('94', 'Vera V', 'V'), ('95', 'Fane V', 'V'),
  ('96', 'Sefa Sectie', 'SP'), ('97', 'Costi PP', 'PP + B')) v (k, n, r)
on conflict do nothing;
insert into public.profile_spaces (user_id, space_id) values
  ('00000000-0000-0000-0000-000000000094', 'porumbescu'), ('00000000-0000-0000-0000-000000000095', 'fructus'), ('00000000-0000-0000-0000-000000000097', 'porumbescu')
on conflict do nothing;
delete from public.cmd_comenzi; delete from public.cmd_produse where nume like 'T24 %'; delete from public.cmd_clienti where nume like 'T24 %';
delete from public.notifications where kind = 'comanda';
update public.cmd_setari set ora_limita = '23:59';
insert into public.cmd_produse (nume, sectie, unitate) values ('T24 Croissant', 'patiserie', 'buc'), ('T24 Paine', 'brutarie', 'buc'), ('T24 Crema', 'cofetarie', 'kg');
insert into public.cmd_clienti (nume, livrare, ora) values ('T24 Cafenea', 'Str. Test 1', '08:00');
create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create or replace function pg_temp.u(k text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || k)::uuid $$;
-- true dacă instrucțiunea e refuzată
create or replace function pg_temp.pica(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
create temp table rez (test text, ok boolean);
create temp table t as select (now() at time zone 'Europe/Bucharest')::date + 1 as maine, (now() at time zone 'Europe/Bucharest')::date as azi,
  (select id from public.cmd_produse where nume = 'T24 Croissant') as cro, (select id from public.cmd_produse where nume = 'T24 Paine') as pai,
  (select id from public.cmd_produse where nume = 'T24 Crema') as cre, (select id from public.cmd_clienti where nume = 'T24 Cafenea') as cli;
create temp table k (nume text primary key, id bigint);
grant all on rez, t, k to authenticated, anon;
-- comanda cu numele dat, văzută de contul logat în ziua de mâine
create or replace function pg_temp.c(n text) returns jsonb language sql as $$
  select x from jsonb_array_elements(public.cmd_zi((select maine from t)) -> 'comenzi') x where (x ->> 'id')::bigint = (select id from k where nume = n) $$;
create or replace function pg_temp.linie(n text, produs text) returns jsonb language sql as $$
  select l from jsonb_array_elements(pg_temp.c(n) -> 'linii') l where l ->> 'produs' = produs $$;

set role authenticated;
-- 1. Biroul pune o comandă B2B, pe două secții
select pg_temp.ca('91');
insert into k select 'b2b', public.cmd_salveaza(jsonb_build_object('fel', 'b2b', 'client_id', cli, 'zi', maine, 'livrare', 'Str. Test 1', 'linii', jsonb_build_array(
  jsonb_build_object('produs_id', cro, 'cantitate', 10), jsonb_build_object('produs_id', pai, 'cantitate', 4, 'detalii', 'feliată')))) from t;
insert into rez select 'Biroul pune o comandă B2B: clientul și liniile vin din catalog', pg_temp.c('b2b') ->> 'client_nume' = 'T24 Cafenea'
  and jsonb_array_length(pg_temp.c('b2b') -> 'linii') = 2 and pg_temp.linie('b2b', 'T24 Paine') ->> 'sectie' = 'brutarie' and pg_temp.linie('b2b', 'T24 Paine') ->> 'stare' = 'noua';
insert into rez select 'Înainte de ora-limită comanda nu e târzie', (pg_temp.linie('b2b', 'T24 Paine') ->> 'tarzie')::boolean = false;
reset role;
insert into rez select 'Secțiile sunt anunțate: brutarul, patisera și șefa de secție, nu și vânzătoarea', 
  (select count(*) from public.notifications where kind = 'comanda' and user_id in (pg_temp.u('92'), pg_temp.u('93'), pg_temp.u('96'))) = 3
  and not exists (select 1 from public.notifications where kind = 'comanda' and user_id in (pg_temp.u('94'), pg_temp.u('91')));
set role authenticated;

-- 2. Cine nu poate
select pg_temp.ca('94');
insert into rez select 'Vânzătoarea nu pune comenzi B2B', pg_temp.pica(format($q$select public.cmd_salveaza('{"fel":"b2b","client_nume":"X","zi":"%s","linii":[{"produs_id":%s,"cantitate":1}]}')$q$, maine, cro)) from t;
insert into rez select 'Vânzătoarea nu comandă pentru alt magazin', pg_temp.pica(format($q$select public.cmd_salveaza('{"fel":"magazin","space_id":"fructus","zi":"%s","linii":[{"produs_id":%s,"cantitate":1}]}')$q$, maine, cro)) from t;
insert into rez select 'Comanda fără produse e refuzată', pg_temp.pica(format($q$select public.cmd_salveaza('{"fel":"magazin","space_id":"porumbescu","zi":"%s","linii":[]}')$q$, maine)) from t;
insert into rez select 'Comanda pe o zi trecută e refuzată', pg_temp.pica(format($q$select public.cmd_salveaza('{"fel":"magazin","space_id":"porumbescu","zi":"%s","linii":[{"produs_id":%s,"cantitate":1}]}')$q$, azi - 1, cro)) from t;
insert into rez select 'Cantitatea zero e refuzată', pg_temp.pica(format($q$select public.cmd_salveaza('{"fel":"magazin","space_id":"porumbescu","zi":"%s","linii":[{"produs_id":%s,"cantitate":0}]}')$q$, maine, cro)) from t;
insert into rez select 'Comanda de client fără nume e refuzată', pg_temp.pica(format($q$select public.cmd_salveaza('{"fel":"client","space_id":"porumbescu","zi":"%s","linii":[{"produs_id":%s,"cantitate":1}]}')$q$, maine, cro)) from t;
insert into rez select 'Vânzătoarea nu scrie direct în tabelul de comenzi', pg_temp.pica($q$insert into public.cmd_comenzi (fel, zi) values ('magazin', current_date + 1)$q$);
insert into rez select 'Vânzătoarea nu schimbă catalogul', pg_temp.pica($q$insert into public.cmd_produse (nume, sectie) values ('T24 Fals', 'brutarie')$q$);

-- 3. Magazinul: necesarul zilnic și comanda unui client, cu telefon
insert into k select 'nec', public.cmd_salveaza(jsonb_build_object('fel', 'magazin', 'space_id', 'porumbescu', 'zi', maine, 'linii', jsonb_build_array(jsonb_build_object('produs_id', pai, 'cantitate', 6)))) from t;
insert into k select 'cli', public.cmd_salveaza(jsonb_build_object('fel', 'client', 'space_id', 'porumbescu', 'zi', maine, 'client_nume', 'Dna Test', 'telefon', '0700000000', 'avans', 100, 'ora', '16:00',
  'linii', jsonb_build_array(jsonb_build_object('produs_nume', 'T24 Tort la comandă', 'sectie', 'cofetarie', 'cantitate', 1, 'unitate', 'kg', 'detalii', 'fără zahăr')))) from t;
insert into rez select 'Magazinul pune necesarul și comanda unui client, cu produs în afara catalogului', pg_temp.c('nec') ->> 'fel' = 'magazin'
  and pg_temp.linie('cli', 'T24 Tort la comandă') ->> 'sectie' = 'cofetarie' and (pg_temp.c('cli') ->> 'avans')::numeric = 100;
insert into rez select 'Vânzătoarea își vede telefonul clientului', pg_temp.c('cli') ->> 'telefon' = '0700000000';
insert into rez select 'Vânzătoarea de la Porumbescu nu vede comanda B2B a biroului', pg_temp.c('b2b') is null;
select pg_temp.ca('95');
insert into rez select 'Vânzătorul de la Fructus nu vede comenzile de la Porumbescu', pg_temp.c('nec') is null and pg_temp.c('cli') is null;
select pg_temp.ca('97');
insert into k select 'creme', public.cmd_salveaza(jsonb_build_object('fel', 'intern', 'space_id', 'porumbescu', 'zi', maine, 'linii', jsonb_build_array(jsonb_build_object('produs_id', cre, 'cantitate', 4)))) from t;
insert into rez select 'Patiserul din magazin cere creme', pg_temp.linie('creme', 'T24 Crema') ->> 'unitate' = 'kg';

-- 4. Producția: vede tot, fără telefon; confirmă doar liniile secției ei
select pg_temp.ca('93');
insert into rez select 'Brutarul vede toate comenzile zilei, dar nu telefonul clientului', jsonb_array_length(public.cmd_zi((select maine from t)) -> 'comenzi') = 4 and pg_temp.c('cli') ->> 'telefon' = '';
insert into rez select 'Brutarul nu confirmă linia patiseriei', pg_temp.pica(format('select public.cmd_raspunde(array[%s]::bigint[], ''confirmata'')', (pg_temp.linie('b2b', 'T24 Croissant') ->> 'id')));
select public.cmd_raspunde(array[(pg_temp.linie('b2b', 'T24 Paine') ->> 'id')::bigint, (pg_temp.linie('nec', 'T24 Paine') ->> 'id')::bigint], 'confirmata') \g /dev/null
insert into rez select 'Brutarul își confirmă liniile din două comenzi', pg_temp.linie('b2b', 'T24 Paine') ->> 'stare' = 'confirmata' and pg_temp.linie('nec', 'T24 Paine') ->> 'stare' = 'confirmata'
  and pg_temp.linie('b2b', 'T24 Croissant') ->> 'stare' = 'noua';
select pg_temp.ca('92');
insert into rez select 'Refuzul fără motiv nu trece', pg_temp.pica(format('select public.cmd_raspunde(array[%s]::bigint[], ''refuzata'', '''')', (pg_temp.linie('b2b', 'T24 Croissant') ->> 'id')));
select public.cmd_raspunde(array[(pg_temp.linie('b2b', 'T24 Croissant') ->> 'id')::bigint], 'refuzata', 'Croissantele sunt congelate') \g /dev/null
insert into rez select 'Patisera refuză cu motiv', pg_temp.linie('b2b', 'T24 Croissant') ->> 'stare' = 'refuzata' and pg_temp.linie('b2b', 'T24 Croissant') ->> 'raspuns' = 'Croissantele sunt congelate';
insert into rez select 'Producția nu schimbă comanda altcuiva', pg_temp.pica(format($q$select public.cmd_salveaza('{"id":%s,"zi":"%s","linii":[{"produs_id":%s,"cantitate":99}]}')$q$, (select id from k where nume = 'b2b'), maine, cro)) from t;
reset role;
insert into rez select 'Cine a comandat află răspunsul: biroul primește confirmarea și refuzul, vânzătoarea confirmarea',
  (select count(*) from public.notifications where user_id = pg_temp.u('91') and kind = 'comanda') = 2
  and exists (select 1 from public.notifications where user_id = pg_temp.u('91') and title like 'Producția nu poate%' and body like '%congelate%')
  and (select count(*) from public.notifications where user_id = pg_temp.u('94') and kind = 'comanda' and title like 'Comandă confirmată%') = 1;
delete from public.notifications where kind = 'comanda';
set role authenticated;

-- 5. Schimbarea unei linii confirmate o întoarce la „de confirmat”; liniile neatinse rămân
select pg_temp.ca('91');
select public.cmd_salveaza(jsonb_build_object('id', (select id from k where nume = 'b2b'), 'client_id', cli, 'zi', maine, 'linii', jsonb_build_array(
  jsonb_build_object('id', (pg_temp.linie('b2b', 'T24 Croissant') ->> 'id')::bigint, 'produs_id', cro, 'cantitate', 10),
  jsonb_build_object('id', (pg_temp.linie('b2b', 'T24 Paine') ->> 'id')::bigint, 'produs_id', pai, 'cantitate', 8, 'detalii', 'feliată')))) from t \g /dev/null
insert into rez select 'Linia schimbată se confirmă din nou, cea neatinsă își păstrează răspunsul', pg_temp.linie('b2b', 'T24 Paine') ->> 'stare' = 'noua'
  and (pg_temp.linie('b2b', 'T24 Paine') ->> 'modificata')::boolean and (pg_temp.linie('b2b', 'T24 Paine') ->> 'cantitate')::numeric = 8
  and pg_temp.linie('b2b', 'T24 Croissant') ->> 'stare' = 'refuzata';
reset role;
insert into rez select 'La schimbare e anunțată doar secția atinsă', exists (select 1 from public.notifications where user_id = pg_temp.u('93') and title like 'Comandă schimbată%')
  and not exists (select 1 from public.notifications where user_id = pg_temp.u('92'));
delete from public.notifications where kind = 'comanda';
set role authenticated;
select public.cmd_salveaza(jsonb_build_object('id', (select id from k where nume = 'b2b'), 'client_id', cli, 'zi', maine, 'linii', jsonb_build_array(
  jsonb_build_object('id', (pg_temp.linie('b2b', 'T24 Paine') ->> 'id')::bigint, 'produs_id', pai, 'cantitate', 8, 'detalii', 'feliată')))) from t \g /dev/null
insert into rez select 'O linie scoasă dispare din comandă', jsonb_array_length(pg_temp.c('b2b') -> 'linii') = 1;

-- 6. După ora-limită comanda e târzie
reset role; update public.cmd_setari set ora_limita = '00:00'; delete from public.notifications where kind = 'comanda'; set role authenticated;
select pg_temp.ca('94');
insert into k select 'tarzie', public.cmd_salveaza(jsonb_build_object('fel', 'magazin', 'space_id', 'porumbescu', 'zi', maine, 'linii', jsonb_build_array(jsonb_build_object('produs_id', pai, 'cantitate', 2)))) from t;
insert into rez select 'După ora-limită comanda intră ca târzie', (pg_temp.linie('tarzie', 'T24 Paine') ->> 'tarzie')::boolean and (public.cmd_zi((select maine from t)) ->> 'tarzie')::boolean;
reset role;
insert into rez select 'Secția e anunțată că e târzie', exists (select 1 from public.notifications where user_id = pg_temp.u('93') and title like 'Comandă târzie%');
update public.cmd_setari set ora_limita = '23:59';
set role authenticated;

-- 7. Anularea
insert into rez select 'Vânzătoarea nu anulează comanda biroului', pg_temp.pica(format('select public.cmd_anuleaza(%s, ''nu mai trebuie'')', (select id from k where nume = 'b2b')));
insert into rez select 'Anularea cere motiv', pg_temp.pica(format('select public.cmd_anuleaza(%s, '''')', (select id from k where nume = 'nec')));
select public.cmd_anuleaza((select id from k where nume = 'nec'), 'Am comandat din greșeală') \g /dev/null
insert into rez select 'Vânzătoarea își anulează comanda', pg_temp.c('nec') ->> 'stare' = 'anulata' and pg_temp.c('nec') ->> 'motiv' = 'Am comandat din greșeală';
insert into rez select 'O comandă anulată nu se mai schimbă', pg_temp.pica(format($q$select public.cmd_salveaza('{"id":%s,"space_id":"porumbescu","zi":"%s","linii":[{"produs_id":%s,"cantitate":1}]}')$q$, (select id from k where nume = 'nec'), maine, pai)) from t;
select pg_temp.ca('93');
insert into rez select 'Nu se răspunde la liniile unei comenzi anulate', pg_temp.pica(format('select public.cmd_raspunde(array[%s]::bigint[], ''confirmata'')', (pg_temp.linie('nec', 'T24 Paine') ->> 'id')));

-- 8. Zilele din jur și șefa de secție
select pg_temp.ca('96');
insert into rez select 'Șefa de secție confirmă linii din orice secție', public.cmd_raspunde(array[(pg_temp.linie('creme', 'T24 Crema') ->> 'id')::bigint, (pg_temp.linie('cli', 'T24 Tort la comandă') ->> 'id')::bigint], 'confirmata') = 2;
insert into rez select 'Rezumatul zilelor numără comenzile active și liniile de confirmat',
  (select (z ->> 'comenzi')::int = 4 and (z ->> 'de_confirmat')::int = 2 from jsonb_array_elements(public.cmd_zile((select azi from t), (select maine from t) + 3)) z where (z ->> 'zi')::date = (select maine from t));
reset role;
select set_config('request.jwt.claim.sub', '', false) \g /dev/null
set role anon;
insert into rez select 'Anonimul nu are acces', pg_temp.pica('select public.cmd_zi(current_date)');
reset role;

delete from public.cmd_comenzi; delete from public.cmd_produse where nume like 'T24 %'; delete from public.cmd_clienti where nume like 'T24 %';
delete from public.notifications where kind = 'comanda';
delete from public.profile_spaces where user_id in (select pg_temp.u(x) from unnest(array['91','92','93','94','95','96','97']) x);
delete from public.profiles where username like 'cmd.%'; delete from auth.users where email like 'cmd.%@x';
select test, ok from rez where not ok;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
