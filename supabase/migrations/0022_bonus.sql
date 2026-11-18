-- =============================================================================
-- Ghidul echipei Madame Magnifique · Bonusul pe magazin, ținut în aplicație
--
-- Se rulează după 0021, în Supabase → SQL Editor. Se poate rula de mai multe ori.
-- Aici e doar mecanismul. Cifrele firmei (treptele, sumele, criteriile, vânzările de referință) se
-- încarcă separat, dintr-un fișier care nu stă în repo; până atunci pagina „Bonus” nu apare nimănui.
--
-- Cum se calculează bonusul unui magazin, pe o lună:
--   1. Creșterea an-la-an: media zilnică de vânzări a lunii față de aceeași lună a anului trecut.
--      Treapta de creștere dă fondul (sumă fixă), împărțit între vânzare (după aportul fiecăruia la
--      vânzări) și coacere. Magazin în declin (sub 0%): nu se plătește nimic din sistemul magazinului.
--   2. Conformitatea vânzării: sumă fixă, doar dacă toate criteriile sunt îndeplinite. Le evaluează
--      responsabilul de magazin; criteriul „proceduri” vine propus din fișele de deschidere / închidere.
--   3. Calitatea: cine vinde dă zilnic o notă produselor din vitrină; media lunii peste prag aduce
--      bonusul fix al celui care coace.
--   4. Bonusul de management: sumă împărțită egal pe criterii; cele de echipă se calculează singure,
--      cele individuale le bifează GM / AE.
--   Cine nu a încasat prima de calitate nu primește nimic din toate acestea.
-- GM sau AE închide bonusul lunii pe fiecare magazin; cifrele rămân înghețate.
-- Punctele (XP) nu aduc bani: măsoară doar criteriul „proceduri” și rămân pentru niveluri și clasament.
-- =============================================================================

