#!/usr/bin/env python3
"""Încarcă procedurile verificate (PDF-urile din „Madame Verificate”) în Supabase.

Intrare: un folder cu câte un fișier .json pe document, de forma
    {"title": "Vanzator_Tura_25_Deschiderea_casei_si_a_turei_POS.pdf", "text": "…"}
(„text” = textul PDF-ului, așa cum îl dă Google Drive), plus harta de operațiuni
(Excel sau exportul JSON al hărții), din care se iau codurile procedurilor.

Ieșire: un fișier SQL care adaugă / actualizează documentele (după numele
fișierului), fără să atingă PDF-urile deja atașate din Admin.

Utilizare:
    python3 tools/proceduri_verificate.py Harta.xlsx proceduri/ date-proceduri.sql
    python3 tools/proceduri_verificate.py Harta.xlsx proceduri/ --verifica   # doar potrivirile
    python3 tools/proceduri_verificate.py Harta.xlsx proceduri/ date-proceduri.sql --tabele corpuri_tab/

Cu --tabele, textul unui document se ia din <folder>/<nume>.txt, unde tabelele sunt marcate
Markdown („| Când | Ce faci |”). Se acceptă doar dacă are exact aceleași cuvinte, în aceeași
ordine, ca textul extras din PDF (se pot adăuga doar separatoarele „|” și rânduri goale).

Fișierul SQL conține textul procedurilor: NU îl pune în repo (date-*.sql e în .gitignore).
"""
import difflib
import json
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

# Prefixul numelui de fișier → rolul și, unde e cazul, locația.
PREFIXE = [
    ("Vanzator_Tura_", "VT", None),
    ("Vanzator_", "V", None),
    ("Responsabil_Locatie_", "RL", None),
    ("Barista_Porumbescu_", "BAR", "porumbescu"),
    ("Barista_Fructus_", "BAR", "fructus"),
    ("Barista_Dumbravita_", "BAR", "dumbravita"),
]
# Corecturi cerute după verificare (rânduri scoase din textul unui document).
SCOASE = {
    # Diferențele merg pe aviz la contabilitate, nu se raportează la producție (2 oct. 2026).
    "Vanzator_Tura_04_Receptia_cantitativa_a_livrarii_din_laboratoare.pdf": [
        "8. Raportezi diferențele către producție în aceeași zi (Modulul 6).",
    ],
}
NUME_ROL = {"V": "Vânzător", "VT": "Vânzător de tură", "RL": "Responsabil locație", "BAR": "Barista"}
# Modulele barista fără locație în nume („02_Calibrarea…”): valabile peste tot.
BARISTA_FARA_LOCATIE = re.compile(r"^\d\d_")
# Fișele locațiilor: procedura din registru, rolul (None = toată echipa locației), locația.
FISE = {
    "Procedura_Deschidere_Porumbescu": (None, None, "porumbescu"),
    "Procedura_Inchidere_Porumbescu": (None, None, "porumbescu"),
    "Procedura_Deschidere_Fructus": (None, None, "fructus"),
    "Procedura_Inchidere_Fructus": (None, None, "fructus"),
    "Procedura_Deschidere_Dumbravita": (None, None, "dumbravita"),
    "Procedura_Inchidere_Dumbravita": (None, None, "dumbravita"),
    "Procedura_Inchidere_Vectron": ("PR-10.5", "VT", None),
}
# Potriviri pe care titlul nu le prinde singur (numele fișierului fără număr → cod).
MANUAL = {
    ("BAR", "Pornire_si_incalzire_espressor_purjare_grupuri"): "PR-05.1",
    ("BAR", "Curatare_grupuri_portafiltre_si_lance_dupa_fiecare_utilizare"): "PR-05.6",
    ("BAR", "Backflush_cu_detergent_si_curatarea_rasnitei"): "PR-05.6",
    ("BAR", "Servire_cu_vesela_aliniata_brandului"): "PR-05.5",
    ("BAR", "Verificare_stoc_lapte_alternative_vegetale_siropuri_pahare"): "PR-05.3",
    ("BAR", "Verificarea_stocului_de_bar"): "PR-05.3",
}


