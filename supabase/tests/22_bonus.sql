-- Bonusul pe magazin (0022): trepte de creștere, conformitate, nota zilnică, management, închiderea lunii.
-- Rulează după 0022. Cifrele sunt inventate pentru test. Conturi proprii (…0000000081 …), șterse la final.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'bonus.' || k || '@x' from (values ('81'), ('82'), ('83'), ('84'), ('85'), ('86')) v (k)
on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code, created_at)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'bonus.' || k, n, r, now() - interval '200 days' from (values
  ('81', 'Vera V', 'V'), ('82', 'Rica RL', 'RL'), ('83', 'Costi PP', 'PP + B'), ('84', 'Gina GM', 'GM'), ('85', 'Fane V', 'V'), ('86', 'Ada AE', 'AE')) v (k, n, r)
on conflict do nothing;
insert into public.profile_spaces (user_id, space_id) values
  ('00000000-0000-0000-0000-000000000081', 'porumbescu'), ('00000000-0000-0000-0000-000000000082', 'porumbescu'),
  ('00000000-0000-0000-0000-000000000083', 'porumbescu'), ('00000000-0000-0000-0000-000000000085', 'fructus')
on conflict do nothing;
delete from public.notifications; delete from public.clockings; delete from public.shifts; delete from public.checklist_runs;
delete from public.contestatii; delete from public.note_calitate; delete from public.bonus_luni; delete from public.bonus_vanzari; delete from public.bonus_setari;
delete from public.procedure_docs where source_file like 'Procedura_Deschidere_Test22%';
insert into public.procedure_docs (space_id, title, body, source_file)
values ('porumbescu', 'Procedura de deschidere — test 22', '## A\n1. Unu', 'Procedura_Deschidere_Test22.pdf');
create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create or replace function pg_temp.u(k text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || k)::uuid $$;
create temp table rez (test text, ok boolean);
create temp table cod as select token from public.space_qr where space_id = 'porumbescu';
-- lp = luna trecută (se poate închide), lc = luna în curs
create temp table t as select (date_trunc('month', (now() at time zone 'Europe/Bucharest')::date) - interval '1 month')::date as lp,
                              date_trunc('month', (now() at time zone 'Europe/Bucharest')::date)::date as lc;
grant all on rez, cod, t to authenticated, anon;
-- omul k, din calculul văzut de contul logat
create or replace function pg_temp.om(k text) returns jsonb language sql as $$
  select o from jsonb_array_elements(public.bonus_calcul('porumbescu', (select lp from t)) -> 'oameni') o where o ->> 'user_id' = pg_temp.u(k)::text $$;

insert into public.bonus_setari (space_id, trepte, procent_vanzare, procent_coacere, conformitate_suma, conformitate_criterii, prag_proceduri,
                                 calitate_suma, calitate_prag, management_suma, management_criterii, plafon_procent)
values ('porumbescu', '[{"prag": 10, "fond": 1000}, {"prag": 20, "fond": 2000}]', 80, 20, 200,
        '[{"cheie": "proceduri", "nume": "Proceduri", "auto": "proceduri"}, {"cheie": "vitrina", "nume": "Vitrina"}]', 100, 100, 9.5, 800,
        '[{"cheie": "prima", "nume": "Toți au prima", "auto": "prima"}, {"cheie": "conf", "nume": "Toți au conformitatea", "auto": "conformitate"},
          {"cheie": "barem", "nume": "Toți au baremul", "auto": "barem"}, {"cheie": "acte", "nume": "Acte la zi"}]', 9);