create table if not exists public.bonus_setari (
  space_id              text primary key references public.spaces (id) on delete cascade,
  activ                 boolean not null default true,
  trepte                jsonb not null default '[]' check (jsonb_typeof(trepte) = 'array'),                -- [{"prag": 10, "fond": 1000}]: creștere % → fond (lei brut)
  procent_vanzare       numeric not null default 0 check (procent_vanzare between 0 and 100),
  procent_coacere       numeric not null default 0 check (procent_coacere between 0 and 100),
  conformitate_suma     numeric not null default 0 check (conformitate_suma >= 0),
  conformitate_criterii jsonb not null default '[]' check (jsonb_typeof(conformitate_criterii) = 'array'), -- [{"cheie": "…", "nume": "…", "auto": "proceduri"}]
  prag_proceduri        numeric not null default 100 check (prag_proceduri between 0 and 100),             -- % din fișe făcute, pentru propunerea automată
  calitate_suma         numeric not null default 0 check (calitate_suma >= 0),
  calitate_prag         numeric not null default 9.5 check (calitate_prag between 1 and 10),
  management_suma       numeric not null default 0 check (management_suma >= 0),
  management_criterii   jsonb not null default '[]' check (jsonb_typeof(management_criterii) = 'array'),   -- auto: "prima" | "conformitate" | "barem" | fără (îl bifează GM / AE)
  plafon_procent        numeric check (plafon_procent between 0 and 100),                                  -- cât din vânzările lunii poate costa sistemul (doar afișat)
  updated_at            timestamptz not null default now()
);
create table if not exists public.bonus_vanzari (
  space_id      text not null references public.spaces (id) on delete cascade,
  an            int not null check (an between 2000 and 2100),
  luna          int not null check (luna between 1 and 12),
  vanzari       numeric check (vanzari >= 0),               -- vânzarea lunii, fără TVA
  medie_zilnica numeric check (medie_zilnica >= 0),         -- media zilnică de vânzări: baza creșterii an-la-an
  bonuri_zi     numeric check (bonuri_zi >= 0),
  bon_mediu     numeric check (bon_mediu >= 0),
  updated_at    timestamptz not null default now(),
  primary key (space_id, an, luna)
);
create table if not exists public.bonus_luni (
  space_id        text not null references public.spaces (id) on delete cascade,
  luna            date not null check (luna = date_trunc('month', luna)::date),
  conformitate    jsonb not null default '{}',              -- {"cheie": {"ok": true, "nota": "…"}}
  conformitate_de uuid references public.profiles (user_id) on delete set null,
  conformitate_la timestamptz,
  management      jsonb not null default '{}',
  management_de   uuid references public.profiles (user_id) on delete set null,
  management_la   timestamptz,
  inchis_la       timestamptz,
  inchis_de       uuid references public.profiles (user_id) on delete set null,
  rezultat        jsonb,                                    -- fotografia calculului, la închidere
  primary key (space_id, luna)
);
create table if not exists public.bonus_oameni (
  space_id       text not null,
  luna           date not null,
  user_id        uuid not null references public.profiles (user_id) on delete cascade,
  fel            text not null check (fel in ('vanzare', 'coacere')),
  manager        boolean not null default false,
  aport          numeric not null default 0 check (aport >= 0),   -- vânzările omului în lună: după ele se împarte partea de vânzare
  prima_calitate boolean,                                         -- gol = încă nehotărât
  primary key (space_id, luna, user_id),
  foreign key (space_id, luna) references public.bonus_luni (space_id, luna) on delete cascade
);
create index if not exists bonus_oameni_om on public.bonus_oameni (user_id, luna desc);
create table if not exists public.note_calitate (
  space_id   text not null references public.spaces (id) on delete cascade,
  zi         date not null default (now() at time zone 'Europe/Bucharest')::date,
  user_id    uuid not null default auth.uid() references public.profiles (user_id) on delete cascade,
  nota       numeric(3, 1) not null check (nota between 1 and 10 and nota * 2 = floor(nota * 2)),
  comentariu text not null default '' check (length(comentariu) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (space_id, zi, user_id)
);

-- 1240.5 → „1.240,50”; 400 → „400”
create or replace function public.lei(n numeric)
returns text language sql immutable as $$
  select regexp_replace(translate(to_char(round(coalesce(n, 0), 2), 'FM999,999,990.00'), ',.', '.,'), ',00$', '')
$$;

-- Cine vede bonusul unei locații: GM / AE, oamenii din echipa ei de bonus și cei legați de locație în Admin.
create or replace function public.vede_bonus(s text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.sees_all()
    or exists (select 1 from public.bonus_oameni o where o.space_id = s and o.user_id = auth.uid())
    or (exists (select 1 from public.profile_spaces ps where ps.user_id = auth.uid() and ps.space_id = s)
        and exists (select 1 from public.space_roles sr where sr.space_id = s and sr.role_code = public.my_role())))
$$;
revoke all on function public.vede_bonus(text) from public, anon;
grant execute on function public.vede_bonus(text) to authenticated;

-- Luna de bonus a magazinului și echipa ei: se creează singure (din luna trecută sau din conturile legate de locație).
create or replace function public.bonus_asigura(p_space text, p_luna date)
returns void language plpgsql security definer set search_path = public as $$
declare l date := date_trunc('month', p_luna)::date; ant date := (date_trunc('month', p_luna) - interval '1 month')::date;
begin
  if exists (select 1 from public.bonus_luni where space_id = p_space and luna = l) then return; end if;
  if not exists (select 1 from public.bonus_setari where space_id = p_space and activ) then return; end if;
  insert into public.bonus_luni (space_id, luna) values (p_space, l) on conflict do nothing;
  if exists (select 1 from public.bonus_oameni where space_id = p_space and luna = ant) then
    insert into public.bonus_oameni (space_id, luna, user_id, fel, manager)
    select p_space, l, o.user_id, o.fel, o.manager
    from public.bonus_oameni o join public.profiles p on p.user_id = o.user_id and p.active
    where o.space_id = p_space and o.luna = ant on conflict do nothing;
  else
    insert into public.bonus_oameni (space_id, luna, user_id, fel, manager)
    select p_space, l, p.user_id, case when p.role_code = 'PP + B' then 'coacere' else 'vanzare' end, p.role_code = 'RL'
    from public.profiles p join public.profile_spaces ps on ps.user_id = p.user_id and ps.space_id = p_space
    where p.active and p.role_code in ('RL', 'VT', 'V', 'BAR', 'PP + B') on conflict do nothing;
  end if;
end $$;
revoke all on function public.bonus_asigura(text, date) from public, anon, authenticated;

-- Echipa unei luni închise nu se mai schimbă.
create or replace function public.bonus_om_protejat()
returns trigger language plpgsql set search_path = public as $$
declare r record;
begin
  if current_user = 'authenticated' then
    if tg_op = 'DELETE' then r := old; else r := new; end if;
    if exists (select 1 from public.bonus_luni b where b.space_id = r.space_id and b.luna = r.luna and b.inchis_la is not null) then
      raise exception 'Bonusul lunii e închis.';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists bonus_om_protejat on public.bonus_oameni;
create trigger bonus_om_protejat before insert or update or delete on public.bonus_oameni for each row execute function public.bonus_om_protejat();

alter table public.bonus_setari enable row level security;
alter table public.bonus_vanzari enable row level security;
alter table public.bonus_luni enable row level security;
alter table public.bonus_oameni enable row level security;
alter table public.note_calitate enable row level security;
revoke all on public.bonus_setari, public.bonus_vanzari, public.bonus_luni, public.bonus_oameni, public.note_calitate from anon, authenticated;
grant select, insert, update, delete on public.bonus_setari, public.bonus_vanzari, public.bonus_oameni to authenticated;
grant select on public.bonus_luni to authenticated;
grant select, insert on public.note_calitate to authenticated;
grant update (nota, comentariu) on public.note_calitate to authenticated;
grant all on public.bonus_setari, public.bonus_vanzari, public.bonus_luni, public.bonus_oameni, public.note_calitate to service_role;
drop policy if exists "regulile bonusului: echipa locației" on public.bonus_setari;
drop policy if exists "regulile bonusului le scrie conducerea" on public.bonus_setari;
create policy "regulile bonusului: echipa locației" on public.bonus_setari for select to authenticated using (public.vede_bonus(space_id));
create policy "regulile bonusului le scrie conducerea" on public.bonus_setari for all to authenticated
  using (public.sees_all()) with check (public.sees_all());
drop policy if exists "vânzările de referință: echipa locației" on public.bonus_vanzari;
drop policy if exists "vânzările le scrie conducerea" on public.bonus_vanzari;
create policy "vânzările de referință: echipa locației" on public.bonus_vanzari for select to authenticated using (public.vede_bonus(space_id));
create policy "vânzările le scrie conducerea" on public.bonus_vanzari for all to authenticated
  using (public.sees_all()) with check (public.sees_all());
-- luna (cu fotografia sumelor tuturor) o citește direct doar conducerea; ceilalți, prin bonus_calcul()
drop policy if exists "luna de bonus: conducerea" on public.bonus_luni;
create policy "luna de bonus: conducerea" on public.bonus_luni for select to authenticated using (public.sees_all());
drop policy if exists "echipa de bonus: rândul meu, iar conducerea toate" on public.bonus_oameni;
drop policy if exists "echipa de bonus o scrie conducerea" on public.bonus_oameni;
create policy "echipa de bonus: rândul meu, iar conducerea toate" on public.bonus_oameni for select to authenticated
  using (user_id = auth.uid() or public.sees_all());
create policy "echipa de bonus o scrie conducerea" on public.bonus_oameni for all to authenticated
  using (public.sees_all()) with check (public.sees_all());

-- ---------------------------------------------------------------------------
-- Nota zilnică de calitate a vitrinei
-- ---------------------------------------------------------------------------
-- O dă cine vinde, în tură la locația aceea, pentru ziua de azi.
create or replace function public.poate_nota(s text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.in_tura(s)
    and exists (select 1 from public.bonus_setari b where b.space_id = s and b.activ and b.calitate_suma > 0)
    and exists (select 1 from public.bonus_oameni o where o.space_id = s and o.user_id = auth.uid() and o.fel = 'vanzare'
                and o.luna = date_trunc('month', (now() at time zone 'Europe/Bucharest')::date)::date)
$$;
revoke all on function public.poate_nota(text) from public, anon;
grant execute on function public.poate_nota(text) to authenticated;

create or replace function public.nota_protejata()
returns trigger language plpgsql set search_path = public as $$
declare prag numeric;
begin
  if current_user = 'authenticated' then
    new.user_id := auth.uid(); new.zi := (now() at time zone 'Europe/Bucharest')::date; new.updated_at := now();
    if tg_op = 'UPDATE' then new.space_id := old.space_id; new.created_at := old.created_at; end if;
    select calitate_prag into prag from public.bonus_setari where space_id = new.space_id;
    if new.nota < coalesce(prag, 10) and length(trim(new.comentariu)) < 3 then
      raise exception 'La o notă sub %, scrie pe scurt ce nu a fost în regulă: cine coace trebuie să știe de ce.', replace(prag::text, '.', ',');
    end if;
  end if;
  return new;
end $$;
drop trigger if exists nota_protejata on public.note_calitate;
create trigger nota_protejata before insert or update on public.note_calitate for each row execute function public.nota_protejata();

-- O notă sub prag ajunge, cu motivul ei, la cine coace.
create or replace function public.nota_anunta()
returns trigger language plpgsql security definer set search_path = public as $$
declare prag numeric;
begin
  select calitate_prag into prag from public.bonus_setari where space_id = new.space_id;
  if new.nota < coalesce(prag, 0) and (tg_op = 'INSERT' or old.nota is distinct from new.nota or old.comentariu is distinct from new.comentariu) then
    insert into public.notifications (user_id, kind, title, body, url, space_id)
    select o.user_id, 'calitate', 'Nota vitrinei de azi la ' || public.nume_loc(new.space_id) || ': ' || replace(new.nota::text, '.', ','),
           '„' || left(new.comentariu, 200) || '” · ' || coalesce(public.nume_om(new.user_id), ''), '#/bonus', new.space_id
    from public.bonus_oameni o
    where o.space_id = new.space_id and o.fel = 'coacere' and o.user_id <> new.user_id
      and o.luna = date_trunc('month', new.zi)::date;
  end if;
  return new;
end $$;
drop trigger if exists nota_anunta on public.note_calitate;
create trigger nota_anunta after insert or update on public.note_calitate for each row execute function public.nota_anunta();

drop policy if exists "notele vitrinei: echipa locației și șefii" on public.note_calitate;
drop policy if exists "nota de azi o dă cine vinde, în tură" on public.note_calitate;
drop policy if exists "îmi schimb nota de azi" on public.note_calitate;
create policy "notele vitrinei: echipa locației și șefii" on public.note_calitate for select to authenticated
  using (public.vede_bonus(space_id) or (public.vede_echipa() and public.can_see_space(space_id)));
create policy "nota de azi o dă cine vinde, în tură" on public.note_calitate for insert to authenticated
  with check (user_id = auth.uid() and zi = (now() at time zone 'Europe/Bucharest')::date and public.poate_nota(space_id));
create policy "îmi schimb nota de azi" on public.note_calitate for update to authenticated
  using (user_id = auth.uid() and zi = (now() at time zone 'Europe/Bucharest')::date)
  with check (user_id = auth.uid() and public.poate_nota(space_id));

-- ---------------------------------------------------------------------------
-- Dovezile pentru criteriul „proceduri”: fișele de deschidere / închidere ale locației
-- ---------------------------------------------------------------------------
-- O fișă se așteaptă în fiecare zi lucrată (cu tură în program sau cu pontaj) și se socotește făcută dacă
-- e terminată până la 03:00 a doua zi. O lipsă a cărei contestație a fost admisă nu se numără.
create or replace function public.bonus_proceduri(p_space text, p_de date, p_pana date)
returns jsonb language sql stable security definer set search_path = public as $$
  with zile as (
    select distinct x.d as zi from (
      select s.day as d from public.shifts s where s.space_id = p_space and s.day between p_de and p_pana
      union
      select (c.clock_in at time zone 'Europe/Bucharest')::date from public.clockings c
      where c.space_id = p_space and (c.clock_in at time zone 'Europe/Bucharest')::date between p_de and p_pana) x
    where now() > ((x.d + 1)::timestamp + interval '3 hours') at time zone 'Europe/Bucharest'
  ), tipuri as (
    select k.tip from (values ('deschidere'), ('inchidere')) k (tip)
    where exists (select 1 from public.procedure_docs d where d.space_id = p_space and d.procedure_code is null
                  and d.role_code is null and d.source_file ilike 'Procedura_' || k.tip || '%')
  ), st as (
    select z.zi, t.tip, f.gata_la, f.la_termen,
           exists (select 1 from public.contestatii c join public.shifts s on s.id = split_part(c.cheie, ':', 2)::bigint
                   where c.status = 'admisa' and c.cheie like 'fisa-lipsa:%' and s.space_id = p_space and s.day = z.zi
                     and split_part(c.cheie, ':', 3) = left(t.tip, 1)) as scuzata
    from zile z cross join tipuri t
    cross join lateral (
      select min(r.finished_at) as gata_la, coalesce(bool_or(r.due_at is null or r.finished_at <= r.due_at), false) as la_termen
      from public.checklist_runs r join public.procedure_docs d on d.id = r.doc_id
      where r.space_id = p_space and r.day = z.zi and r.finished_at <= ((z.zi + 1)::timestamp + interval '3 hours') at time zone 'Europe/Bucharest'
        and d.procedure_code is null and d.role_code is null and d.source_file ilike 'Procedura_' || t.tip || '%') f
  ), pe_tip as (
    select tip, jsonb_build_object('asteptate', count(*), 'facute', count(gata_la), 'la_termen', count(*) filter (where gata_la is not null and la_termen),
             'scuzate', count(*) filter (where gata_la is null and scuzata)) as j from st group by tip
  )
  select jsonb_build_object(
    'zile', (select count(*) from zile),
    'deschideri', (select j from pe_tip where tip = 'deschidere'),
    'inchideri', (select j from pe_tip where tip = 'inchidere'),
    'procent', case when (select count(*) from st) > 0
                 then round(100.0 * (select count(*) from st where gata_la is not null or scuzata) / (select count(*) from st), 1) end,
    'lipsa', (select coalesce(jsonb_agg(jsonb_build_object('zi', zi, 'tip', tip) order by zi, tip), '[]') from st where gata_la is null and not scuzata),
    'ture', (select count(*) from public.shifts s where s.space_id = p_space and s.day between p_de and p_pana
               and public.tura_start(s) < now() - interval '10 minutes'),
    'ture_la_timp', (select count(*) from public.shifts s where s.space_id = p_space and s.day between p_de and p_pana
               and exists (select 1 from public.clockings c where c.shift_id = s.id and c.clock_in <= public.tura_start(s) + interval '5 minutes')))
$$;
revoke all on function public.bonus_proceduri(text, date, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Calculul întreg al unei luni (nefiltrat: îl folosesc bonus_calcul și bonus_inchide)
-- ---------------------------------------------------------------------------
create or replace function public.bonus_calcul_intern(p_space text, p_luna date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  l date := date_trunc('month', p_luna)::date; sf date; azi date := (now() at time zone 'Europe/Bucharest')::date;
  an_l int; luna_l int;
  st public.bonus_setari; bl public.bonus_luni; trecut public.bonus_vanzari; acum_ public.bonus_vanzari;
  crestere numeric; declin boolean; fond numeric; treapta jsonb;
  proc jsonb; propunere boolean; conf jsonb; conf_completa boolean; conf_ok boolean;
  cal_medie numeric; cal_zile int; cal_ok boolean;
  toti_prima boolean; vanz_prima boolean;
  mng jsonb; n_mng int; n_mng_ok int; mng_completa boolean;
  oameni jsonb; total_sistem numeric;
begin
  select * into st from public.bonus_setari where space_id = p_space;
  if st.space_id is null then return null; end if;
  sf := (l + interval '1 month')::date - 1; an_l := extract(year from l)::int; luna_l := extract(month from l)::int;
  select * into bl from public.bonus_luni where space_id = p_space and luna = l;
  select * into trecut from public.bonus_vanzari where space_id = p_space and an = an_l - 1 and luna = luna_l;
  select * into acum_ from public.bonus_vanzari where space_id = p_space and an = an_l and luna = luna_l;

  -- 1. creșterea an-la-an și treapta
  if trecut.medie_zilnica > 0 and acum_.medie_zilnica is not null then
    crestere := (acum_.medie_zilnica / trecut.medie_zilnica - 1) * 100; declin := crestere < 0;
    select t into treapta from jsonb_array_elements(st.trepte) t
    where (t ->> 'prag')::numeric <= crestere order by (t ->> 'prag')::numeric desc limit 1;
    fond := coalesce((treapta ->> 'fond')::numeric, 0);
  end if;

  -- 2. conformitatea: criteriile din setări, cu verdictul responsabilului; „proceduri” vine cu propunerea din fișe
  proc := public.bonus_proceduri(p_space, l, least(sf, azi));
  propunere := case when proc ->> 'procent' is null then null else (proc ->> 'procent')::numeric >= st.prag_proceduri end;
  select coalesce(jsonb_agg(jsonb_build_object('cheie', c ->> 'cheie', 'nume', c ->> 'nume', 'auto', c ->> 'auto',
             'ok', (bl.conformitate -> (c ->> 'cheie') ->> 'ok')::boolean,
             'nota', coalesce(bl.conformitate -> (c ->> 'cheie') ->> 'nota', ''),
             'propunere', case when c ->> 'auto' = 'proceduri' then propunere end) order by ord), '[]'),
         coalesce(bool_and(bl.conformitate -> (c ->> 'cheie') ->> 'ok' is not null), false),
         coalesce(bool_and(coalesce((bl.conformitate -> (c ->> 'cheie') ->> 'ok')::boolean, false)), false)
    into conf, conf_completa, conf_ok
  from jsonb_array_elements(st.conformitate_criterii) with ordinality as x (c, ord);

  -- 3. calitatea: media zilelor notate
  select round(avg(z.m), 2), count(*) into cal_medie, cal_zile
  from (select avg(nota) as m from public.note_calitate where space_id = p_space and zi between l and sf group by zi) z;
  cal_ok := cal_medie is not null and cal_medie >= st.calitate_prag;

  -- 4. managementul: criteriile de echipă se calculează, cele individuale le bifează conducerea
  select coalesce(bool_and(prima_calitate is true), true), coalesce(bool_and(prima_calitate is true) filter (where fel = 'vanzare'), true)
    into toti_prima, vanz_prima
  from public.bonus_oameni where space_id = p_space and luna = l and not manager;
  select coalesce(jsonb_agg(jsonb_build_object('cheie', y.k, 'nume', y.nume, 'auto', y.auto, 'ok', y.ok, 'nota', y.nota) order by y.ord), '[]'),
         count(*), count(*) filter (where y.ok), coalesce(bool_and(y.ok is not null) filter (where y.auto is null), true)
    into mng, n_mng, n_mng_ok, mng_completa
  from (select c ->> 'cheie' as k, c ->> 'nume' as nume, c ->> 'auto' as auto, ord,
               case c ->> 'auto' when 'prima' then toti_prima
                                 when 'conformitate' then conf_ok and vanz_prima and declin is false
                                 when 'barem' then toti_prima and fond > 0
                                 else (bl.management -> (c ->> 'cheie') ->> 'ok')::boolean end as ok,
               coalesce(bl.management -> (c ->> 'cheie') ->> 'nota', '') as nota
        from jsonb_array_elements(st.management_criterii) with ordinality as x (c, ord)) y;

  -- 5. sumele fiecăruia (brut). Fără prima de calitate: nimic. Până se introduc vânzările lunii, partea de magazin e necunoscută.
  with m as (
    select o.user_id, o.fel, o.manager, o.aport, o.prima_calitate, p.full_name, p.role_code,
           sum(o.aport) filter (where o.fel = 'vanzare') over () as sa,
           count(*) filter (where o.fel = 'vanzare') over () as nv,
           count(*) filter (where o.fel = 'coacere') over () as nc
    from public.bonus_oameni o left join public.profiles p on p.user_id = o.user_id
    where o.space_id = p_space and o.luna = l
  ), c as (
    select m.*, case when m.fel <> 'vanzare' then null when m.sa > 0 then m.aport / m.sa else 1.0 / nullif(m.nv, 0) end as cota,
           case when m.prima_calitate is false then 0 else 1 end as acces
    from m
  ), s as (
    select c.*,
      case when crestere is null then null
           else round(c.acces * case when c.fel = 'vanzare' then fond * st.procent_vanzare / 100 * c.cota
                                     else fond * st.procent_coacere / 100 / nullif(c.nc, 0) end, 2) end as barem,
      case when c.fel <> 'vanzare' then 0 when crestere is null then null
           else round(c.acces * case when conf_ok and not declin then st.conformitate_suma * c.cota else 0 end, 2) end as conformitate,
      case when c.fel <> 'coacere' then 0 when crestere is null then null
           else round(c.acces * case when cal_ok and not declin then st.calitate_suma / nullif(c.nc, 0) else 0 end, 2) end as calitate,
      case when not c.manager or n_mng = 0 then 0
           else round(c.acces * st.management_suma / n_mng * n_mng_ok, 2) end as management
    from c
  )
  select coalesce(jsonb_agg(jsonb_build_object('user_id', s.user_id, 'nume', coalesce(s.full_name, '—'), 'rol', coalesce(s.role_code, ''),
             'fel', s.fel, 'manager', s.manager, 'aport', s.aport, 'cota', round(s.cota * 100, 1), 'cota_egala', s.fel = 'vanzare' and coalesce(s.sa, 0) = 0,
             'prima_calitate', s.prima_calitate, 'barem', s.barem, 'conformitate', s.conformitate, 'calitate', s.calitate,
             'management', s.management,
             'total', coalesce(s.barem, 0) + coalesce(s.conformitate, 0) + coalesce(s.calitate, 0) + s.management)
           order by s.manager desc, s.fel desc, s.full_name), '[]'),
         sum(coalesce(s.barem, 0) + coalesce(s.conformitate, 0) + coalesce(s.calitate, 0))
    into oameni, total_sistem
  from s;

  return jsonb_build_object(
    'space_id', p_space, 'luna', l, 'activ', st.activ, 'pornita', bl.luna is not null,
    'setari', jsonb_build_object('trepte', st.trepte, 'procent_vanzare', st.procent_vanzare, 'procent_coacere', st.procent_coacere,
        'conformitate_suma', st.conformitate_suma, 'conformitate_criterii', st.conformitate_criterii, 'prag_proceduri', st.prag_proceduri,
        'calitate_suma', st.calitate_suma, 'calitate_prag', st.calitate_prag, 'management_suma', st.management_suma,
        'management_criterii', st.management_criterii, 'plafon_procent', st.plafon_procent),
    'vanzari', jsonb_build_object(
        'an_trecut', case when trecut.space_id is null then null else jsonb_build_object('an', an_l - 1, 'vanzari', trecut.vanzari,
            'medie_zilnica', trecut.medie_zilnica, 'bonuri_zi', trecut.bonuri_zi, 'bon_mediu', trecut.bon_mediu) end,
        'acum', case when acum_.space_id is null then null else jsonb_build_object('an', an_l, 'vanzari', acum_.vanzari,
            'medie_zilnica', acum_.medie_zilnica, 'bonuri_zi', acum_.bonuri_zi, 'bon_mediu', acum_.bon_mediu) end,
        'crestere', round(crestere, 1), 'declin', declin, 'treapta', treapta, 'fond', fond,
        'repere', (select coalesce(jsonb_agg(jsonb_build_object('prag', (t ->> 'prag')::numeric, 'fond', (t ->> 'fond')::numeric,
                     'medie_necesara', case when trecut.medie_zilnica > 0 then ceil(trecut.medie_zilnica * (1 + (t ->> 'prag')::numeric / 100)) end)
                     order by (t ->> 'prag')::numeric), '[]') from jsonb_array_elements(st.trepte) t)),
    'proceduri', proc || jsonb_build_object('propunere', propunere),
    'dovezi', jsonb_build_object(
        'reclamatii', (select coalesce(jsonb_agg(jsonb_build_object('zi', (g.created_at at time zone 'Europe/Bucharest')::date, 'text', left(g.text, 160),
                         'status', g.status) order by g.created_at), '[]')
                       from public.semnalari g where g.space_id = p_space and g.categorie = 'client' and g.status <> 'respinsa'
                         and (g.created_at at time zone 'Europe/Bucharest')::date between l and sf),
        'aprecieri', (select count(*) from public.feedback f join public.bonus_oameni o on o.user_id = f.to_user and o.space_id = p_space and o.luna = l
                      where f.fel = 'apreciere' and (f.created_at at time zone 'Europe/Bucharest')::date between l and sf),
        'observatii', (select count(*) from public.feedback f join public.bonus_oameni o on o.user_id = f.to_user and o.space_id = p_space and o.luna = l
                       where f.fel = 'imbunatatire' and (f.created_at at time zone 'Europe/Bucharest')::date between l and sf)),
    'conformitate', jsonb_build_object('criterii', conf, 'completa', conf_completa, 'indeplinita', conf_ok,
        'de', public.nume_om(bl.conformitate_de), 'la', bl.conformitate_la),
    'calitate', jsonb_build_object('medie', cal_medie, 'zile', cal_zile, 'prag', st.calitate_prag, 'indeplinit', cal_ok,
        'note', (select coalesce(jsonb_agg(jsonb_build_object('zi', n.zi, 'nota', n.nota, 'comentariu', n.comentariu, 'cine', public.nume_om(n.user_id))
                   order by n.zi desc, n.created_at desc), '[]')
                 from public.note_calitate n where n.space_id = p_space and n.zi between l and sf)),
    'management', jsonb_build_object('criterii', mng, 'completa', mng_completa, 'indeplinite', n_mng_ok, 'total', n_mng,
        'pe_criteriu', case when n_mng > 0 then round(st.management_suma / n_mng, 2) end, 'de', public.nume_om(bl.management_de), 'la', bl.management_la),
    'oameni', oameni,
    'plafon', jsonb_build_object('total_sistem', total_sistem, 'vanzari', acum_.vanzari,
        'procent', case when acum_.vanzari > 0 then round(100 * total_sistem / acum_.vanzari, 1) end, 'plafon', st.plafon_procent));
end $$;
revoke all on function public.bonus_calcul_intern(text, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Ce vede fiecare: sumele mele; conducerea, pe ale tuturor
-- ---------------------------------------------------------------------------
create or replace function public.bonus_calcul(p_space text, p_luna date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; l date; bl public.bonus_luni; r jsonb; eu jsonb; adm boolean;
begin
  if not public.vede_bonus(p_space) then raise exception 'Nu vezi bonusul acestei locații.'; end if;
  l := date_trunc('month', coalesce(p_luna, azi))::date;
  if l = date_trunc('month', azi)::date then perform public.bonus_asigura(p_space, l); end if;
  select * into bl from public.bonus_luni where space_id = p_space and luna = l;
  r := case when bl.inchis_la is not null then bl.rezultat else public.bonus_calcul_intern(p_space, l) end;
  if r is null then return jsonb_build_object('space_id', p_space, 'luna', l, 'activ', false); end if;
  adm := public.sees_all();
  select o into eu from jsonb_array_elements(r -> 'oameni') o where o ->> 'user_id' = auth.uid()::text;
  if not adm then
    -- ceilalți oameni: doar cine sunt și ce fac; fără sume, aport sau prima lor
    r := jsonb_set(r, '{oameni}', (select coalesce(jsonb_agg(case when o ->> 'user_id' = auth.uid()::text then o
            else jsonb_build_object('user_id', o -> 'user_id', 'nume', o -> 'nume', 'rol', o -> 'rol', 'fel', o -> 'fel', 'manager', o -> 'manager') end), '[]')
          from jsonb_array_elements(r -> 'oameni') o)) - 'plafon';
    if coalesce((eu ->> 'manager')::boolean, false) is not true then r := r - 'management'; end if;
  end if;
  return r || jsonb_build_object('eu', eu, 'pot_administra', adm,
    'pot_evalua', bl.inchis_la is null and (adm or coalesce((eu ->> 'manager')::boolean, false)),
    'inchisa', case when bl.inchis_la is null then null else jsonb_build_object('la', bl.inchis_la, 'de', public.nume_om(bl.inchis_de)) end,
    'luna_terminata', now() >= ((l + interval '1 month')::timestamp at time zone 'Europe/Bucharest'),
    'luni', (select jsonb_agg(jsonb_build_object('luna', m::date,
               'inchisa', exists (select 1 from public.bonus_luni b where b.space_id = p_space and b.luna = m::date and b.inchis_la is not null)) order by m desc)
             from (select date_trunc('month', azi)::date - (k || ' months')::interval as m from generate_series(0, 5) k) y));
end $$;
revoke all on function public.bonus_calcul(text, date) from public, anon;
grant execute on function public.bonus_calcul(text, date) to authenticated;

-- Conducerea pornește de mână o lună mai veche (cea în curs se pornește singură).
create or replace function public.bonus_porneste(p_space text, p_luna date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.sees_all() then raise exception 'Luna de bonus o pornește GM sau AE.'; end if;
  if not exists (select 1 from public.bonus_setari where space_id = p_space and activ) then
    raise exception 'Pentru locația asta bonusul nu e configurat.'; end if;
  perform public.bonus_asigura(p_space, p_luna);
end $$;
revoke all on function public.bonus_porneste(text, date) from public, anon;
grant execute on function public.bonus_porneste(text, date) to authenticated;

-- Locațiile la care am pagina „Bonus”.
create or replace function public.bonus_locatii()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(b.space_id order by s.position), '[]')
  from public.bonus_setari b join public.spaces s on s.id = b.space_id
  where b.activ and public.vede_bonus(b.space_id)
$$;
revoke all on function public.bonus_locatii() from public, anon;
grant execute on function public.bonus_locatii() to authenticated;

-- Pentru pagina „Tura”: pot da azi nota vitrinei, și ce notă am dat?
create or replace function public.bonus_azi()
returns jsonb language plpgsql security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; loc text; l date;
begin
  if not public.is_member() then return null; end if;
  select space_id into loc from public.clockings where user_id = auth.uid() and clock_out is null order by clock_in desc limit 1;
  if loc is null or not exists (select 1 from public.bonus_setari where space_id = loc and activ) then return null; end if;
  l := date_trunc('month', azi)::date;
  perform public.bonus_asigura(loc, l);
  return jsonb_build_object('space_id', loc, 'pot_nota', public.poate_nota(loc),
    'prag', (select calitate_prag from public.bonus_setari where space_id = loc),
    'nota_mea', (select jsonb_build_object('nota', n.nota, 'comentariu', n.comentariu) from public.note_calitate n
                 where n.space_id = loc and n.zi = azi and n.user_id = auth.uid()),
    'medie_luna', (select round(avg(z.m), 2) from (select avg(nota) as m from public.note_calitate where space_id = loc and zi >= l group by zi) z),
    'zile_notate', (select count(distinct zi) from public.note_calitate where space_id = loc and zi >= l));
end $$;
revoke all on function public.bonus_azi() from public, anon;
grant execute on function public.bonus_azi() to authenticated;

-- ---------------------------------------------------------------------------
-- Evaluarea criteriilor
-- ---------------------------------------------------------------------------
-- p_ce = 'conformitate' (responsabilul de magazin sau conducerea) | 'management' (doar conducerea, doar criteriile fără calcul automat)
-- p_valori = {"cheie": {"ok": true, "nota": "…"}}
create or replace function public.bonus_evalueaza(p_space text, p_luna date, p_ce text, p_valori jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare l date := date_trunc('month', p_luna)::date; bl public.bonus_luni; st public.bonus_setari; calc jsonb; c jsonb; k text; v jsonb;
        curat jsonb := '{}'; criterii jsonb; complet boolean; toate boolean;
        nume_luna text[] := array['ianuarie','februarie','martie','aprilie','mai','iunie','iulie','august','septembrie','octombrie','noiembrie','decembrie'];
begin
  if p_ce not in ('conformitate', 'management') then raise exception 'Nu știu ce să evaluez.'; end if;
  perform public.bonus_asigura(p_space, l);
  select * into bl from public.bonus_luni where space_id = p_space and luna = l;
  select * into st from public.bonus_setari where space_id = p_space;
  if bl.luna is null or st.space_id is null then raise exception 'Bonusul nu e pornit pentru locația și luna asta.'; end if;
  if bl.inchis_la is not null then raise exception 'Bonusul lunii e închis.'; end if;
  if p_ce = 'management' and not public.sees_all() then raise exception 'Criteriile de management le bifează GM sau AE.'; end if;
  if p_ce = 'conformitate' and not (public.sees_all() or exists (select 1 from public.bonus_oameni o
       where o.space_id = p_space and o.luna = l and o.user_id = auth.uid() and o.manager)) then
    raise exception 'Conformitatea o evaluează responsabilul de magazin.';
  end if;
  criterii := case p_ce when 'conformitate' then st.conformitate_criterii else st.management_criterii end;
  calc := public.bonus_calcul_intern(p_space, l);
  for k, v in select * from jsonb_each(coalesce(p_valori, '{}')) loop
    select x into c from jsonb_array_elements(criterii) x where x ->> 'cheie' = k;
    if c is null then raise exception 'Criteriu necunoscut: %', k; end if;
    if p_ce = 'management' and c ->> 'auto' is not null then raise exception 'Criteriul „%” se calculează singur.', c ->> 'nume'; end if;
    if jsonb_typeof(v -> 'ok') is distinct from 'boolean' then raise exception 'La „%” lipsește verdictul.', c ->> 'nume'; end if;
    -- verdictul care contrazice fișele se motivează în scris
    if c ->> 'auto' = 'proceduri' and (calc -> 'proceduri' ->> 'propunere') is not null
       and (v ->> 'ok')::boolean is distinct from (calc -> 'proceduri' ->> 'propunere')::boolean
       and length(trim(coalesce(v ->> 'nota', ''))) < 5 then
      raise exception 'La „%” verdictul tău diferă de ce arată fișele: scrie de ce.', c ->> 'nume';
    end if;
    if not (v ->> 'ok')::boolean and length(trim(coalesce(v ->> 'nota', ''))) < 3 and c ->> 'auto' is distinct from 'proceduri' then
      raise exception 'La „%” scrie pe scurt de ce nu e îndeplinit: omul trebuie să știe de ce pierde.', c ->> 'nume';
    end if;
    curat := curat || jsonb_build_object(k, jsonb_build_object('ok', (v ->> 'ok')::boolean, 'nota', trim(coalesce(v ->> 'nota', ''))));
  end loop;
  if p_ce = 'conformitate' then
    update public.bonus_luni set conformitate = conformitate || curat, conformitate_de = auth.uid(), conformitate_la = now()
    where space_id = p_space and luna = l returning conformitate into curat;
    select bool_and(curat -> (x ->> 'cheie') ->> 'ok' is not null), bool_and(coalesce((curat -> (x ->> 'cheie') ->> 'ok')::boolean, false))
      into complet, toate from jsonb_array_elements(criterii) x;
    if complet then   -- cei care vând află verdictul și, dacă e cazul, criteriul căzut
      insert into public.notifications (user_id, kind, title, body, url, space_id)
      select o.user_id, 'bonus', 'Conformitatea pe ' || nume_luna[extract(month from l)::int] || ' la ' || public.nume_loc(p_space) || ': '
               || case when toate then 'îndeplinită' else 'neîndeplinită' end,
             case when toate then 'Toate criteriile sunt îndeplinite.' else 'Neîndeplinit: ' || (
               select string_agg((x ->> 'nume') || coalesce(' — ' || nullif(curat -> (x ->> 'cheie') ->> 'nota', ''), ''), '; ')
               from jsonb_array_elements(criterii) x where not (curat -> (x ->> 'cheie') ->> 'ok')::boolean) end
               || ' · ' || coalesce(public.nume_om(auth.uid()), ''), '#/bonus', p_space
      from public.bonus_oameni o where o.space_id = p_space and o.luna = l and o.fel = 'vanzare' and o.user_id <> auth.uid();
    end if;
  else
    update public.bonus_luni set management = management || curat, management_de = auth.uid(), management_la = now()
    where space_id = p_space and luna = l;
  end if;
end $$;
revoke all on function public.bonus_evalueaza(text, date, text, jsonb) from public, anon;
grant execute on function public.bonus_evalueaza(text, date, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Închiderea bonusului unei luni, pe magazin
-- ---------------------------------------------------------------------------
create or replace function public.bonus_inchide(p_space text, p_luna date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l date := date_trunc('month', p_luna)::date; sf date; bl public.bonus_luni; r jsonb; n int;
        nume_luna text[] := array['ianuarie','februarie','martie','aprilie','mai','iunie','iulie','august','septembrie','octombrie','noiembrie','decembrie'];
begin
  if not public.sees_all() then raise exception 'Bonusul lunii îl închide GM sau AE.'; end if;
  sf := (l + interval '1 month')::date - 1;
  if now() < ((sf + 1)::timestamp at time zone 'Europe/Bucharest') then raise exception 'Luna nu s-a terminat încă.'; end if;
  select * into bl from public.bonus_luni where space_id = p_space and luna = l;
  if bl.luna is null then raise exception 'Bonusul nu e pornit pentru locația și luna asta.'; end if;
  if bl.inchis_la is not null then raise exception 'Bonusul lunii e deja închis.'; end if;
  r := public.bonus_calcul_intern(p_space, l);
  if r -> 'vanzari' ->> 'crestere' is null then raise exception 'Lipsesc vânzările: media zilnică a lunii și a aceleiași luni de anul trecut.'; end if;
  if jsonb_array_length(r -> 'oameni') = 0 then raise exception 'Echipa lunii e goală.'; end if;
  if exists (select 1 from public.bonus_oameni where space_id = p_space and luna = l and prima_calitate is null) then
    raise exception 'Bifează pentru fiecare om dacă a încasat prima de calitate.'; end if;
  if exists (select 1 from public.bonus_oameni where space_id = p_space and luna = l and fel = 'vanzare')
     and jsonb_array_length(r -> 'conformitate' -> 'criterii') > 0 and not (r -> 'conformitate' ->> 'completa')::boolean then
    raise exception 'Conformitatea nu e evaluată la toate criteriile.'; end if;
  if exists (select 1 from public.bonus_oameni where space_id = p_space and luna = l and manager)
     and not (r -> 'management' ->> 'completa')::boolean then
    raise exception 'Criteriile de management nu sunt toate bifate.'; end if;
  select count(*) into n from public.contestatii c join public.bonus_oameni o on o.user_id = c.user_id and o.space_id = p_space and o.luna = l
  where c.status = 'deschisa' and c.zi between l and sf;
  if n > 0 then raise exception 'Mai sunt % contestații nedecise ale echipei pentru luna asta. Decide-le întâi.', n; end if;
  update public.bonus_luni set rezultat = r, inchis_la = now(), inchis_de = auth.uid() where space_id = p_space and luna = l;
  insert into public.notifications (user_id, kind, title, body, url, space_id)
  select (o ->> 'user_id')::uuid, 'bonus', 'Bonusul pe ' || nume_luna[extract(month from l)::int] || ' la ' || public.nume_loc(p_space) || ': '
           || public.lei((o ->> 'total')::numeric) || ' lei brut',
         'Vezi în aplicație din ce se compune și de ce.', '#/bonus', p_space
  from jsonb_array_elements(r -> 'oameni') o join public.profiles p on p.user_id = (o ->> 'user_id')::uuid and p.active;
  return r -> 'plafon';
end $$;
revoke all on function public.bonus_inchide(text, date) from public, anon;
grant execute on function public.bonus_inchide(text, date) to authenticated;

create or replace function public.bonus_redeschide(p_space text, p_luna date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Bonusul lunii îl redeschide doar adminul.'; end if;
  update public.bonus_luni set inchis_la = null, inchis_de = null, rezultat = null
  where space_id = p_space and luna = date_trunc('month', p_luna)::date;
end $$;
revoke all on function public.bonus_redeschide(text, date) from public, anon;
grant execute on function public.bonus_redeschide(text, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Punctele nu sunt bani: textul notificării de la închiderea lunii de puncte (0021) nu mai pomenește bonusul.
-- ---------------------------------------------------------------------------
create or replace function public.inchide_luna(p_luna date)
returns int language plpgsql security definer set search_path = public as $$
declare l date := date_trunc('month', p_luna)::date; sf date; n int;
        nume_luna text[] := array['ianuarie','februarie','martie','aprilie','mai','iunie','iulie','august','septembrie','octombrie','noiembrie','decembrie'];
begin
  if not public.sees_all() then raise exception 'Luna o închide GM sau AE.'; end if;
  sf := (l + interval '1 month')::date - 1;
  if now() < ((sf + 1)::timestamp + interval '3 hours') at time zone 'Europe/Bucharest' then
    raise exception 'Luna se poate închide din % ora 03:00.', to_char(sf + 1, 'DD.MM.YYYY'); end if;
  if public.luna_inchisa(l) then raise exception 'Luna e deja închisă.'; end if;
  select count(*) into n from public.contestatii where status = 'deschisa' and zi between l and sf;
  if n > 0 then raise exception 'Mai sunt % contestații nedecise pentru luna asta. Decide-le întâi.', n; end if;
  insert into public.luni_inchise (luna, inchis_de) values (l, auth.uid());
  with ev as (select * from public.xp_evenimente(l, sf)),
       tot as (select user_id, coalesce(sum(puncte) filter (where puncte > 0), 0) as c,
                      coalesce(-sum(puncte) filter (where puncte < 0), 0) as p, coalesce(sum(puncte), 0) as net from ev group by user_id),
       srs as (select user_id, jsonb_object_agg(sursa, jsonb_build_object('plus', plus, 'minus', minus)) as j from (
                 select user_id, sursa, coalesce(sum(puncte) filter (where puncte > 0), 0) as plus,
                        coalesce(-sum(puncte) filter (where puncte < 0), 0) as minus from ev group by user_id, sursa) x group by user_id),
       prd as (select user_id, jsonb_agg(jsonb_build_object('zi', zi, 'puncte', puncte, 'detaliu', detaliu) order by la) as j
               from ev where puncte < 0 group by user_id)
  insert into public.puncte_luna (luna, user_id, nume, rol, locatie, castigat, pierdut, net, surse, pierderi, ture, ture_la_timp)
  select l, t.user_id, coalesce(pr.full_name, '—'), coalesce(pr.role_code, ''), public.locatia_omului(t.user_id),
         t.c, t.p, t.net, coalesce(s.j, '{}'), coalesce(d.j, '[]'),
         (select count(*) from public.shifts h where h.user_id = t.user_id and h.day between l and sf),
         (select count(*) from public.shifts h where h.user_id = t.user_id and h.day between l and sf
            and exists (select 1 from public.clockings k where k.shift_id = h.id and k.clock_in <= public.tura_start(h) + interval '5 minutes'))
  from tot t left join srs s on s.user_id = t.user_id left join prd d on d.user_id = t.user_id
  left join public.profiles pr on pr.user_id = t.user_id;
  get diagnostics n = row_count;
  insert into public.notifications (user_id, kind, title, body, url)
  select pl.user_id, 'luna', 'Luna ' || nume_luna[extract(month from l)::int] || ' s-a închis: ' || pl.net || ' XP',
         'Câștigate ' || pl.castigat || ', pierdute ' || pl.pierdut || '. Punctele lunii rămân înghețate.', '#/progres'
  from public.puncte_luna pl join public.profiles p on p.user_id = pl.user_id and p.active where pl.luna = l;
  return n;
end $$;
revoke all on function public.inchide_luna(date) from public, anon;
grant execute on function public.inchide_luna(date) to authenticated;

do $$ declare t text; begin
  foreach t in array array['note_calitate', 'bonus_luni', 'bonus_oameni'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
              when undefined_object then raise notice 'publicația supabase_realtime lipsește (mediu local)';
    end;
  end loop;
end $$;
