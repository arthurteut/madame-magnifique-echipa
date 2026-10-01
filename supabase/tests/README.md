# Teste locale pentru schema și regulile de acces

Rulează pe un Postgres 16 local, nu pe Supabase. `00_mediu_supabase_local.sql`
imită ce oferă Supabase (rolurile `anon` / `authenticated` / `service_role` și
`auth.uid()` citit din `request.jwt.claim.sub`).

```bash
createdb ghid
psql -d ghid -f supabase/tests/00_mediu_supabase_local.sql
psql -d ghid -f supabase/migrations/0001_schema_si_autentificare.sql
python3 tools/import_supabase.py Harta.xlsx date-ghid.sql && psql -d ghid -f date-ghid.sql
psql -d ghid -f supabase/tests/01_pas1_autentificare.sql
```

Ce trebuie să iasă la pasul 1: anonimul primește „permission denied”; un VT
activ vede cele 103 proceduri și doar propriul profil; GM vede toate profilurile;
un cont dezactivat sau fără profil vede 0 proceduri; orice UPDATE din rolul
`authenticated` e refuzat.
