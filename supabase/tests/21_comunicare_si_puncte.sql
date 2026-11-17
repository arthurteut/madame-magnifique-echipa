-- Comunicarea și punctajul transparent (0021): semnalări, anunțuri, feedback, pierderi, contestații, luna închisă.
-- Rulează după 0021. Conturi proprii testului (…0000000071 …), șterse la final.
\set ON_ERROR_STOP off
\pset footer off
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'com.' || k || '@x' from (values ('71'), ('72'), ('73'), ('74'), ('75'), ('76')) v (k)
on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code, created_at)
select ('00000000-0000-0000-0000-0000000000' || k)::uuid, 'com.' || k, n, r, now() - interval '120 days' from (values
  ('71', 'Vio V', 'V'), ('72', 'Rica RL', 'RL'), ('73', 'Gina GM', 'GM'), ('74', 'Tavi VT', 'VT'), ('75', 'Fane V', 'V'), ('76', 'Cora V', 'V')) v (k, n, r)
on conflict do nothing;
insert into public.profile_spaces (user_id, space_id) values
  ('00000000-0000-0000-0000-000000000071', 'porumbescu'), ('00000000-0000-0000-0000-000000000072', 'porumbescu'),
  ('00000000-0000-0000-0000-000000000074', 'porumbescu'), ('00000000-0000-0000-0000-000000000076', 'porumbescu'),
  ('00000000-0000-0000-0000-000000000075', 'fructus')
on conflict do nothing;
delete from public.notifications; delete from public.clockings; delete from public.shifts; delete from public.checklist_runs;
delete from public.semnalari; delete from public.anunturi; delete from public.feedback; delete from public.contestatii; delete from public.luni_inchise;
delete from public.procedure_docs where source_file like 'Procedura_Deschidere_Test21%';
insert into public.procedure_docs (space_id, title, body, source_file)
values ('porumbescu', 'Procedura de deschidere — test 21', '## A\n1. Unu', 'Procedura_Deschidere_Test21.pdf');
create or replace function pg_temp.ca(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || k, false); end $$;
create or replace function pg_temp.u(k text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || k)::uuid $$;
-- punctele unui om pe chei care încep cu un prefix (citite direct, ca administrator al bazei)
create or replace function pg_temp.xp(k text, prefix text) returns int language sql as $$
  select coalesce(sum(puncte), 0)::int from public.xp_evenimente('2000-01-01', (now() at time zone 'Europe/Bucharest')::date, pg_temp.u(k))
  where cheie like prefix || '%' $$;
create temp table rez (test text, ok boolean);
create temp table cod as select token from public.space_qr where space_id = 'porumbescu';
create temp table luna as select (date_trunc('month', (now() at time zone 'Europe/Bucharest')::date) - interval '2 months')::date as l;
grant all on rez, cod, luna to authenticated, anon;
set role authenticated;

-- ===== Semnalări =====
select pg_temp.ca('71');
insert into public.semnalari (space_id, categorie, text, urgent, status) values ('porumbescu', 'echipament', 'Frigiderul de la bar nu răcește', true, 'rezolvata');
insert into rez select 'Vânzătoarea semnalează; pornește mereu ca deschisă', count(*) = 1 and bool_and(status = 'deschisa' and user_id = pg_temp.u('71')) from public.semnalari;
insert into public.semnalari (space_id, categorie, text, privata) values ('porumbescu', 'echipa', 'Am o problemă cu programul de sâmbătă', true);
select pg_temp.ca('76');
insert into rez select 'Colega vede semnalarea locației, nu și pe cea „doar pentru șefi”', count(*) = 1 from public.semnalari;
update public.semnalari set status = 'rezolvata';
insert into rez select 'Colega nu rezolvă semnalări', bool_and(status = 'deschisa') from public.semnalari;
select pg_temp.ca('75');
insert into rez select 'Altă locație nu vede semnalările', count(*) = 0 from public.semnalari;
do $$ begin
  insert into public.semnalari (space_id, text) values ('porumbescu', 'nu sunt de aici');
  insert into rez values ('Nu semnalezi la o locație pe care nu o vezi', false);
