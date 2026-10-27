-- =============================================================================
-- Ghidul echipei Madame Magnifique · Notificările ajung și la cine vede tot (AE)
--
-- Se rulează după 0016, în Supabase → SQL Editor. Se poate rula de mai multe ori.
-- Pe lângă linia de șefi din organigramă, notificările echipei (clock-in / clock-out,
-- fișă gata, pas nefăcut, observații, întârzieri) le primesc și rolurile cu sees_all
-- (asistentul executiv, AE), de la toate locațiile.
-- =============================================================================

create or replace function public.notifica_sefii(p_user uuid, p_space text, p_kind text, p_title text, p_body text, p_url text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.notifications (user_id, kind, title, body, url, space_id)
  select p.user_id, p_kind, p_title, p_body, p_url, p_space
  from public.profiles p join public.roles r on r.code = p.role_code
  where p.active and p.user_id <> p_user
    and (p.role_code in (select public.sefii((select role_code from public.profiles where user_id = p_user))) or r.sees_all)
    and (r.is_admin or r.sees_all or p_space is null
         or exists (select 1 from public.role_space_access a where a.role_code = p.role_code and a.space_id = p_space));
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.notifica_sefii(uuid, text, text, text, text, text) from public, anon, authenticated;

create or replace function public.verifica_ture()
returns void language plpgsql security definer set search_path = public as $$
declare s record; f record; acum timestamptz := now(); azi date := (now() at time zone 'Europe/Bucharest')::date;
begin
  for s in select t.*, public.tura_start(t) as st, public.tura_sfarsit(t) as sf from public.shifts t
            where t.day between azi - 1 and azi + 1 loop
    -- 1. cu 15 minute înainte de tură: memento să scaneze QR-ul la sosire
    if acum between s.st - interval '20 minutes' and s.st and public.o_data('memento-start:' || s.id) then
      insert into public.notifications (user_id, kind, title, body, url, space_id) values (s.user_id, 'memento',
        case when s.opens then 'Deschizi ' else 'Tura ta la ' end || public.nume_loc(s.space_id) || ' începe la ' || to_char(s.starts, 'HH24:MI'),
        'Când ajungi, scanează codul QR de la intrare (clock-in)'
          || case when s.opens then ', apoi deschide fișa de deschidere și bifează pașii.' else '.' end, '#/tura', s.space_id);
    end if;
    -- 2. la 10 minute după începutul turei, fără clock-in: anunță șefii
    if acum between s.st + interval '10 minutes' and s.sf
       and not exists (select 1 from public.clockings c where c.user_id = s.user_id and c.space_id = s.space_id
                       and c.clock_in > s.st - interval '3 hours')
       and public.o_data('fara-clock-in:' || s.id) then
      perform public.notifica_sefii(s.user_id, s.space_id, 'intarziere',
        public.nume_loc(s.space_id) || ': ' || public.nume_om(s.user_id) || ' nu a făcut clock-in',
        'Tura începea la ' || to_char(s.starts, 'HH24:MI') || case when s.opens then ' și deschide locația' else '' end || '.', '#/echipa');
    end if;
    -- 3. la sfârșitul turei: memento pentru clock-out (și pentru fișa de închidere, la cine închide)
    if acum between s.sf - interval '5 minutes' and s.sf + interval '15 minutes'
       and exists (select 1 from public.clockings c where c.user_id = s.user_id and c.space_id = s.space_id and c.clock_out is null)
       and public.o_data('memento-final:' || s.id) then
      insert into public.notifications (user_id, kind, title, body, url, space_id) values (s.user_id, 'memento',
        'Tura ta la ' || public.nume_loc(s.space_id) || ' se termină la ' || to_char(s.ends, 'HH24:MI'),
        case when s.closes then 'Termină fișa de închidere, apoi ' else '' end || 'scanează codul QR la plecare (clock-out).', '#/tura', s.space_id);
    end if;
  end loop;

  -- 4. fișele de deschidere / închidere neterminate la termen (doar la locațiile cu program și cu om programat să deschidă / închidă)
  for f in
    select h.space_id, k.tip, (azi + case when k.tip = 'deschidere' then h.opens else h.closes end) at time zone 'Europe/Bucharest'
             + case when k.tip = 'inchidere' then interval '60 minutes' else interval '0' end as termen
    from public.space_hours h cross join (values ('deschidere'), ('inchidere')) k (tip)
    where h.weekday = extract(isodow from azi)
  loop
    if acum between f.termen and f.termen + interval '3 hours'
       and exists (select 1 from public.shifts t where t.space_id = f.space_id and t.day = azi
                   and ((f.tip = 'deschidere' and t.opens) or (f.tip = 'inchidere' and t.closes)))
       and not exists (select 1 from public.checklist_runs r join public.procedure_docs d on d.id = r.doc_id
                       where r.space_id = f.space_id and r.day = azi and r.finished_at is not null
                         and d.procedure_code is null and d.role_code is null
                         and d.source_file ilike 'Procedura_' || f.tip || '%')
       and public.o_data('fisa-termen:' || f.tip || ':' || f.space_id || ':' || azi) then
      -- anunță șefii celor programați să deschidă / închidă (o singură dată pe șef)
      insert into public.notifications (user_id, kind, title, body, url, space_id)
      select distinct p.user_id, 'intarziere',
             public.nume_loc(f.space_id) || ': fișa de ' || case when f.tip = 'deschidere' then 'deschidere' else 'închidere' end || ' nu e gata',
             'Termenul era ' || public.ora(f.termen) || '.', '#/echipa', f.space_id
      from public.shifts t
      join public.profiles om on om.user_id = t.user_id
      join public.roles r on true
      join public.profiles p on p.active and p.role_code = r.code and (r.code in (select public.sefii(om.role_code)) or r.sees_all)
      where t.space_id = f.space_id and t.day = azi and ((f.tip = 'deschidere' and t.opens) or (f.tip = 'inchidere' and t.closes))
        and (r.is_admin or r.sees_all or exists (select 1 from public.role_space_access a where a.role_code = p.role_code and a.space_id = f.space_id));
    end if;
  end loop;
  delete from public.notificari_trimise where at < now() - interval '3 days';
end $$;
revoke all on function public.verifica_ture() from public, anon, authenticated;
