# Madame Magnifique — Ghidul echipei

Pagina internă la care angajații revin de fiecare dată când au o întrebare:
cine face, ce face, când și cum se verifică. Adresa: **echipa.madamemagnifique.ro**.

## Ce conține

Construită din *Harta Operațiunilor Madame Magnifique* (Excel), în stilul
vizual al madamemagnifique.ro: antracit `#242424`, bej-gri `#dedcd8`, nisip
`#e3d0aa`, Montserrat + Roboto și logo-ul oficial.

- **Spații separate**, fiecare cu particularitățile lui:
  - Magazinele **Porumbescu**, **Dumbrăvița** și **Fructus**: standardul de rețea
    (P01–P14, cu task-uri și proceduri), plus abaterile locației, marcate
    „Diferit aici” direct în procesul respectiv.
  - **Laboratorul Peciu Nou**: brutărie și patiserie.
  - **Laboratorul Fructus**: cofetărie, creme și dulcețuri, coacere patiserie.
  - **B2B, evenimente și candybar**.
  - **Birou central**: aprovizionare, marketing, financiar, oameni.
- **Filtru pe rol** în fiecare spațiu, plus o **fișă de lucru** pentru fiecare
  rol (procese, task-uri pas cu pas, proceduri).
- **Registrul procedurilor**, filtrabil, cu lanțul „vine după / urmează”.
- **Căutare** pe tot conținutul, fără diacritice obligatorii (tasta `/`).
- **Conturi individuale** (utilizator + parolă), cu acces pe rol.
- **Cursuri de onboarding** pe rol: lecții (text, video din link, fișiere), bifă
  „am parcurs” și test la final. Adminul le editează și vede progresul echipei.

## Conturi și confidențialitate

Fiecare angajat se loghează cu utilizatorul și parola lui (fără înregistrare
publică: conturile le creează adminul). Conținutul stă în **Supabase**, nu în
repo: pagina îl citește după logare, iar regulile din baza de date (Row Level
Security) decid ce primește fiecare. Excel-ul și exportul SQL nu se pun niciodată
în repo. Configurarea: [`SUPABASE-SETUP.md`](SUPABASE-SETUP.md).

## Actualizare

```bash
pip install openpyxl
python3 tools/import_supabase.py Harta.xlsx date-ghid.sql   # conținutul → Supabase (SQL Editor)
python3 tools/pagina.py                                     # aspectul → index.html
```

- Structura spațiilor, fișele, ajustările de dimineață și actualizările de pe
  teren se editează în `tools/harta.py`.
- Aspectul se editează în `src/template.html`.
- Schema bazei de date: `supabase/migrations/`; teste locale: `supabase/tests/`.

## Publicare

Detaliile pentru domeniu sunt în [`DNS-SETUP.md`](DNS-SETUP.md).
