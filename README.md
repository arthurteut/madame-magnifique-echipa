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

## Confidențialitate

Repo-ul e public (cerință GitHub Pages pe contul gratuit), dar conținutul **nu**:
tot ce e în ghid e criptat în `index.html` (AES-256-GCM, cheie derivată din
parola echipei cu PBKDF2-SHA256, 310.000 de iterații). Fără parolă se vede doar
ecranul de intrare. Excel-ul sursă nu se pune niciodată în repo (`.gitignore`).
Pagina e exclusă de la indexare (`robots.txt` + `noindex`).

Parola se împarte doar oral sau în grupul intern. Pe tabletele din magazine,
bifa „Ține-mă minte” păstrează accesul.

## Actualizare (conținut nou sau parolă nouă)

```bash
pip install openpyxl cryptography
python3 tools/build.py /cale/catre/Harta_Operatiuni_Madame_Magnifique_FIRMA.xlsx
# cere parola; apoi:
git add index.html && git commit -m "Actualizare ghid" && git push
```

- Structura spațiilor (ce procese, roluri și note are fiecare magazin sau
  laborator) se editează în `SPATII`, în `tools/build.py`.
- Aspectul se editează în `src/template.html`.
- Schimbarea parolei = rulezi build-ul cu parola nouă. Dispozitivele cu parola
  veche salvată vor cere din nou parola.

## Publicare

Detaliile pentru domeniu sunt în [`DNS-SETUP.md`](DNS-SETUP.md).
