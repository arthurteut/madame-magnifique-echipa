-- 0033 · Lista de contacte, acoperirea pe ore și sarcinile din agendă care se bifează singure
--
--   contacte            oameni și firme de sunat: echipă, furnizori, service, urgențe (o țin șefii)
--   acoperire_necesar   câți oameni trebuie să fie în magazin, pe intervale orare
--   agenda_sarcini.auto sarcina se consideră făcută când există datele zilei (încasări, nota zilei)
-- Se poate rula de mai multe ori. Cere 0030_agenda.sql.

-- ---------------------------------------------------------------------------
-- Contacte
-- ---------------------------------------------------------------------------
create table if not exists public.contacte (
  id       bigint generated always as identity primary key,
  grupa    text not null default 'Echipă' check (grupa in ('Echipă', 'Conducere', 'Producție', 'Furnizori', 'Service', 'Urgențe', 'Altele')),
  nume     text not null check (length(trim(nume)) between 2 and 120),
  rol      text not null default '',
  telefon  text not null default '',
  email    text not null default '',
  space_id text references public.spaces(id) on update cascade on delete set null,
  nota     text not null default '',
  position int not null default 0,
  pus_de   uuid default auth.uid(),
  pus_la   timestamptz not null default now()
);
alter table public.contacte enable row level security;
revoke all on public.contacte from anon, authenticated;
grant select, insert, update, delete on public.contacte to authenticated;
grant all on public.contacte to service_role;
drop policy if exists "contacte: le vede echipa" on public.contacte;
create policy "contacte: le vede echipa" on public.contacte for select to authenticated using (public.is_member());
drop policy if exists "contacte: le tin sefii" on public.contacte;
create policy "contacte: le tin sefii" on public.contacte for all to authenticated using (public.vede_echipa()) with check (public.vede_echipa());

-- ---------------------------------------------------------------------------
-- Acoperirea pe ore
-- ---------------------------------------------------------------------------
create table if not exists public.acoperire_necesar (
  id       bigint generated always as identity primary key,
  space_id text not null references public.spaces(id) on update cascade on delete cascade,
  zi_sapt  int check (zi_sapt between 1 and 7),             -- gol = în fiecare zi; 1 = luni … 7 = duminică
  de_la    time not null,
  pana     time not null,
  oameni   int not null check (oameni between 1 and 20),
  nota     text not null default '',
  check (pana > de_la)
);
alter table public.acoperire_necesar enable row level security;
revoke all on public.acoperire_necesar from anon, authenticated;
grant all on public.acoperire_necesar to service_role;

-- Săptămâna unei locații, oră cu oră: câți oameni sunt puși în program și câți trebuie.
create or replace function public.acoperire(p_space text, p_luni date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare luni date := date_trunc('week', coalesce(p_luni, (now() at time zone 'Europe/Bucharest')::date))::date; h0 int; h1 int;
begin
  if not public.vede_echipa() or not public.can_see_space(p_space) then raise exception 'Acoperirea o văd șefii locației.'; end if;
  select least(coalesce(min(extract(hour from x.a)), 7), 7)::int, greatest(coalesce(max(extract(hour from x.b - interval '1 minute')), 20), 20)::int into h0, h1
    from (select starts a, ends b from public.shifts where space_id = p_space and day between luni and luni + 6 and ends > starts
          union all select de_la, pana from public.acoperire_necesar where space_id = p_space) x;
  return jsonb_build_object('space_id', p_space, 'luni', luni, 'azi', (now() at time zone 'Europe/Bucharest')::date, 'de_la', h0, 'pana', h1,
    'zile', (select jsonb_agg(jsonb_build_object('zi', z.zi, 'ore', (select jsonb_agg(jsonb_build_object('h', h,
          'pusi', (select count(*) from public.shifts s where s.space_id = p_space and s.day = z.zi and s.starts < make_time(h, 59, 59) and s.ends > make_time(h, 0, 0)),
          'necesar', (select max(n.oameni) from public.acoperire_necesar n where n.space_id = p_space and (n.zi_sapt is null or n.zi_sapt = extract(isodow from z.zi))
                       and n.de_la <= make_time(h, 0, 0) and n.pana > make_time(h, 0, 0))) order by h) from generate_series(h0, h1) h)) order by z.zi)
      from (select (luni + i)::date as zi from generate_series(0, 6) i) z),
    'necesar', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'zi_sapt', n.zi_sapt, 'de_la', to_char(n.de_la, 'HH24:MI'), 'pana', to_char(n.pana, 'HH24:MI'), 'oameni', n.oameni, 'nota', n.nota)
      order by n.zi_sapt nulls first, n.de_la) from public.acoperire_necesar n where n.space_id = p_space), '[]'));