exception when others then insert into rez values ('Nu semnalezi la o locație pe care nu o vezi', true); end $$;
select pg_temp.ca('74');
insert into rez select 'VT vede și semnalarea „doar pentru șefi”', count(*) = 2 from public.semnalari;
update public.semnalari set status = 'in_lucru', raspuns = 'Am chemat service-ul' where categorie = 'echipament';
insert into rez select 'VT preia semnalarea', status = 'in_lucru' and preluat_de = pg_temp.u('74') from public.semnalari where categorie = 'echipament';
do $$ begin
  update public.semnalari set text = 'altceva';
  insert into rez values ('Textul semnalării nu se schimbă', false);
exception when others then insert into rez values ('Textul semnalării nu se schimbă', true); end $$;
select pg_temp.ca('72');
do $$ begin
  update public.semnalari set status = 'respinsa' where categorie = 'echipa';
  insert into rez values ('Respingerea cere un motiv', false);
exception when others then insert into rez values ('Respingerea cere un motiv', true); end $$;
update public.semnalari set status = 'respinsa', raspuns = 'Programul rămâne cum e afișat' where categorie = 'echipa';
update public.semnalari set status = 'rezolvata' where categorie = 'echipament';
insert into rez select 'RL rezolvă semnalarea', status = 'rezolvata' and rezolvat_de = pg_temp.u('72') and rezolvat_la is not null
  from public.semnalari where categorie = 'echipament';
reset role;
insert into rez select 'Semnalare rezolvată: +10 celui care a trimis-o, +5 celui care a rezolvat-o', pg_temp.xp('71', 'semnalare:') = 10 and pg_temp.xp('72', 'semnalare-rez:') = 5;
insert into rez select 'Semnalarea respinsă nu aduce puncte', (select count(*) from public.xp_evenimente('2000-01-01', current_date + 1, pg_temp.u('71')) where cheie like 'semnalare:%') = 1;
insert into rez select 'Semnalarea ajunge la VT, RL și GM, nu la colegi', (select count(distinct user_id) from public.notifications
  where kind = 'semnalare' and title like '%URGENT%' and user_id in (pg_temp.u('72'), pg_temp.u('73'), pg_temp.u('74'))) = 3
  and not exists (select 1 from public.notifications where kind = 'semnalare' and user_id in (pg_temp.u('75'), pg_temp.u('76')));
insert into rez select 'Vânzătoarea află când e în lucru și când e rezolvată', (select count(*) from public.notifications
  where user_id = pg_temp.u('71') and kind = 'semnalare' and title in ('Semnalarea ta e în lucru', 'Semnalarea ta e rezolvată')) = 2;
-- plafonul: din 4 semnalări rezolvate în aceeași zi se punctează primele 3
set role authenticated;
select pg_temp.ca('76');
insert into public.semnalari (space_id, text) select 'porumbescu', 'Lipsă pungi mari, nr. ' || g from generate_series(1, 4) g;
select pg_temp.ca('72');
update public.semnalari set status = 'rezolvata' where text like 'Lipsă pungi mari%';
reset role;
insert into rez select 'Din 4 semnalări rezolvate într-o zi se punctează 3', pg_temp.xp('76', 'semnalare:') = 30;
set role authenticated;

-- ===== Anunțuri =====
select pg_temp.ca('71');
do $$ begin
  insert into public.anunturi (space_id, title) values ('porumbescu', 'Anunț de la o vânzătoare');
  insert into rez values ('Vânzătoarea nu trimite anunțuri', false);
exception when others then insert into rez values ('Vânzătoarea nu trimite anunțuri', true); end $$;
select pg_temp.ca('72');
do $$ begin
  insert into public.anunturi (space_id, title) values (null, 'Anunț pentru toată firma, de la RL');
  insert into rez values ('RL nu anunță toată firma', false);
