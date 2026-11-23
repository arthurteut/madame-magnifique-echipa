-- =============================================================================
-- Ghidul echipei Madame Magnifique · Adrese salvate, anunț pentru B2B, secții pe oameni
--
-- Se rulează după 0028, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
--   1. Adresele clienților B2B se salvează singure la prima comandă: clientul intră în listă cu adresa,
--      ora și avizul lui, iar adresele folosite apar ca sugestii la următoarea comandă.
--   2. Un anunț se poate trimite „doar pentru B2B”: îl primesc conturile CB2B și AE.
--   3. Înainte de trimitere, cine scrie anunțul vede cine îl primește, pe roluri.
--   4. Fiecare om poate primi comenzile unei secții anume (Comenzi → Catalog → Cine răspunde): cine are
--      secții puse de mână le primește și le confirmă doar pe acelea, indiferent de rol.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Adresele clienților
-- ---------------------------------------------------------------------------
create table if not exists public.cmd_adrese (
  client_id bigint not null references public.cmd_clienti (id) on delete cascade,
  adresa    text not null check (length(trim(adresa)) > 0),
  folosita  timestamptz not null default now(),
  primary key (client_id, adresa)
);
alter table public.cmd_adrese enable row level security;
revoke all on public.cmd_adrese from anon, authenticated;
grant select, delete on public.cmd_adrese to authenticated;
grant all on public.cmd_adrese to service_role;
drop policy if exists "adresele: echipa" on public.cmd_adrese;
create policy "adresele: echipa" on public.cmd_adrese for select to authenticated using (public.is_member());
drop policy if exists "adresele: le șterge biroul" on public.cmd_adrese;
create policy "adresele: le șterge biroul" on public.cmd_adrese for delete to authenticated using (public.cmd_birou());

-- La o comandă B2B: clientul scris de mână intră în listă, iar adresa, ora și avizul devin cele obișnuite ale lui.
create or replace function public.cmd_tine_minte_clientul()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if new.fel <> 'b2b' or trim(new.client_nume) = '' then return new; end if;
  if new.client_id is null then
    select id into v_id from public.cmd_clienti where lower(trim(nume)) = lower(trim(new.client_nume)) limit 1;
    if v_id is null then
      insert into public.cmd_clienti (nume, livrare, ora, aviz_pe) values (trim(new.client_nume), new.livrare, new.ora, new.aviz_pe)
      on conflict (nume) do update set activ = true returning id into v_id;
    end if;
    new.client_id := v_id;
  end if;
  update public.cmd_clienti set activ = true,
    livrare = case when new.livrare <> '' then new.livrare else livrare end,
    ora = case when new.ora <> '' then new.ora else ora end,
    aviz_pe = case when new.aviz_pe <> '' then new.aviz_pe else aviz_pe end
  where id = new.client_id;
  if new.livrare <> '' then
    insert into public.cmd_adrese (client_id, adresa) values (new.client_id, new.livrare)
    on conflict (client_id, adresa) do update set folosita = now();
  end if;
  return new;
end $$;
drop trigger if exists cmd_comenzi_client on public.cmd_comenzi;
create trigger cmd_comenzi_client before insert or update of client_nume, client_id, livrare, ora, aviz_pe on public.cmd_comenzi
  for each row execute function public.cmd_tine_minte_clientul();
-- adresele deja scrise în lista de clienți
insert into public.cmd_adrese (client_id, adresa) select id, livrare from public.cmd_clienti where livrare <> '' on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 2 și 3. Anunțul doar pentru B2B și lista destinatarilor
-- ---------------------------------------------------------------------------
alter table public.anunturi add column if not exists tinta text;
alter table public.anunturi drop constraint if exists anunturi_tinta;
alter table public.anunturi add constraint anunturi_tinta check (tinta is null or (tinta = 'b2b' and space_id = 'b2b'));

