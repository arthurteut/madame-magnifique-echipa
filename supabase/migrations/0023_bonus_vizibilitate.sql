-- 0023: pagina Bonus apare și conturilor care nu sunt legate de o locație anume.
-- Până acum o vedea doar cine avea locația bifată în Admin; un RL fără locații bifate (care vede toate
-- magazinele) nu primea fila. Acum regula e aceeași ca în restul site-ului: vezi bonusul locațiilor pe care le vezi.
-- Sumele rămân filtrate: fiecare le vede doar pe ale lui.
create or replace function public.vede_bonus(s text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.sees_all()
    or exists (select 1 from public.bonus_oameni o where o.space_id = s and o.user_id = auth.uid())
    or (public.vede_locatia(auth.uid(), s)
        and exists (select 1 from public.space_roles sr where sr.space_id = s and sr.role_code = public.my_role())))
$$;
revoke all on function public.vede_bonus(text) from public, anon;
grant execute on function public.vede_bonus(text) to authenticated;

-- Verificare: ce locații au bonus configurat și câte conturi sunt legate de fiecare.
select b.space_id, b.activ, jsonb_array_length(b.trepte) as trepte,
       (select count(*) from public.profile_spaces ps where ps.space_id = b.space_id) as conturi_legate,
       (select count(*) from public.bonus_oameni o where o.space_id = b.space_id) as oameni_in_bonus
from public.bonus_setari b order by 1;
