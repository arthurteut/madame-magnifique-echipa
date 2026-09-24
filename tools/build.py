#!/usr/bin/env python3
"""Construiește index.html din harta de operațiuni (Excel) + parola echipei.

Utilizare:
    pip install openpyxl cryptography
    python3 tools/build.py Harta_Operatiuni_Madame_Magnifique_FIRMA.xlsx

Parola se cere interactiv (sau din variabila MM_PAROLA). Conținutul e criptat
AES-256-GCM cu o cheie derivată din parolă (PBKDF2-SHA256), așa că în repo
ajunge doar textul criptat. Excel-ul NU se pune în repo.
"""
import base64
import getpass
import json
import os
import sys
from pathlib import Path

import openpyxl
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

ROOT = Path(__file__).resolve().parent.parent
ITERATII = 310_000

# ---------------------------------------------------------------------------
# Spațiile echipei. Aici se editează ce vede fiecare magazin / laborator.
# "procese" = codurile din Harta Firma; "abateri" = numele locației din foaia
# „Abateri per locatie”; "note" = particularități scrise de mână.
# ---------------------------------------------------------------------------
RETAIL = [f"P{n:02d}" for n in range(1, 15)]
PRODUCTIE_COMUN = ["P15", "P16", "P17", "P22", "P23", "P24"]

SPATII = [
    {
        "id": "porumbescu", "tip": "magazin", "nume": "Porumbescu",
        "titlu": "Magazinul Porumbescu",
        "abateri": "Porumbescu",
        "procese": RETAIL,
        "roluri": ["RL", "VT", "V", "BAR", "PP + B"],
        "note": [
            {"titlu": "Zonă de coacere și umplere patiserie",
             "text": "Magazinul are zonă proprie de coacere și umplere: semipreparatele venite din producție se coc și se umplu aici, la comandă. Rol: Preparator patiserie și bucătar (PP + B)."},
        ],
    },
    {
        "id": "dumbravita", "tip": "magazin", "nume": "Dumbrăvița",
        "titlu": "Magazinul Dumbrăvița",
        "abateri": "Dumbrăvița",
        "procese": RETAIL,
        "roluri": ["RL", "VT", "V", "BAR", "PP + B"],
        "note": [
            {"titlu": "Zonă de coacere și umplere patiserie",
             "text": "Magazinul are zonă proprie de coacere și umplere: semipreparatele venite din producție se coc și se umplu aici, la comandă. Rol: Preparator patiserie și bucătar (PP + B)."},
        ],
    },
    {
        "id": "fructus", "tip": "magazin", "nume": "Fructus",
        "titlu": "Magazinul Fructus",
        "abateri": "Fructus",
        "procese": RETAIL,
        "roluri": ["RL", "VT", "V", "BAR", "PP + B"],
        "note": [
            {"titlu": "Aceeași clădire cu laboratorul de cofetărie",
             "text": "În Fructus funcționează și Laboratorul de cofetărie și creme. Pentru producție, vezi spațiul „Laborator Fructus”."},
        ],
    },
    {
        "id": "peciu-nou", "tip": "productie", "nume": "Peciu Nou",
        "titlu": "Laboratorul Peciu Nou",
        "subtitlu": "Brutărie și patiserie",
        "procese": ["P18", "P19"] + PRODUCTIE_COMUN,
        "specifice": ["P18", "P19"],
        "roluri": ["DP", "SP", "GD", "LOG"],
        "note": [
            {"titlu": "Ce se face aici",
             "text": "Brutăria (maia, frământare, dospire, coacere) și patiseria (laminare, formare, coacere, finisare). De aici pleacă pâinea și patiseria către cele trei magazine și către B2B."},
            {"titlu": "Semipreparate pentru magazine",
             "text": "Porumbescu și Dumbrăvița coc și umplu în magazin o parte din patiserie: semipreparatele pentru ele se dimensionează și se etichetează separat (P15, P22)."},
        ],
    },
    {
        "id": "laborator-fructus", "tip": "productie", "nume": "Fructus",
        "titlu": "Laboratorul Fructus",
        "subtitlu": "Cofetărie, creme și dulcețuri",
        "procese": ["P20", "P21", "P19"] + PRODUCTIE_COMUN,
        "specifice": ["P20", "P21", "P19"],
        "roluri": ["DP", "SP", "GD", "LOG"],
        "abateri_filtru": {"Fructus": ["Interfață D1"]},
        "note": [
            {"titlu": "Ce se face aici",
             "text": "Cofetăria (blaturi, creme, montaj, decor), laboratorul de creme și dulcețuri (Roboq) și o parte de coacere de patiserie."},
            {"titlu": "Laborator la vedere",
             "text": "Laboratorul e în aceeași locație cu magazinul Fructus și cu spațiul demo pentru B2B: ordinea și curățenia se văd din sală."},
        ],
    },
    {
        "id": "b2b", "tip": "b2b", "nume": "B2B",
        "titlu": "B2B, evenimente și candybar",
        "procese": ["P25", "P26", "P27", "P28", "P29", "P30", "P08", "P07"],
        "specifice": ["P25", "P26", "P27", "P28", "P29", "P30"],
        "roluri": ["CB2B", "RL", "VT", "DP", "LOG"],
        "abateri_filtru": {"Fructus": ["D3 B2B", "Proces nou"]},
        "note": [
            {"titlu": "Unde se întâlnesc clienții",
             "text": "Prezentările de candybar și întâlnirile cu clienții corporativi se fac în spațiul demo de la Fructus."},
            {"titlu": "În magazine",
             "text": "Ridicările B2B și comenzile de torturi / candybar primite la pult urmează P08 și P07, în fiecare magazin."},
        ],
    },
    {
        "id": "birou", "tip": "birou", "nume": "Birou central",
        "titlu": "Birou central",
        "subtitlu": "Aprovizionare, marketing, financiar, oameni",
        "domenii": ["D4", "D5", "D6", "D7"],
        "roluri": ["GM", "ADM", "EC", "MKT", "GD", "LOG"],
        "note": [],
    },
]


