-- =============================================================================
-- Ghidul echipei Madame Magnifique · Academia pentru toată echipa
--
-- Se rulează după 0011, în Supabase → SQL Editor. Se poate rula de mai multe ori.
-- Toate rolurile au Academia: cursurile și ghidul brutarului cu calculatorul.
-- Orice curs publicat îl vede toată echipa; rolurile bifate la un curs spun doar
-- pentru cine e obligatoriu (apare la „Pentru rolul tău” și în Admin → Progres).
-- Ciornele le văd în continuare doar adminii.
-- =============================================================================

insert into public.role_section_access (role_code, section)
select r.code, s.section from public.roles r cross join (values ('cursuri'), ('brutar')) s (section)
on conflict do nothing;

create or replace function public.can_see_course(c bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (
    public.is_admin()
    or (public.can_see_section('cursuri') and exists (select 1 from public.courses k where k.id = c and k.published)))
$$;
