-- Tura (0016, 0017): program, clock-in cu QR, fișe bifate, notificări către șefi și AE. Rulează după 0017.
-- Conturi proprii testului (…00000000a1 …), ca să nu depindă de celelalte teste.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'tura.' || k || '@x' from (values
  ('a1'), ('a2'), ('a3'), ('a4'), ('a5'), ('a6'), ('a7'), ('a8'), ('a9')) v (k)
on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'tura.' || k, n, r from (values
  ('a1', 'Ana V', 'V'), ('a2', 'Bia V', 'V'), ('a3', 'Cris BAR', 'BAR'), ('a4', 'Dan VT', 'VT'), ('a5', 'Eva RL', 'RL'),
  ('a6', 'Gigi GM', 'GM'), ('a7', 'Ion PBR', 'PBR'), ('a8', 'Sorin SP', 'SP'), ('a9', 'Alina AE', 'AE')) v (k, n, r)
on conflict do nothing;
delete from public.notifications; delete from public.clockings; delete from public.shifts; delete from public.notificari_trimise;
delete from public.checklist_runs;
delete from public.procedure_docs where source_file like 'Test_tura_%';
insert into public.procedure_docs (space_id, title, body, source_file)
values ('porumbescu', 'Procedura de deschidere — test', '## A\n1. Unu\n2. Doi\n3. Trei', 'Test_tura_Procedura_Deschidere.pdf');

create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create or replace function pg_temp.u(k text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || k)::uuid $$;
create temp table rez (test text, ok boolean);
create temp table cod as select token from public.space_qr where space_id = 'porumbescu';
create temp table azi as select (now() at time zone 'Europe/Bucharest')::date as d;
grant all on rez, cod, azi to authenticated, anon;
set role authenticated;

-- Programul
select pg_temp.ca('a5');
insert into public.shifts (user_id, space_id, day, starts, ends, opens)
  select pg_temp.u('a1'), 'porumbescu', d, ((now() - interval '1 hour') at time zone 'Europe/Bucharest')::time,
         ((now() + interval '6 hours') at time zone 'Europe/Bucharest')::time, true from azi;
insert into rez select 'RL programează un vânzător', count(*) = 1 from public.shifts where user_id = pg_temp.u('a1');
select pg_temp.ca('a4');
insert into public.shifts (user_id, space_id, day, starts, ends) select pg_temp.u('a2'), 'porumbescu', d, '12:00', '20:00' from azi;
insert into rez select 'VT programează un vânzător', count(*) = 1 from public.shifts where user_id = pg_temp.u('a2');
do $$ begin
  insert into public.shifts (user_id, space_id, day, starts, ends) select pg_temp.u('a5'), 'porumbescu', d, '08:00', '16:00' from azi;
  insert into rez values ('VT nu-și programează șeful (RL)', false);
exception when others then insert into rez values ('VT nu-și programează șeful (RL)', true); end $$;
select pg_temp.ca('a1');
do $$ begin
  insert into public.shifts (user_id, space_id, day, starts, ends) select pg_temp.u('a2'), 'porumbescu', d, '08:00', '16:00' from azi;
  insert into rez values ('V nu face program', false);
exception when others then insert into rez values ('V nu face program', true); end $$;
insert into rez select 'V își vede tura și pe a colegei de aceeași zi', count(*) = 2 from public.shifts;
select pg_temp.ca('a3');
insert into rez select 'Barista fără tură acolo nu vede turele', count(*) = 0 from public.shifts;
select pg_temp.ca('a7');
do $$ begin
  insert into public.shifts (user_id, space_id, day, starts, ends) select pg_temp.u('a7'), 'peciu-nou', d, '22:00', '06:00' from azi;
  insert into rez values ('PBR nu-și face singur program', false);
exception when others then insert into rez values ('PBR nu-și face singur program', true); end $$;
select pg_temp.ca('a8');
insert into public.shifts (user_id, space_id, day, starts, ends) select pg_temp.u('a7'), 'peciu-nou', d, '22:00', '06:00' from azi;
insert into rez select 'SP programează producția (tură de noapte)', count(*) = 1 from public.shifts where user_id = pg_temp.u('a7');

-- Echipa
select pg_temp.ca('a5');
insert into rez select 'RL își vede echipa de vânzare', array_agg(full_name order by full_name) = array['Ana V', 'Bia V', 'Cris BAR', 'Dan VT', 'Eva RL'] from public.echipa_mea();
select pg_temp.ca('a1');
insert into rez select 'V se vede doar pe sine', array_agg(full_name) = array['Ana V'] from public.echipa_mea();
insert into rez select 'V nu are panoul echipei', not public.vede_echipa();
select pg_temp.ca('a9');
insert into rez select 'AE are panoul echipei', public.vede_echipa();
select pg_temp.ca('a1');
insert into rez select 'V nu vede codurile QR', count(*) = 0 from public.space_qr;

-- Clock-in
do $$ begin
  perform public.pontaj_intrare('porumbescu', 'gresit');
  insert into rez values ('Clock-in cu cod greșit e refuzat', false);
exception when others then insert into rez values ('Clock-in cu cod greșit e refuzat', true); end $$;
select public.pontaj_intrare('porumbescu', (select token from cod));
insert into rez select 'Clock-in cu codul locației, legat de tura din program', count(*) = 1 from public.clockings where shift_id is not null and clock_out is null;
select public.pontaj_intrare('porumbescu', (select token from cod));
insert into rez select 'Al doilea scan nu dublează pontajul', count(*) = 1 from public.clockings;
do $$ begin
  perform public.pontaj_intrare('fructus', (select token from public.space_qr where space_id = 'fructus'));
  insert into rez values ('Nu poți intra în tură în două locuri', false);
