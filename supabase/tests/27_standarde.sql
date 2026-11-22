-- Standardele de produs (0027): verificarea zilnică, neconformitatea, decizia, cauza, ce vede fiecare.
-- Rulează după 0027. Date inventate. Conturi proprii (…0000000000d1 …), șterse la final.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'std.' || k || '@x' from (values ('d1'), ('d2'), ('d3'), ('d4'), ('d5'), ('d6'), ('d7')) v (k) on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'std.' || k, n, r from (values
  ('d1', 'Vera V', 'V'), ('d2', 'Rica RL', 'RL'), ('d3', 'Fane V', 'V'), ('d4', 'Gina GM', 'GM'), ('d5', 'Sefa Sectie', 'SP'), ('d6', 'Marius Brutar', 'PBR'), ('d7', 'Lili Patiserie', 'PPT')) v (k, n, r)
on conflict do nothing;
insert into public.profile_spaces (user_id, space_id) values
  ('00000000-0000-0000-0000-0000000000d1', 'porumbescu'), ('00000000-0000-0000-0000-0000000000d2', 'porumbescu'), ('00000000-0000-0000-0000-0000000000d3', 'fructus')
on conflict do nothing;
delete from public.std_verificari; delete from public.std_produse where nume like 'T27 %'; delete from public.notifications where kind = 'standard';
insert into public.std_produse (nume, sectie, criterii) values ('T27 Paine', 'brutarie', '{Coaja,Miez copt}'), ('T27 Croissant', 'patiserie', '{Culoare,Volum,Foietaj}');
create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create or replace function pg_temp.u(k text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || k)::uuid $$;
create or replace function pg_temp.pica(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
create temp table rez (test text, ok boolean);
create temp table t as select (now() at time zone 'Europe/Bucharest')::date as azi, (select id from public.std_produse where nume = 'T27 Paine') as pai, (select id from public.std_produse where nume = 'T27 Croissant') as cro;
create temp table k (nume text primary key, id bigint);
grant all on rez, t, k to authenticated, anon;
create or replace function pg_temp.v(space text, produs text) returns jsonb language sql as $$
  select x -> 'verificare' from jsonb_array_elements(public.std_zi(space, (select azi from t)) -> 'produse') x where x ->> 'nume' = produs $$;
create or replace function pg_temp.n(nume text) returns jsonb language sql as $$
  select x from jsonb_array_elements(public.std_neconforme(14)) x where (x ->> 'id')::bigint = (select id from k where k.nume = n.nume) $$;

set role authenticated;
-- 1. Verificarea de dimineață
select pg_temp.ca('d1');
insert into rez select 'Vânzătoarea vede produsele de verificat, cu criteriile lor', jsonb_array_length(public.std_zi('porumbescu', (select azi from t)) -> 'produse') >= 2
  and (select jsonb_array_length(x -> 'criterii') = 3 from jsonb_array_elements(public.std_zi('porumbescu', (select azi from t)) -> 'produse') x where x ->> 'nume' = 'T27 Croissant');
insert into k select 'cro', public.std_verifica('porumbescu', cro, '{"Culoare": true, "Volum": true, "Foietaj": true}', '', 'p/a.jpg') from t;
insert into rez select 'Un produs cu toate criteriile bifate e în standard', (pg_temp.v('porumbescu', 'T27 Croissant') ->> 'ok')::boolean and pg_temp.v('porumbescu', 'T27 Croissant') ->> 'poza' = 'p/a.jpg';
insert into rez select 'Fără răspuns la un criteriu, verificarea e refuzată', pg_temp.pica(format($q$select public.std_verifica('porumbescu', %s, '{"Coaja": true}', '', 'p/b.jpg')$q$, pai)) from t;
insert into rez select 'Fără poză și fără motiv, verificarea e refuzată', pg_temp.pica(format($q$select public.std_verifica('porumbescu', %s, '{"Coaja": true, "Miez copt": true}')$q$, pai)) from t;
insert into rez select 'Un criteriu picat cere o explicație', pg_temp.pica(format($q$select public.std_verifica('porumbescu', %s, '{"Coaja": true, "Miez copt": false}', '', 'p/b.jpg')$q$, pai)) from t;
insert into rez select 'Vânzătoarea nu verifică pentru alt magazin', pg_temp.pica(format($q$select public.std_verifica('fructus', %s, '{"Coaja": true, "Miez copt": true}', '', 'p/b.jpg')$q$, pai)) from t;
insert into rez select 'Vânzătoarea nu scrie direct în tabel și nu schimbă lista', pg_temp.pica('insert into public.std_verificari (produs_id, space_id, zi, criterii, ok) select id, ''porumbescu'', current_date - 3, ''[]'', true from public.std_produse limit 1')
  and pg_temp.pica('insert into public.std_produse (nume, sectie, criterii) values (''T27 Fals'', ''brutarie'', ''{x}'')');
insert into k select 'pai', public.std_verifica('porumbescu', pai, '{"Coaja": true, "Miez copt": false}', 'Miezul e lipicios la feliere', '', 'Telefonul nu are baterie') from t;
insert into rez select 'Un criteriu picat face o neconformitate, cu explicația și motivul lipsei pozei', not (pg_temp.v('porumbescu', 'T27 Paine') ->> 'ok')::boolean
  and pg_temp.v('porumbescu', 'T27 Paine') ->> 'fara_poza' = 'Telefonul nu are baterie' and pg_temp.n('pai') ->> 'nota' = 'Miezul e lipicios la feliere';
insert into rez select 'Vânzătoarea nu decide și nu scrie cauza', pg_temp.pica(format('select public.std_decide(%s, ''retras'')', (select id from k where nume = 'pai'))) and pg_temp.pica(format('select public.std_cauza(%s, ''Cuptor rece'')', (select id from k where nume = 'pai')));
reset role;
insert into rez select 'Neconformitatea ajunge la brutar, la șefa de secție, la responsabila magazinului și la conducere; nu la patiserie',
  (select count(*) from public.notifications where kind = 'standard' and user_id in (pg_temp.u('d6'), pg_temp.u('d5'), pg_temp.u('d2'), pg_temp.u('d4'))) = 4
  and not exists (select 1 from public.notifications where kind = 'standard' and user_id in (pg_temp.u('d7'), pg_temp.u('d3')))
  and exists (select 1 from public.notifications where user_id = pg_temp.u('d6') and body like 'T27 Paine: Miez copt · Miezul e lipicios%');
delete from public.notifications where kind = 'standard';
set role authenticated;

-- 2. Cine vede ce
select pg_temp.ca('d3');
insert into rez select 'Vânzătorul de la Fructus nu vede verificările de la Porumbescu', pg_temp.pica(format('select public.std_zi(''porumbescu'', %L)', (select azi from t))) and jsonb_array_length(public.std_neconforme(14)) = 0;
select pg_temp.ca('d7');
insert into rez select 'Patisera nu vede neconformitatea brutăriei', pg_temp.n('pai') is null;
select pg_temp.ca('d6');
insert into rez select 'Brutarul vede neconformitatea produsului lui și poate scrie cauza, dar nu decide', (pg_temp.n('pai') ->> 'pot_cauza')::boolean and not (pg_temp.n('pai') ->> 'pot_decide')::boolean
  and pg_temp.pica(format('select public.std_decide(%s, ''retras'')', (select id from k where nume = 'pai')));

-- 3. Decizia și cauza
select pg_temp.ca('d2');
insert into rez select 'O decizie necunoscută e refuzată', pg_temp.pica(format('select public.std_decide(%s, ''aruncat'')', (select id from k where nume = 'pai')));
insert into rez select 'Nu se decide pe un produs în standard', pg_temp.pica(format('select public.std_decide(%s, ''retras'')', (select id from k where nume = 'cro')));
select public.std_decide((select id from k where nume = 'pai'), 'degustare', 'O feliem pentru degustare') \g /dev/null
insert into rez select 'Responsabila magazinului decide ce se face', pg_temp.n('pai') ->> 'decizie' = 'degustare' and pg_temp.n('pai') ->> 'decizie_de' like 'Rica RL%';
reset role;
insert into rez select 'Cine a verificat află decizia', exists (select 1 from public.notifications where user_id = pg_temp.u('d1') and title = 'Decizie: merge la degustare');
set role authenticated;
select pg_temp.ca('d1');
insert into rez select 'După decizie, verificarea de azi nu se mai schimbă', pg_temp.pica(format($q$select public.std_verifica('porumbescu', %s, '{"Coaja": true, "Miez copt": true}', '', 'p/c.jpg')$q$, pai)) from t;
select pg_temp.ca('d7');
insert into rez select 'Altă secție nu scrie cauza', pg_temp.pica(format('select public.std_cauza(%s, ''Nu e a noastră'')', (select id from k where nume = 'pai')));
select pg_temp.ca('d6');
insert into rez select 'Cauza fără text e refuzată', pg_temp.pica(format('select public.std_cauza(%s, ''ok'')', (select id from k where nume = 'pai')));
select public.std_cauza((select id from k where nume = 'pai'), 'Cuptorul a fost pornit târziu; de mâine verificăm temperatura la 3:30') \g /dev/null
insert into rez select 'Brutarul scrie cauza', pg_temp.n('pai') ->> 'cauza' like 'Cuptorul a fost pornit târziu%' and pg_temp.n('pai') ->> 'cauza_de' like 'Marius Brutar%';

-- 4. Rezumatul și lista
select pg_temp.ca('d4');
insert into rez select 'Rezumatul de azi: 2 verificate, 1 în standard, pâinea neconformă',
  (select (z ->> 'verificate')::int = 2 and (z ->> 'in_standard')::int = 1 and z -> 'neconforme' ->> 0 = 'T27 Paine' and (z ->> 'fara_decizie')::int = 0
   from jsonb_array_elements(public.std_rezumat() -> 'azi') z where z ->> 'space_id' = 'porumbescu');
insert into rez select 'Rezumatul pe secții, pe 7 zile',
  (select (z ->> 'verificate')::int = 1 and (z ->> 'in_standard')::int = 0 from jsonb_array_elements(public.std_rezumat() -> 'sectii') z where z ->> 'sectie' = 'brutarie')
  and (select (z ->> 'in_standard')::int = 1 from jsonb_array_elements(public.std_rezumat() -> 'sectii') z where z ->> 'sectie' = 'patiserie');
reset role;
insert into public.std_verificari (produs_id, space_id, zi, criterii, ok, nota) select pai, 'porumbescu', azi - 2, '[{"nume": "Coaja", "ok": false}, {"nume": "Miez copt", "ok": true}]', false, 'Coaja arsă' from t;
set role authenticated;
insert into rez select 'Un produs care pică de două ori apare la „repetate”, cu criteriile picate',
  (select (z ->> 'ori')::int = 2 and z ->> 'criterii' like '%Coaja%' and z ->> 'criterii' like '%Miez copt%' from jsonb_array_elements(public.std_rezumat() -> 'repetate') z where z ->> 'produs' = 'T27 Paine');
select pg_temp.ca('d5');
insert into public.std_produse (nume, sectie, criterii) values ('T27 Tort', 'cofetarie', '{Decor}');
insert into rez select 'Șefa de secție adaugă un produs pe listă', exists (select 1 from public.std_produse where nume = 'T27 Tort');
select pg_temp.ca('d1');
insert into rez select 'Vânzătoarea nu vede rezumatul șefilor', pg_temp.pica('select public.std_rezumat()');
reset role;
select set_config('request.jwt.claim.sub', '', false) \g /dev/null
set role anon;
insert into rez select 'Anonimul nu are acces', pg_temp.pica('select public.std_neconforme(14)');
reset role;
delete from public.std_verificari; delete from public.std_produse where nume like 'T27 %'; delete from public.notifications where kind = 'standard';
delete from public.profile_spaces where user_id::text like '00000000-0000-0000-0000-0000000000d_';
delete from public.profiles where username like 'std.%'; delete from auth.users where email like 'std.%@x';
select test, ok from rez where not ok or ok is null;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
