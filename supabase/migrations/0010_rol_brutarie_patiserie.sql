-- =============================================================================
-- Ghidul echipei Madame Magnifique · Rolul „Producție brutărie și patiserie” (PBP)
--
-- Se rulează după 0009, în Supabase → SQL Editor. Se poate rula de mai multe ori.
-- Pentru cine lucrează în ambele secții: vede tot ce văd PBR și PPT
-- (ambele laboratoare, ghidul brutarului, procedurile celor două roluri).
-- =============================================================================

insert into public.roles (code, name, responsibilities, main_processes, is_admin, sees_all, position) values
  ('PBP', 'Producție brutărie și patiserie',
   'Lucrează în brutărie și în patiserie (Laboratorul Peciu Nou și Laboratorul Fructus), după ghidul brutarului, fișele tehnologice și procedurile secțiilor.',
   '{}', false, false, 19)
on conflict (code) do nothing;

insert into public.role_space_access (role_code, space_id)
select 'PBP', s from (values ('peciu-nou'), ('laborator-fructus')) v (s)
where exists (select 1 from public.spaces where id = s)
on conflict do nothing;

insert into public.role_section_access (role_code, section)
select 'PBP', s from (values ('roluri'), ('proceduri'), ('cursuri'), ('ghid'), ('brutar')) v (s)
on conflict do nothing;

insert into public.role_role_access (viewer_role, sees_role)
select v, s from (values ('PBP', 'PBR'), ('PBP', 'PPT'), ('DP', 'PBP'), ('SP', 'PBP')) x (v, s)
where exists (select 1 from public.roles where code = v) and exists (select 1 from public.roles where code = s)
on conflict do nothing;

insert into public.space_roles (space_id, role_code, position)
select s, 'PBP', 12 from (values ('peciu-nou'), ('laborator-fructus')) v (s)
where exists (select 1 from public.spaces where id = s)
on conflict do nothing;
