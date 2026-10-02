-- =============================================================================
-- Ghidul echipei Madame Magnifique · Pasul 3: panoul de administrare
--
-- Se rulează după 0002, în Supabase → SQL Editor.
--
-- Din pagină, adminul (roles.is_admin, implicit GM) poate:
--   - schimba numele, rolul și starea (activ / inactiv) unui cont;
--   - edita matricea de acces (spații, roluri vizibile, pagini din meniu).
-- Crearea, ștergerea conturilor și resetarea parolelor trec prin funcția
-- Edge `admin-users`, care are cheia secretă și verifică și ea că apelantul
-- e admin.
-- Un admin nu-și poate modifica propriul cont (nu se poate bloca pe dinafară).
-- =============================================================================

-- Profiluri: adminul modifică numele, rolul și starea altor conturi.
grant update (full_name, role_code, active) on public.profiles to authenticated;

create policy "adminul modifică alte conturi" on public.profiles
  for update to authenticated
  using (public.is_admin() and user_id <> auth.uid())
  with check (public.is_admin() and user_id <> auth.uid());

-- Matricea de acces: adminul adaugă și scoate drepturi.
do $$
declare t text;
begin
  foreach t in array array['role_space_access', 'role_role_access', 'role_section_access'] loop
    execute format('grant insert, delete on public.%I to authenticated', t);
    execute format(
      'create policy "adminul editează matricea (adaugă)" on public.%I for insert to authenticated
         with check (public.is_admin())', t);
    execute format(
      'create policy "adminul editează matricea (scoate)" on public.%I for delete to authenticated
         using (public.is_admin())', t);
  end loop;
end $$;

-- Rolurile de admin nu pot rămâne fără acces la panou: un rol admin vede tot
-- oricum (is_admin), iar dreptul de admin se schimbă doar din SQL Editor:
--   update public.roles set is_admin = true where code = 'RL';