end $$;
revoke all on function public.acoperire(text, date) from public, anon;
grant execute on function public.acoperire(text, date) to authenticated;

create or replace function public.acoperire_pune(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not public.vede_echipa() or not public.can_see_space(p ->> 'space_id') then raise exception 'Necesarul de oameni îl pun șefii locației.'; end if;
  insert into public.acoperire_necesar (space_id, zi_sapt, de_la, pana, oameni, nota)
  values (p ->> 'space_id', nullif(p ->> 'zi_sapt', '')::int, (p ->> 'de_la')::time, (p ->> 'pana')::time, (p ->> 'oameni')::int, coalesce(trim(p ->> 'nota'), ''))
  returning id into v_id;
  return v_id;
end $$;
create or replace function public.acoperire_sterge(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.vede_echipa() or not exists (select 1 from public.acoperire_necesar n where n.id = p_id and public.can_see_space(n.space_id)) then
    raise exception 'Necesarul de oameni îl pun șefii locației.'; end if;
  delete from public.acoperire_necesar where id = p_id;
end $$;
revoke all on function public.acoperire_pune(jsonb), public.acoperire_sterge(bigint) from public, anon;
grant execute on function public.acoperire_pune(jsonb), public.acoperire_sterge(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Agenda: sarcini care se bifează singure din datele zilei
-- ---------------------------------------------------------------------------
alter table public.agenda_sarcini add column if not exists auto text check (auto in ('incasari', 'nota'));

create or replace function public.agenda_stare(s public.agenda_sarcini, p_space text, p_azi date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare de_la date; pana date; facute int; bifat boolean; stare text; termen date; ramase int;
begin
  if s.ritm = 'lunar' then de_la := date_trunc('month', p_azi)::date; pana := (date_trunc('month', p_azi) + interval '1 month - 1 day')::date;
  elsif s.ritm = 'zilnic' then de_la := p_azi; pana := p_azi;
  else de_la := date_trunc('week', p_azi)::date; pana := de_la + 6; end if;
  if s.auto = 'incasari' then
    select count(*), coalesce(bool_or(i.zi = p_azi), false) into facute, bifat from public.incasari_zi i where i.space_id = p_space and i.zi between de_la and pana;
  elsif s.auto = 'nota' then
    select count(*), coalesce(bool_or(n.zi = p_azi), false) into facute, bifat from public.nota_zilei n where n.space_id = p_space and n.zi between de_la and pana;
  else
    select count(*), coalesce(bool_or(b.zi = p_azi), false) into facute, bifat from public.agenda_bife b
     where b.sarcina_id = s.id and b.space_id = p_space and b.zi between de_la and pana;
  end if;
  ramase := pana - p_azi + 1;
  if s.ritm = 'la_nevoie' then stare := 'la_nevoie';
  elsif s.ritm = 'zilnic' then stare := case when bifat then 'gata' else 'azi' end;
  elsif facute >= s.tinta then stare := 'gata';
  else
    termen := case when s.ritm = 'lunar' and s.zi_luna is not null then public.agenda_zi_luna(s.zi_luna, p_azi)
                   when s.ritm = 'saptamanal' and s.zi_sapt is not null then de_la + s.zi_sapt - 1 end;
    stare := case when termen is not null and p_azi > termen then 'intarziata'
                  when termen = p_azi and not bifat then 'azi'
                  when termen is null and not bifat and ramase <= s.tinta - facute then 'azi'
                  else 'in_curs' end;
  end if;
  return jsonb_build_object('facute', facute, 'bifat_azi', bifat, 'stare', stare, 'termen', termen, 'auto', s.auto);
end $$;
revoke all on function public.agenda_stare(public.agenda_sarcini, text, date) from public, anon, authenticated;

-- O sarcină care se bifează singură nu se bifează de mână.
create or replace function public.agenda_fara_bifa_la_auto()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.agenda_sarcini where id = new.sarcina_id and auto is not null) then
    raise exception 'Sarcina asta se bifează singură, când scrii datele zilei.';
  end if;
  return new;
end $$;
drop trigger if exists agenda_fara_bifa_la_auto on public.agenda_bife;
create trigger agenda_fara_bifa_la_auto before insert on public.agenda_bife for each row execute function public.agenda_fara_bifa_la_auto();

notify pgrst, 'reload schema';
