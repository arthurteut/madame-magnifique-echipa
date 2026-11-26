# Configurarea Supabase

Ghidul nu mai are o parolă comună. Fiecare angajat are utilizatorul lui, iar
conținutul stă în Supabase, nu în repo. Durează ~20 de minute, o singură dată.

## 1. Proiectul

1. [supabase.com/dashboard](https://supabase.com/dashboard) → **New project**.
   - Nume: `madame-magnifique-echipa`
   - Regiune: **Central EU (Frankfurt)**, ca datele să rămână în UE
   - Parola bazei de date: o generezi și o păstrezi (în managerul de parole)
2. **SQL Editor** → **New query** → lipești tot fișierul
   [`supabase/migrations/0001_schema_si_autentificare.sql`](supabase/migrations/0001_schema_si_autentificare.sql)
   → **Run**. Trebuie să apară „Success. No rows returned”.

## 2. Autentificarea

**Authentication → Sign In / Providers**
- **Allow new users to sign up**: **dezactivat**. Conturile le creează doar adminul.
- **Email** rămâne activ (conturile folosesc un email intern, vezi mai jos),
  dar **Confirm email** nu contează: adminul creează conturile deja confirmate.

**Authentication → URL Configuration**
- **Site URL**: `https://echipa.madamemagnifique.ro`
- **Redirect URLs**: adaugă și `https://arthurteut.github.io/madame-magnifique-echipa/`
  (adresa folosită până e gata DNS-ul)

## 3. Conținutul ghidului

Pe calculatorul tău, în folderul repo-ului:

```bash
pip install openpyxl
python3 tools/import_supabase.py Harta_Operatiuni_Madame_Magnifique_FIRMA.xlsx date-ghid.sql
```

Apoi **SQL Editor** → **New query** → lipești conținutul din `date-ghid.sql` → **Run**.
Importul înlocuiește tot conținutul într-o singură tranzacție și nu atinge conturile.
Îl rulezi din nou de fiecare dată când se schimbă harta.

`date-ghid.sql` conține tot ghidul: **nu îl urca în repo** (e deja în `.gitignore`)
și șterge-l după import.

## 3b. Accesul pe rol

**După primul import** (are nevoie de roluri și spații), **SQL Editor** → lipești
[`supabase/migrations/0002_acces_pe_rol.sql`](supabase/migrations/0002_acces_pe_rol.sql) → **Run**.

De acum fiecare cont primește din baza de date doar ce ține de rolul lui:

| Rol | Spații | Vede și procedurile rolurilor |
|---|---|---|
| GM (admin) | toate | toate |
| RL | cele 3 magazine | VT, V, BAR, PP + B |
| VT | cele 3 magazine | V, BAR, PP + B |
| V, BAR, PP + B | cele 3 magazine | doar ale lor |
| DP | ambele laboratoare | SP, GD |
| SP, GD | ambele laboratoare | doar ale lor |
| LOG | laboratoarele, magazinele, B2B | doar ale lui |
| CB2B | B2B, Laboratorul Fructus | doar ale lui |
| MKT, ADM, EC | Biroul central | doar ale lor |

Matricea stă în tabelele `role_space_access`, `role_role_access` și
`role_section_access` (paginile din meniu). Reimportul hărții nu o atinge.

## 4. Primul cont de administrator

Conturile se fac din panoul de admin (pasul 3). Primul admin îl creezi manual:

1. **Authentication → Users → Add user → Create new user**
   - Email: `<utilizator>@echipa.madamemagnifique.ro`, de exemplu `ana.gm@echipa.madamemagnifique.ro`
   - Parola: minimum 8 caractere
   - Bifează **Auto Confirm User**
2. **SQL Editor**, înlocuind numele cu cele reale:

```sql
insert into public.profiles (user_id, username, full_name, role_code)
select id, 'ana.gm', 'Ana Madame', 'GM'
from auth.users where email = 'ana.gm@echipa.madamemagnifique.ro';
```

Utilizatorul (`ana.gm`) e partea dinaintea lui `@`: doar litere mici, cifre,
punct, cratimă sau underscore. La logare se scrie doar utilizatorul.

## 5. Legarea paginii

**Project Settings → API** (sau butonul **Connect**) → copiezi:
- **Project URL**
- cheia **anon public** / **publishable**

și le pui în [`assets/config.js`](assets/config.js). Ambele sunt publice prin
design: fără logare nu dau acces la nimic, iar ce vede fiecare decide baza de date.

**Nu pune niciodată** cheia `service_role` / `secret` în pagină sau în repo.

## 6. Panoul de administrare

Pagina **Admin** (doar pentru GM) creează conturi, schimbă roluri, dezactivează,
resetează parole și editează matricea de acces.

1. **SQL Editor** → lipești
   [`supabase/migrations/0003_panou_admin.sql`](supabase/migrations/0003_panou_admin.sql) → **Run**.
2. **Edge Functions → Deploy a new function → Via Editor**
   - Numele funcției: **`admin-users`**. Dacă Supabase îi dă alt nume (de exemplu
     `smooth-handler`), treci acel nume la `adminFunction` în `assets/config.js`.
   - Ștergi codul de exemplu și lipești tot fișierul
     [`supabase/functions/admin-users/index.ts`](supabase/functions/admin-users/index.ts)
   - **Deploy function**
3. În funcția `admin-users` → **Details** (sau **Settings**): dezactivezi
   **Verify JWT with legacy secret** / **Enforce JWT verification**. Funcția își
   verifică singură sesiunea și dreptul de admin.
4. **Edge Functions → Secrets** (sau **Project Settings → Edge Functions**) →
   **Add new secret**:
   - Name: `ALLOWED_ORIGIN`
   - Value: `https://arthurteut.github.io,https://echipa.madamemagnifique.ro`

URL-ul proiectului și cheia secretă sunt puse automat în funcție de Supabase:
nu le copiezi nicăieri.

## 7. Rolul „Asistent executiv” (AE)

**SQL Editor** → lipești
[`supabase/migrations/0004_asistent_executiv.sql`](supabase/migrations/0004_asistent_executiv.sql) → **Run**.

AE vede tot ghidul, ca administratorul, dar nu are pagina **Admin**. Ca să poată
și administra: `update public.roles set is_admin = true where code = 'AE';`

## 8. Cursurile de onboarding

**SQL Editor** → lipești
[`supabase/migrations/0005_cursuri.sql`](supabase/migrations/0005_cursuri.sql) → **Run**.
Se poate rula de mai multe ori.

Migrarea adaugă:

- tabelele cursurilor (lecții, fișiere, întrebări, progres, încercări la test);
- bucketul privat **cursuri** din Storage (max. 50 MB pe fișier: PDF, Word, Excel, PowerPoint, poze);
- pagina **Cursuri** în meniu, pentru toate rolurile.

Cine vede ce:

- **Cursurile comune** le vede toată echipa.
- **Celelalte cursuri** le văd doar rolurile bifate în curs.
- **GM și AE** văd toate cursurile publicate.
- **Ciornele** le văd doar adminii.

Răspunsurile corecte nu ajung niciodată în browserul angajatului: testul se corectează în
baza de date (`submit_quiz`), iar scorul nu poate fi scris direct.

Cursurile se fac din **Admin → Cursuri**. Progresul echipei e în **Admin → Progres**.
Video-urile nu se încarcă în ghid: pui un link YouTube (poate fi „nelistat”),
Vimeo sau Google Drive („oricine are linkul”), ca să nu umpli spațiul de 1 GB
din planul gratuit.

## 9. Procedurile verificate

Textul procedurilor verificate pe teren (folderul „Madame Verificate” din Google
Drive) apare în ghid la procedura respectivă, cu eticheta **✓ Verificată**. Fișele
de deschidere / închidere apar pe pagina locației.

1. **SQL Editor** → lipești
   [`supabase/migrations/0006_proceduri_verificate.sql`](supabase/migrations/0006_proceduri_verificate.sql) → **Run**.
2. **SQL Editor** → lipești `date-proceduri.sql` (conținutul, generat cu
   `tools/proceduri_verificate.py`; nu stă în repo) → **Run**. Se poate rula din
   nou oricând se schimbă documentele: le actualizează după numele fișierului.
3. Opțional: **Admin → Proceduri verificate** → **Alege PDF-urile** → selectezi toate
   PDF-urile din folder (descărcat din Drive). Ghidul le potrivește după nume și
   le atașează, ca angajații să le poată descărca.

Fiecare vede doar documentele rolului lui (și ale rolurilor pe care le vede), iar
cele legate de o locație doar dacă vede locația. PDF-urile stau în bucketul privat
**proceduri**.

## 10. Ghidul brutarului și calculatorul de pâine

**SQL Editor** → lipești `9-ghidul-brutarului.sql` → **Run**. Fișierul conține
[`supabase/migrations/0007_ghidul_brutarului.sql`](supabase/migrations/0007_ghidul_brutarului.sql)
plus capitolele (generate cu `tools/ghid_brutar.py`) și rețetele casei pentru
calculator; capitolele și rețetele nu stau în repo. Se poate rula din nou oricând
se schimbă ghidul.

Pagina **Brutar** (ghidul + calculatorul) o văd DP, SP, GD, GM și AE; o dai și
altor roluri din **Admin → Acces pe rol → Paginile din meniu**.

## 11. Rolul „Brutar” (BRT)

**SQL Editor** → lipești
[`supabase/migrations/0008_rol_brutar.sql`](supabase/migrations/0008_rol_brutar.sql) → **Run**.

Un cont cu rolul BRT vede doar pagina **Brutar** (ghidul, rețetele casei și
calculatorul) și ajunge direct acolo după logare. Migrarea face și ca paginile
Cursuri și Cum funcționează să fie citite din baza de date doar de rolurile care
le au în meniu.

## 12. Rolurile de producție pe secții

**SQL Editor** → lipești
[`supabase/migrations/0009_roluri_productie.sql`](supabase/migrations/0009_roluri_productie.sql) → **Run**.

| Rol | Spații | Pagini |
|---|---|---|
| PPT · Producție patiserie | Laboratorul Peciu Nou, Laboratorul Fructus | Roluri, Proceduri, Cursuri, Cum funcționează |
| PCF · Producție cofetărie | Laboratorul Fructus | la fel |
| PBR · Producție brutărie | Laboratorul Peciu Nou | la fel + Brutar |

DP și SP le văd procedurile și task-urile. Totul se schimbă din **Admin → Acces pe rol**.

Pentru cine lucrează în ambele secții:
[`0010_rol_brutarie_patiserie.sql`](supabase/migrations/0010_rol_brutarie_patiserie.sql)
adaugă **PBP · Producție brutărie și patiserie** (vede tot ce văd PBR și PPT).

Conturile se pot crea și toate odată: **Admin → Utilizatori → Conturi din tabel**
(lipești rândurile din tabelul „Conturi echipa”; primești lista cu parole, de
copiat sau de printat ca bilețele).

## 13. Academia Madame

**SQL Editor** → lipești
[`supabase/migrations/0011_academia.sql`](supabase/migrations/0011_academia.sql) → **Run**.

Pagina **Cursuri** se numește acum **Academia Madame** și cuprinde cursurile de
onboarding și ghidurile de meserie (ghidul brutarului și calculatorul de pâine).
Meniul nu mai are pagina separată **Brutar**. Ghidul brutarului îl primește și
patiseria (PPT). În Admin → Acces pe rol, „Academia: cursuri” și „Academia: ghidul
brutarului” se bifează separat.

Apoi [`0012_academia_pentru_toti.sql`](supabase/migrations/0012_academia_pentru_toti.sql):
toată echipa vede tot în Academie (toate cursurile publicate, ghidul brutarului,
calculatorul). Rolurile bifate la un curs arată doar pentru cine e obligatoriu.

### 14. Categoriile din Academie

Rulează [`0013_categorii_academie.sql`](supabase/migrations/0013_categorii_academie.sql).
Academia își grupează cursurile în casete, fiecare cu poza ei: **Brutărie** (cu
ghidul brutarului și calculatorul), **Barista**, **Patiserie și cofetărie**,
**Vânzare și servire** și, dacă există, **Cursuri generale**. Categoria unui curs
se alege în Admin → Cursuri → editorul cursului. Cursurile de dinainte rămân
„generale” până le muți.

Un curs întreg (lecții + test) se poate încărca și dintr-un fișier JSON cu
[`tools/curs_din_text.py`](tools/curs_din_text.py):

```bash
python3 tools/curs_din_text.py curs.json date-curs.sql
```

Fișierul `date-curs.sql` conține materialele cursului: îl rulezi în SQL Editor și
**nu** îl pui în repo.

### 15. Patiseria și cofetăria, separate

Rulează [`0014_patiserie_cofetarie.sql`](supabase/migrations/0014_patiserie_cofetarie.sql).
Caseta „Patiserie și cofetărie” se împarte în două: **Patiserie** (aluaturi,
viennoiserie, flanuri) și **Cofetărie** (creme, ciocolată, zahăr, entremets).
Cursurile comune (categoria „Comun patiserie și cofetărie”, ex. Fundamentele
laboratorului) apar în ambele casete.

### 16. P&L (profit și pierdere)

Rulează [`0015_pl.sql`](supabase/migrations/0015_pl.sql). În meniu apare **P&L**,
doar pentru **GM, AE, EC și ADM**. Lista e fixată și în baza de date
(`can_use_pl()`): chiar dacă pagina „pl” ar fi bifată pentru alt rol, sumele nu
ajung la el. Dacă scoți rândul `pl` al unuia dintre cele patru roluri din
`role_section_access`, rolul acela pierde accesul.

- Un P&L = o entitate (firma sau o locație) pe un an, cu setările lui (TVA pe
  fluxuri, curs EUR/RON, CAM, ținte). Primul, „Madame Magnifique” pe anul curent,
  îl creează migrarea; altele se creează din pagină (Setări → P&L nou).
- Lunile se salvează automat în `pl_months`; ultima modificare ține data și contul.
- Veniturile sunt pe fluxurile Madame: Cafenea, Patiserie și cofetărie, Brutărie,
  B2B și evenimente. Secțiunea **B2B** din fiecare lună ține încasările B2B pe
  tipuri și cheltuielile directe (transport, ambalaje, personal, discounturi și
  comisioane); acestea intră și în totalurile firmei. Nu e nevoie de altă migrare.
- COGS-ul e pe materiile prime Madame: făină și cereale; unt, lactate și ouă;
  zahăr, ciocolată și cacao; fructe, nuci și umpluturi; alte materii prime de
  laborator; cafea, ceai și băuturi; ambalaje; marfă pentru revânzare; alte COGS.
- Un P&L întreg îl poate șterge doar adminul (GM); lunile le poate goli oricine
  dintre cele patru roluri.
- Ghidul de interpretare (benchmark-uri, decizii, glosar) stă în `pl_guide`:
  îl încarci cu `date-pl-ghid.sql`, care **nu** intră în repo.

Formulele sunt cele din modelul ATC P&L Toolkit: vânzările se introduc cu TVA și
se aduc la venit net cu cotele din setări; restul sumelor, fără TVA; toate
procentele se raportează la venitul net.

### 17. Tura: program, clock-in cu QR, fișe bifate, notificări

Rulează [`0016_tura.sql`](supabase/migrations/0016_tura.sql) (activează și `pg_cron` și `pg_net`).

- **Organigrama** (`role_parents`): V, BAR, PP + B → VT → RL → GM; PBR, PPT, PCF, BRT, GD →
  PBP → SP → DP → GM. Notificările urcă pe toată linia, la cei care văd locația. AE vede
  panoul și primește și el toate notificările echipei (migrarea 0017, rolurile cu `sees_all`).
- **Program pe ture** (meniul *Echipa* → *Program pe ture*): îl fac cei de deasupra (RL / VT
  la vânzare, SP / DP / PBP la producție), pe locație și săptămână, cu cine deschide / închide.
- **Clock-in / clock-out** doar cu codul QR al locației (*Admin → Coduri QR*: printezi și
  lipești la intrare; „Cod nou” anulează codul vechi). Funcțiile `pontaj_intrare` / `pontaj_iesire`.
- **Fișele zilei** (meniul *Tura*): deschiderea și închiderea locației, fișele rolului (ex.
  Preparator patiserie) și task-urile zilnice din hartă, bifate pas cu pas; se pot bifa doar
  în tură. Fișa e comună echipei de la locație.
- **Notificări** (clopoțelul + push pe telefon): clock-in / clock-out, fișă gata, pas nefăcut,
  observație, întârziere (fără clock-in la 10 min după începutul turei, fișa de deschidere
  negata la ora de deschidere, cea de închidere la o oră după închidere) și mementouri pentru
  omul programat: cu 15 min înainte (scanează QR-ul) și la finalul turei (clock-out).
- **Push**: cheile VAPID și adresa funcției stau în `push_config` (o citește doar
  `service_role`). Publică funcția din [`supabase/functions/trimite-push`](supabase/functions/trimite-push/index.ts)
  cu numele `trimite-push` și **fără** „Verify JWT”. Telefoanele activează notificările din
  pagina *Tura* sau din clopoțel (pe iPhone: întâi „Add to Home Screen”, iOS 16.4+).
- Orele magazinelor (`space_hours`) dau termenul fișelor de deschidere / închidere.

### 18. Jurnalul de croissant

Rulează [`0018_jurnal_croissant.sql`](supabase/migrations/0018_jurnal_croissant.sql). În Academia,
caseta **Patiserie** primește „Jurnalul de croissant”: fiecare batch de aluat laminat (rețeta cu
procentele de brutar calculate, détrempe, cele trei tururi, modelarea, dospirea, coacerea, scorul
și concluziile), salvat automat. Jurnalul e comun și îl văd / completează doar PPT, PBP, PP + B,
SP, DP, GM și AE; un batch îl șterge doar autorul sau adminul. „Batch nou pornind de la acesta”
copiază rețeta și procesul, fără rezultat și concluzii.

### 19. Locația fiecărui om

Rulează [`0019_locatia_omului.sql`](supabase/migrations/0019_locatia_omului.sql). În *Admin →
Utilizatori* apare coloana **Locații**: bifezi magazinul (sau laboratorul) de care răspunde omul.
Un cont legat de locații vede doar acele locații (dintre cele ale rolului) și primește notificările
echipei doar de acolo; un cont fără locații vede, ca până acum, toate locațiile rolului. Responsabilul
de locație (RL) deschide aplicația direct pe *Echipa → Azi*, cu legătura spre pagina locației.

### 20. Jocul echipei: puncte, niveluri, insigne, clasamente

Rulează [`0020_joc.sql`](supabase/migrations/0020_joc.sql). Punctele (XP) se calculează singure din
ce se întâmplă deja în aplicație, nu se introduc de mână:

| De unde | Puncte |
|---|---|
| Clock-in la timp (≤ 5 min după începutul turei) / până la 15 min / fără tură în program | +10 / +3 / +2 |
| Pas făcut · fișă gata la termen (după termen) · fișă fără niciun pas nefăcut | +2 · +15 (+5) · +10 |
| Lecție parcursă în Academie · primul test trecut la un curs | +5 · +30 |
| Problemă semnalată, când șeful o rezolvă: celui care a semnalat / șefului (primele 3 pe zi) | +10 / +5 |

(De la 0021 problema semnalată nu mai aduce puncte la trimitere, ci doar când e rezolvată.)

Pe *Tura* fiecare își vede nivelul (de la 1 la 11), seria de ture începute la timp,
punctele săptămânii, insignele și scorul echipei lui. Pe *Echipa → Azi* șefii (RL pentru locația lui,
GM și AE pentru oricare) au tabloul locației: scorul săptămânii (media dintre clock-in la timp, fișe
la termen, pași făcuți și probleme rezolvate) față de săptămâna trecută, nivelul echipei, obiectivele
cu ținta de 90%, clasamentul oamenilor, clasamentul magazinelor și punctele zilei. La *De rezolvat*
șeful apasă **Rezolvat**; cine a semnalat problema primește notificare și +10 XP.
Tot aici: șefii văd programul și pontajul colegilor doar la locațiile lor.

### 21. Comunicarea în aplicație și punctajul transparent

Rulează [`0021_comunicare_si_puncte.sql`](supabase/migrations/0021_comunicare_si_puncte.sql). Fără el,
paginile de mai jos spun că lipsește migrarea, iar restul site-ului merge ca înainte.

- **Semnalări** (`#/semnalari`): problemele de lucru se scriu în aplicație, nu pe grup. Le vede echipa
  locației și șefii (cu bifa „doar pentru șefi” le văd doar șefii). Șeful le preia, le rezolvă sau scrie
  de ce nu se confirmă; cine a semnalat e anunțat la fiecare pas.
- **Mesaje** (`#/mesaje`): anunțurile conducerii, pentru o locație (orice șef care o vede) sau pentru
  toată firma (GM, AE). Destinatarii se fixează la trimitere și confirmă cu „Am citit”; autorul vede cine
  nu a confirmat. Tot aici, feedbackul de la șefi: apreciere (0, +5, +10, +20 XP) sau „de îmbunătățit”
  (0, −5, −10 XP), mereu cu text. Îl dă șeful direct sau cineva de deasupra lui, cu o locație comună.
  Plafon pe zi pentru un om: +20 din aprecieri, −10 din observații.
- **Punctele mele** (`#/progres`): jurnalul lunii, cu fiecare punct câștigat sau pierdut și motivul lui.
  Șefii deschid jurnalul oamenilor lor din *Echipa → Oameni și puncte*.

| Se pierd puncte pentru | Puncte |
|---|---|
| Clock-in cu peste 15 minute întârziere (omul e avertizat la 10 minute) | −5 |
| Fișa de deschidere / închidere a locației nefăcută până la 03:00 a doua zi (celui programat să deschidă / să închidă; doar unde locația are o astfel de fișă) | −10 |
| Anunț neconfirmat în 24 de ore (omul e avertizat cu 4 ore înainte) | −2 |
| „De îmbunătățit” de la șef | −5 / −10 |

Orice pierdere se poate **contesta** din jurnal. O decide șeful omului; o observație dată de un șef o
decide cineva de deasupra lui. Dacă e admisă, punctele se dau înapoi.

**Raportul lunar** (*Echipa → Oameni și puncte*): punctele câștigate, pierdute și nete ale fiecărui om,
cu descărcare în tabel. GM sau AE apasă **Închide luna** după ce luna s-a terminat și nu mai sunt
contestații nedecise; cifrele rămân înghețate în `puncte_luna`, iar pierderile lunii nu se
mai pot contesta. Adminul o poate redeschide.

Verificările de la 5 minute (`verifica-ture`, din 0016) trimit acum și avertismentele către om. Nu e
nimic de configurat în plus.

## 22. Bonusul pe magazin

Rulează [`0022_bonus.sql`](supabase/migrations/0022_bonus.sql), apoi fișierul intern cu datele
(`45-bonus-date.sql`: treptele, sumele, criteriile și vânzările de referință). Datele sunt interne și
nu stau în acest depozit; fără ele, pagina nu apare la nicio locație. Fără migrare, pagina spune că
lipsește, iar restul site-ului merge ca înainte.

Punctele (XP) **nu sunt bani**: rămân pentru niveluri, insigne și clasament. Banii vin doar din
sistemul de bonusare pe magazin, iar aplicația îi măsoară criteriile.

- **Bonus** (`#/bonus`, filă în *Tura* și *Echipa*, doar la locațiile cu bonus configurat): creșterea
  față de aceeași lună a anului trecut (media zilnică de vânzări), treapta atinsă, media necesară
  pentru fiecare treaptă și bonusul fiecăruia. Omul își vede doar sumele lui; GM și AE le văd pe toate.
- **Echipa lunii**: se preia din luna trecută sau din conturile legate de locație (RL este managerul,
  PP + B coace). GM / AE o corectează, scriu vânzările lunii, aportul fiecăruia la vânzări și cine a
  încasat prima de calitate.
- **Conformitatea**: o evaluează lunar responsabilul de magazin, criteriu cu criteriu. La procedurile
  de deschidere / închidere aplicația arată dovada din fișe; un verdict contrar fișelor cere o notă.
  „Neîndeplinit” cere motiv, iar omul îl vede. Suma se plătește doar dacă toate criteriile sunt
  îndeplinite (pragul fișelor se schimbă din `bonus_setari.prag_proceduri`, implicit 100%).
- **Nota de calitate**: cine vinde dă zilnic, din pagina Tura, o notă produselor din vitrină (din
  jumătate în jumătate de punct; sub prag scrie și motivul). Cine coace vede notele și media lunii.
- **Bonusul de management**: criteriile de echipă le calculează aplicația, pe cele individuale le
  bifează GM / AE.
- **Închiderea**: GM / AE apasă *Închide bonusul lunii* după ce luna s-a terminat, vânzările sunt
  scrise și evaluările făcute. Sumele îngheață, fiecare primește o notificare cu suma lui brută.
  Adminul poate redeschide luna.

Regulile eliminatorii se aplică automat: magazin în declin = nimic din sistem; fără prima de calitate
= niciun bonus pentru acel om. Partea celui fără primă nu se împarte celorlalți.

## 23. P&L: importul din Gesto

Nu e nimic de rulat în Supabase. În pagina **P&L**, tabul **Import Gesto** (la un P&L de locație, nu la
cel consolidat) citește în browser două rapoarte și completează luna:

- **Centralizatorul de documente** (Excel, pe o perioadă care cuprinde luna): încasările pe card,
  numerar, Tazz și BonApp, TVA-ul real din bonuri, avizele către clienți (B2B) și marfa primită la preț
  de cost, de la laborator („Depozit”), de la alte magazine și de la furnizori direcți.
- **Cost Margin — Departament** (opțional, câte un fișier pe locație și lună): împarte încasările pe
  Cafenea, Patiserie și cofetărie, Brutărie și Alte vânzări și dă costul de rețetă.

Înainte de salvare se vede ce ajunge pe fiecare linie. Furnizorii direcți se așază pe o linie de COGS,
iar alegerea se ține minte pentru lunile următoare. Schimburile mari între gestiuni (mutări de stoc) vin
nebifate. Fișierele nu se încarcă nicăieri: în baza de date ajung doar sumele lunii. Reimportul aceleiași
luni înlocuiește cifrele importate, fără să le dubleze; cheltuielile scrise de mână rămân.

## 24. Comenzi către producție

Rulează [`0024_comenzi.sql`](supabase/migrations/0024_comenzi.sql), apoi fișierul intern cu catalogul de
pornire (`48-comenzi-date.sql`: produsele comandate des și clienții B2B; nu stă în acest depozit). Fără
migrare, pagina spune că lipsește, iar restul site-ului merge ca înainte.

Pagina **Comenzi** (`#/comenzi`, filă în *Tura* și *Echipa*) ține locul grupului de comenzi:

| Fel | Cine o pune |
|---|---|
| B2B și evenimente | biroul: GM, AE, CB2B, DP, ADM |
| Comandă de client (nume, telefon, avans, ora ridicării) | oricine, pentru o locație pe care o vede |
| Necesarul magazinului | la fel |
| Creme și materii prime | la fel |

- Fiecare produs ține de o **secție** (`cmd_sectii`: brutărie, patiserie, cofetărie și creme, depozit),
  iar rolurile secției îi confirmă liniile sau scriu de ce nu se poate. SP, DP și PBP răspund pentru
  orice secție. Cine a comandat primește notificare la fiecare răspuns.
- **Ora-limită** (implicit 19:00, cu o zi înainte; se schimbă din *Catalog*): după ea comanda pleacă
  drept „târzie” și se face doar dacă secția o confirmă.
- O linie schimbată după confirmare se întoarce la „de confirmat”; liniile neatinse își păstrează
  răspunsul. Anularea cere motiv, iar secțiile sunt anunțate.
- **Foaia de producție** a zilei adună comenzile pe secții: totalul pe produs și pentru cine e.
  Se tipărește din pagină.
- **Cine ce vede**: biroul și producția văd toate comenzile; magazinul pe ale locațiilor lui; oricine pe
  ale sale. Telefonul clientului nu ajunge la producție. Citirea se face doar prin `cmd_zi` și `cmd_zile`.
- **Catalogul** (produse, clienți, ora-limită) îl ține biroul; produsele le pot adăuga și SP / PBP.

Ca rolurile secțiilor să se potrivească cu oamenii voștri, schimbați coloana `roluri` din `cmd_sectii`.

## 25. Fișa de livrare

Rulează [`0025_livrari.sql`](supabase/migrations/0025_livrari.sql). Migrarea creează și bucket-ul privat
`livrari` din Storage, cu regulile lui; verifică în Supabase → Storage că apare. Fără migrare, pagina
spune că lipsește, iar restul site-ului merge ca înainte.

Pagina **Livrări** (`#/livrari`, filă în *Tura* și *Echipa*) ține locul grupului de livrări:

- **Livrările apar singure**: o comandă B2B devine o livrare, cu clientul, adresa și ora ei, și se ține
  după comandă (zi schimbată, anulare). Marfa unui magazin e o livrare pe zi și pe tură, cu tot ce a
  cerut magazinul: necesar, comenzi de clienți, creme.
- **Sarcini scrise de mână** (ridicări, transferuri, cumpărături): le adaugă biroul, șoferii, producția,
  RL, VT, GD și PP + B.
- **Șoferii** sunt conturile cu rolul LOG. Biroul alege șoferul din listă sau șoferul apasă „Preiau”
  pe o livrare liberă; poate și renunța la a lui. Livrările fără șofer apar marcate.
- **„Livrat”** cere cine a primit marfa și o poză (micșorată în browser, urcată în bucket-ul `livrari`)
  sau motivul pentru care poza nu se poate face. **„Problemă”** cere ce nu a mers. Ora și șoferul se
  pun singure. Sunt anunțați: cine a cerut livrarea, responsabilul magazinului pentru marfa lui și,
  la problemă, GM, AE și CB2B.
- **Cine ce vede**: biroul, șoferii și producția văd toate livrările; magazinul doar marfa lui; oricine
  pe cele cerute de el. Citirea se face doar prin `liv_zi` și `liv_zile`.

## 26. Panoul șefilor: toate locațiile

Rulează [`0026_panou.sql`](supabase/migrations/0026_panou.sql). Fără migrare, fila spune că lipsește, iar
restul site-ului merge ca înainte.

- **Echipa → Toate locațiile** (prima filă pentru cine vede mai multe locații; se reîmprospătează la un
  minut): pentru fiecare magazin și laborator, cine e în tură și de când e deschis, cine lipsește din
  program, fișele zilei, nota vitrinei, semnalările, marfa de azi, feedbackul săptămânii. „Detalii”
  deschide locația ca înainte (*Pe locație*).
- **Ziua locației** (`#/zi`, din *Tura* și din panou):
  - **Încasările zilei**: totalul încasat și numărul de bonuri, scrise de magazin la închidere (azi sau
    ieri; zilele mai vechi, doar șefii). Media bonului se calculează; panoul o compară cu aceeași zi de
    săptămâna trecută.
  - **Nota zilei**: câteva rânduri de la cine conduce locația.
  - **Stocul de azi**, la laboratoare: pe o listă (`stoc_produse`: produs, grupă, unitate, minim) ținută
    de SP, DP, PBP și birou. Sub minim, produsul apare ca „puțin”.

## 27. Standardele de produs

Rulează [`0027_standarde.sql`](supabase/migrations/0027_standarde.sql), apoi lista de pornire
(`49-standarde-date.sql`: opt produse cu criteriile lor; e o propunere și se schimbă din pagină).
Migrarea creează bucket-ul privat `standarde` din Storage. Fără migrare, pagina spune că lipsește.

Pagina **Standarde** (`#/standarde`, filă în *Tura* și *Echipa*) ține locul pozelor de dimineață de pe grup:

- **Produse și etaloane** (SP, DP, PBP și biroul): fiecare produs urmărit are o secție, 1–8 criterii
  scurte și o poză-etalon.
- **Verificarea de azi** (magazinul), pe secții: o singură poză cu toate produsele secției (de sus, tăiate
  și netăiate). Fiecare produs vine pe „în regulă”; la cel cu probleme se deschid criteriile lui și se scrie
  o explicație, iar produsul devine neconformitate. Cere și
  [`0028_standarde_grup.sql`](supabase/migrations/0028_standarde_grup.sql).
- **Sub standard**: neconformitatea ajunge la secția care a făcut produsul, la șefii de secție, la
  responsabilul magazinului și la conducere. Un șef hotărăște ce se face (rămâne la vânzare, degustare,
  retras), iar secția scrie cauza. După decizie, verificarea zilei nu se mai schimbă.
- **Rezumatul** (șefi și producție; apare și în *Echipa → Toate locațiile*): azi, pe magazine; ultimele
  7 zile, pe secții; produsele care au picat de cel puțin două ori în 14 zile, cu criteriile picate.

## 28. Adrese salvate, anunț doar pentru B2B, secții pe oameni (migrarea 0029)

Rulează `supabase/migrations/0029_notite.sql` în SQL Editor.

- **Adresele clienților**: la o comandă B2B, clientul nou intră singur în listă, iar adresa, ora și
  „aviz pe” se țin minte. La următoarea comandă vin completate; dacă clientul are mai multe adrese,
  apar ca sugestii.
- **Anunț „Doar B2B”**: ajunge numai la Coordonator B2B și Asistent Executiv. Ceilalți nu îl văd.
- **Cine îl primește**: înainte de trimitere, formularul de anunț arată destinatarii, grupați pe roluri.
- **Cine răspunde de fiecare secție** (*Comenzi → Catalog*): biroul bifează, pe fiecare om din
  producție, secțiile lui. Cine are bife primește și confirmă doar acele secții; cine nu are niciuna
  rămâne pe secțiile rolului.

## 29. Agenda responsabilului de locație (migrarea 0030)

Rulează `supabase/migrations/0030_agenda.sql`, apoi fișierul de date cu lista de sarcini (nu e în depozit).

- **Agenda** (tab nou la responsabil): sarcinile care se repetă, pe zi, săptămână și lună. Sus apare
  ce e de făcut acum; se bifează pe locație, cu o notă dacă e cazul.
- **Stările**: „de făcut azi” (zilnicele nebifate, sarcina cu zi fixă în ziua ei, sau când altfel
  nu mai iese numărul săptămânii), „în urmă” (ziua ei a trecut), „mai e timp”, „făcut”.
- **Mementoul** pleacă la ora pusă pe sarcină, doar dacă nu e bifată, către responsabilii locației.
- **Panoul șefilor**: pe fiecare magazin, câte sunt făcute azi, săptămâna și luna asta, și ce a rămas în urmă.
- **Lista** o ține biroul (cine vede tot): adaugă sarcini și le scoate, din josul paginii Agenda.
- **Fișa rolului** (*Roluri → Responsabil Locație*) arată aceeași listă, la „Responsabilități care se
  repetă”. Pentru asta rulează și `supabase/migrations/0031_agenda_pe_rol.sql`.

## 30. Jurnalul de activitate și rezumatul pentru șefi (migrarea 0032)

Rulează `supabase/migrations/0032_activitate.sql`.

- **Jurnalul**: bifele din agendă, încasările, nota zilei, stocul, comenzile și răspunsurile la ele,
  livrările, verificările de standard și testele se scriu singure, cu om, oră și locație.
- **Pagina Activitate** (*Echipa → Activitate*): șeful vede tot ce au făcut oamenii de sub el, pe
  locațiile lui; cine vede tot, vede tot. Se filtrează pe fel și pe locație.
- **Rezumatul** pleacă la 11:00, 15:00 și 21:00 (ora României): o singură notificare pe șef, cu ce s-a
  făcut de la rezumatul trecut, pe locații. Fără acțiuni noi, nu pleacă nimic.
- **Seara, la 21:00**: pe fiecare magazin, ce a rămas nefăcut din agendă ajunge pe loc la șefii responsabilului.
- Problemele (întârzieri, pași nefăcuți, semnalări, livrări cu probleme, produse sub standard) vin pe loc, ca înainte.
- Jurnalul păstrează 60 de zile.

## 31. Contacte, acoperire pe ore, sarcini care se bifează singure (migrarea 0033)

Rulează `supabase/migrations/0033_contacte_acoperire.sql` (cere 0030).

- **Contacte** (tab nou pentru toată echipa): oameni și firme de sunat, pe grupe, cu căutare. Numărul
  e legătură de sunat. Le adaugă și le șterg șefii.
- **Acoperire** (*Echipa → Acoperire*): pe fiecare locație, câți oameni sunt în program oră cu oră față
  de câți trebuie. Necesarul se pune pe intervale, în fiecare zi sau într-o zi anume.
- **Agenda**: o sarcină poate fi legată de încasări sau de nota zilei; atunci se bifează singură când
  responsabilul le scrie în „Ziua locației”.

## 32. Programul: și pentru cel care îl face (migrarea 0034)

Rulează `supabase/migrations/0034_program_si_pentru_sef.sql`.

În *Echipa → Program pe ture*, cine face programul se poate pune pe sine, pe colegii cu același rol și
pe șefii lui de pe teren (un vânzător de tură își poate pune responsabilul). Conducerea nu apare în listă.

## 33. Prezentarea rolului la primele trei deschideri (migrarea 0035)

Rulează `supabase/migrations/0035_prezentare_rol.sql`.

Responsabilul de locație vede, la primele trei deschideri ale aplicației, un ecran cu rolul lui: de ce
răspunde, sarcinile din agendă și unde găsește fiecare lucru. Numărătoarea e pe cont. Ecranul se poate
redeschide oricând din *Roluri → Responsabil Locație*. Pagina Contacte arată acum și contactele scrise
în pagina fiecărei locații, cu ce mai e de completat.

## 34. Orarul general (migrarea 0036)

Rulează `supabase/migrations/0036_orar_general.sql` (cere 0034).

- **Orar general** (*Echipa → Orar general*): toți oamenii pe rânduri, zilele pe coloane, tura colorată
  după locație. Îl lucrează responsabilii de locație, șefii de secție, coordonatorul de producție și
  conducerea: pot pune pe oricine, la orice magazin sau laborator. Rolurile sunt în tabela `orar_roluri`.
- **Tură nouă**: apeși pe căsuța omului în ziua dorită; aceeași tură se poate pune pe mai multe zile deodată.
  Două ture suprapuse pentru același om sunt refuzate. Fiecare tură ține minte cine a pus-o.
- **Acum**: pe fiecare locație, cine e în tură, cine lipsește sau a întârziat, cine a plecat și cine urmează.
  În tabel, turele de azi și cele trecute arată starea din pontaj.
- **Notificări la fiecare mutare**: omul pus, mutat sau scos află pe loc; responsabilii locației află și ei,
  dacă schimbarea a făcut-o altcineva. La mai multe ture puse deodată pleacă un singur mesaj de om.
  Schimbările intră și în Activitate și în rezumatul pentru șefi.

## Variabilele, pe scurt

| Ce | Unde | Public? |
|---|---|---|
| Project URL | `assets/config.js` | da |
| Cheia anon / publishable | `assets/config.js` | da |
| Cheia service_role / secret | doar în Supabase (funcția `admin-users` o primește automat) | **nu** |
| `ALLOWED_ORIGIN` | Edge Functions → Secrets (vezi pasul 6) | da |
| `SUPABASE_DB_URL` (opțional) | `.env` local, dacă vrei importul cu `psql "$SUPABASE_DB_URL" -f date-ghid.sql` | **nu** |

## De știut

- **Planul gratuit** suspendă proiectul după 7 zile fără nicio logare. Pentru
  un ghid folosit zilnic nu se întâmplă; dacă se întâmplă, îl repornești din
  dashboard cu un clic.
- **Fără email real**: pe adresele `@echipa.madamemagnifique.ro` nu se trimite
  nimic. Parola uitată o resetează adminul, din pagina **Admin**.
- **Spațiul de fișiere** (planul gratuit): 1 GB în Storage. Îl vezi în
  dashboard → **Storage**. Fișierele șterse din editor se șterg și din Storage.
