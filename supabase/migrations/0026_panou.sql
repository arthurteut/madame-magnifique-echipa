-- =============================================================================
-- Ghidul echipei Madame Magnifique · Panoul șefilor: toate locațiile, într-un loc
--
-- Se rulează după 0025, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Echipa → „Toate locațiile”: pentru fiecare magazin și laborator, în timp real: cine e în tură și cine
-- lipsește din program, când s-a deschis, cum merg fișele, semnalările, nota vitrinei, marfa zilei.
-- Trei lucruri noi se scriu în aplicație, din pagina „Ziua locației”:
--   · încasările zilei și numărul de bonuri (magazinul, seara; media bonului se calculează);
--   · nota zilei de la responsabilul locației (ce a mers, ce nu, ce are nevoie);
--   · stocul laboratorului (produse finite, aluaturi, torturi), pe o listă pe care o țin șefii de secție.
-- =============================================================================

create table if not exists public.incasari_zi (
  space_id   text not null references public.spaces (id) on delete cascade,
  zi         date not null,
  incasari   numeric not null check (incasari >= 0),          -- cu TVA, ca pe raportul casei
  bonuri     int not null check (bonuri >= 0),
  nota       text not null default '' check (length(nota) <= 1000),
  scris_de   uuid references public.profiles (user_id) on delete set null,
  scris_la   timestamptz not null default now(),
  primary key (space_id, zi)
);
create table if not exists public.nota_zilei (
  space_id   text not null references public.spaces (id) on delete cascade,
  zi         date not null,
  text       text not null check (length(trim(text)) between 3 and 3000),
  scris_de   uuid references public.profiles (user_id) on delete set null,
  scris_la   timestamptz not null default now(),
  primary key (space_id, zi)
);
create table if not exists public.stoc_produse (
  id       bigint generated always as identity primary key,
  space_id text not null references public.spaces (id) on delete cascade,
  nume     text not null check (length(trim(nume)) > 0),
  grupa    text not null default '',                           -- „Aluaturi”, „Torturi”, „Produse finite”…
  unitate  text not null default 'buc' check (unitate in ('buc', 'kg', 'g', 'tavă', 'l')),
  minim    numeric check (minim is null or minim >= 0),        -- sub el, stocul apare ca „puțin”
  activ    boolean not null default true,
  position int not null default 0,
  unique (space_id, nume)
);
create table if not exists public.stoc_zi (
  produs_id bigint not null references public.stoc_produse (id) on delete cascade,
  zi        date not null,
  cantitate numeric not null check (cantitate >= 0),
  scris_de  uuid references public.profiles (user_id) on delete set null,
  scris_la  timestamptz not null default now(),
  primary key (produs_id, zi)
);
alter table public.incasari_zi enable row level security;
alter table public.nota_zilei enable row level security;
alter table public.stoc_produse enable row level security;
alter table public.stoc_zi enable row level security;
revoke all on public.incasari_zi, public.nota_zilei, public.stoc_produse, public.stoc_zi from anon, authenticated;
grant select, insert, update, delete on public.stoc_produse to authenticated;
grant all on public.incasari_zi, public.nota_zilei, public.stoc_produse, public.stoc_zi to service_role;

-- Lista de stoc o țin șefii producției și biroul; o vede cine vede locația.
create or replace function public.stoc_tine_lista()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.cmd_birou() or public.my_role() in ('SP', 'DP', 'PBP'))
$$;
revoke all on function public.stoc_tine_lista() from public, anon;
grant execute on function public.stoc_tine_lista() to authenticated;
drop policy if exists "lista de stoc: cine vede locația" on public.stoc_produse;
create policy "lista de stoc: cine vede locația" on public.stoc_produse for select to authenticated using (public.can_see_space(space_id));
drop policy if exists "lista de stoc: șefii producției" on public.stoc_produse;
create policy "lista de stoc: șefii producției" on public.stoc_produse for all to authenticated
  using (public.stoc_tine_lista() and public.can_see_space(space_id)) with check (public.stoc_tine_lista() and public.can_see_space(space_id));