def curat(v):
    if v is None:
        return ""
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v).strip()


def randuri(ws, start):
    for r in ws.iter_rows(min_row=start, values_only=True):
        if any(c is not None and str(c).strip() for c in r):
            yield [curat(c) for c in r]


def citeste(xlsx):
    wb = openpyxl.load_workbook(xlsx, data_only=True)

    domenii = {}
    for r in randuri(wb["Sinteza"], 1):
        if len(r) > 6 and r[0].startswith("D") and r[0][1:].isdigit():
            domenii[r[0]] = {"cod": r[0], "nume": r[1], "miza": r[6]}

    procese = {}
    for r in randuri(wb["Harta Firma"], 5):
        dc, pc, pn, sub, _dom, rol, val, miza, nou = r[:9]
        p = procese.setdefault(pc, {"cod": pc, "nume": pn, "domeniu": dc, "rol": rol,
                                    "val": val, "miza": miza, "sub": []})
        p["sub"].append(sub)
    for p in procese.values():
        domenii[p["domeniu"]].setdefault("procese", []).append(p["cod"])

    taskuri = []
    for r in randuri(wb["Retail nivel 4"], 5):
        pc, _pn, sub, task, rol, minute, cand, verif, proc = r[:9]
        taskuri.append({"p": pc, "sub": sub, "t": task, "rol": rol, "min": minute,
                        "cand": cand, "verif": verif, "proc": proc})

    proceduri = []
    for r in randuri(wb["Registru Proceduri"], 5):
        cod, titlu, pc, rol, decl, tip, prio, val, pasi = r[:9]
        proceduri.append({"cod": cod, "titlu": titlu, "p": pc, "rol": rol, "decl": decl,
                          "tip": tip, "prio": prio, "val": val, "pasi": pasi})

    abateri = []
    for r in randuri(wb["Abateri per locatie"], 5):
        abateri.append({"loc": r[0], "zona": r[1], "text": r[2], "dece": r[3]})

    roluri = []
    for r in randuri(wb["Roluri"], 5):
        procs = [x.strip() for x in r[3].split("·") if x.strip()] if len(r) > 3 else []
        roluri.append({"cod": r[0], "nume": r[1], "raspunde": r[2], "procese": procs})

    legenda, sectiune = [], None
    for r in randuri(wb["Legenda"], 4):
        t = r[0] or next((x for x in r if x), "")
        if t.startswith("—"):
            sectiune["linii"].append(t.lstrip("— ").strip())
        else:
            sectiune = {"titlu": t, "linii": []}
            legenda.append(sectiune)

    return {
        "domenii": domenii, "procese": procese, "taskuri": taskuri,
        "proceduri": proceduri, "abateri": abateri, "roluri": roluri,
        "legenda": legenda, "spatii": SPATII,
    }


def cripteaza(date, parola):
    sare, iv = os.urandom(16), os.urandom(12)
    kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=sare, iterations=ITERATII)
    cheie = kdf.derive(parola.encode("utf-8"))
    ct = AESGCM(cheie).encrypt(iv, json.dumps(date, ensure_ascii=False).encode("utf-8"), None)
    b64 = lambda b: base64.b64encode(b).decode()
    return {"v": 1, "iter": ITERATII, "salt": b64(sare), "iv": b64(iv), "ct": b64(ct)}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    date = citeste(sys.argv[1])
    parola = os.environ.get("MM_PAROLA") or getpass.getpass("Parola echipei: ")
    if len(parola) < 8:
        sys.exit("Parola trebuie să aibă minimum 8 caractere.")

    sablon = (ROOT / "src" / "template.html").read_text(encoding="utf-8")
    logo = (ROOT / "src" / "logo.svg").read_text(encoding="utf-8")
    html = (sablon.replace("<!--LOGO-->", logo)
                  .replace("/*PAYLOAD*/null", json.dumps(cripteaza(date, parola))))
    (ROOT / "index.html").write_text(html, encoding="utf-8")
    print(f"index.html scris: {len(date['procese'])} procese, {len(date['taskuri'])} task-uri, "
          f"{len(date['proceduri'])} proceduri, {len(date['roluri'])} roluri.")


if __name__ == "__main__":
    main()
