-- 0034 · Cine face programul se poate pune și pe el, pe colegii cu același rol și pe șeful lui de magazin
--
-- Până acum, în „Program pe ture”, un responsabil putea programa doar oamenii de sub el. Nu se putea
-- pune pe sine, nici pe alt responsabil care îi ține locul, iar un vânzător de tură nu își putea pune
-- responsabilul. Acum se poate, pe locațiile pe care le vede. Conducerea (cine vede tot) nu intră în listă.
-- Se poate rula de mai multe ori.

-- Pe cine pot pune în program: oamenii de sub mine, eu, colegii cu rolul meu și șefii mei de pe teren
-- (nu și conducerea). Doar pentru cine conduce o echipă.
create or replace function public.poate_programa(u uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.poate_conduce(u)
      or (public.vede_echipa() and exists (select 1 from public.profiles p
            where p.user_id = u and p.active and (u = auth.uid() or p.role_code = public.my_role()
              or p.role_code in (select x from public.sefii(public.my_role()) x join public.roles r on r.code = x where not r.is_admin and not r.sees_all))))
$$;
revoke all on function public.poate_programa(uuid) from public, anon;
grant execute on function public.poate_programa(uuid) to authenticated;

-- Lista din formularul „Tură nouă”.
create or replace function public.oameni_de_programat()
returns table (user_id uuid, full_name text, role_code text, active boolean)
language sql stable security definer set search_path = public as $$
  select p.user_id, p.full_name, p.role_code, p.active from public.profiles p
  where public.vede_echipa() and (public.sees_all() or p.user_id = auth.uid() or p.role_code = public.my_role()
     or p.role_code in (select public.subordonatii(public.my_role()))
     or p.role_code in (select x from public.sefii(public.my_role()) x join public.roles r on r.code = x where not r.is_admin and not r.sees_all))
  order by p.full_name
$$;
revoke all on function public.oameni_de_programat() from public, anon;
grant execute on function public.oameni_de_programat() to authenticated;

drop policy if exists "șefii fac programul" on public.shifts;
create policy "șefii fac programul" on public.shifts for all to authenticated
  using (public.poate_programa(user_id) and (public.is_admin() or public.can_see_space(space_id)))
  with check (public.poate_programa(user_id) and (public.is_admin() or public.can_see_space(space_id)));

drop policy if exists "îmi văd turele, șefii le văd pe ale echipei" on public.shifts;
create policy "îmi văd turele, șefii le văd pe ale echipei" on public.shifts for select to authenticated
  using (public.is_member() and (user_id = auth.uid() or public.sees_all()
         or (public.poate_programa(user_id) and public.can_see_space(space_id)) or public.am_tura(space_id, day)));

notify pgrst, 'reload schema';
