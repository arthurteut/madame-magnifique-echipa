-- =============================================================================
-- Ghidul echipei Madame Magnifique · Fișa de livrare
--
-- Se rulează după 0024, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Pagina „Livrări” ține locul grupului de livrări:
--   · o comandă B2B devine singură o livrare (client, adresă, oră); se ține după comandă: dacă se
--     schimbă ziua sau se anulează, se schimbă și livrarea;
--   · marfa pentru un magazin e o livrare pe zi și pe tură, cu tot ce a cerut magazinul
--     (necesar, comenzi de clienți, creme);
--   · sarcinile scrise de mână: ridicări, transferuri, cumpărături, veselă pentru evenimente;
--   · șoferul îl alege biroul sau livrarea o preia un șofer (rolul LOG);
--   · „Livrat” cere cine a primit și o poză (sau motivul pentru care nu se poate face); „Problemă”
--     cere motivul. Biroul și cine a cerut livrarea sunt anunțați.
--
-- Pozele stau în Supabase Storage, în bucket-ul privat „livrari” (creat mai jos, dacă proiectul are Storage).
-- =============================================================================

create table if not exists public.livrari (
  id         bigint generated always as identity primary key,
  zi         date not null,
  fel        text not null check (fel in ('comanda', 'magazin', 'sarcina')),
  comanda_id bigint unique references public.cmd_comenzi (id) on delete cascade,     -- fel = 'comanda'
  space_id   text references public.spaces (id) on delete cascade,                   -- fel = 'magazin': unde merge marfa
  tura       int check (tura in (1, 2)),
  titlu      text not null default '',               -- clientul sau ce e de făcut
  unde       text not null default '',
  ora        text not null default '',
  de_unde    text not null default '',               -- de unde se ridică
  detalii    text not null default '',
  sofer      uuid references public.profiles (user_id) on delete set null,
  stare      text not null default 'de_facut' check (stare in ('de_facut', 'pe_drum', 'livrat', 'problema', 'anulata')),
  primit_de  text not null default '',
  problema   text not null default '',
  poza       text not null default '',               -- calea din bucket-ul „livrari”
  fara_poza  text not null default '',               -- de ce nu s-a putut face poza
  facut_la   timestamptz,
  facut_de   uuid references public.profiles (user_id) on delete set null,
  created_by uuid references public.profiles (user_id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists livrari_zi on public.livrari (zi);
create unique index if not exists livrari_magazin on public.livrari (zi, space_id, tura) where fel = 'magazin';
alter table public.livrari enable row level security;
revoke all on public.livrari from anon, authenticated;
grant all on public.livrari to service_role;

-- Șoferii: rolul LOG.
create or replace function public.liv_sofer()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and public.my_role() = 'LOG'
$$;
revoke all on function public.liv_sofer() from public, anon;
grant execute on function public.liv_sofer() to authenticated;

-- Văd livrarea: biroul, șoferii și producția pe toate; magazinul pe ale lui; oricine pe cele cerute de el.
create or replace function public.liv_vede(l public.livrari)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.cmd_birou() or public.liv_sofer() or cardinality(public.cmd_sectiile_mele()) > 0
    or l.created_by = auth.uid() or (l.space_id is not null and public.can_see_space(l.space_id))
    or exists (select 1 from public.cmd_comenzi c where c.id = l.comanda_id and c.created_by = auth.uid()))
$$;
revoke all on function public.liv_vede(public.livrari) from public, anon, authenticated;

-- Livrarea unei comenzi: o ține la zi cu comanda. Se cheamă la fiecare comandă nouă sau schimbată.
create or replace function public.liv_din_comanda()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_tura int;
begin
  if new.fel = 'b2b' then
    insert into public.livrari (zi, fel, comanda_id, tura, titlu, unde, ora, created_by)
    values (new.zi, 'comanda', new.id, new.tura, new.client_nume, new.livrare, new.ora, new.created_by)
    on conflict (comanda_id) do update set zi = excluded.zi, tura = excluded.tura, titlu = excluded.titlu, unde = excluded.unde, ora = excluded.ora
      where public.livrari.stare in ('de_facut', 'pe_drum', 'anulata');
    update public.livrari set stare = case when new.stare = 'anulata' then 'anulata' else 'de_facut' end
    where comanda_id = new.id and ((new.stare = 'anulata' and stare in ('de_facut', 'pe_drum')) or (new.stare <> 'anulata' and stare = 'anulata'));
  elsif new.space_id is not null and new.stare = 'trimisa' then
    v_tura := coalesce(new.tura, 1);
    insert into public.livrari (zi, fel, space_id, tura, titlu, created_by)
    values (new.zi, 'magazin', new.space_id, v_tura, coalesce((select name from public.spaces where id = new.space_id), new.space_id), null)
    on conflict (zi, space_id, tura) where fel = 'magazin' do nothing;
  end if;
  return new;
end $$;
drop trigger if exists cmd_comenzi_livrare on public.cmd_comenzi;
create trigger cmd_comenzi_livrare after insert or update on public.cmd_comenzi
  for each row execute function public.liv_din_comanda();
-- comenzile puse înainte de migrare
update public.cmd_comenzi set updated_at = updated_at where zi >= (now() at time zone 'Europe/Bucharest')::date;

-- Ce se duce: liniile comenzii, sau tot ce a cerut magazinul pe ziua și tura aceea. Liniile refuzate nu apar.
create or replace function public.liv_continut(l public.livrari)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('produs', x.produs_nume, 'cantitate', x.cantitate, 'unitate', x.unitate, 'detalii', x.detalii,
      'confirmat', x.stare = 'confirmata', 'pentru', x.pentru) order by x.pentru, x.id), '[]')
  from (select li.*, case when c.fel = 'client' then c.client_nume else '' end as pentru
        from public.cmd_linii li join public.cmd_comenzi c on c.id = li.comanda_id
        where li.stare <> 'refuzata' and c.stare = 'trimisa'
          and ((l.fel = 'comanda' and c.id = l.comanda_id)
            or (l.fel = 'magazin' and c.fel <> 'b2b' and c.zi = l.zi and c.space_id = l.space_id and coalesce(c.tura, 1) = l.tura))) x
