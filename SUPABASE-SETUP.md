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
   - Numele funcției: **`admin-users`** (exact așa)
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