-- Încasările zilei: le scrie echipa locației pentru azi sau ieri; șefii, pentru orice zi trecută.
create or replace function public.incasari_pune(p_space text, p_zi date, p_incasari numeric, p_bonuri int, p_nota text default '')
returns void language plpgsql security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date;
begin
  if not public.is_member() or not public.can_see_space(p_space) then raise exception 'Nu lucrezi la locația asta.'; end if;
  if p_zi is null or p_zi > azi then raise exception 'Ziua nu a venit încă.'; end if;
  if p_zi < azi - 1 and not public.vede_echipa() then raise exception 'Pentru zile mai vechi de ieri, vorbește cu responsabilul.'; end if;
  if p_incasari is null or p_incasari < 0 or p_bonuri is null or p_bonuri < 0 then raise exception 'Scrie încasările și numărul de bonuri.'; end if;
  if p_incasari > 0 and p_bonuri = 0 then raise exception 'Cu încasări, numărul de bonuri nu poate fi zero.'; end if;
  insert into public.incasari_zi (space_id, zi, incasari, bonuri, nota, scris_de)
  values (p_space, p_zi, p_incasari, p_bonuri, trim(coalesce(p_nota, '')), auth.uid())
  on conflict (space_id, zi) do update set incasari = excluded.incasari, bonuri = excluded.bonuri, nota = excluded.nota, scris_de = auth.uid(), scris_la = now();
end $$;
revoke all on function public.incasari_pune(text, date, numeric, int, text) from public, anon;
grant execute on function public.incasari_pune(text, date, numeric, int, text) to authenticated;

-- Nota zilei: o scrie cine conduce locația (are oameni în subordine și o vede).
create or replace function public.nota_zilei_pune(p_space text, p_zi date, p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date;
begin
  if not public.vede_echipa() or not public.can_see_space(p_space) then raise exception 'Nota zilei o scrie responsabilul locației.'; end if;
  if p_zi is null or p_zi > azi or p_zi < azi - 7 then raise exception 'Nota se scrie pentru azi sau pentru ultimele zile.'; end if;
  if length(trim(coalesce(p_text, ''))) < 3 then raise exception 'Scrie câteva cuvinte despre zi.'; end if;
  insert into public.nota_zilei (space_id, zi, text, scris_de) values (p_space, p_zi, trim(p_text), auth.uid())
  on conflict (space_id, zi) do update set text = excluded.text, scris_de = auth.uid(), scris_la = now();
end $$;
revoke all on function public.nota_zilei_pune(text, date, text) from public, anon;
grant execute on function public.nota_zilei_pune(text, date, text) to authenticated;

-- Stocul de azi: {"<id produs>": cantitate}. Îl scrie echipa laboratorului.
create or replace function public.stoc_pune(p_space text, p_valori jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; k text; v text; n int := 0; pid bigint; cant numeric;
begin
  if not public.is_member() or not public.can_see_space(p_space) then raise exception 'Nu lucrezi la locația asta.'; end if;
  if jsonb_typeof(p_valori) is distinct from 'object' then raise exception 'Nimic de salvat.'; end if;
  for k, v in select * from jsonb_each_text(p_valori) loop
    pid := k::bigint;
    if not exists (select 1 from public.stoc_produse where id = pid and space_id = p_space) then raise exception 'Un produs nu e pe lista acestei locații.'; end if;
    if v is null or v = '' then delete from public.stoc_zi where produs_id = pid and zi = azi; continue; end if;
    cant := v::numeric;
    if cant < 0 then raise exception 'Stocul nu poate fi negativ.'; end if;
    insert into public.stoc_zi (produs_id, zi, cantitate, scris_de) values (pid, azi, cant, auth.uid())
    on conflict (produs_id, zi) do update set cantitate = excluded.cantitate, scris_de = auth.uid(), scris_la = now();
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.stoc_pune(text, jsonb) from public, anon;
grant execute on function public.stoc_pune(text, jsonb) to authenticated;

create or replace function public.incasari_j(p_space text, p_zi date)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('zi', i.zi, 'incasari', i.incasari, 'bonuri', i.bonuri, 'medie', case when i.bonuri > 0 then round(i.incasari / i.bonuri, 2) end,
    'nota', i.nota, 'de', public.nume_om(i.scris_de), 'la', i.scris_la)
  from public.incasari_zi i where i.space_id = p_space and i.zi = p_zi
$$;
revoke all on function public.incasari_j(text, date) from public, anon, authenticated;

-- Ziua unei locații, pentru cine lucrează acolo: ce e scris deja și ce poate scrie contul logat.
create or replace function public.zi_locatie(p_space text, p_zi date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date;
begin
  if not public.is_member() or not public.can_see_space(p_space) then raise exception 'Nu vezi locația asta.'; end if;
  return jsonb_build_object('space_id', p_space, 'zi', p_zi, 'azi', azi, 'sef', public.vede_echipa(), 'tine_lista', public.stoc_tine_lista(),
    'pot_incasari', p_zi <= azi and (p_zi >= azi - 1 or public.vede_echipa()),
    'incasari', public.incasari_j(p_space, p_zi), 'incasari_ieri', public.incasari_j(p_space, p_zi - 1), 'incasari_sapt', public.incasari_j(p_space, p_zi - 7),
    'nota', (select jsonb_build_object('text', n.text, 'de', public.nume_om(n.scris_de), 'la', n.scris_la) from public.nota_zilei n where n.space_id = p_space and n.zi = p_zi),
    'stoc', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nume', p.nume, 'grupa', p.grupa, 'unitate', p.unitate, 'minim', p.minim,
        'azi', (select z.cantitate from public.stoc_zi z where z.produs_id = p.id and z.zi = azi),
        'ultim', (select jsonb_build_object('cantitate', z.cantitate, 'zi', z.zi) from public.stoc_zi z where z.produs_id = p.id and z.zi < azi order by z.zi desc limit 1))
      order by p.grupa, p.position, p.nume) from public.stoc_produse p where p.space_id = p_space and p.activ), '[]'));