$$;
revoke all on function public.liv_continut(public.livrari) from public, anon, authenticated;

-- Livrările unei zile, pentru contul logat.
create or replace function public.liv_zi(p_zi date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare birou boolean := public.cmd_birou(); sunt_sofer boolean := public.liv_sofer();
begin
  if not public.is_member() then raise exception 'Nu ai acces.'; end if;
  return jsonb_build_object('zi', p_zi, 'birou', birou, 'sofer', sunt_sofer,
    'pot_adauga', birou or sunt_sofer or cardinality(public.cmd_sectiile_mele()) > 0 or public.my_role() in ('RL', 'VT', 'GD', 'PP + B'),
    'soferi', case when birou then coalesce((select jsonb_agg(jsonb_build_object('user_id', p.user_id, 'nume', p.full_name) order by p.full_name)
                                             from public.profiles p where p.active and p.role_code = 'LOG'), '[]') else '[]'::jsonb end,
    'livrari', coalesce((select jsonb_agg(x.j order by x.ord, x.tura, x.ora, x.id) from (
      select l.id, coalesce(l.tura, 1) as tura, l.ora,
        case l.stare when 'livrat' then 2 when 'anulata' then 3 else 1 end as ord,
        jsonb_build_object('id', l.id, 'fel', l.fel, 'comanda_id', l.comanda_id, 'space_id', l.space_id, 'tura', l.tura, 'titlu', l.titlu, 'unde', l.unde, 'ora', l.ora,
          'de_unde', l.de_unde, 'detalii', l.detalii, 'sofer_id', l.sofer, 'sofer', (select full_name from public.profiles where user_id = l.sofer),
          'al_meu', l.sofer = auth.uid(), 'stare', l.stare, 'primit_de', l.primit_de, 'problema', l.problema, 'poza', l.poza, 'fara_poza', l.fara_poza,
          'facut_la', l.facut_la, 'facut_de', (select full_name from public.profiles where user_id = l.facut_de),
          'nota', (select c.nota from public.cmd_comenzi c where c.id = l.comanda_id), 'aviz_pe', (select c.aviz_pe from public.cmd_comenzi c where c.id = l.comanda_id),
          'pot_sterge', l.fel = 'sarcina' and (birou or l.created_by = auth.uid()) and l.stare in ('de_facut', 'pe_drum'),
          'ceruta_de', case when l.fel = 'sarcina' then (select full_name from public.profiles where user_id = l.created_by) end,
          'continut', public.liv_continut(l)) as j
      from public.livrari l
      where l.zi = p_zi and public.liv_vede(l)
        -- marfa unui magazin apare doar cât are ce duce (sau dacă a fost deja dusă)
        and (l.fel <> 'magazin' or l.stare in ('livrat', 'problema', 'pe_drum') or jsonb_array_length(public.liv_continut(l)) > 0)) x), '[]'));
end $$;
revoke all on function public.liv_zi(date) from public, anon;
grant execute on function public.liv_zi(date) to authenticated;

create or replace function public.liv_zile(p_de date, p_pana date)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('zi', z.zi, 'toate', z.toate, 'fara_sofer', z.fara_sofer, 'ramase', z.ramase) order by z.zi), '[]')
  from (select l.zi, count(*) as toate, count(*) filter (where l.sofer is null and l.stare = 'de_facut') as fara_sofer,
               count(*) filter (where l.stare in ('de_facut', 'pe_drum')) as ramase
        from public.livrari l
        where l.zi between p_de and p_pana and l.stare <> 'anulata' and public.liv_vede(l)
          and (l.fel <> 'magazin' or l.stare <> 'de_facut' or jsonb_array_length(public.liv_continut(l)) > 0)
        group by l.zi) z