exception when others then insert into rez values ('RL nu anunță toată firma', true); end $$;
insert into public.anunturi (space_id, title, body) values ('porumbescu', 'Vitrina de lunch se face la 10:45', 'De luni, nu la 11:00.');
reset role;
insert into rez select 'Anunțul locației: destinatari sunt colegii de acolo, nu autorul, nu GM, nu altă locație',
  array_agg(right(user_id::text, 2) order by user_id) = array['71', '74', '76']
  from public.anunturi_citiri where user_id::text like '00000000-0000-0000-0000-00000000007%';
set role authenticated;
select pg_temp.ca('73');
insert into public.anunturi (space_id, title) values (null, 'Inventar general pe 30');
select pg_temp.ca('75');
insert into rez select 'Anunțul firmei ajunge și la Fructus; cel de la Porumbescu nu', count(*) = 1 from public.anunturi;
select pg_temp.ca('71');
update public.anunturi_citiri set read_at = now();
insert into rez select '„Am citit” îmi confirmă doar anunțurile mele', (select count(*) from public.anunturi_citiri where user_id = pg_temp.u('71') and read_at is not null) = 2
  and (public.joc_eu() ->> 'de_confirmat')::int = 0;
select pg_temp.ca('72');
insert into rez select 'RL vede cine nu a citit', (a -> 'stare' -> 'necitite') ? 'Cora V (V)' and not (a -> 'stare' -> 'necitite') ? 'Vio V (V)'
  from jsonb_array_elements(public.mesajele_mele() -> 'anunturi') a where a ->> 'title' like 'Vitrina de lunch%';
-- trec 25 de ore: Vio a confirmat la timp, Cora nu
reset role;
update public.anunturi set created_at = now() - interval '25 hours';
update public.anunturi_citiri set read_at = now() - interval '24 hours' where read_at is not null;
insert into rez select 'Anunț neconfirmat în 24 h: −2 pentru fiecare; cine a confirmat nu pierde',
  pg_temp.xp('76', 'anunt:') = -4 and pg_temp.xp('71', 'anunt:') = 0 and pg_temp.xp('75', 'anunt:') = -2 and pg_temp.xp('72', 'anunt:') = -2;
set role authenticated;

-- ===== Feedback de la șefi =====
select pg_temp.ca('71');
do $$ begin
  insert into public.feedback (to_user, fel, text, puncte) values (pg_temp.u('76'), 'apreciere', 'Bravo, colega', 10);
  insert into rez values ('Colegii nu-și dau puncte între ei', false);
exception when others then insert into rez values ('Colegii nu-și dau puncte între ei', true); end $$;
select pg_temp.ca('72');
insert into public.feedback (to_user, fel, text, puncte) values (pg_temp.u('71'), 'apreciere', 'Vitrina de azi a fost exemplară', 10);
do $$ begin
  insert into public.feedback (to_user, fel, text, puncte) values (pg_temp.u('71'), 'apreciere', 'Încă o apreciere mare', 20);
  insert into rez values ('Plafon: cel mult 20 XP din aprecieri pe zi', false);
exception when others then insert into rez values ('Plafon: cel mult 20 XP din aprecieri pe zi', true); end $$;
do $$ begin
  insert into public.feedback (to_user, fel, text, puncte) values (pg_temp.u('71'), 'imbunatatire', 'Prea mult', -20);
  insert into rez values ('„De îmbunătățit” ia cel mult 10 XP', false);
exception when others then insert into rez values ('„De îmbunătățit” ia cel mult 10 XP', true); end $$;
insert into public.feedback (to_user, fel, text, puncte) values (pg_temp.u('71'), 'imbunatatire', 'Etichetele de alergeni lipseau la 3 produse', -5);
do $$ begin
  insert into public.feedback (to_user, fel, text, puncte) values (pg_temp.u('75'), 'apreciere', 'Om de la altă locație', 5);
  insert into rez values ('RL nu dă puncte la altă locație', false);
