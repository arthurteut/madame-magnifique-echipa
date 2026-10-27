#!/usr/bin/env python3
"""PDF-urile de proceduri din Drive („Proceduri Bune”) → SQL pentru procedure_docs.

Spre deosebire de proceduri_verificate.py (care pornește de la textul dat de Drive), aici textul
vine din PDF, cu pdftotext; tabelele se refac din coloanele aliniate (-layout), iar fișele de
deschidere / închidere din textul -raw. Rolul Preparator patiserie (PP + B) are fișele lui.

Pregătire, pentru fiecare PDF:  pdftotext -layout X.pdf txt/X.layout.txt  și  pdftotext -raw X.pdf txt/X.raw.txt
Uz: python3 tools/proceduri_din_pdf.py <folder txt> <Harta.xlsx> <pdf_meta.json> <date-proceduri.sql> [<folder preview>]
pdf_meta.json: {"<nume fișier.pdf>": "<modifiedTime din Drive, ISO>"}

SQL-ul adaugă documentele noi și actualizează doar ce e pe site mai vechi decât în Drive, are altă
versiune (_v2 → _v3) sau alt nume pentru același modul și aceeași procedură; la final arată ce a făcut.
Conține textul procedurilor: NU îl pune în repo (date-*.sql e în .gitignore).
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import harta  # noqa: E402
import proceduri_verificate as pv  # noqa: E402

LOC = {'porumbescu': 'Porumbescu', 'fructus': 'Fructus', 'dumbravita': 'Dumbrăvița'}
MANUAL = dict(pv.MANUAL)
MANUAL[('BAR', 'Verificare_stoc_lapte_alternative_vegetale_pahare')] = 'PR-05.3'
MANUAL[('BAR', 'Propunerea_unei_asocieri_cafea_patiserie')] = 'PR-05.8'
MANUAL[('BAR', 'Calibrare_rasnita_si_extractie_de_test')] = 'PR-05.2'
MANUAL[('V', 'Cross-selling_standard')] = 'PR-04.4'
pv.MANUAL = MANUAL


def curat_nume(n):
    return re.sub(r' \(\d+\)(?=\.pdf$)', '', n)


# ---------------------------------------------------------------- module
def segmente(linie):
    return [(m.start(), m.group()) for m in re.finditer(r'\S+(?: \S+)*', linie)]


def este_tabel(linie):
    return linie.startswith(' ') and len(segmente(linie)) >= 2


def modul_corp(text):
    linii = text.replace('\f', '\n').split('\n')
    # subsolurile de pagină („MODULUL 2 · … — … 1”, „MODULUL 5 — … 1”)
    linii = [x for x in linii if not re.match(r'^MODULUL \d+.*—.*\s\d+\s*$', x)]
    nevide = [i for i, x in enumerate(linii) if x.strip()]
    modul, titlu = linii[nevide[0]].strip(), linii[nevide[1]].strip()
    linii = linii[nevide[1] + 1:]
    out, i = [], 0

    def bloc_tabel(i):
        starts = [s for s, _ in segmente(linii[i])]
        randuri, rand = [], None
        while i < len(linii):
            x = linii[i]
            if not x.strip():
                # rândurile tabelului sunt despărțite de un rând gol; tabelul continuă dacă urmează tot un rând indentat
                j = i
                while j < len(linii) and not linii[j].strip():
                    j += 1
                if j < len(linii) and linii[j].startswith(' ') and (j - i) <= 6 and \
                        all(any(abs(s - c) <= 2 for c in starts) for s, _ in segmente(linii[j])[:1]) and este_tabel_sau_cont(linii[j], starts):
                    rand = None
                    i = j
                    continue
                break
            if not x.startswith(' '):
                break
            if rand is None:
                rand = [''] * len(starts)
                randuri.append(rand)
            for s, t in segmente(x):
                k = max([k for k, c in enumerate(starts) if c <= s + 2] or [0])
                rand[k] = (rand[k] + ' ' + t).strip()
            i += 1
        # capul de tabel repetat pe pagina următoare
        uniq = [randuri[0]] + [r for r in randuri[1:] if r != randuri[0]]
        return i, uniq

    def este_tabel_sau_cont(x, starts):
        # un rând nou de tabel are cel puțin două celule; o casetă de după tabel are una
        return len(segmente(x)) >= 2

    while i < len(linii):
        x = linii[i]
        if not x.strip():
            i += 1
            continue
        if x.startswith(' ') and este_tabel(x) and (not out or out[-1] == '' or not re.match(r'^(\d+\.|-) ', out[-1])):
            i, randuri = bloc_tabel(i)
            if out and out[-1] != '':
                out.append('')
            out += ['| ' + ' | '.join(c for c in r) + ' |' for r in randuri]
            out.append('')
            continue
        if x.startswith('   ') and not este_tabel(x):
            # casetă (callout): rânduri indentate, fără coloane
            txt = []
            while i < len(linii) and linii[i].startswith('  ') and linii[i].strip() and not este_tabel(linii[i]):
                txt.append(linii[i].strip())
                i += 1
            if out and out[-1] != '':
                out.append('')
            out += ['> ' + ' '.join(txt), '']
            continue
        s = x.strip()
        m = re.match(r'^(\d{1,2})\.\s+(.*)$', s)
        if m and re.fullmatch(rf"[{pv.MAJ}0-9 ,/()–—\-’'„”:+&.%·]+", m.group(2)):
            if out and out[-1] != '':
                out.append('')
            out += ['## ' + m.group(2), '']
            i += 1
            continue
        if m or s.startswith('- ') or s.startswith('• '):
            txt = s if m else '- ' + re.sub(r'^[-•]\s*', '', s)
            i += 1
            while i < len(linii) and linii[i].startswith(' ') and linii[i].strip() and not este_tabel(linii[i]):
                txt += ' ' + linii[i].strip()
                i += 1
            out.append(txt)
            continue
        # paragraf: rândurile consecutive neindentate
        txt = s
        i += 1
        while i < len(linii) and linii[i].strip() and not linii[i].startswith(' ') and \
                not re.match(r'^(\d{1,2}\.\s|[-•]\s)', linii[i].strip()):
            txt += ' ' + linii[i].strip()
            i += 1
        if out and out[-1] != '' and not out[-1].startswith('## '):
            out.append('')
        out.append(txt)
        out.append('')
    corp = re.sub(r'\n{3,}', '\n\n', '\n'.join(out)).strip()
    corp = re.sub(r'_{3,}', '____', corp)
    return modul, titlu, corp


# ---------------------------------------------------------------- fișe (deschidere / închidere)
def fisa_corp(text):
    linii = [x.strip() for x in text.replace('\f', '\n').split('\n')]
    linii = [x for x in linii if x]
    antet = linii[0]
    linii = [x for x in linii[1:] if x != antet and not x.startswith('Document intern Madame Magnifique')]
    modul = antet[len('MADAME MAGNIFIQUE '):] if antet.upper().startswith('MADAME MAGNIFIQUE ') else ''
    titlu = linii[0]
    rest = linii[1:]
    # nota de sub titlu („Pe ore: …”, „Locația … · Se face la începutul turei”) vine după câmpurile de completat
    note = []
    while rest and '_' not in rest[0] and not re.match(r'^\d{1,2}\.?\s', rest[0]):
        note.append(rest.pop(0))
    campuri = []
    while rest and '_' in rest[0] and not re.match(r'^\d{1,2}\.?\s', rest[0]):
        campuri.append(rest.pop(0))
    text_drive = '\n'.join([titlu] + campuri + note + rest)
    _, _, corp = pv.curata('MADAME MAGNIFIQUE\n' + text_drive, True)
    corp = pv.lipeste_pasi(corp)
    # fișa de temperaturi: „Punct de măsurare Dimineața După-amiaza Seara” + câte un rând pe punct
    cel = r'(____ °C Ora: ____)'
    def tabel_temp(m):
        cap = m.group(1).replace('Punct de măsurare', 'Punct de măsurare|').split('|')
        cap = [cap[0].strip()] + cap[1].split()
        randuri = re.findall(rf'^(.+?) {cel} {cel} {cel}$', m.group(2), flags=re.M)
        return '\n'.join('| ' + ' | '.join(r) + ' |' for r in [cap] + randuri) + '\n\n'
    corp = re.sub(rf'^(Punct de măsurare(?: \S+){{3}})\n\n?((?:.+ {cel} {cel} {cel}\n\n?)+)', tabel_temp, corp + '\n', flags=re.M).strip()
    return modul, titlu, corp


def main():
    txt, harta_cale, meta_cale, iesire = sys.argv[1:5]
    preview = Path(sys.argv[5]) if len(sys.argv) > 5 else None
    proceduri = harta.citeste(harta_cale)['proceduri']
    for p in proceduri:
        p['rol'] = 'PP + B' if p['rol'] == 'PP+B' else p['rol']
    meta = json.loads(Path(meta_cale).read_text())
    docs, probleme = [], []
    for sursa_drive, modificat in sorted(meta.items()):
        f = Path(txt) / (sursa_drive[:-4] + '.layout.txt')
        if not f.exists():
            probleme.append(f'lipsește textul: {sursa_drive}')
            continue
        sursa = curat_nume(sursa_drive)
        stem = sursa[:-4]
        baza = re.sub(r'_v\d+$', '', stem)
        text = f.read_text(encoding='utf-8')
        raw = (Path(txt) / (sursa_drive[:-4] + '.raw.txt')).read_text(encoding='utf-8')
        m_prep = re.match(r'^Preparator_Patiserie_(Porumbescu|Fructus|Dumbravita)_(Deschidere|Inchidere)$', stem)
        if baza in pv.FISE:
            cod, rol, loc = pv.FISE[baza]
            modul, titlu, corp = fisa_corp(raw)
            poz = 0
        elif m_prep:
            cod, rol, loc = None, 'PP + B', m_prep.group(1).lower()
            modul, titlu, corp = fisa_corp(raw)
            poz = 0
        else:
            rol, loc, nume = pv.clasifica(stem)
            cod, scor = pv.potriveste(proceduri, rol, nume)
            if scor < 0.6:
                probleme.append(f'fără procedură ({scor:.2f}): {sursa}')
                cod = None
            modul, titlu, corp = modul_corp(text)
            n = re.match(r'^MODULUL (\d+)', modul)
            modul = f'Modulul {n.group(1)} · ' + (f'Barista {LOC[loc]}' if rol == 'BAR' and loc else pv.NUME_ROL.get(rol, rol))
            poz = int(re.search(r'_(\d+)_', stem).group(1))
        # verificare: niciun cuvânt pierdut (față de textul brut, fără subsoluri și antete)
        cuv_pdf = re.findall(r'\w+', re.sub(r'(?m)^(MODULUL \d+.*—.*\d+|Document intern Madame Magnifique.*)$', '', text))
        cuv_doc = re.findall(r'\w+', titlu + ' ' + modul + ' ' + corp)
        from collections import Counter
        lipsa = Counter(cuv_pdf) - Counter(cuv_doc)
        lipsa = {k: v for k, v in lipsa.items() if not re.fullmatch(r'_+|MADAME|MAGNIFIQUE|MODULUL|\d+', k)}
        if lipsa:
            probleme.append(f'cuvinte pierdute în {sursa}: {lipsa}')
        for tab in re.findall(r'(?:^\|.*\|$\n?)+', corp, flags=re.M):
            if len({r.count('|') for r in tab.strip().split('\n')}) > 1:
                probleme.append(f'tabel inegal: {sursa}')
        docs.append(dict(sursa=sursa, cod=cod, rol=rol, loc=loc, titlu=titlu, modul=modul, corp=corp, poz=poz, modificat=modificat))
        if preview:
            preview.mkdir(exist_ok=True)
            (preview / (stem + '.md')).write_text(f'# {titlu}\n[{modul}] cod={cod} rol={rol} loc={loc}\n\n{corp}\n', encoding='utf-8')
    q = pv.q
    norm = lambda x: f"lower(regexp_replace({x}, '( \\(\\d+\\))?(_v\\d+)?\\.pdf$', '', 'i'))"
    sql = ['-- Proceduri Bune (Drive) → procedure_docs. Conținut intern: nu se pune în repo.\n',
           '-- Adaugă documentele noi; actualizează doar ce e mai vechi pe site decât în Drive sau are alt nume/versiune.\n',
           'begin;\n', 'create temp table if not exists raport (fisier text, ce_s_a_facut text, inainte text);\n', 'truncate raport;\n']
    for d in docs:
        nr = re.match(r'^((?:Barista_\w+?_|Vanzator_)\d\d_)', d['sursa'])
        potrivire = f"{norm('source_file')} = {norm(q(d['sursa']))}"
        if nr:
            # același modul, redenumit: același prefix + număr și aceeași procedură
            potrivire = f"({potrivire} or (source_file like {q(nr.group(1).replace('_', chr(92) + '_') + '%')} and procedure_code is not distinct from {q(d['cod'])}))"
        sql.append(f"""do $$
