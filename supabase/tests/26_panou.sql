-- Panoul șefilor (0026): încasările zilei, nota zilei, stocul laboratorului, vederea pe toate locațiile.
-- Rulează după 0026. Date inventate. Conturi proprii (…0000000000c1 …), șterse la final.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'pan.' || k || '@x' from (values ('c1'), ('c2'), ('c3'), ('c4'), ('c5'), ('c6')) v (k) on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'pan.' || k, n, r from (values
  ('c1', 'Vera V', 'V'), ('c2', 'Rica RL', 'RL'), ('c3', 'Fane V', 'V'), ('c4', 'Gina GM', 'GM'), ('c5', 'Sefa Sectie', 'SP'), ('c6', 'Marius Brutar', 'PBR')) v (k, n, r)
on conflict do nothing;
insert into public.profile_spaces (user_id, space_id) values
  ('00000000-0000-0000-0000-0000000000c1', 'porumbescu'), ('00000000-0000-0000-0000-0000000000c2', 'porumbescu'), ('00000000-0000-0000-0000-0000000000c3', 'fructus')
on conflict do nothing;
delete from public.incasari_zi; delete from public.nota_zilei; delete from public.stoc_zi; delete from public.stoc_produse where nume like 'T26 %';
delete from public.clockings where user_id::text like '00000000-0000-0000-0000-0000000000c_'; delete from public.shifts where user_id::text like '00000000-0000-0000-0000-0000000000c_';
create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create or replace function pg_temp.u(k text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || k)::uuid $$;
create or replace function pg_temp.pica(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
create temp table rez (test text, ok boolean);
create temp table t as select (now() at time zone 'Europe/Bucharest')::date as azi;
grant all on rez, t to authenticated, anon;
create or replace function pg_temp.loc(s text) returns jsonb language sql as $$ select x from jsonb_array_elements(public.panou_sefi()) x where x ->> 'space_id' = s $$;
-- programul și pontajul de azi: Vera a venit, Rica e programată de la 00:00 și lipsește
insert into public.shifts (user_id, space_id, day, starts, ends, opens) values (pg_temp.u('c1'), 'porumbescu', (select azi from t), '00:00', '23:59', true), (pg_temp.u('c2'), 'porumbescu', (select azi from t), '00:00', '23:59', false);
insert into public.clockings (user_id, space_id, clock_in) values (pg_temp.u('c1'), 'porumbescu', now() - interval '1 minute');
insert into public.stoc_produse (space_id, nume, grupa, unitate, minim) values ('peciu-nou', 'T26 Aluat croissant', 'Aluaturi', 'kg', 10), ('peciu-nou', 'T26 Tort Joffre', 'Torturi', 'buc', null);

set role authenticated;
-- 1. Încasările
select pg_temp.ca('c1');
select public.incasari_pune('porumbescu', (select azi from t), 3200, 80, 'zi bună') \g /dev/null
insert into rez select 'Vânzătoarea scrie încasările zilei, iar media bonului se calculează', (public.zi_locatie('porumbescu', (select azi from t)) -> 'incasari' ->> 'medie')::numeric = 40
  and public.zi_locatie('porumbescu', (select azi from t)) -> 'incasari' ->> 'de' like 'Vera V%';
select public.incasari_pune('porumbescu', (select azi from t), 3300, 82, '') \g /dev/null
insert into rez select 'Încasările se pot corecta', (public.zi_locatie('porumbescu', (select azi from t)) -> 'incasari' ->> 'incasari')::numeric = 3300;
insert into rez select 'Vânzătoarea nu scrie pentru alt magazin', pg_temp.pica(format('select public.incasari_pune(''fructus'', %L, 100, 2)', (select azi from t)));
insert into rez select 'Nu se scriu încasări pentru mâine', pg_temp.pica(format('select public.incasari_pune(''porumbescu'', %L, 100, 2)', (select azi + 1 from t)));
insert into rez select 'Vânzătoarea nu scrie pentru zile mai vechi de ieri', pg_temp.pica(format('select public.incasari_pune(''porumbescu'', %L, 100, 2)', (select azi - 3 from t)));
insert into rez select 'Încasări cu zero bonuri sunt refuzate', pg_temp.pica(format('select public.incasari_pune(''porumbescu'', %L, 100, 0)', (select azi from t)));
insert into rez select 'Vânzătoarea nu scrie direct în tabel', pg_temp.pica('insert into public.incasari_zi (space_id, zi, incasari, bonuri) values (''porumbescu'', current_date - 9, 1, 1)');
insert into rez select 'Vânzătoarea nu scrie nota zilei', pg_temp.pica(format('select public.nota_zilei_pune(''porumbescu'', %L, ''A fost bine'')', (select azi from t)));
insert into rez select 'Vânzătoarea nu vede panoul șefilor', pg_temp.pica('select public.panou_sefi()');
-- 2. Responsabila: nota zilei, zile vechi, panoul
select pg_temp.ca('c2');
select public.nota_zilei_pune('porumbescu', (select azi from t), 'Coadă la 8, a lipsit pâinea cu semințe.') \g /dev/null
select public.incasari_pune('porumbescu', (select azi - 7 from t), 2800, 70, '') \g /dev/null
insert into rez select 'Responsabila scrie nota zilei și poate completa o zi veche', public.zi_locatie('porumbescu', (select azi from t)) -> 'nota' ->> 'text' like 'Coadă la 8%'
  and (public.zi_locatie('porumbescu', (select azi from t)) -> 'incasari_sapt' ->> 'bonuri')::int = 70;
insert into rez select 'Nota zilei fără text e refuzată', pg_temp.pica(format('select public.nota_zilei_pune(''porumbescu'', %L, '' '')', (select azi from t)));
insert into rez select 'Responsabila nu scrie pentru alt magazin', pg_temp.pica(format('select public.nota_zilei_pune(''fructus'', %L, ''Text'')', (select azi from t)));
insert into rez select 'Responsabila vede în panou doar magazinul ei', jsonb_array_length(public.panou_sefi()) = 1 and pg_temp.loc('porumbescu') is not null;
insert into rez select 'Panoul arată cine e în tură și de când e deschis', exists (select 1 from jsonb_array_elements(pg_temp.loc('porumbescu') -> 'in_tura') o where o ->> 'nume' = 'Vera V')
  and pg_temp.loc('porumbescu') ->> 'deschis_la' is not null;
insert into rez select 'Panoul arată programul: cine a venit și cine lipsește',
  (select (x ->> 'venit_la') is not null and not (x ->> 'lipseste')::boolean from jsonb_array_elements(pg_temp.loc('porumbescu') -> 'program') x where x ->> 'nume' = 'Vera V')
  and (select (x ->> 'lipseste')::boolean from jsonb_array_elements(pg_temp.loc('porumbescu') -> 'program') x where x ->> 'nume' = 'Rica RL');
insert into rez select 'Panoul arată încasările de azi, cele de acum o săptămână și nota zilei', (pg_temp.loc('porumbescu') -> 'incasari' ->> 'bonuri')::int = 82
  and (pg_temp.loc('porumbescu') -> 'incasari_sapt' ->> 'incasari')::numeric = 2800 and pg_temp.loc('porumbescu') -> 'nota_zilei' ->> 'de' like 'Rica RL%';
-- 3. Stocul laboratorului
select pg_temp.ca('c6');
insert into rez select 'Brutarul nu schimbă lista de stoc', pg_temp.pica('insert into public.stoc_produse (space_id, nume) values (''peciu-nou'', ''T26 Fals'')');
select public.stoc_pune('peciu-nou', jsonb_build_object((select id::text from public.stoc_produse where nume = 'T26 Aluat croissant'), 6, (select id::text from public.stoc_produse where nume = 'T26 Tort Joffre'), 3)) \g /dev/null
insert into rez select 'Brutarul scrie stocul de azi', (select (x ->> 'azi')::numeric from jsonb_array_elements(public.zi_locatie('peciu-nou', (select azi from t)) -> 'stoc') x where x ->> 'nume' = 'T26 Aluat croissant') = 6;
insert into rez select 'Stocul negativ e refuzat', pg_temp.pica(format('select public.stoc_pune(''peciu-nou'', ''{"%s": -1}'')', (select id from public.stoc_produse where nume = 'T26 Tort Joffre')));
insert into rez select 'Un produs de pe altă listă e refuzat', pg_temp.pica(format('select public.stoc_pune(''laborator-fructus'', ''{"%s": 1}'')', (select id from public.stoc_produse where nume = 'T26 Tort Joffre')));
select pg_temp.ca('c5');
insert into public.stoc_produse (space_id, nume, grupa) values ('peciu-nou', 'T26 Blat', 'Torturi');
insert into rez select 'Șefa de secție adaugă un produs pe lista de stoc', exists (select 1 from public.stoc_produse where nume = 'T26 Blat');
insert into rez select 'Șefa de secție vede în panou stocul laboratorului, cu minimul', (select (x ->> 'cantitate')::numeric = 6 and (x ->> 'minim')::numeric = 10 from jsonb_array_elements(pg_temp.loc('peciu-nou') -> 'stoc') x where x ->> 'nume' = 'T26 Aluat croissant');
-- 4. Conducerea vede tot
select pg_temp.ca('c4');
insert into rez select 'GM vede toate locațiile, magazine și laboratoare', pg_temp.loc('porumbescu') is not null and pg_temp.loc('fructus') is not null and pg_temp.loc('peciu-nou') is not null;
select pg_temp.ca('c3');
insert into rez select 'Vânzătorul de la Fructus nu vede ziua de la Porumbescu', pg_temp.pica(format('select public.zi_locatie(''porumbescu'', %L)', (select azi from t)));
reset role;
select set_config('request.jwt.claim.sub', '', false) \g /dev/null
set role anon;
insert into rez select 'Anonimul nu are acces', pg_temp.pica('select public.panou_sefi()') and pg_temp.pica('select public.zi_locatie(''porumbescu'', current_date)');
reset role;
delete from public.incasari_zi; delete from public.nota_zilei; delete from public.stoc_zi; delete from public.stoc_produse where nume like 'T26 %';
delete from public.clockings where user_id::text like '00000000-0000-0000-0000-0000000000c_'; delete from public.shifts where user_id::text like '00000000-0000-0000-0000-0000000000c_';
delete from public.profile_spaces where user_id::text like '00000000-0000-0000-0000-0000000000c_';
delete from public.profiles where username like 'pan.%'; delete from auth.users where email like 'pan.%@x';
select test, ok from rez where not ok or ok is null;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
