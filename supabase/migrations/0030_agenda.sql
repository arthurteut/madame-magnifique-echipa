-- 0030 · Agenda responsabilului de locație
--
-- Sarcinile care se repetă (zilnic, săptămânal, lunar sau la nevoie), pe rol. Responsabilul le
-- bifează pe locația lui; șefii văd în panou ce e făcut și ce a rămas în urmă. La ora pusă pe
-- sarcină pleacă un memento, dacă nu e încă bifată.
--
--   agenda_sarcini   lista de sarcini (o ține biroul: cine vede tot)
--   agenda_bife      o bifă pe sarcină, locație și zi
--
-- Lista de sarcini nu e în depozit: se încarcă separat, din fișierul de date.
-- Se poate rula de mai multe ori.

create table if not exists public.agenda_sarcini (
  id        bigint generated always as identity primary key,
  rol       text not null default 'RL' references public.roles(code) on update cascade,
  titlu     text not null check (length(trim(titlu)) between 3 and 160),
  detaliu   text not null default '',
  ritm      text not null check (ritm in ('zilnic', 'saptamanal', 'lunar', 'la_nevoie')),
  tinta     int  not null default 1 check (tinta between 1 and 7),      -- de câte ori pe săptămână / lună
  zi_sapt   int  check (zi_sapt between 1 and 7),                       -- 1 = luni … 7 = duminică
  zi_luna   int  check (zi_luna between 1 and 31),                      -- 31 = ultima zi a lunii
  ora       time,                                                       -- ora mementoului
  unde      text not null default '',                                   -- pagina din site (#/comenzi) sau programul (SoftPro, Gesto)
  activ     boolean not null default true,
  position  int not null default 0
);
create table if not exists public.agenda_bife (
  id         bigint generated always as identity primary key,
  sarcina_id bigint not null references public.agenda_sarcini(id) on delete cascade,
  space_id   text not null references public.spaces(id) on update cascade on delete cascade,
  zi         date not null,
  user_id    uuid not null,
  nota       text not null default '',
  la         timestamptz not null default now(),
  unique (sarcina_id, space_id, zi)
);
create index if not exists agenda_bife_loc on public.agenda_bife (space_id, zi);
alter table public.agenda_sarcini enable row level security;
alter table public.agenda_bife enable row level security;
revoke all on public.agenda_sarcini, public.agenda_bife from anon, authenticated;
grant all on public.agenda_sarcini, public.agenda_bife to service_role;

-- Ziua din lună a unei sarcini lunare (31 într-o lună de 30 de zile = ultima zi).
create or replace function public.agenda_zi_luna(p_zi_luna int, p_azi date)
returns date language sql immutable as $$
  select (date_trunc('month', p_azi) + (least(p_zi_luna, extract(day from date_trunc('month', p_azi) + interval '1 month - 1 day')::int) - 1) * interval '1 day')::date
$$;

-- Starea unei sarcini pe o locație, azi: câte bife are în perioada ei și ce urmează.
--   gata         ținta perioadei e atinsă (la zilnic: e bifată azi)
--   azi          trebuie făcută azi
--   intarziata   ziua ei a trecut și nu e făcută
--   in_curs      mai e timp în perioadă
--   la_nevoie    fără țintă
create or replace function public.agenda_stare(s public.agenda_sarcini, p_space text, p_azi date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare de_la date; pana date; facute int; bifat boolean; stare text; termen date; ramase int;
begin
  if s.ritm = 'lunar' then de_la := date_trunc('month', p_azi)::date; pana := (date_trunc('month', p_azi) + interval '1 month - 1 day')::date;
  elsif s.ritm = 'zilnic' then de_la := p_azi; pana := p_azi;
  else de_la := date_trunc('week', p_azi)::date; pana := de_la + 6; end if;
  select count(*), coalesce(bool_or(b.zi = p_azi), false) into facute, bifat from public.agenda_bife b
   where b.sarcina_id = s.id and b.space_id = p_space and b.zi between de_la and pana;
  ramase := pana - p_azi + 1;                                            -- zile rămase în perioadă, cu azi
  if s.ritm = 'la_nevoie' then stare := 'la_nevoie';
  elsif s.ritm = 'zilnic' then stare := case when bifat then 'gata' else 'azi' end;
  elsif facute >= s.tinta then stare := 'gata';
  else
    termen := case when s.ritm = 'lunar' and s.zi_luna is not null then public.agenda_zi_luna(s.zi_luna, p_azi)
                   when s.ritm = 'saptamanal' and s.zi_sapt is not null then de_la + s.zi_sapt - 1 end;
    stare := case when termen is not null and p_azi > termen then 'intarziata'
                  when termen = p_azi and not bifat then 'azi'
                  when termen is null and not bifat and ramase <= s.tinta - facute then 'azi'   -- altfel nu mai iese ținta
                  else 'in_curs' end;
  end if;
  return jsonb_build_object('facute', facute, 'bifat_azi', bifat, 'stare', stare, 'termen', termen);
end $$;
revoke all on function public.agenda_stare(public.agenda_sarcini, text, date) from public, anon, authenticated;

-- Are contul meu agendă? (rolul lui are sarcini)
create or replace function public.agenda_am()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and exists (select 1 from public.agenda_sarcini where rol = public.my_role() and activ)
$$;
revoke all on function public.agenda_am() from public, anon;
grant execute on function public.agenda_am() to authenticated;

-- Agenda unei locații: o vede cine are sarcini pe rolul lui (pe locațiile lui) și șefii.
create or replace function public.agenda_zi(p_space text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; eu text := public.my_role(); sef boolean := public.vede_echipa();
begin
  if not public.is_member() or not public.can_see_space(p_space) then raise exception 'Nu vezi locația asta.'; end if;
  if not sef and not public.agenda_am() then raise exception 'Agenda e pentru responsabilul locației și pentru șefi.'; end if;
  return jsonb_build_object('space_id', p_space, 'azi', azi, 'sef', sef, 'pot_edita', public.sees_all(),
    'sarcini', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'rol', s.rol, 'titlu', s.titlu, 'detaliu', s.detaliu, 'ritm', s.ritm, 'tinta', s.tinta,
        'zi_sapt', s.zi_sapt, 'zi_luna', s.zi_luna, 'ora', to_char(s.ora, 'HH24:MI'), 'unde', s.unde, 'activ', s.activ, 'position', s.position,
        'pot_bifa', s.activ and (s.rol = eu or public.sees_all()),
        'ultima', (select jsonb_build_object('zi', b.zi, 'de', public.nume_om(b.user_id), 'la', b.la, 'nota', b.nota)
                   from public.agenda_bife b where b.sarcina_id = s.id and b.space_id = p_space order by b.zi desc limit 1))
        || public.agenda_stare(s, p_space, azi) order by s.position, s.id)
      from public.agenda_sarcini s where (s.activ or public.sees_all()) and (sef or s.rol = eu)), '[]'));