exception when others then insert into rez values ('Nu poți intra în tură în două locuri', true); end $$;
reset role;
insert into rez select 'Clock-in: notificare la VT, RL, GM și AE', array_agg(p.role_code order by p.role_code) = array['AE', 'GM', 'RL', 'VT']
  from public.notifications n join public.profiles p using (user_id) where n.kind = 'clock_in';
insert into rez select 'Barista (fără legătură cu tura) nu primește', not exists (select 1 from public.notifications where user_id = pg_temp.u('a3'));
set role authenticated;

-- Fișa
select pg_temp.ca('a3');
do $$ begin
  insert into public.checklist_runs (cheie, title, space_id, steps) values ('doc:x', 'x', 'porumbescu', '[]');
  insert into rez values ('Fără clock-in nu pornești o fișă', false);
exception when others then insert into rez values ('Fără clock-in nu pornești o fișă', true); end $$;
select pg_temp.ca('a1');
insert into public.checklist_runs (cheie, doc_id, title, space_id, steps)
select 'doc:' || id, id, 'Deschiderea', 'porumbescu', '[{"t":"Unu"},{"t":"Doi"},{"t":"Trei"}]'
from public.procedure_docs where source_file = 'Test_tura_Procedura_Deschidere.pdf';
insert into public.checklist_marks (run_id, idx, status) select id, 0, 'facut' from public.checklist_runs;
insert into public.checklist_marks (run_id, idx, status) select id, 1, 'facut' from public.checklist_runs;
insert into rez select 'Fișa nu e gata după 2 din 3 pași', finished_at is null from public.checklist_runs;
update public.checklist_runs set steps = '[]', title = 'altceva', note = '';
insert into rez select 'Pașii fișei nu se schimbă din pagină', jsonb_array_length(steps) = 3 and title = 'Deschiderea' from public.checklist_runs;
insert into public.checklist_marks (run_id, idx, status, note) select id, 2, 'nefacut', 'Frigiderul nu pornește' from public.checklist_runs;
insert into rez select 'Ultimul pas o termină', finished_at is not null from public.checklist_runs;
do $$ begin
  update public.checklist_marks set status = 'facut' where idx = 2;
  insert into rez select 'După final pașii nu se mai schimbă', status = 'nefacut' from public.checklist_marks where idx = 2;
end $$;
reset role;
insert into rez select 'Pas nefăcut: șefii și AE primesc notificarea', count(*) = 4 from public.notifications where kind = 'pas_nefacut';
insert into rez select 'Fișa gata: șefii și AE primesc notificarea', count(*) = 4 from public.notifications
  where kind = 'fisa_gata' and body like '%1 pași nefăcuți%';
set role authenticated;

-- Notificările
select pg_temp.ca('a4');
insert into rez select 'VT își vede notificările', count(*) >= 3 from public.notifications;
update public.notifications set read_at = now();
insert into rez select 'VT le marchează citite', bool_and(read_at is not null) from public.notifications;
select pg_temp.ca('a1');
insert into rez select 'V nu vede notificările șefilor', count(*) = 0 from public.notifications;
do $$ begin
  insert into public.notifications (user_id, kind, title) values (pg_temp.u('a4'), 'x', 'fals');
  insert into rez values ('Nimeni nu scrie notificări din pagină', false);
exception when others then insert into rez values ('Nimeni nu scrie notificări din pagină', true); end $$;

-- Clock-out
select public.pontaj_iesire('porumbescu', (select token from cod));
insert into rez select 'Clock-out închide tura', count(*) = 1 from public.clockings where clock_out is not null;
reset role;
insert into rez select 'Clock-out: notificare la șefi și AE', count(*) = 4 from public.notifications where kind = 'clock_out';

-- Verificările de la 5 minute
insert into public.shifts (user_id, space_id, day, starts, ends, opens)
select pg_temp.u('a2'), 'fructus', (n at time zone 'Europe/Bucharest')::date, (n at time zone 'Europe/Bucharest')::time, '23:59', true
from (select now() + interval '15 minutes' as n) x;
insert into public.shifts (user_id, space_id, day, starts, ends)
select pg_temp.u('a3'), 'fructus', (n at time zone 'Europe/Bucharest')::date, (n at time zone 'Europe/Bucharest')::time, '23:59'
from (select now() - interval '20 minutes' as n) x;
select public.verifica_ture();
select public.verifica_ture();
insert into rez select 'Memento cu 15 min înainte (o singură dată)', count(*) = 1 from public.notifications
  where kind = 'memento' and user_id = pg_temp.u('a2') and title like 'Deschizi Fructus%';
insert into rez select 'Fără clock-in după 10 min: șefii și AE află', count(*) = 4 from public.notifications
  where kind = 'intarziere' and title like '%Cris BAR%nu a făcut clock-in';

set role anon;
do $$ begin perform 1 from public.shifts; insert into rez values ('Anonimul nu vede programul', false);
exception when others then insert into rez values ('Anonimul nu vede programul', true); end $$;
reset role;
delete from public.procedure_docs where source_file like 'Test_tura_%';
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
