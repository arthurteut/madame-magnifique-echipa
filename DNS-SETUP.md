# Legarea la madamemagnifique.ro

Ghidul se publică pe GitHub Pages și se leagă la subdomeniul
**echipa.madamemagnifique.ro**. Site-ul public madamemagnifique.ro nu se
modifică.

## 1. GitHub (o singură dată)

1. În repo: **Settings → Pages → Build and deployment → Deploy from a branch**,
   branch `main`, folder `/ (root)` → **Save**.
2. Până e gata DNS-ul, ghidul e online la
   https://arthurteut.github.io/madame-magnifique-echipa/ (fișierul `CNAME`
   e scos intenționat). După ce firma de hosting confirmă înregistrarea, scrie
   `echipa.madamemagnifique.ro` la **Custom domain** → **Save** (GitHub
   readaugă singur `CNAME`), apoi bifează **Enforce HTTPS**.
3. (Recomandat) **Settings-ul contului → Pages → Add a domain** →
   `madamemagnifique.ro`: GitHub dă o înregistrare TXT de verificare, care
   împiedică pe altcineva să folosească subdomeniul. Se trimite firmei de
   hosting împreună cu înregistrarea de mai jos.

## 2. Mesaj gata de trimis firmei care administrează domeniul

> Bună ziua,
>
> Vă rugăm să adăugați în zona DNS a domeniului **madamemagnifique.ro**
> următoarea înregistrare:
>
> | Tip   | Nume / Host | Valoare / Țintă        | TTL  |
> |-------|-------------|------------------------|------|
> | CNAME | `echipa`    | `arthurteut.github.io.` | 3600 |
>
> Subdomeniul **echipa.madamemagnifique.ro** va găzdui un ghid intern pentru
> angajați, publicat pe GitHub Pages. Înregistrarea nu afectează site-ul
> principal, emailul sau alte subdomenii existente.
>
> Dacă aveți înregistrare CAA pe domeniu, vă rugăm să permiteți și
> `letsencrypt.org`, ca să se poată emite certificatul HTTPS.
>
> [Opțional: înregistrarea TXT de verificare GitHub, din pasul 1.3.]
>
> Vă mulțumim!

## 3. Verificare

După propagare (de obicei sub o oră):

```bash
dig +short echipa.madamemagnifique.ro CNAME   # → arthurteut.github.io.
```

Apoi în GitHub **Settings → Pages** apare „DNS check successful”; bifează
**Enforce HTTPS** când certificatul e emis (câteva minute).
