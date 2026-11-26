-- 0036 · Orarul general
--
-- Un singur orar pentru toate magazinele și laboratoarele. Îl lucrează toți responsabilii de locație și
-- șefii de producție (și conducerea): pot pune pe oricine, la orice locație. Fiecare tură ține minte cine
-- a pus-o. „Acum” arată, pe locații, cine e în tură, cine lipsește sau a întârziat, cine a plecat și cine urmează.
--
--   orar_roluri   rolurile care lucrează la orar (pe lângă cine vede tot)
-- Se poate rula de mai multe ori. Cere 0034.

create table if not exists public.orar_roluri (rol text primary key references public.roles(code) on update cascade on delete cascade);
insert into public.orar_roluri (rol) select code from public.roles where code in ('RL', 'SP', 'DP') on conflict do nothing;
alter table public.orar_roluri enable row level security;
revoke all on public.orar_roluri from anon, authenticated;
grant all on public.orar_roluri to service_role;

create or replace function public.orar_sef()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.sees_all() or exists (select 1 from public.orar_roluri where rol = public.my_role()))
$$;
revoke all on function public.orar_sef() from public, anon;
grant execute on function public.orar_sef() to authenticated;

-- Cine poate fi pus în orar: orice cont activ, în afară de conducere (admin și cine vede tot).
create or replace function public.orar_om(u uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p join public.roles r on r.code = p.role_code where p.user_id = u and p.active and not r.is_admin and not r.sees_all)
$$;
revoke all on function public.orar_om(uuid) from public, anon;
grant execute on function public.orar_om(uuid) to authenticated;       -- o folosește regula tabelei shifts
create or replace function public.orar_loc(s text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.spaces where id = s and type in ('magazin', 'productie'))
$$;
revoke all on function public.orar_loc(text) from public, anon;
grant execute on function public.orar_loc(text) to authenticated;

-- Regulile tabelei: pe lângă cele de până acum, cine lucrează la orar vede și schimbă toate turele.
drop policy if exists "șefii fac programul" on public.shifts;
create policy "șefii fac programul" on public.shifts for all to authenticated
  using ((public.orar_sef() and public.orar_om(user_id) and public.orar_loc(space_id))
         or (public.poate_programa(user_id) and (public.is_admin() or public.can_see_space(space_id))))
  with check ((public.orar_sef() and public.orar_om(user_id) and public.orar_loc(space_id))
         or (public.poate_programa(user_id) and (public.is_admin() or public.can_see_space(space_id))));
drop policy if exists "îmi văd turele, șefii le văd pe ale echipei" on public.shifts;
create policy "îmi văd turele, șefii le văd pe ale echipei" on public.shifts for select to authenticated
  using (public.is_member() and (user_id = auth.uid() or public.sees_all() or public.orar_sef()
         or (public.poate_programa(user_id) and public.can_see_space(space_id)) or public.am_tura(space_id, day)));

-- Săptămâna întreagă: oameni, locații, ture și pontaj.
create or replace function public.orar_saptamana(p_luni date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; luni date := date_trunc('week', coalesce(p_luni, azi))::date;
begin
  if not public.orar_sef() then raise exception 'Orarul general îl lucrează responsabilii de locație și șefii de producție.'; end if;
  return jsonb_build_object('luni', luni, 'azi', azi, 'acum', to_char(now() at time zone 'Europe/Bucharest', 'HH24:MI'),
    'locatii', (select jsonb_agg(jsonb_build_object('id', s.id, 'nume', public.nume_loc(s.id), 'tip', s.type) order by s.type, s.position) from public.spaces s where s.type in ('magazin', 'productie')),
    'oameni', coalesce((select jsonb_agg(jsonb_build_object('user_id', p.user_id, 'nume', p.full_name, 'rol', p.role_code, 'rol_nume', r.name,
        'acasa', coalesce((select ps.space_id from public.profile_spaces ps where ps.user_id = p.user_id order by ps.space_id limit 1),
                          (select t.space_id from public.shifts t where t.user_id = p.user_id and t.day >= luni - 28 group by t.space_id order by count(*) desc limit 1)))
        order by r.position, p.full_name)
      from public.profiles p join public.roles r on r.code = p.role_code where p.active and not r.is_admin and not r.sees_all
        and (exists (select 1 from public.role_space_access a join public.spaces s on s.id = a.space_id where a.role_code = p.role_code and s.type in ('magazin', 'productie'))
             or exists (select 1 from public.shifts t where t.user_id = p.user_id and t.day between luni and luni + 6))), '[]'),
    'ture', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'user_id', t.user_id, 'space_id', t.space_id, 'day', t.day, 'starts', to_char(t.starts, 'HH24:MI'), 'ends', to_char(t.ends, 'HH24:MI'),
        'opens', t.opens, 'closes', t.closes, 'note', t.note, 'de', public.nume_om(t.created_by)) order by t.day, t.starts)
      from public.shifts t where t.day between luni and luni + 6), '[]'),
    'pontaj', coalesce((select jsonb_agg(jsonb_build_object('user_id', c.user_id, 'space_id', c.space_id, 'day', (c.clock_in at time zone 'Europe/Bucharest')::date,
        'in', to_char(c.clock_in at time zone 'Europe/Bucharest', 'HH24:MI'), 'out', to_char(c.clock_out at time zone 'Europe/Bucharest', 'HH24:MI')) order by c.clock_in)
      from public.clockings c where (c.clock_in at time zone 'Europe/Bucharest')::date between luni and luni + 6), '[]'));
