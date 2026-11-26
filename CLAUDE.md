# Reguli de lucru pentru acest depozit

- **Notificări la orice funcție nouă.** Orice acțiune care schimbă ceva pentru altcineva (o tură, o comandă,
  o sarcină, o livrare) trimite notificare omului afectat și intră în jurnalul de activitate al șefilor
  (`public.act`, migrarea 0032). La acțiuni în masă pleacă un singur mesaj de om. Cerută de proprietar
  la orarul general (noiembrie 2026), ca regulă pentru tot ce se construiește de acum.
- Conținutul intern (proceduri, cifre, telefoane, liste de sarcini) nu intră în depozit: stă în Supabase.
- Pagina se construiește din `src/template.html` cu `python3 tools/pagina.py`; `index.html` nu se editează de mână.