insert into public.bonus_vanzari (space_id, an, luna, vanzari, medie_zilnica)
select 'porumbescu', extract(year from lp)::int - 1, extract(month from lp)::int, 26000, 1000 from t
union all select 'porumbescu', extract(year from lp)::int, extract(month from lp)::int, 30000, 1150 from t;
insert into public.bonus_luni (space_id, luna) select 'porumbescu', lp from t;
insert into public.bonus_oameni (space_id, luna, user_id, fel, manager, aport)
select 'porumbescu', lp, pg_temp.u('81'), 'vanzare', false, 6000 from t union all
select 'porumbescu', lp, pg_temp.u('82'), 'vanzare', true, 4000 from t union all
select 'porumbescu', lp, pg_temp.u('83'), 'coacere', false, 0 from t;
-- două zile lucrate în luna trecută, cu fișa de deschidere făcută în amândouă; note de calitate 10 și 9 (media 9,5)
insert into public.shifts (user_id, space_id, day, starts, ends, opens) select pg_temp.u('81'), 'porumbescu', lp + k, '07:00', '15:00', true from t, generate_series(1, 2) k;
insert into public.checklist_runs (cheie, doc_id, title, space_id, day, steps, due_at, finished_at, finished_by)
select 'doc:' || d.id, d.id, 'Deschidere', 'porumbescu', lp + k, '[{"t":"Unu"}]', ((lp + k) + time '09:00') at time zone 'Europe/Bucharest',
       ((lp + k) + time '08:00') at time zone 'Europe/Bucharest', pg_temp.u('81')
from t, generate_series(1, 2) k, public.procedure_docs d where d.source_file = 'Procedura_Deschidere_Test22.pdf';
insert into public.note_calitate (space_id, zi, user_id, nota, comentariu)
select 'porumbescu', lp + 1, pg_temp.u('81'), 10, '' from t union all select 'porumbescu', lp + 2, pg_temp.u('82'), 9, 'Croissante prea închise la culoare' from t;
set role authenticated;

-- ===== Cine vede ce =====
select pg_temp.ca('85');
do $$ begin
  perform public.bonus_calcul('porumbescu', (select lp from t));
  insert into rez values ('Altă locație nu vede bonusul magazinului', false);
exception when others then insert into rez values ('Altă locație nu vede bonusul magazinului', true); end $$;
insert into rez select 'Altă locație nu vede regulile și vânzările magazinului', (select count(*) from public.bonus_setari) = 0 and (select count(*) from public.bonus_vanzari) = 0;
select pg_temp.ca('81');
insert into rez select 'Vânzătoarea vede regulile magazinului ei, rândul ei din echipă și nimic din fotografia lunii',
  (select count(*) from public.bonus_setari) = 1 and (select count(*) from public.bonus_oameni) = 1 and (select count(*) from public.bonus_luni) = 0;
update public.bonus_setari set conformitate_suma = 9999;
update public.bonus_oameni set prima_calitate = true, aport = 99999;
do $$ begin
  insert into public.bonus_vanzari (space_id, an, luna, medie_zilnica) values ('porumbescu', 2099, 1, 1);
  insert into rez values ('Vânzătoarea nu scrie vânzări', false);
exception when others then insert into rez values ('Vânzătoarea nu scrie vânzări', true); end $$;
reset role;
insert into rez select 'Vânzătoarea nu-și schimbă regulile, aportul sau prima', (select conformitate_suma from public.bonus_setari) = 200
  and (select aport = 6000 and prima_calitate is null from public.bonus_oameni where user_id = pg_temp.u('81'));
set role authenticated;

-- ===== Calculul: +15% → fondul treptei de 10% =====
select pg_temp.ca('84');
insert into rez select 'Creștere 15% an-la-an: treapta de 10%, fond 1000', (v ->> 'crestere')::numeric = 15 and (v ->> 'fond')::numeric = 1000 and (v ->> 'declin')::boolean = false
  from (select public.bonus_calcul('porumbescu', (select lp from t)) -> 'vanzari' as v) x;
insert into rez select 'Reperele lunii: media zilnică necesară pentru fiecare treaptă', (v -> 0 ->> 'medie_necesara')::numeric = 1100 and (v -> 1 ->> 'medie_necesara')::numeric = 1200
  from (select public.bonus_calcul('porumbescu', (select lp from t)) -> 'vanzari' -> 'repere' as v) x;
insert into rez select 'Fondul: 80% la vânzare după aport (60 / 40), 20% la coacere',
  (pg_temp.om('81') ->> 'barem')::numeric = 480 and (pg_temp.om('82') ->> 'barem')::numeric = 320 and (pg_temp.om('83') ->> 'barem')::numeric = 200;