exception when others then insert into rez values ('RL nu dă puncte la altă locație', true); end $$;
reset role;
insert into rez select 'Apreciere +10 și observație −5, cu motiv în jurnal', pg_temp.xp('71', 'feedback:') = 5
  and exists (select 1 from public.xp_evenimente('2000-01-01', current_date + 1, pg_temp.u('71')) where puncte = -5 and detaliu like 'De îmbunătățit, de la Rica RL (RL): Etichetele%');
insert into rez select 'Omul primește notificare cu punctele', (select count(*) from public.notifications where user_id = pg_temp.u('71') and kind = 'feedback'
  and (title = 'Apreciere de la Rica RL (RL) · +10 XP' or title = 'De îmbunătățit, de la Rica RL (RL) · −5 XP')) = 2;
set role authenticated;
select pg_temp.ca('76');
insert into rez select 'Colega nu vede feedbackul altcuiva', count(*) = 0 from public.feedback;
select pg_temp.ca('71');
update public.feedback set raspuns = 'Am înțeles, le verific în fiecare dimineață' where fel = 'imbunatatire';
insert into rez select 'Omul confirmă și răspunde', read_at is not null and raspuns like 'Am înțeles%' from public.feedback where fel = 'imbunatatire';
do $$ begin
  update public.feedback set puncte = 20;
  insert into rez values ('Omul nu-și schimbă singur punctele', false);
exception when others then insert into rez values ('Omul nu-și schimbă singur punctele', true); end $$;

-- ===== Contestații =====
do $$ begin
  perform public.contesta((select 'feedback:' || id from public.feedback where fel = 'apreciere'), 'vreau mai mult');
  insert into rez values ('Se contestă doar pierderile', false);
exception when others then insert into rez values ('Se contestă doar pierderile', true); end $$;
select public.contesta((select 'feedback:' || id from public.feedback where fel = 'imbunatatire'), 'Etichetele erau puse; au căzut la curățenia vitrinei');
insert into rez select 'Vânzătoarea contestă observația', count(*) = 1 and bool_and(status = 'deschisa' and puncte = -5) from public.contestatii;
do $$ begin
  perform public.contesta((select 'feedback:' || id from public.feedback where fel = 'imbunatatire'), 'încă o dată');
  insert into rez values ('O pierdere se contestă o singură dată', false);
exception when others then insert into rez values ('O pierdere se contestă o singură dată', true); end $$;
select pg_temp.ca('72');
do $$ begin
  perform public.decide_contestatie((select id from public.contestatii), true, '');
  insert into rez values ('Cine a dat observația nu-și judecă singur contestația', false);
exception when others then insert into rez values ('Cine a dat observația nu-și judecă singur contestația', true); end $$;
select pg_temp.ca('74');
do $$ begin
  perform public.decide_contestatie((select id from public.contestatii), true, '');
  insert into rez values ('Nici cei de sub el (VT) nu o judecă', false);
exception when others then insert into rez values ('Nici cei de sub el (VT) nu o judecă', true); end $$;
select pg_temp.ca('73');
select public.decide_contestatie((select id from public.contestatii), true, 'Ai dreptate');
reset role;
insert into rez select 'GM admite: punctele se dau înapoi și omul află', pg_temp.xp('71', 'feedback:') = 10
  and exists (select 1 from public.notifications where user_id = pg_temp.u('71') and kind = 'contestatie' and title like 'Contestația ta a fost admisă · 5 XP înapoi');
-- întârzierea la clock-in: tura a început acum 40 de minute
insert into public.shifts (user_id, space_id, day, starts, ends)
select pg_temp.u('76'), 'porumbescu', (n at time zone 'Europe/Bucharest')::date, (n at time zone 'Europe/Bucharest')::time,
       ((n + interval '6 hours') at time zone 'Europe/Bucharest')::time from (select now() - interval '40 minutes' as n) x;
set role authenticated;
select pg_temp.ca('76');
select public.pontaj_intrare('porumbescu', (select token from cod));
select public.pontaj_iesire('porumbescu', (select token from cod));
select public.pontaj_intrare('porumbescu', (select token from cod));
reset role;
insert into rez select 'Clock-in cu peste 15 min întârziere: −5, o singură dată pe tură', pg_temp.xp('76', 'pontaj:') = -5
  and (select count(*) from public.xp_evenimente('2000-01-01', current_date + 1, pg_temp.u('76')) where cheie like 'pontaj:%') = 1;
