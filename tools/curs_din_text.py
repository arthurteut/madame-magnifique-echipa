#!/usr/bin/env python3
"""Pune un curs întreg (lecții + test) în Academia Madame, dintr-un fișier JSON.

Utilizare:
    python3 tools/curs_din_text.py curs.json date-curs.sql [curs2.json ...]

Ultimul argument care se termină în .sql e fișierul generat; restul sunt cursuri.
curs.json:
    {
      "title": "Introducere în lumea cafelei",
      "description": "…",
      "category": "barista",            # brutarie | barista | patiserie-cofetarie | vanzare-servire | general
      "roles": ["BAR"],                 # pentru cine e „de făcut” (toți îl văd, după 0012)
      "is_common": false,
      "published": true,
      "pass_percent": 70,
      "position": 10,
      "lessons": ["b1.md", "b2.md"],    # căi relative la curs.json; prima linie „TITLE: …”
      "quiz": [{"q": "…", "options": ["…", "…"], "correct": 1}]
    }
Lecțiile folosesc formatul procedurilor verificate (##, ###, -, 1., >, | tabel |, **bold**).
Cursul cu același titlu se înlocuiește (lecțiile, testul și progresul lui se refac).
Variantele de răspuns se amestecă (determinist), ca răspunsul corect să nu fie mereu pe
aceeași poziție.

Fișierul SQL conține materialele cursului: NU îl pune în repo (date-*.sql e în .gitignore).
"""
import json
import random
import re
import sys
from pathlib import Path

CATEGORII = {"general", "brutarie", "barista", "patiserie-cofetarie", "vanzare-servire"}


def q(v):
    return "'" + str(v).replace("'", "''") + "'"


def arr(xs):
    return "array[" + ", ".join(q(x) for x in xs) + "]::text[]"


def verifica(nume, corp):
    probleme = []
    for nr, rand in enumerate(corp.split("\n"), 1):
        if re.match(r"^\|\s*:?-{3,}", rand):
            probleme.append(f"{nume}:{nr}: rând separator de tabel „|---|”")
        if re.match(r"^#{4,}\s|^#\s", rand):
            probleme.append(f"{nume}:{nr}: titlu cu alt nivel decât ## sau ###")
        if "\\*" in rand or "\\_" in rand:
            probleme.append(f"{nume}:{nr}: caractere scăpate (\\* sau \\_)")
    for tab in re.findall(r"(?:^\|.*\|$\n?)+", corp, flags=re.M):
        if len({r.count("|") for r in tab.strip().split("\n")}) > 1:
            probleme.append(f"{nume}: tabel cu rânduri de lungimi diferite: {tab.splitlines()[0][:60]}")
    return probleme


def curs_sql(f, probleme):
    c = json.loads(f.read_text(encoding="utf-8"))
    if c.get("category", "general") not in CATEGORII:
        sys.exit(f"{f}: categorie necunoscută {c.get('category')!r}")
    lectii = []
    for nume in c.get("lessons", []):
        text = (f.parent / nume).read_text(encoding="utf-8").strip()
        m = re.match(r"TITLE:\s*(.+)\n", text)
        if not m:
            sys.exit(f"{nume}: prima linie trebuie să fie „TITLE: …”")
        corp = text[m.end():].strip()
        probleme += verifica(nume, corp)
        lectii.append((m.group(1).strip(), corp))
    rnd = random.Random(c["title"])
    intrebari = []
    for i, x in enumerate(c.get("quiz", [])):
        opt = list(x["options"])
        if not 2 <= len(opt) <= 6 or not 0 <= x["correct"] < len(opt):
            sys.exit(f"{f}: întrebarea {i + 1} are variante greșite")
        bun = opt[x["correct"]]
        rnd.shuffle(opt)
        intrebari.append((x["q"], opt, opt.index(bun)))
    out = [f"-- {c['title']}\n", "do $$\ndeclare v_curs bigint; v_q bigint;\nbegin\n",
           f"  delete from public.courses where title = {q(c['title'])};\n",
           "  insert into public.courses (title, description, category, is_common, published, pass_percent, position)\n",
           f"  values ({q(c['title'])}, {q(c.get('description', ''))}, {q(c.get('category', 'general'))}, "
           f"{str(bool(c.get('is_common'))).lower()}, {str(c.get('published', True)).lower()}, "
           f"{int(c.get('pass_percent', 80))}, {int(c.get('position', 0))})\n  returning id into v_curs;\n"]
    for r in c.get("roles", []):
        out.append(f"  insert into public.course_roles (course_id, role_code) select v_curs, code from public.roles where code = {q(r)};\n")
    for i, (titlu, corp) in enumerate(lectii):
        out.append(f"  insert into public.lessons (course_id, position, title, body) values (v_curs, {i}, {q(titlu)}, {q(corp)});\n")
    for i, (intr, opt, corect) in enumerate(intrebari):
        out.append(f"  insert into public.quiz_questions (course_id, position, question, options) values (v_curs, {i}, {q(intr)}, {arr(opt)})\n"
                   f"    returning id into v_q;\n  insert into public.quiz_answers (question_id, correct) values (v_q, {corect});\n")
    out.append("end $$;\n")
    return "".join(out), len(lectii), len(intrebari)


def main():
    args = sys.argv[1:]
    if len(args) < 2 or not args[-1].endswith(".sql"):
        sys.exit(__doc__)
    iesire, cursuri = Path(args[-1]), [Path(a) for a in args[:-1]]
    sql = ["-- Generat de tools/curs_din_text.py. Conținut intern: nu se pune în repo.\n",
           "-- Rulează după 0013_categorii_academie.sql.\n", "begin;\n"]
    probleme = []
    for f in cursuri:
        bucata, nl, nq = curs_sql(f, probleme)
        sql.append(bucata)
        print(f"{f.name}: {nl} lecții, {nq} întrebări")
    sql.append("commit;\n")
    iesire.write_text("".join(sql), encoding="utf-8")
    for p in probleme:
        print("ATENȚIE:", p)
    print(f"{iesire} scris.")


if __name__ == "__main__":
    main()