end $$;
revoke all on function public.agenda_zi(text) from public, anon;
grant execute on function public.agenda_zi(text) to authenticated;

-- Bifează azi (sau scoate bifa de azi). O face omul cu rolul sarcinii, pe locația lui, sau biroul.
create or replace function public.agenda_bifeaza(p_sarcina bigint, p_space text, p_facut boolean, p_nota text default '')
returns void language plpgsql security definer set search_path = public as $$
declare s public.agenda_sarcini; azi date := (now() at time zone 'Europe/Bucharest')::date;
begin
  select * into s from public.agenda_sarcini where id = p_sarcina and activ;
  if not found then raise exception 'Sarcina nu mai e în listă.'; end if;
  if not public.is_member() or not public.can_see_space(p_space) or not (s.rol = public.my_role() or public.sees_all()) then
    raise exception 'Sarcina asta o bifează %.', (select name from public.roles where code = s.rol);
  end if;
  if p_facut then
    insert into public.agenda_bife (sarcina_id, space_id, zi, user_id, nota) values (p_sarcina, p_space, azi, auth.uid(), left(coalesce(trim(p_nota), ''), 300))
    on conflict (sarcina_id, space_id, zi) do update set nota = excluded.nota, user_id = excluded.user_id, la = now();
  else
    delete from public.agenda_bife where sarcina_id = p_sarcina and space_id = p_space and zi = azi;
  end if;
end $$;
revoke all on function public.agenda_bifeaza(bigint, text, boolean, text) from public, anon;
grant execute on function public.agenda_bifeaza(bigint, text, boolean, text) to authenticated;