end $$;
revoke all on function public.orar_saptamana(date) from public, anon;
grant execute on function public.orar_saptamana(date) to authenticated;

-- Pune sau schimbă o tură. p.zile = mai multe zile deodată (doar la tură nouă).
create or replace function public.orar_pune(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_id bigint := nullif(p ->> 'id', '')::bigint; u uuid := (p ->> 'user_id')::uuid; s text := p ->> 'space_id';
  a time := (p ->> 'starts')::time; b time := (p ->> 'ends')::time; z date; n int := 0;
begin
  if not public.orar_sef() then raise exception 'Orarul general îl lucrează responsabilii de locație și șefii de producție.'; end if;
  if not public.orar_om(u) then raise exception 'Omul ăsta nu poate fi pus în orar.'; end if;
  if not public.orar_loc(s) then raise exception 'Alege un magazin sau un laborator.'; end if;
  if b <= a then raise exception 'Ora de sfârșit trebuie să fie după cea de început.'; end if;
  if v_id is not null then
    update public.shifts set user_id = u, space_id = s, day = (p ->> 'day')::date, starts = a, ends = b, opens = coalesce((p ->> 'opens')::boolean, false),
      closes = coalesce((p ->> 'closes')::boolean, false), note = coalesce(trim(p ->> 'note'), ''), created_by = auth.uid() where id = v_id;
    if not found then raise exception 'Tura nu mai există.'; end if;
    return 1;
  end if;
  if jsonb_array_length(coalesce(p -> 'zile', '[]')) > 1 then perform set_config('orar.in_masa', '1', true); end if;
  for z in select x::date from jsonb_array_elements_text(coalesce(p -> 'zile', jsonb_build_array(p ->> 'day'))) x loop
    if exists (select 1 from public.shifts t where t.user_id = u and t.day = z and t.starts < b and t.ends > a) then
      raise exception '% are deja o tură care se suprapune în %.', (select full_name from public.profiles where user_id = u), to_char(z, 'DD.MM');
    end if;
    insert into public.shifts (user_id, space_id, day, starts, ends, opens, closes, note, created_by)
    values (u, s, z, a, b, coalesce((p ->> 'opens')::boolean, false), coalesce((p ->> 'closes')::boolean, false), coalesce(trim(p ->> 'note'), ''), auth.uid());
    n := n + 1;
  end loop;
  if current_setting('orar.in_masa', true) = '1' then
    perform set_config('orar.in_masa', '', true);
    perform public.orar_notifica_masa(now(), 'a pus ture pe mai multe zile');
  end if;
  return n;
end $$;
create or replace function public.orar_sterge(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.orar_sef() then raise exception 'Orarul general îl lucrează responsabilii de locație și șefii de producție.'; end if;
  delete from public.shifts where id = p_id;
end $$;
-- Copiază săptămâna dinainte în cea aleasă: doar turele care nu se suprapun cu ce e deja pus.
create or replace function public.orar_copiaza(p_luni date)
returns int language plpgsql security definer set search_path = public as $$
declare luni date := date_trunc('week', p_luni)::date; n int;
begin
  if not public.orar_sef() then raise exception 'Orarul general îl lucrează responsabilii de locație și șefii de producție.'; end if;
  perform set_config('orar.in_masa', '1', true);
  insert into public.shifts (user_id, space_id, day, starts, ends, opens, closes, note, created_by)
  select t.user_id, t.space_id, t.day + 7, t.starts, t.ends, t.opens, t.closes, t.note, auth.uid() from public.shifts t
  where t.day between luni - 7 and luni - 1 and public.orar_om(t.user_id)
    and not exists (select 1 from public.shifts x where x.user_id = t.user_id and x.day = t.day + 7 and x.starts < t.ends and x.ends > t.starts);
  get diagnostics n = row_count;
  perform set_config('orar.in_masa', '', true);
  if n > 0 then perform public.orar_notifica_masa(now(), 'a copiat săptămâna trecută'); end if;
  return n;
end $$;
revoke all on function public.orar_pune(jsonb), public.orar_sterge(bigint), public.orar_copiaza(date) from public, anon;
grant execute on function public.orar_pune(jsonb), public.orar_sterge(bigint), public.orar_copiaza(date) to authenticated;

-- Acum: pe fiecare locație, cine e în tură, cine lipsește sau a întârziat, cine a plecat, cine urmează.
create or replace function public.orar_acum()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; ora time := (now() at time zone 'Europe/Bucharest')::time;
begin
  if not public.orar_sef() and not public.vede_echipa() then raise exception 'Vederea e pentru șefi.'; end if;
  return jsonb_build_object('azi', azi, 'acum', to_char(ora, 'HH24:MI'), 'locatii', coalesce((select jsonb_agg(l order by l ->> 'tip', (l ->> 'pos')::int) from (
    select jsonb_build_object('id', s.id, 'nume', public.nume_loc(s.id), 'tip', s.type, 'pos', s.position,
      'in_tura', coalesce((select jsonb_agg(jsonb_build_object('nume', p.full_name, 'rol', p.role_code, 'de_la', to_char(c.clock_in at time zone 'Europe/Bucharest', 'HH24:MI'),
            'program', (select to_char(t.starts, 'HH24:MI') || '–' || to_char(t.ends, 'HH24:MI') from public.shifts t where t.user_id = c.user_id and t.day = azi and t.space_id = s.id order by t.starts limit 1),
            'intarziere', (select greatest(0, round(extract(epoch from ((c.clock_in at time zone 'Europe/Bucharest')::time - t.starts)) / 60))::int from public.shifts t
                           where t.user_id = c.user_id and t.day = azi and t.space_id = s.id order by t.starts limit 1)) order by c.clock_in)
          from public.clockings c join public.profiles p on p.user_id = c.user_id
          where c.space_id = s.id and c.clock_out is null and c.clock_in > now() - interval '18 hours'), '[]'),
      'lipsesc', coalesce((select jsonb_agg(jsonb_build_object('nume', p.full_name, 'rol', p.role_code, 'program', to_char(t.starts, 'HH24:MI') || '–' || to_char(t.ends, 'HH24:MI'),
            'minute', round(extract(epoch from (ora - t.starts)) / 60)::int) order by t.starts)
          from public.shifts t join public.profiles p on p.user_id = t.user_id
          where t.space_id = s.id and t.day = azi and t.starts <= ora and t.ends > ora
            and not exists (select 1 from public.clockings c where c.user_id = t.user_id and (c.clock_in at time zone 'Europe/Bucharest')::date = azi)), '[]'),
      'plecati', coalesce((select jsonb_agg(jsonb_build_object('nume', p.full_name, 'rol', p.role_code, 'de_la', to_char(c.clock_in at time zone 'Europe/Bucharest', 'HH24:MI'),
            'pana', to_char(c.clock_out at time zone 'Europe/Bucharest', 'HH24:MI'), 'minute', round(extract(epoch from (c.clock_out - c.clock_in)) / 60)::int,
            'program', (select to_char(t.starts, 'HH24:MI') || '–' || to_char(t.ends, 'HH24:MI') from public.shifts t where t.user_id = c.user_id and t.day = azi and t.space_id = s.id order by t.starts limit 1)) order by c.clock_out)
          from public.clockings c join public.profiles p on p.user_id = c.user_id
          where c.space_id = s.id and c.clock_out is not null and (c.clock_in at time zone 'Europe/Bucharest')::date = azi), '[]'),
      'urmeaza', coalesce((select jsonb_agg(jsonb_build_object('nume', p.full_name, 'rol', p.role_code, 'program', to_char(t.starts, 'HH24:MI') || '–' || to_char(t.ends, 'HH24:MI')) order by t.starts)
          from public.shifts t join public.profiles p on p.user_id = t.user_id
          where t.space_id = s.id and t.day = azi and t.starts > ora
            and not exists (select 1 from public.clockings c where c.user_id = t.user_id and c.space_id = s.id and (c.clock_in at time zone 'Europe/Bucharest')::date = azi)), '[]')) as l
    from public.spaces s where s.type in ('magazin', 'productie') and (public.orar_sef() or public.can_see_space(s.id))) q), '[]'));
end $$;
revoke all on function public.orar_acum() from public, anon;
grant execute on function public.orar_acum() to authenticated;

-- ---------------------------------------------------------------------------
-- Notificări la fiecare mutare din orar
-- ---------------------------------------------------------------------------
-- Omul pus, mutat sau scos din tură află pe loc. Responsabilii locației află și ei, dacă schimbarea a
-- făcut-o altcineva. Șefii o găsesc în Activitate și în rezumat. La mai multe ture puse deodată
-- (mai multe zile, copierea săptămânii) pleacă un singur mesaj de om, nu câte unul de tură.
create or replace function public.orar_tura_text(t public.shifts)
returns text language sql stable security definer set search_path = public as $$
  select to_char(t.day, 'DD.MM') || ', ' || public.nume_loc(t.space_id) || ', ' || to_char(t.starts, 'HH24:MI') || '–' || to_char(t.ends, 'HH24:MI')
$$;
revoke all on function public.orar_tura_text(public.shifts) from public, anon, authenticated;

-- Anunță responsabilii unei locații (în afară de cel care a făcut schimbarea și de omul în cauză).
create or replace function public.orar_anunta_locatia(p_space text, p_fara uuid[], p_title text, p_body text, p_url text)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, kind, title, body, url, space_id)
  select p.user_id, 'orar', p_title, p_body, p_url, p_space from public.profiles p
  where p.active and p.role_code in (select rol from public.orar_roluri) and public.vede_locatia(p.user_id, p_space)
    and not (p.user_id = any (p_fara))
$$;
revoke all on function public.orar_anunta_locatia(text, uuid[], text, text, text) from public, anon, authenticated;

create or replace function public.orar_notifica()
returns trigger language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); azi date := (now() at time zone 'Europe/Bucharest')::date; cine text; om text; t public.shifts; ce text;
begin
  if coalesce(current_setting('orar.in_masa', true), '') = '1' then return coalesce(new, old); end if;   -- mesajul comun pleacă din funcție
  t := coalesce(new, old);
  if t.day < azi then return t; end if;
  if tg_op = 'UPDATE' and new.user_id = old.user_id and new.space_id = old.space_id and new.day = old.day and new.starts = old.starts and new.ends = old.ends
     and new.opens = old.opens and new.closes = old.closes then return new; end if;
  cine := coalesce(public.nume_om(eu), 'Conducerea'); om := (select full_name from public.profiles where user_id = t.user_id);
  if tg_op = 'UPDATE' and new.user_id <> old.user_id then                       -- tura a trecut de la un om la altul
    if old.user_id is distinct from eu then
      insert into public.notifications (user_id, kind, title, body, url, space_id)
      values (old.user_id, 'orar', 'Tura ta a fost scoasă', public.orar_tura_text(old) || ' · de ' || cine, '#/tura', old.space_id);
    end if;
    ce := 'Ai o tură nouă';
  else
    ce := case tg_op when 'INSERT' then 'Ai o tură nouă' when 'DELETE' then 'Tura ta a fost scoasă' else 'Tura ta s-a schimbat' end;
  end if;
  if t.user_id is distinct from eu then
    insert into public.notifications (user_id, kind, title, body, url, space_id)
    values (t.user_id, 'orar', ce, case when tg_op = 'UPDATE' and new.user_id = old.user_id then 'Era: ' || public.orar_tura_text(old) || '. Acum: ' else '' end
      || public.orar_tura_text(t) || case when t.opens then ' · deschizi' else '' end || case when t.closes then ' · închizi' else '' end || ' · de ' || cine, '#/tura', t.space_id);
  end if;
  perform public.orar_anunta_locatia(t.space_id, array[coalesce(eu, t.user_id), t.user_id],
    'Orar ' || public.nume_loc(t.space_id) || ': ' || case tg_op when 'INSERT' then 'tură nouă' when 'DELETE' then 'tură scoasă' else 'tură schimbată' end,
    om || ' · ' || public.orar_tura_text(t) || ' · de ' || cine, '#/orar?luni=' || date_trunc('week', t.day)::date);
  if tg_op = 'UPDATE' and new.space_id <> old.space_id then                    -- și magazinul de unde a plecat omul
    perform public.orar_anunta_locatia(old.space_id, array[coalesce(eu, t.user_id), t.user_id], 'Orar ' || public.nume_loc(old.space_id) || ': tură mutată',
      om || ' nu mai vine ' || public.orar_tura_text(old) || '. S-a mutat la ' || public.nume_loc(new.space_id) || ' · de ' || cine, '#/orar?luni=' || date_trunc('week', t.day)::date);
  end if;
  if to_regprocedure('public.act(uuid, text, text, text, text, boolean)') is not null and eu is not null then
    perform public.act(eu, t.space_id, 'orar', case tg_op when 'INSERT' then 'a pus în orar: ' when 'DELETE' then 'a scos din orar: ' else 'a schimbat în orar: ' end
      || om || ', ' || public.orar_tura_text(t), '#/orar?luni=' || date_trunc('week', t.day)::date);
  end if;
  return t;
