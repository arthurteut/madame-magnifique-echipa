-- =============================================================================
-- Ghidul echipei Madame Magnifique · Comenzi către producție
--
-- Se rulează după 0023, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Pagina „Comenzi” ține locul grupului de comenzi:
--   · patru feluri de comandă: B2B și evenimente (biroul), comandă de client luată în magazin,
--     necesarul zilnic al magazinului, necesarul de creme și materii prime;
--   · fiecare linie merge la o secție (brutărie, patiserie, cofetărie, depozit), iar secția o confirmă
--     sau scrie de ce nu se poate; cine a comandat e anunțat;
--   · ora-limită (implicit 19:00, cu o zi înainte): după ea comanda se poate trimite, dar e „târzie”
--     și intră doar dacă secția o confirmă;
--   · o linie schimbată după confirmare se întoarce la „de confirmat”;
--   · foaia de producție a zilei iese din comenzi, pe secții.
--
-- Citirea se face doar prin funcții (cmd_zi, cmd_zile): telefonul clientului nu ajunge la producție.
-- Catalogul (produse, clienți) se încarcă separat, dintr-un fișier intern; nu stă în repo.
-- =============================================================================

create table if not exists public.cmd_setari (
  id         int primary key default 1 check (id = 1),
  ora_limita time not null default '19:00'            -- până la ora asta, cu o zi înainte, comanda nu e târzie
);
insert into public.cmd_setari (id) values (1) on conflict do nothing;

create table if not exists public.cmd_sectii (
  cod      text primary key,
  nume     text not null,
  roluri   text[] not null default '{}',              -- rolurile care lucrează în secție și îi confirmă liniile
  position int not null default 0
);
insert into public.cmd_sectii (cod, nume, roluri, position) values
  ('brutarie', 'Brutărie', '{PBR,BRT}', 1),
  ('patiserie', 'Patiserie', '{PPT}', 2),
  ('cofetarie', 'Cofetărie și creme', '{PCF}', 3),
  ('depozit', 'Depozit și materii prime', '{GD}', 4)
on conflict (cod) do nothing;

create table if not exists public.cmd_produse (
  id       bigint generated always as identity primary key,
  nume     text not null check (length(trim(nume)) > 0),
  sectie   text not null references public.cmd_sectii (cod),
  unitate  text not null default 'buc' check (unitate in ('buc', 'kg', 'g', 'tavă', 'l')),
  optiuni  text not null default '',                  -- ce se întreabă de obicei: „feliat?, cu semințe?”
  activ    boolean not null default true,
  position int not null default 0,
  unique (nume, sectie)
);

create table if not exists public.cmd_clienti (
  id       bigint generated always as identity primary key,
  nume     text not null unique check (length(trim(nume)) > 0),
  livrare  text not null default '',                  -- unde se livrează, de obicei
  ora      text not null default '',                  -- până la ce oră
  aviz_pe  text not null default '',                  -- dacă avizul se face pe alt nume
  nota     text not null default '',
  activ    boolean not null default true
);