declare v_id bigint; v_sursa text; v_data timestamptz;
begin
  select id, source_file, updated_at into v_id, v_sursa, v_data from public.procedure_docs
   where source_file = {q(d['sursa'])} or {potrivire}
   order by (source_file = {q(d['sursa'])}) desc, updated_at desc limit 1;
  if v_id is null then
    insert into public.procedure_docs (procedure_code, role_code, space_id, title, module, body, source_file, position, updated_at)
    values ({q(d['cod'])}, {q(d['rol'])}, {q(d['loc'])}, {q(d['titlu'])}, {q(d['modul'])}, {q(d['corp'])}, {q(d['sursa'])}, {d['poz']}, now());
    insert into raport values ({q(d['sursa'])}, 'adăugat', null);
  elsif v_sursa <> {q(d['sursa'])} or v_data < {q(d['modificat'])}::timestamptz then
    update public.procedure_docs set procedure_code = {q(d['cod'])}, role_code = {q(d['rol'])}, space_id = {q(d['loc'])},
      title = {q(d['titlu'])}, module = {q(d['modul'])}, body = {q(d['corp'])}, source_file = {q(d['sursa'])}, position = {d['poz']},
      pdf_path = case when v_sursa = {q(d['sursa'])} then pdf_path end, updated_at = now()
    where id = v_id;
    insert into raport values ({q(d['sursa'])}, case when v_sursa = {q(d['sursa'])} then 'actualizat' else 'actualizat (înlocuiește versiunea veche)' end,
      case when v_sursa <> {q(d['sursa'])} then v_sursa end);
  else
    insert into raport values ({q(d['sursa'])}, 'deja la zi', null);
  end if;
end $$;
""")
    sql.append("select ce_s_a_facut, count(*) as cate, string_agg(fisier || coalesce(' ← ' || inainte, ''), ' · ' order by fisier) as fisiere\n"
               "from raport where ce_s_a_facut <> 'deja la zi' group by 1\n"
               "union all select 'deja la zi', count(*), null from raport where ce_s_a_facut = 'deja la zi'\n"
               "order by 1;\n")
    sql.insert(len(sql) - 1, 'commit;\n')
    Path(iesire).write_text(''.join(sql), encoding='utf-8')
    for p in probleme:
        print('ATENȚIE:', p)
    for d in docs:
        print(f"{d['sursa']:<88} {str(d['cod']):<8} {str(d['rol']):<6} {str(d['loc']):<11} {d['modul']}")
    print(len(docs), 'documente')


if __name__ == '__main__':
    main()
