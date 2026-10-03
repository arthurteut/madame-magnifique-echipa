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
