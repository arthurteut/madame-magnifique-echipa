# Teste locale pentru schema și regulile de acces

Rulează pe un Postgres 16 local, nu pe Supabase. `00_mediu_supabase_local.sql`
imită ce oferă Supabase (rolurile `anon` / `authenticated` / `service_role` și
`auth.uid()` citit din `request.jwt.claim.sub`).

```bash
createdb ghid
psql -d ghid -f supabase/tests/00_mediu_supabase_local.sql
psql -d ghid -f supabase/migrations/0001_schema_si_autentificare.sql
python3 tools/import_supabase.py Harta.xlsx date-ghid.sql && psql -d ghid -f date-ghid.sql
psql -d ghid -f supabase/tests/01_pas1_autentificare.sql   # înainte de 0002
psql -d ghid -f supabase/migrations/0002_acces_pe_rol.sql
psql -d ghid -f supabase/tests/02_pas2_acces_pe_rol.sql     # ce vede fiecare rol
```

Ce trebuie să iasă la pasul 1: anonimul primește „permission denied”; un VT
activ vede cele 103 proceduri și doar propriul profil; GM vede toate profilurile;
un cont dezactivat sau fără profil vede 0 proceduri; orice UPDATE din rolul
`authenticated` e refuzat.

Pasul 2 (`02_pas2_acces_pe_rol.sql`) face câte un cont pentru fiecare rol și
afișează ce primește: spațiile, procedurile, task-urile, procesele, rolurile,
abaterile, fișele și ajustările. De exemplu: VT vede doar cele 3 magazine și 78
de proceduri (VT + V + BAR), V doar cele 30 ale lui, PP + B cele 2 task-uri de
deschidere de la Porumbescu și Dumbrăvița, CB2B doar B2B și Laboratorul Fructus.

Pasul 3 (`03_pas3_panou_admin.sql`, după 0003): GM modifică alte conturi și
matricea; nu-și poate schimba propriul rol și nu poate schimba username-uri;
VT nu-și poate da acces, nu se poate promova și nu poate scoate drepturi.

Funcția `admin-users` are teste proprii, cu un client Supabase simulat:

```bash
ADMIN_USERS_TEST=1 deno test --allow-env supabase/functions/admin-users/
```

Cursurile (`05_cursuri.sql`, după 0003, 0004 și 0005): V vede cursul comun și
pe al rolului lui, nu și pe cel de B2B sau ciornele; nimeni în afară de admin nu
vede răspunsurile corecte; `submit_quiz` corectează și salvează încercarea;
fiecare își bifează doar lecțiile proprii; doar adminul scrie cursuri și
încarcă fișiere; din Storage, fiecare descarcă doar fișierele cursurilor pe
care le vede. Ultimul rând trebuie să fie „31 din 31”.

Procedurile verificate (`06_proceduri_verificate.sql`, după 0006): fiecare rol
vede documentele lui și pe ale rolurilor pe care le vede, cele legate de o
locație doar dacă vede locația, iar fișele locației le vede toată echipa ei;
la fel pentru PDF-uri; doar adminul scrie. Ultimul rând: „12 din 12”.

Ghidul brutarului (`07_ghidul_brutarului.sql`, după 0007): DP, AE și GM citesc
capitolele, V nu; nimeni nu le modifică din pagină. Ultimul rând: „7 din 7”.

Rolul Brutar (`08_rol_brutar.sql`, după 0008): BRT citește ghidul și rețetele,
nu vede spații, proceduri, cursuri sau „Cum funcționează”. Ultimul rând: „8 din 8”.

Rolurile de producție (`09_roluri_productie.sql`, după 0009): PPT vede ambele
laboratoare, PCF Laboratorul Fructus, PBR Peciu Nou și ghidul brutarului; DP și
SP le văd rolurile, V nu. Ultimul rând: „11 din 11”.

Academia pentru toți (`12_academia_pentru_toti.sql`, după 0012): orice cont vede
toate cursurile publicate și ghidul brutarului; ciornele și răspunsurile rămân
doar ale adminului; BRT tot nu vede spații sau proceduri. Ultimul rând: „7 din 7”.
Testele 05, 07 și 08 descriu accesul de dinainte de 0012 și se rulează înainte.

Categoriile din Academie (`13_categorii_academie.sql`, după 0013): un curs nou e
„general”, se mută în altă categorie, categoriile necunoscute sunt refuzate.
Ultimul rând: „3 din 3”.

Patiserie și cofetărie (`14_patiserie_cofetarie.sql`, după 0014): categoriile
patiserie, cofetarie și patiserie-cofetarie sunt acceptate, cele scrise greșit
sunt refuzate. Ultimul rând: „2 din 2”.

P&L (`15_pl.sql`, după 0015): EC, ADM, AE și GM văd și completează P&L-ul; RL și
V nu văd nimic, nici dacă pagina e bifată pentru RL; fără pagina „pl”, nici ADM
nu mai vede; un P&L întreg îl șterge doar GM, iar lunile lui se șterg odată cu el.
Ultimul rând: „20 din 20”.