create table if not exists public.cmd_comenzi (
  id          bigint generated always as identity primary key,
  fel         text not null check (fel in ('b2b', 'client', 'magazin', 'intern')),
  client_id   bigint references public.cmd_clienti (id) on delete set null,
  client_nume text not null default '',               -- firma, sau numele clientului de la pult
  telefon     text not null default '',
  avans       numeric check (avans is null or avans >= 0),
  space_id    text references public.spaces (id) on delete set null,   -- magazinul care cere sau unde se ridică
  zi          date not null,                          -- ziua livrării
  tura        int check (tura in (1, 2)),
  ora         text not null default '',
  livrare     text not null default '',
  aviz_pe     text not null default '',
  nota        text not null default '',
  stare       text not null default 'trimisa' check (stare in ('trimisa', 'anulata')),
  motiv       text not null default '',
  created_by  uuid references public.profiles (user_id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists cmd_comenzi_zi on public.cmd_comenzi (zi);

create table if not exists public.cmd_linii (
  id          bigint generated always as identity primary key,
  comanda_id  bigint not null references public.cmd_comenzi (id) on delete cascade,
  produs_id   bigint references public.cmd_produse (id) on delete set null,
  produs_nume text not null check (length(trim(produs_nume)) > 0),
  sectie      text not null references public.cmd_sectii (cod),
  cantitate   numeric not null check (cantitate > 0),
  unitate     text not null default 'buc',
  detalii     text not null default '',
  stare       text not null default 'noua' check (stare in ('noua', 'confirmata', 'refuzata')),
  tarzie      boolean not null default false,         -- pusă sau schimbată după ora-limită
  modificata  boolean not null default false,         -- schimbată după ce fusese trimisă
  raspuns     text not null default '',
  raspuns_de  uuid references public.profiles (user_id) on delete set null,
  raspuns_la  timestamptz
);
create index if not exists cmd_linii_comanda on public.cmd_linii (comanda_id);

alter table public.cmd_setari enable row level security;
alter table public.cmd_sectii enable row level security;
alter table public.cmd_produse enable row level security;
alter table public.cmd_clienti enable row level security;
alter table public.cmd_comenzi enable row level security;
alter table public.cmd_linii enable row level security;
revoke all on public.cmd_setari, public.cmd_sectii, public.cmd_produse, public.cmd_clienti, public.cmd_comenzi, public.cmd_linii from anon, authenticated;
grant select on public.cmd_setari, public.cmd_sectii to authenticated;
grant update (ora_limita) on public.cmd_setari to authenticated;
grant select, insert, update, delete on public.cmd_produse, public.cmd_clienti to authenticated;
grant all on public.cmd_setari, public.cmd_sectii, public.cmd_produse, public.cmd_clienti, public.cmd_comenzi, public.cmd_linii to service_role;

-- Biroul: pune comenzi B2B și ține catalogul.
create or replace function public.cmd_birou()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and public.my_role() in ('GM', 'AE', 'CB2B', 'DP', 'ADM')
$$;
revoke all on function public.cmd_birou() from public, anon;
grant execute on function public.cmd_birou() to authenticated;

-- Secțiile ale căror linii le confirmă contul logat (coordonatorii producției: toate).
create or replace function public.cmd_sectiile_mele()
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(s.cod order by s.position), '{}')
  from public.cmd_sectii s
  where public.is_member() and (public.my_role() = any (s.roluri) or public.my_role() in ('SP', 'DP', 'PBP'))
$$;
revoke all on function public.cmd_sectiile_mele() from public, anon;
grant execute on function public.cmd_sectiile_mele() to authenticated;

drop policy if exists "setările comenzilor: echipa" on public.cmd_setari;
create policy "setările comenzilor: echipa" on public.cmd_setari for select to authenticated using (public.is_member());
drop policy if exists "setările comenzilor: biroul" on public.cmd_setari;
create policy "setările comenzilor: biroul" on public.cmd_setari for update to authenticated using (public.cmd_birou()) with check (public.cmd_birou());
drop policy if exists "secțiile: echipa" on public.cmd_sectii;
create policy "secțiile: echipa" on public.cmd_sectii for select to authenticated using (public.is_member());
drop policy if exists "produsele: echipa" on public.cmd_produse;
create policy "produsele: echipa" on public.cmd_produse for select to authenticated using (public.is_member());
drop policy if exists "produsele: biroul și producția" on public.cmd_produse;
create policy "produsele: biroul și producția" on public.cmd_produse for all to authenticated
  using (public.cmd_birou() or public.my_role() in ('SP', 'PBP')) with check (public.cmd_birou() or public.my_role() in ('SP', 'PBP'));
drop policy if exists "clienții: echipa" on public.cmd_clienti;
create policy "clienții: echipa" on public.cmd_clienti for select to authenticated using (public.is_member());
drop policy if exists "clienții: biroul" on public.cmd_clienti;
create policy "clienții: biroul" on public.cmd_clienti for all to authenticated using (public.cmd_birou()) with check (public.cmd_birou());

-- E târzie o comandă pentru ziua asta, pusă acum?
create or replace function public.cmd_tarzie(p_zi date)
returns boolean language sql stable security definer set search_path = public as $$
  select now() > (((p_zi - 1)::timestamp + (select ora_limita from public.cmd_setari where id = 1)) at time zone 'Europe/Bucharest')
$$;
revoke all on function public.cmd_tarzie(date) from public, anon;
grant execute on function public.cmd_tarzie(date) to authenticated;

-- Văd comanda: biroul și producția pe toate; magazinul pe ale locațiilor lui; oricine pe ale sale.
create or replace function public.cmd_vede(c public.cmd_comenzi)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.cmd_birou() or cardinality(public.cmd_sectiile_mele()) > 0 or c.created_by = auth.uid()
    or (c.space_id is not null and public.can_see_space(c.space_id)))
