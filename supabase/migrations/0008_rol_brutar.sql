-- =============================================================================
-- Ghidul echipei Madame Magnifique · Rolul „Brutar” (BRT)
--
-- Se rulează după 0007, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- BRT vede doar pagina „Ghidul brutarului” (capitolele, rețetele casei și
-- calculatorul): nu are spații, nu vede procedurile altor roluri și nu are
-- celelalte pagini din meniu. Accesul se poate lărgi oricând din
-- Admin → Acces pe rol.
-- =============================================================================

insert into public.roles (code, name, responsibilities, main_processes, is_admin, sees_all, position)
values ('BRT', 'Brutar',
        'Produce pâinea cu maia după ghidul brutarului și fișele tehnologice ale casei.',
        '{}', false, false, 15)
on conflict (code) do nothing;

-- Doar pagina „brutar”.
delete from public.role_section_access where role_code = 'BRT' and section <> 'brutar';
insert into public.role_section_access (role_code, section) values ('BRT', 'brutar')
on conflict do nothing;

-- Paginile din meniu contează și în baza de date: cursurile le citește doar cine
-- are pagina „cursuri”, iar „Cum funcționează” doar cine are pagina „ghid”
-- (până acum le citea orice cont activ, chiar dacă pagina nu apărea în meniu).
create or replace function public.can_see_course(c bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (
    public.is_admin()
    or (public.can_see_section('cursuri') and exists (
      select 1 from public.courses k
      where k.id = c and k.published
        and (public.sees_all() or k.is_common
             or exists (select 1 from public.course_roles cr
                        where cr.course_id = k.id and cr.role_code = public.my_role())))))
$$;

drop policy if exists "membrii citesc" on public.guide_sections;
drop policy if exists "pagina „Cum funcționează”" on public.guide_sections;
create policy "pagina „Cum funcționează”" on public.guide_sections for select to authenticated
  using (public.can_see_section('ghid'));