Tura (`16_tura.sql`, după 0016 și 0017): RL, VT și SP fac programul, V și PBR nu; colegii din aceeași zi
și locație se văd în program; clock-in doar cu codul QR al locației, legat de tura din program,
fără dublură și nu în două locuri deodată; fișa se pornește și se bifează doar în tură, pașii ei
nu se schimbă din pagină și după final nu se mai bifează; șefii (VT, RL, GM) și AE primesc clock-in /
clock-out, pas nefăcut și fișă gata, colegii nu; mementoul de dinainte de tură pleacă o singură dată,
iar lipsa clock-ului după 10 minute ajunge la șefi. Ultimul rând: „35 din 35”.

Jurnalul de croissant (`18_jurnal_croissant.sql`, după 0018): patiseria (PPT, PP + B), SP și AE
citesc și scriu, vânzătorul nu vede și nu scrie nimic; autorul rămâne cel care a creat batch-ul,
chiar dacă îl modifică altcineva; un batch îl șterge doar autorul. Ultimul rând: „12 din 12”.

Locația fiecărui om (`19_locatia_omului.sql`, după 0019): adminul leagă un RL de Porumbescu; RL-ul
vede doar Porumbescu și nu-și adaugă singur locații; un RL fără locații vede toate magazinele;
clock-in-ul de la Fructus nu ajunge la RL-ul de Porumbescu, cel de la Porumbescu da. Ultimul rând: „9 din 9”.

Jocul echipei (`20_joc.sql`, după 0020): clock-in la timp +10, fișa terminată adună pașii, fișa și
problema semnalată, observația +5 și poartă numele celui care a scris-o; vânzătoarea nu rezolvă
probleme și nu vede tabloul echipei sau clasamentul magazinelor; RL-ul rezolvă o problemă o singură
dată (+5 lui, +10 celui care a semnalat-o, cu notificare); RL-ul de Porumbescu nu vede tabloul și
programul de la Fructus, GM-ul vede orice locație; seria de ture la timp se numără corect; anonimul
nu are acces. Ultimul rând: „25 din 25”. Testul jurnalului (18) își șterge acum conturile la final.

Comunicarea și punctajul transparent (`21_comunicare_si_puncte.sql`, după 0021): semnalarea pornește
mereu deschisă, colegii o văd, cea „doar pentru șefi” nu; doar șefii o preiau și o rezolvă, textul ei
nu se schimbă, respingerea cere motiv; rezolvarea aduce +10 și +5, cu plafon de 3 pe zi. Anunțul îl
trimit doar șefii, pe toată firma doar GM / AE; destinatarii sunt colegii locației, iar cine nu
confirmă în 24 de ore pierde 2 puncte. Feedbackul cu puncte îl dau doar șefii, la locația lor, cu
plafon pe zi; omul îl confirmă și răspunde, dar nu-și schimbă punctele. Se contestă doar pierderile,
o singură dată; cine a dat observația și cei de sub el nu o judecă, GM o admite și punctele se dau
înapoi. Întârzierea peste 15 minute costă 5 puncte, o singură dată pe tură; fișa de deschidere
nefăcută costă 10, dar nu dacă a făcut-o un coleg sau dacă locația nu are fișă. Raportul lunar îl văd
șefii, pentru oamenii lor; luna o închide doar GM / AE, nu în curs și nu cu contestații nedecise;
după închidere cifrele rămân înghețate. Ultimul rând: „58 din 58”.

Bonusul pe magazin (`22_bonus.sql`, după 0022; cifrele din test sunt inventate): creșterea se calculează
din media zilnică față de aceeași lună a anului trecut și alege treapta; fondul se împarte între vânzare
(după aport) și coacere; declinul și lipsa primei de calitate taie tot; conformitatea e tot sau nimic,
o evaluează doar responsabilul locației, cu motiv la „neîndeplinit”; nota zilnică o dă doar cine vinde,
o dată pe zi, cu motiv sub prag; bonusul de management își calculează singur criteriile de echipă;
vânzătoarea își vede doar sumele ei; luna o închide doar GM / AE, iar după închidere nu se mai schimbă
nimic. Ultimul rând: „47 din 47”.

Comenzile către producție (`24_comenzi.sql`, după 0024; produse și clienți inventați): biroul pune B2B,
magazinul necesarul și comanda unui client, patiserul cere creme; vânzătoarea nu pune B2B, nu comandă
pentru alt magazin și nu scrie direct în tabele; comanda fără produse, cu cantitate zero sau pe o zi
trecută e refuzată. Secțiile sunt anunțate; brutarul confirmă doar brutăria, refuzul cere motiv, iar
cine a comandat află răspunsul. Producția vede toate comenzile, dar nu telefonul clientului; magazinele
nu-și văd comenzile între ele. O linie schimbată se confirmă din nou, cea neatinsă nu; după ora-limită
comanda e târzie; anularea cere motiv și blochează comanda. Ultimul rând: „36 din 36”.

Bancul de probă din `tools/banc/` (`banc.js`, `dbmock.js`) deschide pagina reală în Playwright și
trimite fiecare operație către baza locală, ca un cont anume: aceleași RLS, triggere și funcții ca în
Supabase. Așa se verifică fluxurile cap-coadă (clock-in, fișă, semnalare, feedback, contestație).