-- Biroul adaugă sau schimbă o sarcină (id lipsă = sarcină nouă).
create or replace function public.agenda_pune(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := nullif(p ->> 'id', '')::bigint; r text := coalesce(nullif(p ->> 'ritm', ''), 'zilnic');
begin
  if not public.sees_all() then raise exception 'Lista de sarcini o ține biroul.'; end if;
  if v_id is null then
    insert into public.agenda_sarcini (rol, titlu, detaliu, ritm, tinta, zi_sapt, zi_luna, ora, unde, position)
    values (coalesce(nullif(p ->> 'rol', ''), 'RL'), trim(p ->> 'titlu'), coalesce(trim(p ->> 'detaliu'), ''), r,
            case when r in ('saptamanal', 'lunar') then coalesce(nullif(p ->> 'tinta', '')::int, 1) else 1 end,
            case when r = 'saptamanal' then nullif(p ->> 'zi_sapt', '')::int end, case when r = 'lunar' then nullif(p ->> 'zi_luna', '')::int end,
            nullif(p ->> 'ora', '')::time, coalesce(trim(p ->> 'unde'), ''),
            coalesce(nullif(p ->> 'position', '')::int, (select coalesce(max(position), 0) + 10 from public.agenda_sarcini)))
    returning id into v_id;
  else
    update public.agenda_sarcini set titlu = coalesce(nullif(trim(p ->> 'titlu'), ''), titlu), detaliu = coalesce(p ->> 'detaliu', detaliu),
      ora = case when p ? 'ora' then nullif(p ->> 'ora', '')::time else ora end,
      activ = coalesce((p ->> 'activ')::boolean, activ) where id = v_id;
    if not found then raise exception 'Sarcina nu există.'; end if;
  end if;
  return v_id;
end $$;
revoke all on function public.agenda_pune(jsonb) from public, anon;
grant execute on function public.agenda_pune(jsonb) to authenticated;

-- Pentru panoul șefilor: pe fiecare magazin, cât din agendă e făcut azi, săptămâna și luna asta.
create or replace function public.agenda_panou()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date;
begin
  if not public.vede_echipa() then raise exception 'Panoul e pentru șefi.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('space_id', l.id,
      'azi_gata', (select count(*) from jsonb_array_elements(l.s) x where x ->> 'ritm' = 'zilnic' and x ->> 'stare' = 'gata'),
      'azi_toate', (select count(*) from jsonb_array_elements(l.s) x where x ->> 'ritm' = 'zilnic'),
      'sapt_gata', (select coalesce(sum(least((x ->> 'facute')::int, (x ->> 'tinta')::int)), 0) from jsonb_array_elements(l.s) x where x ->> 'ritm' = 'saptamanal'),
      'sapt_toate', (select coalesce(sum((x ->> 'tinta')::int), 0) from jsonb_array_elements(l.s) x where x ->> 'ritm' = 'saptamanal'),
      'luna_gata', (select count(*) from jsonb_array_elements(l.s) x where x ->> 'ritm' = 'lunar' and x ->> 'stare' = 'gata'),
      'luna_toate', (select count(*) from jsonb_array_elements(l.s) x where x ->> 'ritm' = 'lunar'),
      'de_azi', (select coalesce(jsonb_agg(x ->> 'titlu'), '[]') from jsonb_array_elements(l.s) x where x ->> 'stare' = 'azi' and x ->> 'ritm' <> 'zilnic'),
      'intarziate', (select coalesce(jsonb_agg(x ->> 'titlu'), '[]') from jsonb_array_elements(l.s) x where x ->> 'stare' = 'intarziata')))
    from (select sp.id, (select coalesce(jsonb_agg(jsonb_build_object('titlu', s.titlu, 'ritm', s.ritm, 'tinta', s.tinta) || public.agenda_stare(s, sp.id, azi)), '[]')
                         from public.agenda_sarcini s where s.activ) as s
          from public.spaces sp where sp.type = 'magazin' and public.can_see_space(sp.id)) l
    where jsonb_array_length(l.s) > 0), '[]');
end $$;
revoke all on function public.agenda_panou() from public, anon;
grant execute on function public.agenda_panou() to authenticated;

-- Mementoul: la ora sarcinii, dacă azi e ziua ei și nu e bifată, o primește omul cu rolul ei pe locație.
create or replace function public.agenda_mementouri()
returns int language plpgsql security definer set search_path = public as $$
declare acum timestamp := now() at time zone 'Europe/Bucharest'; azi date := (now() at time zone 'Europe/Bucharest')::date;
  s public.agenda_sarcini; l record; n int := 0; k int;
begin
  for s in select * from public.agenda_sarcini where activ and ora is not null and ritm <> 'la_nevoie'
            and acum::time >= ora and acum::time < ora + interval '30 minutes' loop
    for l in select sp.id, sp.name from public.spaces sp where sp.type = 'magazin' loop
      if public.agenda_stare(s, l.id, azi) ->> 'stare' in ('azi', 'intarziata') and public.o_data('agenda:' || s.id || ':' || l.id || ':' || azi) then
        insert into public.notifications (user_id, kind, title, body, url, space_id)
        select p.user_id, 'agenda', 'De făcut: ' || s.titlu, l.name || ' · bifează în Agendă după ce e gata.', '#/agenda?s=' || l.id, l.id
        from public.profiles p where p.active and p.role_code = s.rol and public.vede_locatia(p.user_id, l.id);
        get diagnostics k = row_count; n := n + k;
      end if;
    end loop;
  end loop;
  return n;
end $$;
revoke all on function public.agenda_mementouri() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('agenda-mementouri') where exists (select 1 from cron.job where jobname = 'agenda-mementouri');
  perform cron.schedule('agenda-mementouri', '*/5 * * * *', 'select public.agenda_mementouri()');
exception when undefined_table or undefined_function or invalid_schema_name then
  raise notice 'pg_cron nu e disponibil: mementourile agendei nu pleacă singure';
end $$;

notify pgrst, 'reload schema';