select pg_temp.ca('81');
insert into rez select 'Vânzătoarea își vede suma; pe ale colegilor, plafonul și managementul nu',
  (pg_temp.om('81') ->> 'barem')::numeric = 480 and not pg_temp.om('82') ? 'barem' and not pg_temp.om('83') ? 'aport'
  and not c ? 'plafon' and not c ? 'management' and (c -> 'eu' ->> 'fel') = 'vanzare' and not (c ->> 'pot_evalua')::boolean
  from (select public.bonus_calcul('porumbescu', (select lp from t)) as c) x;

-- ===== Conformitatea: totul sau nimic, evaluată de responsabil =====
do $$ begin
  perform public.bonus_evalueaza('porumbescu', (select lp from t), 'conformitate', '{"vitrina": {"ok": true}}');
  insert into rez values ('Vânzătoarea nu evaluează conformitatea', false);
exception when others then insert into rez values ('Vânzătoarea nu evaluează conformitatea', true); end $$;
select pg_temp.ca('82');
insert into rez select 'Fișele făcute în toate zilele lucrate: aplicația propune „îndeplinit”', (p ->> 'procent')::numeric = 100 and (p ->> 'propunere')::boolean
  and (p -> 'deschideri' ->> 'facute')::int = 2 and (p -> 'deschideri' ->> 'la_termen')::int = 2 and (p ->> 'zile')::int = 2
  and jsonb_typeof(p -> 'inchideri') = 'null'
  from (select public.bonus_calcul('porumbescu', (select lp from t)) -> 'proceduri' as p) x;
do $$ begin
  perform public.bonus_evalueaza('porumbescu', (select lp from t), 'conformitate', '{"proceduri": {"ok": true}, "vitrina": {"ok": false}}');
  insert into rez values ('Un criteriu neîndeplinit cere motiv scris', false);
exception when others then insert into rez values ('Un criteriu neîndeplinit cere motiv scris', true); end $$;
select public.bonus_evalueaza('porumbescu', (select lp from t), 'conformitate', '{"proceduri": {"ok": true}, "vitrina": {"ok": false, "nota": "Etichete lipsă în 4 zile"}}');
insert into rez select 'Un criteriu căzut din două: conformitatea nu se plătește deloc', (pg_temp.om('82') ->> 'conformitate')::numeric = 0
  and not (c -> 'conformitate' ->> 'indeplinita')::boolean and (c -> 'conformitate' ->> 'completa')::boolean
  from (select public.bonus_calcul('porumbescu', (select lp from t)) as c) x;
reset role;
insert into rez select 'Vânzătoarea află verdictul și criteriul căzut', count(*) = 1 from public.notifications
  where user_id = pg_temp.u('81') and kind = 'bonus' and title like '%neîndeplinită' and body like 'Neîndeplinit: Vitrina — Etichete lipsă%';
set role authenticated;
select pg_temp.ca('82');
select public.bonus_evalueaza('porumbescu', (select lp from t), 'conformitate', '{"vitrina": {"ok": true}}');
select pg_temp.ca('84');
insert into rez select 'Toate criteriile îndeplinite: suma se împarte după aport', (pg_temp.om('81') ->> 'conformitate')::numeric = 120 and (pg_temp.om('82') ->> 'conformitate')::numeric = 80
  and (pg_temp.om('83') ->> 'conformitate')::numeric = 0;
-- o fișă lipsă: propunerea devine „neîndeplinit”, iar responsabilul nu o poate contrazice fără motiv
reset role;
delete from public.checklist_runs where day = (select lp + 2 from t);
set role authenticated;
select pg_temp.ca('82');
insert into rez select 'O fișă lipsă din două: 50%, propunere „neîndeplinit”, cu ziua lipsă la vedere', (p ->> 'procent')::numeric = 50 and not (p ->> 'propunere')::boolean
  and jsonb_array_length(p -> 'lipsa') = 1 and p -> 'lipsa' -> 0 ->> 'tip' = 'deschidere'
  from (select public.bonus_calcul('porumbescu', (select lp from t)) -> 'proceduri' as p) x;
