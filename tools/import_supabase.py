#!/usr/bin/env python3
"""Încarcă harta de operațiuni în Supabase.

Generează un fișier SQL care înlocuiește tot conținutul ghidului într-o singură
tranzacție (angajații nu văd niciodată o bază pe jumătate goală). Conturile și
profilurile nu sunt atinse.

Utilizare:
    pip install openpyxl
    python3 tools/import_supabase.py Harta_Operatiuni_Madame_Magnifique_FIRMA.xlsx date-ghid.sql

Apoi, una dintre variante:
  - Supabase → SQL Editor → lipești conținutul din date-ghid.sql → Run;
  - sau: psql "$SUPABASE_DB_URL" -f date-ghid.sql

Fișierul SQL conține tot ghidul: NU îl pune în repo (e în .gitignore).
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import harta  # noqa: E402

# Rolurile care primesc drept de administrare la prima încărcare. După aceea,
# dreptul se schimbă din panoul de admin, iar importul nu îl mai suprascrie.
ROLURI_ADMIN = {"GM"}

# Roluri care nu sunt în harta din Excel, dar există în ghid (vezi migrarea 0004).
ROLURI_SUPLIMENTARE = [
    {"cod": "AE", "nume": "Asistent executiv",
     "raspunde": "Sprijină conducerea: vede tot ghidul (toate spațiile, rolurile și procedurile), "
                 "fără drept de administrare.",
     "procese": []},
    {"cod": "BRT", "nume": "Brutar",
     "raspunde": "Produce pâinea cu maia după ghidul brutarului și fișele tehnologice ale casei.",
     "procese": []},
    {"cod": "PPT", "nume": "Producție patiserie",
     "raspunde": "Produce patiseria în laboratoare (Peciu Nou și Fructus), după fișele tehnologice și procedurile secției.",
     "procese": []},
    {"cod": "PCF", "nume": "Producție cofetărie",
     "raspunde": "Produce cofetăria, cremele și dulcețurile în Laboratorul Fructus, după fișele tehnologice și procedurile secției.",
     "procese": []},
    {"cod": "PBR", "nume": "Producție brutărie",
     "raspunde": "Produce pâinea în Laboratorul Peciu Nou, după ghidul brutarului, fișele tehnologice și procedurile secției.",
     "procese": []},
]


def q(v):
    """Literal SQL."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def arr(items):
    return "array[" + ", ".join(q(i) for i in items) + "]::text[]" if items else "'{}'::text[]"


def jsonb(v):
    return q(json.dumps(v, ensure_ascii=False)) + "::jsonb"