$$;
revoke all on function public.cmd_vede(public.cmd_comenzi) from public, anon, authenticated;

create or replace function public.cmd_zi_text(p_zi date)
returns text language sql immutable as $$
  select (array['duminică', 'luni', 'marți', 'miercuri', 'joi', 'vineri', 'sâmbătă'])[extract(dow from p_zi)::int + 1] || ' ' || to_char(p_zi, 'DD.MM')
$$;

-- Anunță oamenii unor secții (și coordonatorii producției), fără cel care a făcut schimbarea.
create or replace function public.cmd_anunta_sectii(p_sectii text[], p_title text, p_body text, p_url text)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, kind, title, body, url)
  select distinct p.user_id, 'comanda', p_title, p_body, p_url
  from public.profiles p
  where p.active and p.user_id is distinct from auth.uid()
    and (p.role_code in ('SP', 'DP') or exists (select 1 from public.cmd_sectii s where s.cod = any (p_sectii) and p.role_code = any (s.roluri)))
$$;
revoke all on function public.cmd_anunta_sectii(text[], text, text, text) from public, anon, authenticated;

-- Pune o comandă nouă sau o schimbă pe una trimisă. Întoarce id-ul comenzii.
create or replace function public.cmd_salveaza(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  azi date := (now() at time zone 'Europe/Bucharest')::date;
  v_id bigint := nullif(p ->> 'id', '')::bigint; c public.cmd_comenzi; cl public.cmd_clienti;
  v_fel text := p ->> 'fel'; v_zi date := (p ->> 'zi')::date; v_space text := nullif(p ->> 'space_id', '');
  v_nume text := trim(coalesce(p ->> 'client_nume', '')); v_client bigint := nullif(p ->> 'client_id', '')::bigint;
  l jsonb; pr public.cmd_produse; v_lid bigint; v_pnume text; v_sectie text; v_unit text; v_cant numeric; v_det text;
  v_tarzie boolean; pastrate bigint[] := '{}'; atinse text[] := '{}'; ex public.cmd_linii; nou boolean := v_id is null; cine text;
begin
  if not public.is_member() then raise exception 'Nu ai acces.'; end if;
  if v_zi is null then raise exception 'Alege ziua livrării.'; end if;
  if v_zi < azi then raise exception 'Ziua livrării a trecut.'; end if;
  if jsonb_typeof(p -> 'linii') is distinct from 'array' or jsonb_array_length(p -> 'linii') = 0 then raise exception 'Adaugă cel puțin un produs.'; end if;
  if nou then
    if v_fel is null or v_fel not in ('b2b', 'client', 'magazin', 'intern') then raise exception 'Alege felul comenzii.'; end if;
  else
    select * into c from public.cmd_comenzi where id = v_id for update;
    if c.id is null then raise exception 'Comanda nu există.'; end if;
    if c.created_by is distinct from auth.uid() and not public.cmd_birou() then raise exception 'Comanda o schimbă cine a pus-o sau biroul.'; end if;
    if c.stare = 'anulata' then raise exception 'Comanda e anulată.'; end if;
    if c.zi < azi then raise exception 'Comanda e din trecut.'; end if;
    v_fel := c.fel;
  end if;
  if v_fel = 'b2b' and not public.cmd_birou() then raise exception 'Comenzile B2B le pune biroul.'; end if;
  if v_fel in ('client', 'magazin', 'intern') then
    if v_space is null then raise exception 'Alege locația.'; end if;
    if not public.can_see_space(v_space) then raise exception 'Nu lucrezi la locația asta.'; end if;
  end if;
  if v_client is not null then
    select * into cl from public.cmd_clienti where id = v_client;
    if cl.id is null then raise exception 'Clientul nu mai e în listă.'; end if;
    v_nume := cl.nume;
  end if;
  if v_fel in ('b2b', 'client') and v_nume = '' then raise exception 'Scrie clientul.'; end if;
  v_tarzie := public.cmd_tarzie(v_zi);

  if nou then
    insert into public.cmd_comenzi (fel, client_id, client_nume, telefon, avans, space_id, zi, tura, ora, livrare, aviz_pe, nota)
    values (v_fel, v_client, v_nume, trim(coalesce(p ->> 'telefon', '')), nullif(p ->> 'avans', '')::numeric, v_space, v_zi,
            nullif(p ->> 'tura', '')::int, trim(coalesce(p ->> 'ora', '')), trim(coalesce(p ->> 'livrare', '')), trim(coalesce(p ->> 'aviz_pe', '')), trim(coalesce(p ->> 'nota', '')))
    returning id into v_id;
  else
    update public.cmd_comenzi set client_id = v_client, client_nume = v_nume, telefon = trim(coalesce(p ->> 'telefon', '')), avans = nullif(p ->> 'avans', '')::numeric,
      space_id = v_space, zi = v_zi, tura = nullif(p ->> 'tura', '')::int, ora = trim(coalesce(p ->> 'ora', '')), livrare = trim(coalesce(p ->> 'livrare', '')),
      aviz_pe = trim(coalesce(p ->> 'aviz_pe', '')), nota = trim(coalesce(p ->> 'nota', '')), updated_at = now()
    where id = v_id;
    -- ziua s-a schimbat: toate liniile se confirmă din nou
    if c.zi <> v_zi then
      update public.cmd_linii set stare = 'noua', modificata = true, tarzie = v_tarzie, raspuns = '', raspuns_de = null, raspuns_la = null where comanda_id = v_id;
      select coalesce(array_agg(distinct sectie), '{}') into atinse from public.cmd_linii where comanda_id = v_id;
    end if;
  end if;

  for l in select * from jsonb_array_elements(p -> 'linii') loop
    v_lid := nullif(l ->> 'id', '')::bigint; v_cant := nullif(l ->> 'cantitate', '')::numeric; v_det := trim(coalesce(l ->> 'detalii', ''));
    if v_cant is null or v_cant <= 0 then raise exception 'Fiecare produs are nevoie de o cantitate.'; end if;
    if nullif(l ->> 'produs_id', '') is not null then
      select * into pr from public.cmd_produse where id = (l ->> 'produs_id')::bigint;
      if pr.id is null then raise exception 'Un produs nu mai e în catalog.'; end if;
      v_pnume := pr.nume; v_sectie := pr.sectie; v_unit := coalesce(nullif(l ->> 'unitate', ''), pr.unitate);
    else
      pr := null; v_pnume := trim(coalesce(l ->> 'produs_nume', '')); v_sectie := l ->> 'sectie'; v_unit := coalesce(nullif(l ->> 'unitate', ''), 'buc');
      if v_pnume = '' then raise exception 'Scrie produsul.'; end if;
      if not exists (select 1 from public.cmd_sectii where cod = v_sectie) then raise exception 'Alege secția pentru „%”.', v_pnume; end if;
    end if;
    if v_lid is null then
      insert into public.cmd_linii (comanda_id, produs_id, produs_nume, sectie, cantitate, unitate, detalii, tarzie, modificata)
      values (v_id, pr.id, v_pnume, v_sectie, v_cant, v_unit, v_det, v_tarzie, not nou) returning id into v_lid;
      atinse := atinse || v_sectie;
    else
      select * into ex from public.cmd_linii where id = v_lid and comanda_id = v_id;
      if ex.id is null then raise exception 'O linie nu ține de comanda asta.'; end if;
      if ex.produs_nume <> v_pnume or ex.cantitate <> v_cant or ex.unitate <> v_unit or ex.detalii <> v_det or ex.sectie <> v_sectie then
        update public.cmd_linii set produs_id = pr.id, produs_nume = v_pnume, sectie = v_sectie, cantitate = v_cant, unitate = v_unit, detalii = v_det,
          stare = 'noua', modificata = true, tarzie = v_tarzie, raspuns = '', raspuns_de = null, raspuns_la = null where id = v_lid;
        atinse := atinse || v_sectie || ex.sectie;
      end if;
    end if;
    pastrate := pastrate || v_lid;
  end loop;
  -- liniile scoase din comandă
  with scoase as (delete from public.cmd_linii where comanda_id = v_id and id <> all (pastrate) returning sectie)
  select atinse || coalesce(array_agg(sectie), '{}') into atinse from scoase;

  if cardinality(atinse) > 0 then
    cine := case v_fel when 'magazin' then 'Necesar ' || coalesce((select name from public.spaces where id = v_space), '')
                       when 'intern' then 'Creme și materii prime, ' || coalesce((select name from public.spaces where id = v_space), '')
                       else v_nume end;
    perform public.cmd_anunta_sectii(atinse,
      case when v_tarzie then 'Comandă târzie' when nou then 'Comandă nouă' else 'Comandă schimbată' end || ' · ' || public.cmd_zi_text(v_zi),
      cine || ': ' || (select count(*) from public.cmd_linii where comanda_id = v_id and sectie = any (atinse)) || ' linii de confirmat'
        || case when v_tarzie then ' (după ora-limită)' else '' end,
      '#/comenzi?zi=' || v_zi || '&v=foaie');
  end if;
  return v_id;
end $$;
revoke all on function public.cmd_salveaza(jsonb) from public, anon;
grant execute on function public.cmd_salveaza(jsonb) to authenticated;

-- Secția răspunde la liniile ei: „confirmata”, sau „refuzata” cu motiv.
create or replace function public.cmd_raspunde(p_linii bigint[], p_stare text, p_raspuns text default '')
returns int language plpgsql security definer set search_path = public as $$
declare ale_mele text[] := public.cmd_sectiile_mele(); n int; r record; v_rasp text := trim(coalesce(p_raspuns, ''));
begin
  if cardinality(ale_mele) = 0 then raise exception 'Liniile le confirmă producția.'; end if;
  if p_stare not in ('confirmata', 'refuzata') then raise exception 'Răspuns necunoscut.'; end if;
  if p_stare = 'refuzata' and length(v_rasp) < 3 then raise exception 'Scrie de ce nu se poate.'; end if;
  if exists (select 1 from public.cmd_linii l join public.cmd_comenzi c on c.id = l.comanda_id
             where l.id = any (p_linii) and (l.sectie <> all (ale_mele) or c.stare = 'anulata')) then
    raise exception 'Poți răspunde doar la liniile secției tale, din comenzi active.';
  end if;
  update public.cmd_linii set stare = p_stare, raspuns = v_rasp, raspuns_de = auth.uid(), raspuns_la = now()
  where id = any (p_linii) and (stare <> p_stare or raspuns <> v_rasp);
  get diagnostics n = row_count;
  -- cine a comandat află o dată pe comandă
  for r in select c.id, c.created_by, c.zi, c.fel, c.client_nume, count(*) as cate, string_agg(l.produs_nume, ', ' order by l.id) as produse
           from public.cmd_linii l join public.cmd_comenzi c on c.id = l.comanda_id
           where l.id = any (p_linii) and l.raspuns_de = auth.uid() and l.raspuns_la = now() and c.created_by is distinct from auth.uid() and c.created_by is not null
           group by c.id loop
    insert into public.notifications (user_id, kind, title, body, url)
    values (r.created_by, 'comanda',
      case p_stare when 'confirmata' then 'Comandă confirmată' else 'Producția nu poate' end || ' · ' || public.cmd_zi_text(r.zi),
      coalesce(nullif(r.client_nume, '') || ': ', '') || case p_stare when 'confirmata' then r.cate || ' linii confirmate' else r.produse || ' · ' || v_rasp end,
      '#/comenzi?zi=' || r.zi || '&c=' || r.id);
  end loop;
  return n;
end $$;
revoke all on function public.cmd_raspunde(bigint[], text, text) from public, anon;
grant execute on function public.cmd_raspunde(bigint[], text, text) to authenticated;

create or replace function public.cmd_anuleaza(p_id bigint, p_motiv text)
returns void language plpgsql security definer set search_path = public as $$
declare c public.cmd_comenzi; sectii text[];
begin
  select * into c from public.cmd_comenzi where id = p_id for update;
  if c.id is null then raise exception 'Comanda nu există.'; end if;
  if c.created_by is distinct from auth.uid() and not public.cmd_birou() then raise exception 'Comanda o anulează cine a pus-o sau biroul.'; end if;
  if c.stare = 'anulata' then return; end if;
  if length(trim(coalesce(p_motiv, ''))) < 3 then raise exception 'Scrie de ce se anulează.'; end if;
  update public.cmd_comenzi set stare = 'anulata', motiv = trim(p_motiv), updated_at = now() where id = p_id;
  select coalesce(array_agg(distinct sectie), '{}') into sectii from public.cmd_linii where comanda_id = p_id;
  perform public.cmd_anunta_sectii(sectii, 'Comandă anulată · ' || public.cmd_zi_text(c.zi),
    coalesce(nullif(c.client_nume, ''), 'Comanda') || ': ' || trim(p_motiv), '#/comenzi?zi=' || c.zi || '&v=foaie');
end $$;
revoke all on function public.cmd_anuleaza(bigint, text) from public, anon;
grant execute on function public.cmd_anuleaza(bigint, text) to authenticated;

-- Comenzile unei zile, cu liniile lor, pentru contul logat.
create or replace function public.cmd_zi(p_zi date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ale_mele text[] := public.cmd_sectiile_mele(); birou boolean := public.cmd_birou();
begin
  if not public.is_member() then raise exception 'Nu ai acces.'; end if;
  return jsonb_build_object('zi', p_zi, 'tarzie', public.cmd_tarzie(p_zi), 'ora_limita', (select to_char(ora_limita, 'HH24:MI') from public.cmd_setari where id = 1),
    'sectiile_mele', to_jsonb(ale_mele), 'birou', birou,
    'comenzi', coalesce((select jsonb_agg(x.j order by x.ord, x.id) from (
      select c.id, case c.stare when 'anulata' then 1 else 0 end as ord, jsonb_build_object(
        'id', c.id, 'fel', c.fel, 'client_id', c.client_id, 'client_nume', c.client_nume, 'space_id', c.space_id, 'loc', (select name from public.spaces where id = c.space_id), 'zi', c.zi, 'tura', c.tura, 'ora', c.ora,
        'livrare', c.livrare, 'aviz_pe', c.aviz_pe, 'nota', c.nota, 'stare', c.stare, 'motiv', c.motiv, 'avans', c.avans,
        -- telefonul îl vede biroul, cine a pus comanda și magazinul; producția nu
        'telefon', case when birou or c.created_by = auth.uid() or (c.space_id is not null and public.can_see_space(c.space_id) and cardinality(ale_mele) = 0) then c.telefon else '' end,
        'autor', public.nume_om(c.created_by), 'a_mea', c.created_by = auth.uid(), 'pot_schimba', (c.created_by = auth.uid() or birou) and c.stare = 'trimisa',
        'created_at', c.created_at, 'updated_at', c.updated_at,
        'linii', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'produs_id', l.produs_id, 'produs', l.produs_nume, 'sectie', l.sectie, 'cantitate', l.cantitate,
            'unitate', l.unitate, 'detalii', l.detalii, 'stare', l.stare, 'tarzie', l.tarzie, 'modificata', l.modificata, 'raspuns', l.raspuns,
            'raspuns_de', public.nume_om(l.raspuns_de), 'raspuns_la', l.raspuns_la, 'a_mea', l.sectie = any (ale_mele)) order by l.id)
          from public.cmd_linii l where l.comanda_id = c.id), '[]')) as j
      from public.cmd_comenzi c where c.zi = p_zi and public.cmd_vede(c)) x), '[]'));
end $$;
revoke all on function public.cmd_zi(date) from public, anon;
grant execute on function public.cmd_zi(date) to authenticated;

-- Zilele din jur: câte comenzi și câte linii mai așteaptă un răspuns (pentru alegerea zilei).
create or replace function public.cmd_zile(p_de date, p_pana date)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('zi', z.zi, 'comenzi', z.comenzi, 'de_confirmat', z.de_confirmat, 'refuzate', z.refuzate) order by z.zi), '[]')
  from (select c.zi, count(distinct c.id) as comenzi,
               count(l.id) filter (where l.stare = 'noua') as de_confirmat, count(l.id) filter (where l.stare = 'refuzata') as refuzate
        from public.cmd_comenzi c left join public.cmd_linii l on l.comanda_id = c.id
        where c.zi between p_de and p_pana and c.stare = 'trimisa' and public.cmd_vede(c) group by c.zi) z
$$;
revoke all on function public.cmd_zile(date, date) from public, anon;
grant execute on function public.cmd_zile(date, date) to authenticated;
