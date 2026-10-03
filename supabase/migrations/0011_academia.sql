-- =============================================================================
-- Ghidul echipei Madame Magnifique · Academia Madame
--
-- Se rulează după 0010, în Supabase → SQL Editor. Se poate rula de mai multe ori.
-- Pagina „Cursuri” devine „Academia Madame” și cuprinde și ghidul brutarului cu
-- calculatorul (pagina „brutar”). Ghidul brutarului îl primește și patiseria (PPT);
-- îl aveau deja DP, SP, GD, GM, AE, BRT, PBR și PBP.
-- =============================================================================

insert into public.role_section_access (role_code, section)
select 'PPT', 'brutar' where exists (select 1 from public.roles where code = 'PPT')
on conflict do nothing;