def intval(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def insert(table, cols, rows, extra=""):
    if not rows:
        return ""
    values = ",\n  ".join("(" + ", ".join(r) + ")" for r in rows)
    return f"insert into public.{table} ({', '.join(cols)}) values\n  {values}{extra};\n\n"


def genereaza(d):
    out = ["-- Generat de tools/import_supabase.py. Conținut intern: nu se pune în repo.\n",
           "begin;\n\n"]

    # 1) Golește conținutul (în ordinea dependențelor). Rolurile și spațiile rămân
    #    (se actualizează pe loc): de ele țin conturile și matricea de acces.
    for t in ["space_task_overrides", "space_facts", "space_notes", "space_roles", "space_processes",
              "tasks", "procedures", "subprocesses", "processes", "domains",
              "deviations", "guide_sections"]:
        out.append(f"delete from public.{t};\n")
    out.append("\n")

    # 2) Roluri: upsert; cele dispărute din hartă se șterg doar dacă nu au conturi.
    roluri = d["roluri"] + [r for r in ROLURI_SUPLIMENTARE if r["cod"] not in {x["cod"] for x in d["roluri"]}]
    out.append(insert("roles", ["code", "name", "responsibilities", "main_processes", "is_admin", "position"],
                      [[q(r["cod"]), q(r["nume"]), q(r["raspunde"]), arr(r["procese"]),
                        q(r["cod"] in ROLURI_ADMIN), q(i)] for i, r in enumerate(roluri)],
                      "\non conflict (code) do update set name = excluded.name, "
                      "responsibilities = excluded.responsibilities, main_processes = excluded.main_processes, "
                      "position = excluded.position"))
    coduri = ", ".join(q(r["cod"]) for r in roluri)
    out.append(f"delete from public.roles r where r.code not in ({coduri})\n"
               f"  and not exists (select 1 from public.profiles p where p.role_code = r.code);\n\n")

    # 3) Harta
    out.append(insert("domains", ["code", "name", "stake", "position"],
                      [[q(x["cod"]), q(x["nume"]), q(x["miza"]), q(i)]
                       for i, x in enumerate(d["domenii"].values())]))
    procese = list(d["procese"].values())
    out.append(insert("processes", ["code", "domain_code", "name", "lead_role", "wave", "stake", "position"],
                      [[q(p["cod"]), q(p["domeniu"]), q(p["nume"]), q(p["rol"] or None), q(p["val"]),
                        q(p["miza"]), q(i)] for i, p in enumerate(procese)]))
    out.append(insert("subprocesses", ["process_code", "position", "name"],
                      [[q(p["cod"]), q(i), q(sub)] for p in procese for i, sub in enumerate(p["sub"])]))
    out.append(insert("procedures", ["code", "title", "process_code", "role_code", "trigger", "trigger_type",
                                     "priority", "wave", "steps", "field_update", "original", "position"],
                      [[q(p["cod"]), q(p["titlu"]), q(p["p"]), q(p["rol"]), q(p["decl"]), q(p["tip"]),
                        q(p["prio"]), q(p["val"]), q(intval(p["pasi"])), q(bool(p.get("teren"))),
                        q(p.get("initial", "")), q(i)] for i, p in enumerate(d["proceduri"])]))
    out.append(insert("tasks", ["id", "process_code", "subprocess", "text", "role_code", "minutes", "schedule",
                                "verification", "procedure_code", "field_update", "original"],
                      [[q(t["id"]), q(t["p"]), q(t["sub"]), q(t["t"]), q(t["rol"]), q(intval(t["min"])),
                        q(t["cand"]), q(t["verif"]), q(t["proc"] or None), q(bool(t.get("teren"))),
                        q(t.get("initial", ""))] for t in d["taskuri"]]))
    out.append(insert("deviations", ["id", "location", "area", "text", "reason"],
                      [[q(i), q(a["loc"]), q(a["zona"]), q(a["text"]), q(a["dece"])]
                       for i, a in enumerate(d["abateri"])]))
    out.append(insert("guide_sections", ["id", "title", "lines"],
                      [[q(i), q(s["titlu"]), arr(s["linii"])] for i, s in enumerate(d["legenda"])]))

    # 4) Spațiile
    spatii = d["spatii"]
    out.append(insert("spaces", ["id", "type", "name", "title", "subtitle", "deviations_location",
                                 "deviations_filter", "domains", "deliveries_note", "equipment_note", "position"],
                      [[q(s["id"]), q(s["tip"]), q(s["nume"]), q(s["titlu"]), q(s.get("subtitlu", "")),
                        q(s.get("abateri")), jsonb(s.get("abateri_filtru", {})), arr(s.get("domenii", [])),
                        q(s.get("fisa", {}).get("nota_livrari", "")),
                        q(s.get("fisa", {}).get("nota_echipamente", "")), q(i)]
                       for i, s in enumerate(spatii)],
                      "\non conflict (id) do update set type = excluded.type, name = excluded.name, "
                      "title = excluded.title, subtitle = excluded.subtitle, "
                      "deviations_location = excluded.deviations_location, "
                      "deviations_filter = excluded.deviations_filter, domains = excluded.domains, "
                      "deliveries_note = excluded.deliveries_note, equipment_note = excluded.equipment_note, "
                      "position = excluded.position"))
    ids = ", ".join(q(s["id"]) for s in spatii)
    out.append(f"delete from public.spaces where id not in ({ids});\n\n")
    out.append(insert("space_processes", ["space_id", "process_code", "position", "is_specific"],
                      [[q(s["id"]), q(c), q(i), q(c in s.get("specifice", []))]
                       for s in spatii for i, c in enumerate(s.get("procese", []))]))
    out.append(insert("space_roles", ["space_id", "role_code", "position"],
                      [[q(s["id"]), q(r), q(i)] for s in spatii for i, r in enumerate(s.get("roluri", []))]))
    out.append(insert("space_notes", ["space_id", "position", "title", "text"],
                      [[q(s["id"]), q(i), q(n["titlu"]), q(n["text"])]
                       for s in spatii for i, n in enumerate(s.get("note", []))]))
    fapte = []
    for s in spatii:
        f = s.get("fisa", {})
        for sectiune in ("program", "livrari"):
            for i, (k, v) in enumerate(f.get(sectiune, [])):
                fapte.append([q(s["id"]), q(sectiune), q(i), q(k), q(v), "null", "''", "''"])
        for i, c in enumerate(f.get("contacte", [])):
            fapte.append([q(s["id"]), q("contacte"), q(i), q(c["functie"]), "''",
                          q(c["rol"] or None), q(c["nume"]), q(c["telefon"])])
        for i, e in enumerate(f.get("echipamente", [])):
            fapte.append([q(s["id"]), q("echipamente"), q(i), q(e["nume"]), q(e["raportezi"]),
                          "null", "''", "''"])
    out.append(insert("space_facts", ["space_id", "section", "position", "label", "value",
                                      "role_code", "person", "phone"], fapte))
    out.append(insert("space_task_overrides", ["space_id", "task_id", "schedule", "role_code", "text"],
                      [[q(s["id"]), q(int(tid)), q(a["cand"]), q(a["rol"] or None), q(a.get("t", ""))]
                       for s in spatii for tid, a in (s.get("ajustari") or {}).items()]))

    out.append("commit;\n")
    return "".join(out)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    d = harta.citeste(sys.argv[1])
    Path(sys.argv[2]).write_text(genereaza(d), encoding="utf-8")
    print(f"{sys.argv[2]} scris: {len(d['procese'])} procese, {len(d['taskuri'])} task-uri, "
          f"{len(d['proceduri'])} proceduri, {len(d['roluri'])} roluri, {len(d['spatii'])} spații.")


if __name__ == "__main__":
    main()