$$;
revoke all on function public.liv_zile(date, date) from public, anon;
grant execute on function public.liv_zile(date, date) to authenticated;

-- O sarcină scrisă de mână: ridicare, transfer, cumpărături.
create or replace function public.liv_adauga(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_zi date := (p ->> 'zi')::date; v_sofer uuid := nullif(p ->> 'sofer', '')::uuid; v_titlu text := trim(coalesce(p ->> 'titlu', ''));
begin
  if not (public.cmd_birou() or public.liv_sofer() or cardinality(public.cmd_sectiile_mele()) > 0 or (public.is_member() and public.my_role() in ('RL', 'VT', 'GD', 'PP + B'))) then
    raise exception 'Nu poți adăuga sarcini pentru șoferi.'; end if;
  if v_zi is null or v_zi < (now() at time zone 'Europe/Bucharest')::date then raise exception 'Alege o zi de azi înainte.'; end if;
  if length(v_titlu) < 3 then raise exception 'Scrie ce e de făcut.'; end if;
  if v_sofer is not null and not public.cmd_birou() and v_sofer <> auth.uid() then raise exception 'Șoferul îl alege biroul.'; end if;
  if v_sofer is not null and not exists (select 1 from public.profiles where user_id = v_sofer and active and role_code = 'LOG') then raise exception 'Alege un șofer din listă.'; end if;
  insert into public.livrari (zi, fel, tura, titlu, unde, ora, de_unde, detalii, sofer)
  values (v_zi, 'sarcina', nullif(p ->> 'tura', '')::int, v_titlu, trim(coalesce(p ->> 'unde', '')), trim(coalesce(p ->> 'ora', '')),
          trim(coalesce(p ->> 'de_unde', '')), trim(coalesce(p ->> 'detalii', '')), v_sofer)
  returning id into v_id;
  insert into public.notifications (user_id, kind, title, body, url)
  select p2.user_id, 'livrare', 'Sarcină nouă · ' || public.cmd_zi_text(v_zi), v_titlu || case when v_sofer is null then ' (fără șofer încă)' else '' end, '#/livrari?zi=' || v_zi || '&l=' || v_id
  from public.profiles p2 where p2.active and p2.user_id is distinct from auth.uid() and ((v_sofer is null and p2.role_code = 'LOG') or p2.user_id = v_sofer);
  return v_id;
end $$;
revoke all on function public.liv_adauga(jsonb) from public, anon;
grant execute on function public.liv_adauga(jsonb) to authenticated;

-- Cine o face: biroul pune orice șofer (sau niciunul); șoferul o preia dacă e liberă și renunță la ale lui.
create or replace function public.liv_pune_sofer(p_id bigint, p_sofer uuid)
returns void language plpgsql security definer set search_path = public as $$
declare l public.livrari;
begin
  select * into l from public.livrari where id = p_id for update;
  if l.id is null then raise exception 'Livrarea nu există.'; end if;
  if l.stare not in ('de_facut', 'pe_drum') then raise exception 'Livrarea e încheiată.'; end if;
  if public.cmd_birou() then
    if p_sofer is not null and not exists (select 1 from public.profiles where user_id = p_sofer and active and role_code = 'LOG') then raise exception 'Alege un șofer din listă.'; end if;
  elsif public.liv_sofer() then
    if p_sofer is null and l.sofer is distinct from auth.uid() then raise exception 'Poți renunța doar la livrările tale.'; end if;
    if p_sofer is not null and p_sofer <> auth.uid() then raise exception 'Poți prelua doar pentru tine.'; end if;
    if p_sofer is not null and l.sofer is not null and l.sofer <> auth.uid() then raise exception 'Livrarea e deja a altui șofer. Vorbește cu biroul.'; end if;
  else raise exception 'Șoferul îl alege biroul sau un șofer.'; end if;
  if l.sofer is not distinct from p_sofer then return; end if;
  update public.livrari set sofer = p_sofer, stare = case when p_sofer is null then 'de_facut' else stare end where id = p_id;
  if p_sofer is not null and p_sofer <> auth.uid() then
    insert into public.notifications (user_id, kind, title, body, url)
    values (p_sofer, 'livrare', 'Ai o livrare · ' || public.cmd_zi_text(l.zi), l.titlu || case when l.ora <> '' then ' · ora ' || l.ora else '' end, '#/livrari?zi=' || l.zi || '&l=' || l.id);
  end if;
end $$;
revoke all on function public.liv_pune_sofer(bigint, uuid) from public, anon;
grant execute on function public.liv_pune_sofer(bigint, uuid) to authenticated;

-- Starea: „pe_drum”, „livrat” (cine a primit + poză sau motivul lipsei ei), „problema” (motiv), „de_facut” (îndreptare).
create or replace function public.liv_stare(p_id bigint, p_stare text, p jsonb default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare l public.livrari; birou boolean := public.cmd_birou(); v_primit text := trim(coalesce(p ->> 'primit_de', ''));
  v_poza text := trim(coalesce(p ->> 'poza', '')); v_fara text := trim(coalesce(p ->> 'fara_poza', '')); v_prob text := trim(coalesce(p ->> 'problema', '')); cine uuid;
begin
  select * into l from public.livrari where id = p_id for update;
  if l.id is null then raise exception 'Livrarea nu există.'; end if;
  if not (birou or (public.liv_sofer() and (l.sofer = auth.uid() or l.sofer is null))) then raise exception 'Starea o schimbă șoferul livrării sau biroul.'; end if;
  if l.stare = 'anulata' then raise exception 'Livrarea e anulată.'; end if;
  if p_stare not in ('de_facut', 'pe_drum', 'livrat', 'problema') then raise exception 'Stare necunoscută.'; end if;
  if p_stare = 'livrat' then
    if length(v_primit) < 2 then raise exception 'Scrie cine a primit marfa.'; end if;
    if v_poza = '' and length(v_fara) < 3 then raise exception 'Fă o poză sau scrie de ce nu se poate.'; end if;
  elsif p_stare = 'problema' then
    if length(v_prob) < 3 then raise exception 'Scrie ce nu a mers.'; end if;
  end if;
  update public.livrari set stare = p_stare, sofer = coalesce(sofer, case when public.liv_sofer() then auth.uid() end),
    primit_de = case when p_stare = 'livrat' then v_primit else '' end, poza = case when p_stare = 'livrat' then v_poza else '' end,
    fara_poza = case when p_stare = 'livrat' and v_poza = '' then v_fara else '' end, problema = case when p_stare = 'problema' then v_prob else '' end,
    facut_la = case when p_stare in ('livrat', 'problema') then now() end, facut_de = case when p_stare in ('livrat', 'problema') then auth.uid() end
  where id = p_id;
  if p_stare in ('livrat', 'problema') then
    -- află cine a cerut livrarea; la problemă, și biroul
    cine := coalesce((select c.created_by from public.cmd_comenzi c where c.id = l.comanda_id), l.created_by);
    insert into public.notifications (user_id, kind, title, body, url, space_id)
    select distinct pr.user_id, 'livrare', case p_stare when 'livrat' then 'Livrat' else 'Problemă la livrare' end || ' · ' || l.titlu,
      case p_stare when 'livrat' then 'A primit ' || v_primit || case when v_poza = '' then ' · fără poză: ' || v_fara else '' end else v_prob end,
      '#/livrari?zi=' || l.zi || '&l=' || l.id, l.space_id
    from public.profiles pr
    where pr.active and pr.user_id is distinct from auth.uid()
      and (pr.user_id = cine or (p_stare = 'problema' and pr.role_code in ('GM', 'AE', 'CB2B'))
        or (l.fel = 'magazin' and pr.role_code = 'RL' and public.vede_locatia(pr.user_id, l.space_id)));
  end if;
end $$;
revoke all on function public.liv_stare(bigint, text, jsonb) from public, anon;
grant execute on function public.liv_stare(bigint, text, jsonb) to authenticated;

-- O sarcină scrisă de mână se poate anula (livrările din comenzi se anulează odată cu comanda).
create or replace function public.liv_anuleaza(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare l public.livrari;
begin
  select * into l from public.livrari where id = p_id for update;
  if l.id is null or l.fel <> 'sarcina' then raise exception 'Se pot anula doar sarcinile scrise de mână.'; end if;
  if not (public.cmd_birou() or l.created_by = auth.uid()) then raise exception 'Sarcina o anulează cine a scris-o sau biroul.'; end if;
  if l.stare not in ('de_facut', 'pe_drum') then raise exception 'Sarcina e încheiată.'; end if;
  update public.livrari set stare = 'anulata' where id = p_id;
  if l.sofer is not null and l.sofer <> auth.uid() then
    insert into public.notifications (user_id, kind, title, body, url)
    values (l.sofer, 'livrare', 'Sarcină anulată · ' || public.cmd_zi_text(l.zi), l.titlu, '#/livrari?zi=' || l.zi);
  end if;
end $$;
revoke all on function public.liv_anuleaza(bigint) from public, anon;
grant execute on function public.liv_anuleaza(bigint) to authenticated;

-- Pozele livrărilor: bucket privat. Le încarcă șoferii și biroul; le vede echipa logată.
do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'Proiectul nu are Storage: pozele livrărilor nu se pot încărca.';
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('livrari', 'livrari', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
  execute 'drop policy if exists "pozele livrărilor: încarcă șoferii și biroul" on storage.objects';
  execute 'create policy "pozele livrărilor: încarcă șoferii și biroul" on storage.objects for insert to authenticated
           with check (bucket_id = ''livrari'' and (public.liv_sofer() or public.cmd_birou()))';
  execute 'drop policy if exists "pozele livrărilor: le vede echipa" on storage.objects';
  execute 'create policy "pozele livrărilor: le vede echipa" on storage.objects for select to authenticated
           using (bucket_id = ''livrari'' and public.is_member())';
end $$;
