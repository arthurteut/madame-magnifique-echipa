-- =============================================================================
-- Ghidul echipei Madame Magnifique · Rolurile de producție pe secții
--
-- Se rulează după 0008, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
--   PPT  Producție patiserie   → Laboratorul Peciu Nou și Laboratorul Fructus
--   PCF  Producție cofetărie   → Laboratorul Fructus
--   PBR  Producție brutărie    → Laboratorul Peciu Nou + Ghidul brutarului
-- Paginile din meniu: Roluri, Proceduri, Cursuri, Cum funcționează (PBR și Brutar).
-- DP și SP le văd procedurile și task-urile. Totul se poate schimba din
-- Admin → Acces pe rol.
-- =============================================================================

insert into public.roles (code, name, responsibilities, main_processes, is_admin, sees_all, position) values
  ('PPT', 'Producție patiserie',
   'Produce patiseria în laboratoare (Peciu Nou și Fructus), după fișele tehnologice și procedurile secției.', '{}', false, false, 16),
  ('PCF', 'Producție cofetărie',
   'Produce cofetăria, cremele și dulcețurile în Laboratorul Fructus, după fișele tehnologice și procedurile secției.', '{}', false, false, 17),
  ('PBR', 'Producție brutărie',
   'Produce pâinea în Laboratorul Peciu Nou, după ghidul brutarului, fișele tehnologice și procedurile secției.', '{}', false, false, 18)
on conflict (code) do nothing;

insert into public.role_space_access (role_code, space_id)
select r, s from (values ('PPT', 'peciu-nou'), ('PPT', 'laborator-fructus'), ('PCF', 'laborator-fructus'), ('PBR', 'peciu-nou')) v (r, s)
where exists (select 1 from public.spaces where id = s)
on conflict do nothing;

insert into public.role_section_access (role_code, section)
select r, s from (values ('PPT'), ('PCF'), ('PBR')) a (r)
cross join (values ('roluri'), ('proceduri'), ('cursuri'), ('ghid')) b (s)
on conflict do nothing;
insert into public.role_section_access (role_code, section) values ('PBR', 'brutar') on conflict do nothing;

insert into public.role_role_access (viewer_role, sees_role)
select v, s from (values ('DP'), ('SP')) a (v) cross join (values ('PPT'), ('PCF'), ('PBR')) b (s)
where exists (select 1 from public.roles where code = v)
on conflict do nothing;

-- „Cine lucrează aici” pe pagina laboratoarelor (importul hărții le adaugă la fel).
insert into public.space_roles (space_id, role_code, position)
select s, r, p from (values ('peciu-nou', 'PPT', 10), ('peciu-nou', 'PBR', 11), ('laborator-fructus', 'PPT', 10), ('laborator-fructus', 'PCF', 11)) v (s, r, p)
where exists (select 1 from public.spaces where id = s)
on conflict do nothing;