-- Cine primește un anunț (fără cel care îl trimite). Aceeași regulă la previzualizare și la trimitere.
create or replace function public.anunt_cine(p_space text, p_tinta text, p_de uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select p.user_id from public.profiles p join public.roles r on r.code = p.role_code
  where p.active and p.user_id is distinct from p_de
    and case when p_tinta = 'b2b' then p.role_code in ('CB2B', 'AE')
             else not (r.is_admin or r.sees_all)
               and (p_space is null or (public.vede_locatia(p.user_id, p_space)
                    and exists (select 1 from public.space_roles sr where sr.space_id = p_space and sr.role_code = p.role_code))) end
$$;
revoke all on function public.anunt_cine(text, text, uuid) from public, anon, authenticated;

create or replace function public.anunt_trimis()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.anunturi_citiri (anunt_id, user_id) select new.id, u from public.anunt_cine(new.space_id, new.tinta, new.from_user) u;
  insert into public.notifications (user_id, kind, title, body, url, space_id)
  select c.user_id, 'anunt', 'Anunț: ' || new.title,
         case when new.body <> '' then left(new.body, 140) || ' · ' else '' end || coalesce(public.nume_om(new.from_user), '')
           || ' · confirmă cu „Am citit” în 24 de ore', '#/mesaje', new.space_id
  from public.anunturi_citiri c where c.anunt_id = new.id;
  return new;
end $$;

-- Previzualizarea: cine ar primi anunțul, cu rolul fiecăruia.
create or replace function public.anunt_destinatari(p_space text, p_tinta text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.vede_echipa() then raise exception 'Anunțurile le trimit șefii.'; end if;
  if p_tinta is null and p_space is not null and not public.can_see_space(p_space) then raise exception 'Nu vezi locația asta.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('nume', p.full_name, 'rol', p.role_code, 'rol_nume', r.name) order by r.name, p.full_name)
    from public.anunt_cine(p_space, p_tinta, auth.uid()) u join public.profiles p on p.user_id = u join public.roles r on r.code = p.role_code), '[]');
end $$;
revoke all on function public.anunt_destinatari(text, text) from public, anon;
grant execute on function public.anunt_destinatari(text, text) to authenticated;

drop policy if exists "anunțurile locațiilor mele și ale firmei" on public.anunturi;
create policy "anunțurile locațiilor mele și ale firmei" on public.anunturi for select to authenticated
  using (public.is_member() and (from_user = auth.uid() or public.is_admin()
    or (tinta is null and (space_id is null or public.can_see_space(space_id)))
    or (tinta = 'b2b' and public.my_role() in ('CB2B', 'AE'))));
drop policy if exists "anunță șefii" on public.anunturi;
create policy "anunță șefii" on public.anunturi for insert to authenticated
  with check (from_user = auth.uid() and public.vede_echipa()
              and ((space_id is null and public.sees_all()) or (tinta = 'b2b' and space_id = 'b2b')
                   or (tinta is null and space_id is not null and public.can_see_space(space_id))));

create or replace function public.mesajele_mele()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'anunturi', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
        select a.id, a.title, a.body, a.space_id, a.tinta, a.created_at, a.created_at + interval '24 hours' as termen,
               public.nume_om(a.from_user) as de_la, a.from_user = auth.uid() as al_meu,
               c.user_id is not null as destinatar, c.read_at as citit_la,
               case when a.from_user = auth.uid() or public.sees_all()
                         or (public.vede_echipa() and a.space_id is not null and public.can_see_space(a.space_id)) then
                 (select jsonb_build_object('total', count(*), 'citite', count(*) filter (where k.read_at is not null),
                    'necitite', coalesce(jsonb_agg(public.nume_om(k.user_id) order by public.nume_om(k.user_id)) filter (where k.read_at is null), '[]'))
                  from public.anunturi_citiri k where k.anunt_id = a.id) end as stare
        from public.anunturi a left join public.anunturi_citiri c on c.anunt_id = a.id and c.user_id = auth.uid()
        where (a.space_id is null or a.from_user = auth.uid() or public.can_see_space(a.space_id))
          -- un anunț doar pentru B2B îl văd cine l-a trimis, cei care îl primesc și conducerea
          and (a.tinta is null or a.from_user = auth.uid() or c.user_id is not null or public.is_admin())
          and (a.created_at > now() - interval '60 days' or (c.user_id is not null and c.read_at is null))
        order by a.created_at desc limit 80) x),
    'feedback', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
        select f.id, f.fel, f.text, f.puncte, f.created_at, f.read_at, f.raspuns, f.to_user,
               public.nume_om(f.from_user) as de_la, public.nume_om(f.to_user) as catre,
               f.to_user = auth.uid() as primit, f.from_user = auth.uid() as dat_de_mine
        from public.feedback f
        where (f.to_user = auth.uid() or f.from_user = auth.uid() or public.conduce_omul(f.to_user))
          and (f.created_at > now() - interval '90 days' or (f.to_user = auth.uid() and f.read_at is null))
        order by f.created_at desc limit 120) x),
    'de_confirmat', (select count(*) from public.anunturi_citiri c where c.user_id = auth.uid() and c.read_at is null)
                    + (select count(*) from public.feedback f where f.to_user = auth.uid() and f.read_at is null),
    'pot_anunta', public.vede_echipa(), 'pot_anunta_firma', public.sees_all())
  where public.is_member()
