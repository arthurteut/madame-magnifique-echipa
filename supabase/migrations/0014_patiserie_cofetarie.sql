-- =============================================================================
-- Ghidul echipei Madame Magnifique · Patiseria și cofetăria, separate
--
-- Se rulează după 0013, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Academia are acum două casete: Patiserie și Cofetărie. Categoriile:
--   patiserie            doar în caseta Patiserie
--   cofetarie            doar în caseta Cofetărie
--   patiserie-cofetarie  comun: apare în ambele casete (ex.: Fundamentele laboratorului)
-- Cine vede ce nu se schimbă.
-- =============================================================================

alter table public.courses drop constraint if exists courses_category_check;
alter table public.courses add constraint courses_category_check
  check (category in ('general', 'brutarie', 'barista', 'patiserie', 'cofetarie', 'patiserie-cofetarie', 'vanzare-servire'));