do $$ begin
  perform public.bonus_evalueaza('porumbescu', (select lp from t), 'conformitate', '{"proceduri": {"ok": true}}');
  insert into rez values ('Verdictul care contrazice fișele cere motiv', false);
exception when others then insert into rez values ('Verdictul care contrazice fișele cere motiv', true); end $$;
-- lipsa e contestată și contestația e admisă: nu se mai numără
reset role;
insert into public.contestatii (user_id, cheie, zi, puncte, detaliu, motiv, status)
select pg_temp.u('81'), 'fisa-lipsa:' || s.id || ':d', s.day, -10, 'Fișa de deschidere nefăcută', 'Aplicația nu a mers în ziua aceea', 'admisa'
from public.shifts s, t where s.user_id = pg_temp.u('81') and s.day = lp + 2;
set role authenticated;
select pg_temp.ca('82');
insert into rez select 'Lipsa cu contestație admisă nu se mai numără', (p ->> 'procent')::numeric = 100 and (p ->> 'propunere')::boolean and (p -> 'deschideri' ->> 'scuzate')::int = 1
  from (select public.bonus_calcul('porumbescu', (select lp from t)) -> 'proceduri' as p) x;

-- ===== Magazin în declin: nimic din sistemul magazinului =====
reset role;
update public.bonus_vanzari set medie_zilnica = 900 where an = (select extract(year from lp)::int from t);
set role authenticated;
select pg_temp.ca('84');
insert into rez select 'Declin (−10%): fără barem, fără conformitate, fără bonusul de calitate',
  (c -> 'vanzari' ->> 'declin')::boolean and (pg_temp.om('81') ->> 'total')::numeric = 0 and (pg_temp.om('83') ->> 'total')::numeric = 0
  and (pg_temp.om('82') ->> 'barem')::numeric = 0 and (pg_temp.om('82') ->> 'conformitate')::numeric = 0
  from (select public.bonus_calcul('porumbescu', (select lp from t)) as c) x;
reset role;
update public.bonus_vanzari set medie_zilnica = 1150 where an = (select extract(year from lp)::int from t);
set role authenticated;

-- ===== Prima de calitate: cine nu a încasat-o nu primește nimic =====
select pg_temp.ca('84');
update public.bonus_oameni set prima_calitate = (user_id <> pg_temp.u('83')) where luna = (select lp from t);
insert into rez select 'Fără prima de calitate: 0 la tot; ceilalți primesc la fel (partea lui nu se împarte)',
  (pg_temp.om('83') ->> 'total')::numeric = 0 and (pg_temp.om('81') ->> 'barem')::numeric = 480 and (pg_temp.om('81') ->> 'conformitate')::numeric = 120;

-- ===== Bonusul de management: criteriile de echipă se calculează, cel individual îl bifează conducerea =====
select pg_temp.ca('82');
do $$ begin
  perform public.bonus_evalueaza('porumbescu', (select lp from t), 'management', '{"acte": {"ok": true}}');
  insert into rez values ('Responsabilul nu-și bifează singur criteriile de management', false);
exception when others then insert into rez values ('Responsabilul nu-și bifează singur criteriile de management', true); end $$;
insert into rez select 'Responsabilul își vede criteriile de management', jsonb_array_length(public.bonus_calcul('porumbescu', (select lp from t)) -> 'management' -> 'criterii') = 4;
select pg_temp.ca('84');
do $$ begin
  perform public.bonus_evalueaza('porumbescu', (select lp from t), 'management', '{"prima": {"ok": true}}');
  insert into rez values ('Un criteriu calculat nu se bifează de mână', false);
exception when others then insert into rez values ('Un criteriu calculat nu se bifează de mână', true); end $$;
select public.bonus_evalueaza('porumbescu', (select lp from t), 'management', '{"acte": {"ok": true}}');
-- cel care coace nu are prima: cad „toți au prima” și „toți au baremul”; rămân conformitatea colegei și actele: 2 din 4
insert into rez select 'Management: 2 criterii din 4, câte 200', (pg_temp.om('82') ->> 'management')::numeric = 400 and (m ->> 'indeplinite')::int = 2
  and (select bool_and((k ->> 'ok')::boolean = (k ->> 'cheie' in ('conf', 'acte'))) from jsonb_array_elements(m -> 'criterii') k)
  from (select public.bonus_calcul('porumbescu', (select lp from t)) -> 'management' as m) x;
