#!/usr/bin/env python3
"""Construiește index.html din src/template.html (+ logo-ul).

Pagina nu mai conține date: după logare, le citește din Supabase, iar fiecare
utilizator primește doar ce îi permite rolul (Row Level Security).

Utilizare:
    python3 tools/pagina.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

if __name__ == "__main__":
    sablon = (ROOT / "src" / "template.html").read_text(encoding="utf-8")
    logo = (ROOT / "src" / "logo.svg").read_text(encoding="utf-8")
    (ROOT / "index.html").write_text(sablon.replace("<!--LOGO-->", logo), encoding="utf-8")
    print("index.html scris.")
