#!/usr/bin/env python3
"""Încarcă „Ghidul brutarului” (capitolele) în Supabase.

Intrare: un folder cu cap01.md … cap13.md (text simplu: ##, ###, 1., -, | tabel |, > casetă).
Ieșire: un fișier SQL care adaugă / actualizează capitolele în handbook_chapters.

Utilizare:
    python3 tools/ghid_brutar.py capitole/ date-brutar.sql

Fișierul SQL conține ghidul: NU îl pune în repo (date-*.sql e în .gitignore).
"""
import re
import sys
from pathlib import Path

TITLURI = {
    "cap01": "Ce este maiaua, de fapt",
    "cap02": "Cum conduci aroma și aciditatea",
    "cap03": "Enzimele și de ce contează pentru brutar",
    "cap04": "Crearea și întreținerea maialei-mamă",
    "cap05": "Dimensionarea și construirea maialei de producție",
    "cap06": "Făina",
    "cap07": "Procesul de producție, pas cu pas",
    "cap08": "Planificarea producției pe 24–48 de ore",
    "cap09": "Sezonalitate și variabilitate",
    "cap10": "Diagnostic și remediere",
    "cap11": "Siguranța alimentară și igiena maialei",
    "cap12": "Fișe de lucru (anexe printabile)",
    "cap13": "Rețetele casei: fișele tehnologice actuale",
}


def q(v):
    return "'" + str(v).replace("'", "''") + "'"


def verifica(slug, corp):
    """Probleme de format pe care site-ul nu le afișează bine."""
    probleme = []
    for nr, rand in enumerate(corp.split("\n"), 1):
        if re.match(r"^\|\s*:?-{3,}", rand):
            probleme.append(f"{slug}:{nr}: rândul separator de tabel „|---|” (se scoate)")
        if re.match(r"^#{4,}\s|^#\s", rand):
            probleme.append(f"{slug}:{nr}: titlu cu alt nivel decât ## sau ###")
    for tab in re.findall(r"(?:^\|.*\|$\n?)+", corp, flags=re.M):
        celule = {r.count("|") for r in tab.strip().split("\n")}
        if len(celule) > 1:
            probleme.append(f"{slug}: tabel cu rânduri de lungimi diferite: {tab.splitlines()[0][:60]}")
    return probleme


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    folder, iesire = Path(sys.argv[1]), Path(sys.argv[2])
    sql = ["-- Generat de tools/ghid_brutar.py. Conținut intern: nu se pune în repo.\n", "begin;\n"]
    probleme = []
    for i, (slug, titlu) in enumerate(TITLURI.items()):
        f = folder / f"{slug}.md"
        if not f.exists():
            probleme.append(f"lipsește {f.name}")
            continue
        corp = f.read_text(encoding="utf-8").strip()
        corp = "\n".join(r for r in corp.split("\n") if not re.match(r"^\|\s*:?-{3,}", r))   # separatoare |---|
        probleme += verifica(slug, corp)
        sql.append("insert into public.handbook_chapters (slug, position, title, body, updated_at)\n"
                   f"values ({q(slug)}, {i}, {q(titlu)}, {q(corp)}, now())\n"
                   "on conflict (slug) do update set position = excluded.position, title = excluded.title,\n"
                   "  body = excluded.body, updated_at = now();\n")
    sql.append("commit;\n")
    iesire.write_text("".join(sql), encoding="utf-8")
    for p in probleme:
        print("ATENȚIE:", p)
    print(f"{iesire} scris.")


if __name__ == "__main__":
    main()