set role authenticated;
select pg_temp.ca('76');
select public.contesta((select e ->> 'cheie' from jsonb_array_elements(public.jurnal_puncte() -> 'evenimente') e where e ->> 'cheie' like 'pontaj:%'), 'Am ajuns la timp, dar nu mergea scanarea');
select pg_temp.ca('74');
do $$ begin
  perform public.decide_contestatie((select id from public.contestatii where status = 'deschisa'), false, '');
  insert into rez values ('Respingerea contestației cere un motiv', false);
exception when others then insert into rez values ('Respingerea contestației cere un motiv', true); end $$;
select public.decide_contestatie((select id from public.contestatii where status = 'deschisa'), false, 'Camera arată că ai intrat la 07:50');
select pg_temp.ca('76');
insert into rez select 'VT respinge: pierderea rămâne, cu răspunsul lui în jurnal', e ->> 'contestatie' = 'respinsa' and e ->> 'raspuns' like 'Camera%' and (e ->> 'puncte')::int = -5
  from jsonb_array_elements(public.jurnal_puncte() -> 'evenimente') e where e ->> 'cheie' like 'pontaj:%';
insert into rez select 'Punctele noi de la ultima privire', jsonb_array_length(public.puncte_noi(now() - interval '2 hours') -> 'evenimente') >= 2
  and jsonb_array_length(public.puncte_noi(now()) -> 'evenimente') = 0;

-- ===== Fișa de deschidere nefăcută =====
reset role;
insert into public.shifts (user_id, space_id, day, starts, ends, opens)
values (pg_temp.u('71'), 'porumbescu', (now() at time zone 'Europe/Bucharest')::date - 2, '07:10', '15:10', true),
       (pg_temp.u('75'), 'fructus', (now() at time zone 'Europe/Bucharest')::date - 2, '07:10', '15:10', true);
insert into rez select 'Fișa de deschidere nefăcută: −10 celui programat să deschidă', pg_temp.xp('71', 'fisa-lipsa:') = -10;
insert into rez select 'Unde locația nu are fișă de deschidere, nu se pierde nimic', pg_temp.xp('75', 'fisa-lipsa:') = 0;
insert into public.checklist_runs (cheie, doc_id, title, space_id, day, steps, finished_at, finished_by)
select 'doc:' || d.id, d.id, 'Deschidere', 'porumbescu', (now() at time zone 'Europe/Bucharest')::date - 2, '[{"t":"Unu"}]',
       now() - interval '2 days', pg_temp.u('76') from public.procedure_docs d where d.source_file = 'Procedura_Deschidere_Test21.pdf';
insert into rez select 'Dacă fișa a făcut-o un coleg în aceeași zi, nu se pierde nimic', pg_temp.xp('71', 'fisa-lipsa:') = 0;

-- ===== Raportul lunar și închiderea lunii =====
insert into public.feedback (to_user, from_user, fel, text, puncte, created_at)
select pg_temp.u('71'), pg_temp.u('72'), v.fel, v.t, v.p, (l + 9)::timestamp at time zone 'Europe/Bucharest' from luna, (values
  ('apreciere', 'Apreciere de acum două luni', 10), ('imbunatatire', 'Observație de acum două luni', -5)) v (fel, t, p);
set role authenticated;
select pg_temp.ca('71');
do $$ begin
  perform public.joc_raport(null);
  insert into rez values ('Vânzătoarea nu vede raportul lunar', false);
exception when others then insert into rez values ('Vânzătoarea nu vede raportul lunar', true); end $$;
do $$ begin
  perform public.joc_om(pg_temp.u('76'));
  insert into rez values ('Vânzătoarea nu vede progresul colegei', false);