exception when others then
  raise warning 'orar_notifica: %', sqlerrm;        -- notificarea nu are voie să oprească schimbarea din orar
  return coalesce(new, old);
end $$;
revoke all on function public.orar_notifica() from public, anon, authenticated;
drop trigger if exists orar_notifica on public.shifts;
create trigger orar_notifica after insert or update or delete on public.shifts for each row execute function public.orar_notifica();

-- Mesajul comun după mai multe ture puse deodată: unul pentru fiecare om, unul pentru responsabilii fiecărei locații.
create or replace function public.orar_notifica_masa(p_dupa timestamptz, p_ce text)
returns void language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); cine text := coalesce(public.nume_om(auth.uid()), 'Conducerea'); azi date := (now() at time zone 'Europe/Bucharest')::date; l record;
begin
  insert into public.notifications (user_id, kind, title, body, url)
  select t.user_id, 'orar', case when count(*) = 1 then 'Ai o tură nouă' else 'Ai ' || count(*) || ' ture noi' end,
         left(string_agg(public.orar_tura_text(t), ' · ' order by t.day, t.starts), 380) || ' · de ' || cine, '#/tura'
  from public.shifts t where t.created_by = eu and t.created_at >= p_dupa and t.day >= azi and t.user_id <> eu group by t.user_id;
  for l in select t.space_id, count(*) as n, count(distinct t.user_id) as oameni, min(t.day) as zi from public.shifts t
            where t.created_by = eu and t.created_at >= p_dupa and t.day >= azi group by t.space_id loop
    perform public.orar_anunta_locatia(l.space_id, array[eu], 'Orar ' || public.nume_loc(l.space_id) || ': ' || l.n || case when l.n = 1 then ' tură nouă' else ' ture noi' end,
      p_ce || ' · ' || l.oameni || case when l.oameni = 1 then ' om' else ' oameni' end || ' · de ' || cine, '#/orar?luni=' || date_trunc('week', l.zi)::date);
    if to_regprocedure('public.act(uuid, text, text, text, text, boolean)') is not null then
      perform public.act(eu, l.space_id, 'orar', p_ce || ': ' || l.n || case when l.n = 1 then ' tură' else ' ture' end, '#/orar?luni=' || date_trunc('week', l.zi)::date);
    end if;
  end loop;
end $$;
revoke all on function public.orar_notifica_masa(timestamptz, text) from public, anon, authenticated;

-- Rezumatul pentru șefi numără și schimbările din orar.
create or replace function public.act_eticheta(p_fel text, n bigint)
returns text language sql immutable as $$
  select case p_fel when 'agenda' then case when n = 1 then 'o bifă în agendă' else n || ' bife în agendă' end
    when 'incasari' then 'încasările scrise' when 'nota' then 'nota zilei scrisă' when 'stoc' then 'stocul scris'
    when 'comanda' then case when n = 1 then 'o comandă' else n || ' comenzi' end
    when 'raspuns' then case when n = 1 then 'un răspuns la comenzi' else n || ' răspunsuri la comenzi' end
    when 'livrare' then case when n = 1 then 'o livrare' else n || ' livrări' end
    when 'standard' then case when n = 1 then 'o verificare de standard' else n || ' verificări de standard' end
    when 'test' then case when n = 1 then 'un test' else n || ' teste' end
    when 'orar' then case when n = 1 then 'o schimbare în orar' else n || ' schimbări în orar' end else n || ' ' || p_fel end
$$;

notify pgrst, 'reload schema';
