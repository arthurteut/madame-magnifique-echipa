-- 0037 · Orarul meu, la îndemână · responsabilul primește notificări doar de la magazinul lui
--
--   orarul_meu()   turele mele pe 14 zile, cu colegii din aceeași zi și locație
--   raspunde_de    magazinul (sau magazinele) de care răspunde un om. Cine are un rând aici primește
--                  notificările „de șef” doar de la locațiile lui: clock-in, clock-out, fișe, întârzieri,
--                  semnalări, standarde, agendă, mutări în orar, rezumat. Ce îl privește pe el (tura lui
--                  la alt magazin, mementourile, punctele) ajunge în continuare, de oriunde.
-- Se poate rula de mai multe ori.

create or replace function public.orarul_meu()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date;
begin
  if not public.is_member() then raise exception 'Intră în cont.'; end if;
  return jsonb_build_object('azi', azi, 'ture', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'zi', t.day, 'space_id', t.space_id, 'loc', public.nume_loc(t.space_id),
      'starts', to_char(t.starts, 'HH24:MI'), 'ends', to_char(t.ends, 'HH24:MI'), 'opens', t.opens, 'closes', t.closes, 'note', t.note,
      'colegi', coalesce((select jsonb_agg(jsonb_build_object('nume', p.full_name, 'rol', p.role_code, 'starts', to_char(c.starts, 'HH24:MI'), 'ends', to_char(c.ends, 'HH24:MI')) order by c.starts, p.full_name)
        from public.shifts c join public.profiles p on p.user_id = c.user_id where c.space_id = t.space_id and c.day = t.day and c.user_id <> t.user_id), '[]')) order by t.day, t.starts)
    from public.shifts t where t.user_id = auth.uid() and t.day between azi and azi + 13), '[]'));
end $$;
revoke all on function public.orarul_meu() from public, anon;
grant execute on function public.orarul_meu() to authenticated;

create table if not exists public.raspunde_de (
  user_id  uuid not null,
  space_id text not null references public.spaces(id) on update cascade on delete cascade,
  primary key (user_id, space_id)
);
alter table public.raspunde_de enable row level security;
revoke all on public.raspunde_de from anon, authenticated;
grant all on public.raspunde_de to service_role;

-- Îl anunț pe u despre locația s? (cine nu are niciun rând în raspunde_de rămâne ca până acum)
create or replace function public.anunta_la(u uuid, s text)
returns boolean language sql stable security definer set search_path = public as $$
  select s is null or not exists (select 1 from public.raspunde_de where user_id = u)
      or exists (select 1 from public.raspunde_de where user_id = u and space_id = s)
$$;
revoke all on function public.anunta_la(uuid, text) from public, anon, authenticated;

-- Un singur loc pentru toate notificările „de șef”: cea de la alt magazin nu se mai scrie.
create or replace function public.notificari_doar_locatia_mea()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.space_id is not null and not public.anunta_la(new.user_id, new.space_id)
     and (new.kind in ('clock_in', 'clock_out', 'fisa_gata', 'pas_nefacut', 'problema', 'intarziere', 'semnalare', 'standard', 'calitate', 'agenda', 'anunt', 'contestatie')
          or (new.kind = 'orar' and new.url is distinct from '#/tura')) then
    return null;
  end if;
  return new;
end $$;
revoke all on function public.notificari_doar_locatia_mea() from public, anon, authenticated;
drop trigger if exists a_doar_locatia_mea on public.notifications;
create trigger a_doar_locatia_mea before insert on public.notifications for each row execute function public.notificari_doar_locatia_mea();

-- La fel în rezumat și în pagina Activitate.
do $$ begin
  if to_regprocedure('public.act_il_vede(uuid, uuid, text)') is not null then
    execute $f$
      create or replace function public.act_il_vede(u uuid, o uuid, s text)
      returns boolean language sql stable security definer set search_path = public as $b$
        select u <> o and exists (select 1 from public.profiles p join public.roles r on r.code = p.role_code
          where p.user_id = u and p.active
            and (r.is_admin or r.sees_all
                 or (p.role_code in (select public.sefii((select role_code from public.profiles where user_id = o)))
                     and (s is null or (public.vede_locatia(u, s) and public.anunta_la(u, s))))))
      $b$ $f$;
  end if;
end $$;

notify pgrst, 'reload schema';
