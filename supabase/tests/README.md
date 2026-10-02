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