$$;
revoke all on function public.mesajele_mele() from public, anon;
grant execute on function public.mesajele_mele() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Secțiile, pe oameni
-- ---------------------------------------------------------------------------
create table if not exists public.cmd_sectii_oameni (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  sectie  text not null references public.cmd_sectii (cod) on delete cascade,
  primary key (user_id, sectie)
);
alter table public.cmd_sectii_oameni enable row level security;
revoke all on public.cmd_sectii_oameni from anon, authenticated;
grant select on public.cmd_sectii_oameni to authenticated;
grant all on public.cmd_sectii_oameni to service_role;
drop policy if exists "secțiile oamenilor: echipa" on public.cmd_sectii_oameni;
create policy "secțiile oamenilor: echipa" on public.cmd_sectii_oameni for select to authenticated using (public.is_member());

-- Secțiile unui om: cele puse de mână; dacă nu are niciuna, cele ale rolului lui (SP, DP și PBP: toate).
create or replace function public.cmd_sectiile_omului(u uuid)
returns text[] language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from public.cmd_sectii_oameni o where o.user_id = u)
    then (select coalesce(array_agg(s.cod order by s.position), '{}') from public.cmd_sectii s join public.cmd_sectii_oameni o on o.sectie = s.cod and o.user_id = u)
    else (select coalesce(array_agg(s.cod order by s.position), '{}') from public.cmd_sectii s, public.profiles p
          where p.user_id = u and p.active and (p.role_code = any (s.roluri) or p.role_code in ('SP', 'DP', 'PBP'))) end
$$;
revoke all on function public.cmd_sectiile_omului(uuid) from public, anon, authenticated;

create or replace function public.cmd_sectiile_mele()
returns text[] language sql stable security definer set search_path = public as $$
  select case when public.is_member() then public.cmd_sectiile_omului(auth.uid()) else '{}'::text[] end
$$;

create or replace function public.cmd_anunta_sectii(p_sectii text[], p_title text, p_body text, p_url text)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, kind, title, body, url)
  select p.user_id, 'comanda', p_title, p_body, p_url
  from public.profiles p
  where p.active and p.user_id is distinct from auth.uid() and public.cmd_sectiile_omului(p.user_id) && p_sectii
$$;

-- Oamenii producției, cu secțiile fiecăruia (pentru Catalog → Cine răspunde).
create or replace function public.cmd_cine_raspunde()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.cmd_birou() then raise exception 'Lista o ține biroul.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', p.user_id, 'nume', p.full_name, 'rol', p.role_code,
      'de_mana', exists (select 1 from public.cmd_sectii_oameni o where o.user_id = p.user_id), 'sectii', to_jsonb(public.cmd_sectiile_omului(p.user_id))) order by p.full_name)
    from public.profiles p
    where p.active and (p.role_code in ('SP', 'DP', 'PBP', 'GD') or exists (select 1 from public.cmd_sectii s where p.role_code = any (s.roluri))
      or exists (select 1 from public.cmd_sectii_oameni o where o.user_id = p.user_id))), '[]');
end $$;
revoke all on function public.cmd_cine_raspunde() from public, anon;
grant execute on function public.cmd_cine_raspunde() to authenticated;

-- Pune secțiile unui om. Lista goală = revine la secțiile rolului lui.
create or replace function public.cmd_pune_sectii(p_user uuid, p_sectii text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.cmd_birou() then raise exception 'Secțiile oamenilor le pune biroul.'; end if;
  if not exists (select 1 from public.profiles where user_id = p_user and active) then raise exception 'Contul nu există.'; end if;
  delete from public.cmd_sectii_oameni where user_id = p_user;
  insert into public.cmd_sectii_oameni (user_id, sectie) select p_user, s.cod from public.cmd_sectii s where s.cod = any (coalesce(p_sectii, '{}'));
end $$;
revoke all on function public.cmd_pune_sectii(uuid, text[]) from public, anon;
grant execute on function public.cmd_pune_sectii(uuid, text[]) to authenticated;