exception when others then insert into rez values ('Vânzătoarea nu vede progresul colegei', true); end $$;
select public.contesta((select 'feedback:' || id from public.feedback where text = 'Observație de acum două luni'), 'Nu eram în tură în ziua aceea');
select pg_temp.ca('72');
insert into rez select 'RL vede în raport oamenii lui și pe sine, nu altă locație',
  (select array_agg(o ->> 'nume' order by o ->> 'nume') from jsonb_array_elements(public.joc_raport(null) -> 'oameni') o
   where o ->> 'nume' in ('Vio V', 'Cora V', 'Tavi VT', 'Rica RL', 'Fane V', 'Gina GM')) = array['Cora V', 'Rica RL', 'Tavi VT', 'Vio V'];
insert into rez select 'RL vede progresul unui om de-al lui', public.joc_om(pg_temp.u('71')) ->> 'nume' = 'Vio V';
do $$ begin
  perform public.inchide_luna((select l from luna));
  insert into rez values ('RL nu închide luna', false);
exception when others then insert into rez values ('RL nu închide luna', true); end $$;
select pg_temp.ca('73');
do $$ begin
  perform public.inchide_luna(current_date);
  insert into rez values ('Luna în curs nu se închide', false);
exception when others then insert into rez values ('Luna în curs nu se închide', true); end $$;
do $$ begin
  perform public.inchide_luna((select l from luna));
  insert into rez values ('Luna nu se închide cu contestații nedecise', false);
exception when others then insert into rez values ('Luna nu se închide cu contestații nedecise', true); end $$;
select public.decide_contestatie((select id from public.contestatii where status = 'deschisa'), false, 'Pontajul arată că erai în tură');
select public.inchide_luna((select l from luna));
insert into rez select 'GM închide luna: cifrele omului rămân înghețate', castigat = 10 and pierdut = 5 and net = 5 and jsonb_array_length(pierderi) = 1 and ture = 0
  from public.puncte_luna where user_id = pg_temp.u('71') and luna = (select l from luna);
select pg_temp.ca('71');
insert into rez select 'Omul își vede luna închisă în jurnal', (j ->> 'inchisa')::boolean and (j -> 'sumar' ->> 'net')::int = 5
  from (select public.jurnal_puncte(null, (select l from luna)) as j) x;
select pg_temp.ca('72');
do $$ begin
  delete from public.feedback where text like '%de acum două luni';
  insert into rez select 'După închidere, feedbackul lunii nu se mai șterge', count(*) = 2 from public.feedback where text like '%de acum două luni';
exception when others then insert into rez values ('După închidere, feedbackul lunii nu se mai șterge', true); end $$;
do $$ begin
  perform public.redeschide_luna((select l from luna));
  insert into rez values ('RL nu redeschide luna', false);
exception when others then insert into rez values ('RL nu redeschide luna', true); end $$;
select pg_temp.ca('73');
select public.redeschide_luna((select l from luna));
insert into rez select 'Adminul (GM) o poate redeschide', count(*) = 0 from public.luni_inchise;

set role anon;
do $$ begin perform public.mesajele_mele(); insert into rez values ('Anonimul nu are mesaje', false);
exception when others then insert into rez values ('Anonimul nu are mesaje', true); end $$;
do $$ begin perform 1 from public.semnalari; insert into rez values ('Anonimul nu vede semnalări', false);
exception when others then insert into rez values ('Anonimul nu vede semnalări', true); end $$;
reset role;
-- datele și conturile testului dispar, ca să nu schimbe numărătorile celorlalte teste
delete from public.contestatii; delete from public.feedback; delete from public.anunturi; delete from public.semnalari;
delete from public.luni_inchise; delete from public.notifications; delete from public.clockings;
delete from public.checklist_runs where cheie like 'doc:%' and title = 'Deschidere';
delete from public.shifts where user_id::text like '00000000-0000-0000-0000-00000000007%';
delete from public.procedure_docs where source_file like 'Procedura_Deschidere_Test21%';
delete from public.profiles where user_id::text like '00000000-0000-0000-0000-00000000007%';
delete from auth.users where id::text like '00000000-0000-0000-0000-00000000007%';
select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