end $$;
revoke all on function public.zi_locatie(text, date) from public, anon;
grant execute on function public.zi_locatie(text, date) to authenticated;

-- Panoul șefilor: toate locațiile pe care le vede contul logat, azi.
create or replace function public.panou_sefi()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; acum timestamp := now() at time zone 'Europe/Bucharest';
  luni date := (date_trunc('week', (now() at time zone 'Europe/Bucharest')))::date;
begin
  if not public.vede_echipa() then raise exception 'Panoul e pentru șefi.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'space_id', s.id, 'nume', s.name,
    -- cine e acum în tură
    'in_tura', coalesce((select jsonb_agg(jsonb_build_object('nume', p.full_name, 'rol', p.role_code, 'de_la', c.clock_in) order by c.clock_in)
       from public.clockings c join public.profiles p on p.user_id = c.user_id where c.space_id = s.id and c.clock_out is null), '[]'),
    -- programul de azi: cine a venit, cine întârzie
    'program', coalesce((select jsonb_agg(jsonb_build_object('nume', p.full_name, 'rol', p.role_code, 'de_la', to_char(h.starts, 'HH24:MI'), 'pana_la', to_char(h.ends, 'HH24:MI'),
          'deschide', h.opens, 'inchide', h.closes,
          'venit_la', (select min(c.clock_in) from public.clockings c where c.user_id = h.user_id and c.space_id = s.id and (c.clock_in at time zone 'Europe/Bucharest')::date = azi),
          'plecat', exists (select 1 from public.clockings c where c.user_id = h.user_id and c.space_id = s.id and (c.clock_in at time zone 'Europe/Bucharest')::date = azi and c.clock_out is not null)
            and not exists (select 1 from public.clockings c where c.user_id = h.user_id and c.space_id = s.id and c.clock_out is null),
          'lipseste', (azi + h.starts) + interval '10 minutes' < acum and not exists (select 1 from public.clockings c where c.user_id = h.user_id and c.space_id = s.id and (c.clock_in at time zone 'Europe/Bucharest')::date = azi))
        order by h.starts, p.full_name)
       from public.shifts h join public.profiles p on p.user_id = h.user_id where h.space_id = s.id and h.day = azi), '[]'),
    'deschis_la', (select min(c.clock_in) from public.clockings c where c.space_id = s.id and (c.clock_in at time zone 'Europe/Bucharest')::date = azi),
    -- fișele zilei
    'fise', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'titlu', r.title, 'pasi', jsonb_array_length(r.steps),
          'facuti', (select count(*) from public.checklist_marks m where m.run_id = r.id and m.status = 'facut'),
          'nefacuti', (select count(*) from public.checklist_marks m where m.run_id = r.id and m.status = 'nefacut'),
          'gata_la', r.finished_at, 'termen', r.due_at, 'nota', r.note) order by r.started_at)
       from public.checklist_runs r where r.space_id = s.id and r.day = azi), '[]'),
    'semnalari', (select count(*) from public.semnalari x where x.space_id = s.id and x.status in ('deschisa', 'in_lucru')),
    'urgente', (select count(*) from public.semnalari x where x.space_id = s.id and x.status in ('deschisa', 'in_lucru') and x.urgent),
    -- nota vitrinei, dată de cine vinde
    'vitrina', (select jsonb_build_object('nota', round(avg(n.nota), 1), 'cate', count(*), 'observatii', coalesce(jsonb_agg(n.comentariu) filter (where n.comentariu <> ''), '[]'))
       from public.note_calitate n where n.space_id = s.id and n.zi = azi having count(*) > 0),
    'incasari', public.incasari_j(s.id, azi), 'incasari_ieri', public.incasari_j(s.id, azi - 1), 'incasari_sapt', public.incasari_j(s.id, azi - 7),
    'nota_zilei', (select jsonb_build_object('text', n.text, 'de', public.nume_om(n.scris_de), 'la', n.scris_la, 'zi', n.zi) from public.nota_zilei n
       where n.space_id = s.id and n.zi >= azi - 1 order by n.zi desc limit 1),
    -- feedbackul dat săptămâna asta de șefii locației
    'feedback', (select jsonb_build_object('aprecieri', count(*) filter (where f.fel = 'apreciere'), 'imbunatatiri', count(*) filter (where f.fel = 'imbunatatire'),
          'ultimul', (select jsonb_build_object('fel', f2.fel, 'text', f2.text, 'de', public.nume_om(f2.from_user), 'catre', (select full_name from public.profiles where user_id = f2.to_user), 'la', f2.created_at)
                      from public.feedback f2 where f2.created_at >= luni and public.vede_locatia(f2.to_user, s.id) and exists (select 1 from public.profile_spaces ps where ps.user_id = f2.to_user and ps.space_id = s.id)
                      order by f2.created_at desc limit 1))
       from public.feedback f where f.created_at >= luni and exists (select 1 from public.profile_spaces ps where ps.user_id = f.to_user and ps.space_id = s.id)),
    -- marfa de azi pentru magazin și comenzile de mâine
    'livrari', (select jsonb_build_object('toate', count(*), 'livrate', count(*) filter (where l.stare = 'livrat'), 'probleme', count(*) filter (where l.stare = 'problema'))
       from public.livrari l where l.zi = azi and l.space_id = s.id and l.stare <> 'anulata' and (l.stare <> 'de_facut' or jsonb_array_length(public.liv_continut(l)) > 0)),
    'stoc', coalesce((select jsonb_agg(jsonb_build_object('nume', p.nume, 'grupa', p.grupa, 'unitate', p.unitate, 'minim', p.minim, 'cantitate', z.cantitate, 'zi', z.zi) order by p.grupa, p.position, p.nume)
       from public.stoc_produse p left join lateral (select z1.cantitate, z1.zi from public.stoc_zi z1 where z1.produs_id = p.id order by z1.zi desc limit 1) z on true
       where p.space_id = s.id and p.activ), '[]')
  ) order by s.position) from public.spaces s where public.can_see_space(s.id)), '[]');
end $$;
revoke all on function public.panou_sefi() from public, anon;
grant execute on function public.panou_sefi() to authenticated;
