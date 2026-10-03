-- =============================================================================
-- Ghidul echipei Madame Magnifique · Categoriile din Academia Madame
--
-- Se rulează după 0012, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Fiecare curs primește o categorie; pagina Academia îi grupează în casete:
--   brutarie            Brutărie (plus ghidul brutarului și calculatorul)
--   barista             Barista
--   patiserie-cofetarie Patiserie și cofetărie
--   vanzare-servire     Vânzare și servire
--   general             Cursuri generale (ce nu intră în celelalte)
-- Cursurile existente rămân „general” până le muți din Admin → Cursuri.
-- Cine vede ce nu se schimbă (0012).
-- =============================================================================

alter table public.courses add column if not exists category text not null default 'general';
alter table public.courses drop constraint if exists courses_category_check;
alter table public.courses add constraint courses_category_check
  check (category in ('general', 'brutarie', 'barista', 'patiserie-cofetarie', 'vanzare-servire'));