def fara_diacritice(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def cheie(s):
    return re.sub(r"[^a-z0-9 ]+", " ", fara_diacritice(s).lower()).split()


def proceduri_din_harta(cale):
    if cale.endswith(".json"):
        return json.loads(Path(cale).read_text(encoding="utf-8"))["proceduri"]
    import harta
    return harta.citeste(cale)["proceduri"]


def clasifica(stem):
    """(rol, locație, nume fără prefix și număr) pentru un fișier de modul."""
    for prefix, rol, loc in PREFIXE:
        if stem.startswith(prefix):
            return rol, loc, re.sub(r"^\d+_", "", stem[len(prefix):])
    if BARISTA_FARA_LOCATIE.match(stem):
        return "BAR", None, stem[3:]
    return None, None, stem


# ---------------------------------------------------------------------------
# Textul PDF-ului → text simplu pentru ghid
# ---------------------------------------------------------------------------
MAJ = "A-ZĂÂÎȘŞȚŢ"


def curata(text, fisa):
    """Întoarce (modul, titlu, corp)."""
    t = text.replace("\\_", "_").replace("\\.", ".").replace("\\-", "-").replace("\\*", "*").replace("\\#", "#")
    linii = [x.strip() for x in t.split("\n")]
    linii = [x for x in linii if x]
    modul, titlu = "", ""
    if fisa:
        if linii and linii[0].upper() == "MADAME MAGNIFIQUE":
            linii = linii[1:]
        elif linii and linii[0].upper().startswith("MADAME MAGNIFIQUE "):
            modul, linii = linii[0][len("MADAME MAGNIFIQUE "):], linii[1:]
        titlu, linii = linii[0], linii[1:]
        # „Procedura de inchidere — Locatie Porumbescu Sambata: …”: restul rândului e o notă.
        nota = None
        m = re.match(r"^(Procedura de \S+ — Locatie \S+)\s+(.+)$", titlu) or \
            re.match(r"^(.+?)\s+((?:Valabil|Sambata|Sâmbăta|Se face)\S*.*)$", titlu)
        if m:
            titlu, nota = m.group(1), m.group(2)
        # câmpurile de completat de pe hârtie (data, ora, operatorul), dinaintea primei secțiuni
        while linii and not re.match(r"^\d{1,2}\.\s", linii[0]) and ("_" in linii[0] or re.match(r"^\w+:$", linii[0])):
            linii = linii[1:]
        if nota:
            linii.insert(0, nota)
    else:
        m = re.match(rf"^(MODULUL\s+\d+(?:\s+·\s+[{MAJ}0-9 ]+?)?)\s+([{MAJ}][a-zăâîșşțţ].*)$", linii[0])
        if m:
            modul, titlu = m.group(1), m.group(2)
            linii = linii[1:]
        modul = " · ".join(x.strip().lower().capitalize() for x in modul.split("·"))
        # subsolurile de pagină: „MODULUL 25 · VÂNZĂTOR DE TURĂ — DESCHIDEREA … 1”
        linii = [x for x in linii if not re.match(r"^MODULUL\s+\d+\s", x)]
    out = []
    for x in linii:
        x = re.sub(r"_{3,}", "____", x)
        x = x.replace("■ DA", "☐ DA").replace("■ NU", "☐ NU")
        m_pas_fisa = re.match(r"^(\d{1,2})\s+[■☐□]\s+(.*)$", x)
        m_num = re.match(r"^(\d{1,2})\.\s+(.*)$", x)
        if fisa and m_pas_fisa:
            out.append(f"{m_pas_fisa.group(1)}. {m_pas_fisa.group(2)}")
        elif m_num and (fisa or re.fullmatch(rf"[{MAJ}0-9 ,/()–—\-’'„”:+&.%]+", m_num.group(2))):
            out.append("")
            out.append("## " + m_num.group(2))
        elif m_num:
            out.append(f"{m_num.group(1)}. {m_num.group(2)}")
        elif re.match(r"^[-•]\s*", x) and len(x) > 2:
            out.append("- " + re.sub(r"^[-•]\s*", "", x))
        elif out and out[-1] and not out[-1].startswith("## ") and re.match(r"^[a-zăâîșşțţ(]", x) \
                and not re.search(r"[.!?:”)]$", out[-1]):
            out[-1] += " " + x          # rând rupt de PDF
        else:
            if out and out[-1] and not re.match(r"^(\d+\.|-|##)\s", out[-1]):
                out.append("")
            out.append(x)
    corp = re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip()
    return modul, titlu, corp


def potriveste(proceduri, rol, nume):
    if (rol, nume) in MANUAL:
        return MANUAL[(rol, nume)], 1.0
    tinta = " ".join(cheie(nume.replace("_", " ")))
    cand = [p for p in proceduri if p["rol"] == rol]
    best, scor = None, 0.0
    for p in cand:
        r = difflib.SequenceMatcher(None, tinta, " ".join(cheie(p["titlu"]))).ratio()
        if r > scor:
            best, scor = p["cod"], r
    return best, scor


def lipeste_pasi(corp):
    """Un pas / punct de listă rupt de PDF pe două rânduri („… tranzacție” + „POS refuzată …”)."""
    out = []
    for x in corp.split("\n"):
        if out and re.match(r"^(\d{1,2}\.|-)\s", out[-1]) and not re.search(r"[.!?:;”)]$", out[-1]) \
                and x.strip() and not re.match(r"^(\d{1,2}\.|-|##|\|)\s?", x):
            out[-1] += " " + x.strip()
        else:
            out.append(x)
    return "\n".join(out)


def cuvinte(t):
    return [w for w in re.split(r"\s+", t.replace("|", " ")) if w]


def q(v):
    return "null" if v is None else "'" + str(v).replace("'", "''") + "'"


def main():
    argv = sys.argv[1:]
    tabele = None
    if "--tabele" in argv:
        i = argv.index("--tabele")
        tabele = Path(argv[i + 1])
        del argv[i:i + 2]
    args = [a for a in argv if not a.startswith("--")]
    doar_verifica = "--verifica" in argv
    if len(args) < 2 or (not doar_verifica and len(args) < 3):
        sys.exit(__doc__)
    proceduri = proceduri_din_harta(args[0])
    titluri = {p["cod"]: p["titlu"] for p in proceduri}
    randuri, probleme = [], []
    for f in sorted(Path(args[1]).glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        sursa = d["title"]
        stem = re.sub(r"\.pdf$", "", sursa, flags=re.I)
        baza = re.sub(r"_v\d+$", "", stem)
        if baza in FISE:
            cod, rol, loc = FISE[baza]
            scor = 1.0
        else:
            rol, loc, nume = clasifica(stem)
            if not rol:
                probleme.append(f"necunoscut: {sursa}")
                continue
            cod, scor = potriveste(proceduri, rol, nume)
        modul, titlu, corp = curata(d["text"], baza in FISE)
        if tabele and (tabele / f"{stem}.txt").exists():
            marcat = (tabele / f"{stem}.txt").read_text(encoding="utf-8").strip()
            if cuvinte(marcat) == cuvinte(corp):
                corp = marcat
                for tab in re.findall(r"(?:^\|.*\|$\n?)+", corp, flags=re.M):
                    nr = {r.count("|") for r in tab.strip().split("\n")}
                    if len(nr) > 1:
                        probleme.append(f"tabel cu rânduri de lungimi diferite ({sorted(n - 1 for n in nr)} celule): {sursa}")
            else:
                a, b = cuvinte(corp), cuvinte(marcat)
                k = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
                probleme.append(f"tabele respinse (textul diferă la cuvântul {k}: {a[k:k+4]} ≠ {b[k:k+4]}): {sursa}")
        corp = lipeste_pasi(re.sub(r"\\([!#*_.\-+()\[\]`>~=])", r"\1", corp))   # „\!” din exportul Drive
        for rand in SCOASE.get(sursa, []):
            if rand not in corp.split("\n"):
                probleme.append(f"corectura nu se mai aplică (rândul nu există): {sursa}: {rand}")
            corp = "\n".join(x for x in corp.split("\n") if x != rand)
        if rol == "BAR" and loc and re.fullmatch(rf"Modulul \d+ · {loc}", modul, flags=re.I):
            modul = modul.split(" · ")[0] + f" · Barista {loc.capitalize()}"
        if re.fullmatch(r"Modulul \d+", modul) and rol in NUME_ROL:
            modul += f" · {NUME_ROL[rol]}" + (f" {loc.capitalize()}" if loc else "")
        nr = re.search(r"_(\d+)_", stem)
        randuri.append(dict(cod=cod, rol=rol, loc=loc, titlu=titlu or (titluri.get(cod) or stem), modul=modul,
                            corp=corp, sursa=sursa, poz=int(nr.group(1)) if nr else 0, scor=scor))
        if scor < 0.6:
            probleme.append(f"fără procedură în registru ({scor:.2f}): {sursa} — apare la fișa rolului {rol}")
            randuri[-1]["cod"] = None

    for r in randuri:
        print(f"{r['scor']:.2f}  {r['sursa']:<80} → {r['cod'] or '(fișa locației)':<8} {titluri.get(r['cod'], '')}"
              f"{'  [' + r['loc'] + ']' if r['loc'] else ''}")
    acoperite = {r["cod"] for r in randuri if r["cod"]}
    for rol in ("V", "VT", "RL", "BAR"):
        lipsa = [p["cod"] + " " + p["titlu"] for p in proceduri if p["rol"] == rol and p["cod"] not in acoperite]
        if lipsa:
            print(f"\n{rol}: proceduri fără document verificat:\n  " + "\n  ".join(lipsa))
    for p in probleme:
        print("ATENȚIE:", p)
    if doar_verifica:
        return

    sql = ["-- Generat de tools/proceduri_verificate.py. Conținut intern: nu se pune în repo.\n", "begin;\n"]
    for r in randuri:
        sql.append(
            "insert into public.procedure_docs (procedure_code, role_code, space_id, title, module, body, source_file, position, updated_at)\n"
            f"values ({q(r['cod'])}, {q(r['rol'])}, {q(r['loc'])}, {q(r['titlu'])}, {q(r['modul'])}, {q(r['corp'])}, {q(r['sursa'])}, {r['poz']}, now())\n"
            "on conflict (source_file) do update set procedure_code = excluded.procedure_code, role_code = excluded.role_code,\n"
            "  space_id = excluded.space_id, title = excluded.title, module = excluded.module, body = excluded.body,\n"
            "  position = excluded.position, updated_at = now();\n")
    sql.append("commit;\n")
    Path(args[2]).write_text("".join(sql), encoding="utf-8")
    print(f"\n{args[2]} scris: {len(randuri)} documente.")


if __name__ == "__main__":
    main()