update public.bonus_oameni set prima_calitate = true where luna = (select lp from t);
insert into rez select 'Toți cu prima: 4 din 4, iar cel care coace primește și bonusul de calitate (media 9,5)',
  (pg_temp.om('82') ->> 'management')::numeric = 800 and (pg_temp.om('83') ->> 'calitate')::numeric = 100 and (pg_temp.om('83') ->> 'total')::numeric = 300
  and (c -> 'calitate' ->> 'medie')::numeric = 9.5 and (c -> 'calitate' ->> 'zile')::int = 2
  from (select public.bonus_calcul('porumbescu', (select lp from t)) as c) x;
insert into rez select 'Conducerea vede cât costă sistemul din vânzările lunii', (p ->> 'total_sistem')::numeric = 1300 and (p ->> 'procent')::numeric = 4.3
  from (select public.bonus_calcul('porumbescu', (select lp from t)) -> 'plafon' as p) x;

-- ===== Nota zilnică de calitate (luna în curs) =====
select pg_temp.ca('82');
insert into rez select 'Fără clock-in nu apare nota de azi', public.bonus_azi() is null;
select pg_temp.ca('81');
select public.pontaj_intrare('porumbescu', (select token from cod));
insert into rez select 'În tură, vânzătoarea poate da nota de azi', (public.bonus_azi() ->> 'pot_nota')::boolean and public.bonus_azi() -> 'nota_mea' = 'null';
do $$ begin
  insert into public.note_calitate (space_id, nota) values ('porumbescu', 9);
  insert into rez values ('Nota sub prag cere motiv', false);
exception when others then insert into rez values ('Nota sub prag cere motiv', true); end $$;
do $$ begin
  insert into public.note_calitate (space_id, nota, comentariu) values ('porumbescu', 9.3, 'aproape');
  insert into rez values ('Nota merge doar din jumătate în jumătate', false);
exception when others then insert into rez values ('Nota merge doar din jumătate în jumătate', true); end $$;
insert into public.note_calitate (space_id, nota, comentariu, zi, user_id) values ('porumbescu', 9, 'Baguette prea coaptă', '2020-01-01', pg_temp.u('82'));
insert into rez select 'Nota se dă doar pentru azi, pe numele celui logat', count(*) = 1 and bool_and(zi = (now() at time zone 'Europe/Bucharest')::date and user_id = pg_temp.u('81'))
  from public.note_calitate where zi >= (select lc from t);
update public.note_calitate set nota = 10, comentariu = '' where zi >= (select lc from t);
insert into rez select 'Își poate schimba nota de azi', (public.bonus_azi() -> 'nota_mea' ->> 'nota')::numeric = 10;
select pg_temp.ca('83');
select public.pontaj_intrare('porumbescu', (select token from cod));
do $$ begin
  insert into public.note_calitate (space_id, nota) values ('porumbescu', 10);
  insert into rez values ('Cel care coace nu-și notează singur produsele', false);
exception when others then insert into rez values ('Cel care coace nu-și notează singur produsele', true); end $$;
insert into rez select 'Cel care coace vede notele și motivele', count(*) = 3 from public.note_calitate;
reset role;
insert into rez select 'Nota sub prag ajunge, cu motivul, la cel care coace', count(*) = 1 from public.notifications
  where user_id = pg_temp.u('83') and kind = 'calitate' and title like 'Nota vitrinei de azi la Porumbescu: 9,0' and body like '„Baguette prea coaptă”%';
insert into rez select 'Luna în curs și-a luat singură echipa din luna trecută', count(*) = 3 from public.bonus_oameni where luna = (select lc from t);
set role authenticated;

-- ===== Închiderea bonusului =====
select pg_temp.ca('82');
do $$ begin
  perform public.bonus_inchide('porumbescu', (select lp from t));
  insert into rez values ('Responsabilul nu închide bonusul', false);
