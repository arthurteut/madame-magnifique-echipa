-- =============================================================================
-- Ghidul echipei Madame Magnifique · Rolul „Asistent executiv” (AE)
--
-- Se rulează după 0003, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- AE vede tot ghidul, ca administratorul (toate spațiile, rolurile, procedurile),
-- dar NU are pagina Admin: nu creează conturi și nu schimbă accesele.
-- Mecanismul: coloana roles.sees_all. Un rol cu sees_all = true vede tot;
-- is_admin rămâne doar pentru administrare.
-- Ca AE să poată și administra:  update public.roles set is_admin = true where code = 'AE';
-- =============================================================================

alter table public.roles add column if not exists sees_all boolean not null default false;

insert into public.roles (code, name, responsibilities, main_processes, is_admin, sees_all, position)
values ('AE', 'Asistent executiv',
        'Sprijină conducerea: vede tot ghidul (toate spațiile, rolurile și procedurile), fără drept de administrare.',
        '{}', false, true, 14)
on conflict (code) do update set sees_all = true;

-- Vede tot: adminii și rolurile cu sees_all.
create or replace function public.sees_all()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select r.is_admin or r.sees_all from public.profiles p join public.roles r on r.code = p.role_code
    where p.user_id = auth.uid() and p.active
  ), false)
$$;
revoke all on function public.sees_all() from public, anon;
grant execute on function public.sees_all() to authenticated;

-- Funcțiile de acces din 0002, cu „vede tot” în loc de „e admin”.
create or replace function public.can_see_role(r text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.sees_all()
      or r = public.my_role()
      or exists (select 1 from public.role_role_access
                 where viewer_role = public.my_role() and sees_role = r)
$$;

create or replace function public.can_see_space(s text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.sees_all()
      or exists (select 1 from public.role_space_access
                 where role_code = public.my_role() and space_id = s)
$$;

create or replace function public.can_see_process(p text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.sees_all()
      or exists (select 1 from public.space_processes sp
                 where sp.process_code = p and public.can_see_space(sp.space_id))
      or exists (select 1 from public.spaces s join public.processes pr on pr.code = p
                 where pr.domain_code = any (s.domains) and public.can_see_space(s.id))
      or exists (select 1 from public.processes pr
                 where pr.code = p and pr.lead_role is not null and public.can_see_role(pr.lead_role))
$$;

-- Paginile din meniu pentru AE: toate.
insert into public.role_section_access (role_code, section)
select 'AE', s from (values ('roluri'), ('proceduri'), ('ghid')) v (s)
on conflict do nothing;
