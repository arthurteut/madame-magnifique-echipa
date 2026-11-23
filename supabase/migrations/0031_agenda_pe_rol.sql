-- 0031 · Sarcinile din agendă, afișate și în fișa rolului (Roluri → rolul)
--
-- Fișa rolului arată responsabilitățile care se repetă, luate direct din agendă: o singură listă,
-- ținută într-un singur loc. O vede cine vede rolul.
-- Se poate rula de mai multe ori.

create or replace function public.agenda_rol(p_rol text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_agg(jsonb_build_object('titlu', s.titlu, 'detaliu', s.detaliu, 'ritm', s.ritm, 'tinta', s.tinta,
           'zi_sapt', s.zi_sapt, 'zi_luna', s.zi_luna, 'ora', to_char(s.ora, 'HH24:MI'), 'unde', s.unde) order by s.position, s.id)
         from public.agenda_sarcini s where s.rol = p_rol and s.activ and public.is_member() and public.can_see_role(p_rol)), '[]')
$$;
revoke all on function public.agenda_rol(text) from public, anon;
grant execute on function public.agenda_rol(text) to authenticated;

notify pgrst, 'reload schema';