exception when others then insert into rez values ('Responsabilul nu închide bonusul', true); end $$;
select pg_temp.ca('84');
do $$ begin
  perform public.bonus_inchide('porumbescu', (select lc from t));
  insert into rez values ('Luna în curs nu se închide', false);
exception when others then insert into rez values ('Luna în curs nu se închide', true); end $$;
update public.bonus_oameni set prima_calitate = null where luna = (select lp from t) and user_id = pg_temp.u('83');
do $$ begin
  perform public.bonus_inchide('porumbescu', (select lp from t));
  insert into rez values ('Nu se închide cu prima de calitate nehotărâtă', false);
exception when others then insert into rez values ('Nu se închide cu prima de calitate nehotărâtă', true); end $$;
update public.bonus_oameni set prima_calitate = true where luna = (select lp from t);
select public.bonus_inchide('porumbescu', (select lp from t));
reset role;
insert into rez select 'GM închide bonusul: fiecare primește suma lui în notificare', (select count(*) from public.notifications where kind = 'bonus' and title like 'Bonusul pe % la Porumbescu: % lei brut') = 3
  and exists (select 1 from public.notifications where user_id = pg_temp.u('81') and title like '%: 600 lei brut');
update public.bonus_vanzari set medie_zilnica = 900 where an = (select extract(year from lp)::int from t);
set role authenticated;
select pg_temp.ca('81');
insert into rez select 'După închidere cifrele rămân înghețate, chiar dacă se schimbă vânzările', (pg_temp.om('81') ->> 'total')::numeric = 600
  and c -> 'inchisa' ->> 'la' is not null and (c -> 'vanzari' ->> 'fond')::numeric = 1000
  from (select public.bonus_calcul('porumbescu', (select lp from t)) as c) x;
select pg_temp.ca('82');
do $$ begin
  perform public.bonus_evalueaza('porumbescu', (select lp from t), 'conformitate', '{"vitrina": {"ok": false, "nota": "m-am răzgândit"}}');
  insert into rez values ('După închidere nu se mai evaluează', false);
exception when others then insert into rez values ('După închidere nu se mai evaluează', true); end $$;
select pg_temp.ca('84');
do $$ begin
  update public.bonus_oameni set aport = 1 where luna = (select lp from t);
  insert into rez values ('După închidere echipa lunii nu se mai schimbă', false);
exception when others then insert into rez values ('După închidere echipa lunii nu se mai schimbă', true); end $$;
select pg_temp.ca('86');
do $$ begin
  perform public.bonus_redeschide('porumbescu', (select lp from t));
  insert into rez values ('AE nu redeschide bonusul', false);
exception when others then insert into rez values ('AE nu redeschide bonusul', true); end $$;
select pg_temp.ca('84');
select public.bonus_redeschide('porumbescu', (select lp from t));
insert into rez select 'Adminul (GM) îl redeschide: calculul e din nou viu (acum declin)', c -> 'inchisa' = 'null' and (c -> 'vanzari' ->> 'declin')::boolean
  from (select public.bonus_calcul('porumbescu', (select lp from t)) as c) x;

set role anon;
do $$ begin perform public.bonus_calcul('porumbescu', null); insert into rez values ('Anonimul nu are bonus', false);
exception when others then insert into rez values ('Anonimul nu are bonus', true); end $$;
do $$ begin perform 1 from public.bonus_vanzari; insert into rez values ('Anonimul nu vede vânzări', false);
exception when others then insert into rez values ('Anonimul nu vede vânzări', true); end $$;
reset role;
-- datele și conturile testului dispar
delete from public.note_calitate; delete from public.bonus_luni; delete from public.bonus_vanzari; delete from public.bonus_setari;
delete from public.contestatii; delete from public.notifications; delete from public.clockings;
delete from public.checklist_runs where title = 'Deschidere';
delete from public.shifts where user_id::text like '00000000-0000-0000-0000-00000000008%';
delete from public.procedure_docs where source_file like 'Procedura_Deschidere_Test22%';
delete from public.profiles where user_id::text like '00000000-0000-0000-0000-00000000008%';
delete from auth.users where id::text like '00000000-0000-0000-0000-00000000008%';
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
