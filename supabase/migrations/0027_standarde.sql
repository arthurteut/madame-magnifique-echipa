-- =============================================================================
-- Ghidul echipei Madame Magnifique · Standardele de produs
--
-- Se rulează după 0026, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Pagina „Standarde” ține locul pozelor de dimineață de pe grup:
--   · fiecare produs urmărit are o secție, câteva criterii scurte și o poză-etalon;
--   · dimineața, magazinul verifică fiecare produs: o poză și criteriile, bifate față de etalon;
--   · ce e în standard nu mai cere nimic; ce pică un criteriu devine o neconformitate: ajunge la
--     secția care l-a făcut și la șefi, cu poza;
--   · un șef hotărăște ce se face (rămâne la vânzare, degustare, retras), iar secția scrie cauza;
--   · rămâne istoricul pe produs, pe magazin și pe secție.
--
-- Pozele stau în Storage, în bucket-ul privat „standarde” (creat mai jos, dacă proiectul are Storage).
-- Lista de produse se încarcă separat și se ține din pagină.
-- =============================================================================

create table if not exists public.std_produse (
  id       bigint generated always as identity primary key,
  nume     text not null unique check (length(trim(nume)) > 0),
  sectie   text not null references public.cmd_sectii (cod),
  criterii text[] not null check (cardinality(criterii) between 1 and 8),
  etalon   text not null default '',                 -- calea pozei-etalon, în bucket-ul „standarde”
  activ    boolean not null default true,
  position int not null default 0
);
create table if not exists public.std_verificari (
  id           bigint generated always as identity primary key,
  produs_id    bigint not null references public.std_produse (id) on delete cascade,
  space_id     text not null references public.spaces (id) on delete cascade,
  zi           date not null,
  user_id      uuid references public.profiles (user_id) on delete set null,
  criterii     jsonb not null check (jsonb_typeof(criterii) = 'array'),   -- [{"nume": "Culoare", "ok": true}]
  ok           boolean not null,
  nota         text not null default '',
  poza         text not null default '',
  fara_poza    text not null default '',
  created_at   timestamptz not null default now(),
  decizie      text check (decizie in ('ramane', 'degustare', 'retras')),
  decizie_nota text not null default '',
  decizie_de   uuid references public.profiles (user_id) on delete set null,
  decizie_la   timestamptz,
  cauza        text not null default '',
  cauza_de     uuid references public.profiles (user_id) on delete set null,
  cauza_la     timestamptz,
  unique (produs_id, space_id, zi)
);
create index if not exists std_verificari_zi on public.std_verificari (zi, space_id);
alter table public.std_produse enable row level security;
alter table public.std_verificari enable row level security;
revoke all on public.std_produse, public.std_verificari from anon, authenticated;
grant select, insert, update on public.std_produse to authenticated;
grant all on public.std_produse, public.std_verificari to service_role;

-- Lista produselor și etaloanele le țin șefii producției și biroul.
drop policy if exists "standarde: echipa vede produsele" on public.std_produse;
create policy "standarde: echipa vede produsele" on public.std_produse for select to authenticated using (public.is_member());
drop policy if exists "standarde: lista o țin șefii" on public.std_produse;
create policy "standarde: lista o țin șefii" on public.std_produse for all to authenticated using (public.stoc_tine_lista()) with check (public.stoc_tine_lista());

-- Văd verificarea: cine vede locația, secția care a făcut produsul, biroul.
create or replace function public.std_vede(v public.std_verificari)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.cmd_birou() or public.can_see_space(v.space_id)
    or exists (select 1 from public.std_produse p where p.id = v.produs_id and p.sectie = any (public.cmd_sectiile_mele())))
$$;
revoke all on function public.std_vede(public.std_verificari) from public, anon, authenticated;

create or replace function public.std_j(v public.std_verificari)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', v.id, 'produs_id', v.produs_id, 'produs', p.nume, 'sectie', p.sectie, 'space_id', v.space_id, 'loc', (select name from public.spaces where id = v.space_id),
    'zi', v.zi, 'de', public.nume_om(v.user_id), 'la', v.created_at, 'criterii', v.criterii, 'ok', v.ok, 'nota', v.nota, 'poza', v.poza, 'fara_poza', v.fara_poza, 'etalon', p.etalon,
    'decizie', v.decizie, 'decizie_nota', v.decizie_nota, 'decizie_de', public.nume_om(v.decizie_de), 'decizie_la', v.decizie_la,
    'cauza', v.cauza, 'cauza_de', public.nume_om(v.cauza_de), 'cauza_la', v.cauza_la,
    'pot_decide', not v.ok and (public.cmd_birou() or (public.vede_echipa() and public.can_see_space(v.space_id)) or public.my_role() in ('SP', 'DP')),
    'pot_cauza', not v.ok and p.sectie = any (public.cmd_sectiile_mele()))
  from public.std_produse p where p.id = v.produs_id
$$;
revoke all on function public.std_j(public.std_verificari) from public, anon, authenticated;

-- Verificarea unui produs, azi, într-un magazin. p_criterii: {"<criteriu>": true|false}.
create or replace function public.std_verifica(p_space text, p_produs bigint, p_criterii jsonb, p_nota text default '', p_poza text default '', p_fara_poza text default '')
returns bigint language plpgsql security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; pr public.std_produse; c text; rez jsonb := '[]'; bun boolean := true; v_id bigint;
  vechi public.std_verificari; v_nota text := trim(coalesce(p_nota, '')); v_poza text := trim(coalesce(p_poza, '')); v_fara text := trim(coalesce(p_fara_poza, '')); picate text;
begin
  if not public.is_member() or not public.can_see_space(p_space) then raise exception 'Nu lucrezi la locația asta.'; end if;
  select * into pr from public.std_produse where id = p_produs and activ;
  if pr.id is null then raise exception 'Produsul nu mai e pe lista de standarde.'; end if;
  foreach c in array pr.criterii loop
    if jsonb_typeof(p_criterii -> c) is distinct from 'boolean' then raise exception 'Răspunde la „%”.', c; end if;
    rez := rez || jsonb_build_object('nume', c, 'ok', (p_criterii ->> c)::boolean);
    bun := bun and (p_criterii ->> c)::boolean;
  end loop;
  if v_poza = '' and length(v_fara) < 3 then raise exception 'Fă o poză produsului sau scrie de ce nu se poate.'; end if;
  if not bun and length(v_nota) < 3 then raise exception 'Scrie pe scurt ce nu e în regulă.'; end if;
  select * into vechi from public.std_verificari where produs_id = p_produs and space_id = p_space and zi = azi;
  if vechi.id is not null and vechi.decizie is not null then raise exception 'Verificarea de azi are deja o decizie; nu se mai schimbă.'; end if;
  insert into public.std_verificari (produs_id, space_id, zi, user_id, criterii, ok, nota, poza, fara_poza)
  values (p_produs, p_space, azi, auth.uid(), rez, bun, v_nota, v_poza, case when v_poza = '' then v_fara else '' end)
  on conflict (produs_id, space_id, zi) do update set user_id = auth.uid(), criterii = excluded.criterii, ok = excluded.ok, nota = excluded.nota,
    poza = excluded.poza, fara_poza = excluded.fara_poza, created_at = now()
  returning id into v_id;
  -- o neconformitate nouă ajunge la secție, la șefii locației și la conducere
  if not bun and (vechi.id is null or vechi.ok) then
    select string_agg(x ->> 'nume', ', ') into picate from jsonb_array_elements(rez) x where not (x ->> 'ok')::boolean;
    insert into public.notifications (user_id, kind, title, body, url, space_id)
    select distinct pf.user_id, 'standard', 'Produs sub standard · ' || coalesce((select name from public.spaces where id = p_space), p_space),
      pr.nume || ': ' || picate || ' · ' || v_nota, '#/standarde?v=neconforme&n=' || v_id, p_space
    from public.profiles pf
    where pf.active and pf.user_id is distinct from auth.uid()
      and (pf.role_code in ('SP', 'DP', 'GM', 'AE') or exists (select 1 from public.cmd_sectii s where s.cod = pr.sectie and pf.role_code = any (s.roluri))
        or (pf.role_code = 'RL' and public.vede_locatia(pf.user_id, p_space)));
  end if;
  return v_id;
end $$;
revoke all on function public.std_verifica(text, bigint, jsonb, text, text, text) from public, anon;
grant execute on function public.std_verifica(text, bigint, jsonb, text, text, text) to authenticated;

-- Ce se face cu produsul: rămâne la vânzare, merge la degustare sau se retrage.
create or replace function public.std_decide(p_id bigint, p_decizie text, p_nota text default '')
returns void language plpgsql security definer set search_path = public as $$
declare v public.std_verificari;
begin
  select * into v from public.std_verificari where id = p_id for update;
  if v.id is null or v.ok then raise exception 'Nu e o neconformitate.'; end if;
  if not (public.cmd_birou() or (public.vede_echipa() and public.can_see_space(v.space_id)) or (public.is_member() and public.my_role() in ('SP', 'DP'))) then
    raise exception 'Decizia o ia un șef.'; end if;
  if p_decizie not in ('ramane', 'degustare', 'retras') then raise exception 'Alege ce se face cu produsul.'; end if;
  update public.std_verificari set decizie = p_decizie, decizie_nota = trim(coalesce(p_nota, '')), decizie_de = auth.uid(), decizie_la = now() where id = p_id;
  if v.user_id is not null and v.user_id <> auth.uid() then
    insert into public.notifications (user_id, kind, title, body, url, space_id)
    values (v.user_id, 'standard', 'Decizie: ' || case p_decizie when 'ramane' then 'rămâne la vânzare' when 'degustare' then 'merge la degustare' else 'se retrage de la vânzare' end,
      (select nume from public.std_produse where id = v.produs_id) || coalesce(' · ' || nullif(trim(p_nota), ''), ''), '#/standarde?v=neconforme&n=' || v.id, v.space_id);
  end if;
end $$;
revoke all on function public.std_decide(bigint, text, text) from public, anon;
grant execute on function public.std_decide(bigint, text, text) to authenticated;

-- Secția care a făcut produsul scrie cauza și ce schimbă.
create or replace function public.std_cauza(p_id bigint, p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare v public.std_verificari;
begin
  select * into v from public.std_verificari where id = p_id for update;
  if v.id is null or v.ok then raise exception 'Nu e o neconformitate.'; end if;
  if not exists (select 1 from public.std_produse p where p.id = v.produs_id and p.sectie = any (public.cmd_sectiile_mele())) then raise exception 'Cauza o scrie secția care a făcut produsul.'; end if;
  if length(trim(coalesce(p_text, ''))) < 5 then raise exception 'Scrie cauza și ce se schimbă.'; end if;
  update public.std_verificari set cauza = trim(p_text), cauza_de = auth.uid(), cauza_la = now() where id = p_id;
end $$;
revoke all on function public.std_cauza(bigint, text) from public, anon;
grant execute on function public.std_cauza(bigint, text) to authenticated;

-- Verificarea de azi a unei locații: produsele, cu ce s-a scris deja.
create or replace function public.std_zi(p_space text, p_zi date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member() or not public.can_see_space(p_space) then raise exception 'Nu vezi locația asta.'; end if;
  return jsonb_build_object('space_id', p_space, 'zi', p_zi, 'azi', (now() at time zone 'Europe/Bucharest')::date, 'tine_lista', public.stoc_tine_lista(),
    'produse', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nume', p.nume, 'sectie', p.sectie, 'criterii', to_jsonb(p.criterii), 'etalon', p.etalon,
        'verificare', (select public.std_j(v) from public.std_verificari v where v.produs_id = p.id and v.space_id = p_space and v.zi = p_zi)) order by p.position, p.nume)
      from public.std_produse p where p.activ), '[]'));
end $$;
revoke all on function public.std_zi(text, date) from public, anon;
grant execute on function public.std_zi(text, date) to authenticated;

-- Neconformitățile din ultimele zile, pentru contul logat.
create or replace function public.std_neconforme(p_zile int default 14)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.std_j(v) order by (v.decizie is not null and v.cauza <> ''), v.zi desc, v.id desc), '[]')
  from public.std_verificari v
  where not v.ok and v.zi >= (now() at time zone 'Europe/Bucharest')::date - least(greatest(p_zile, 1), 90) and public.std_vede(v)
$$;
revoke all on function public.std_neconforme(int) from public, anon;
grant execute on function public.std_neconforme(int) to authenticated;

-- Rezumatul pentru șefi: azi pe magazine, ultimele 7 zile pe secții și produsele care pică repetat.
create or replace function public.std_rezumat()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; n_produse int := (select count(*) from public.std_produse where activ);
begin
  if not (public.vede_echipa() or public.cmd_birou() or cardinality(public.cmd_sectiile_mele()) > 0) then raise exception 'Rezumatul e pentru șefi și producție.'; end if;
  return jsonb_build_object('produse', n_produse,
    'azi', coalesce((select jsonb_agg(jsonb_build_object('space_id', z.space_id, 'verificate', z.verificate, 'in_standard', z.bune,
          'neconforme', z.rele, 'fara_decizie', z.fara_decizie) order by z.space_id)
      from (select v.space_id, count(*) as verificate, count(*) filter (where v.ok) as bune,
                   coalesce(jsonb_agg(p.nume order by p.nume) filter (where not v.ok), '[]') as rele, count(*) filter (where not v.ok and v.decizie is null) as fara_decizie
            from public.std_verificari v join public.std_produse p on p.id = v.produs_id
            where v.zi = azi and public.std_vede(v) group by v.space_id) z), '[]'),
    'sectii', coalesce((select jsonb_agg(jsonb_build_object('sectie', s.cod, 'nume', s.nume, 'verificate', z.n, 'in_standard', z.bune) order by s.position)
      from public.cmd_sectii s join (select p.sectie, count(*) as n, count(*) filter (where v.ok) as bune
            from public.std_verificari v join public.std_produse p on p.id = v.produs_id where v.zi > azi - 7 and public.std_vede(v) group by p.sectie) z on z.sectie = s.cod), '[]'),
    'repetate', coalesce((select jsonb_agg(jsonb_build_object('produs', z.nume, 'ori', z.n, 'criterii', z.crit) order by z.n desc, z.nume)
      from (select p.nume, count(*) as n, (select string_agg(distinct x ->> 'nume', ', ') from public.std_verificari v2, jsonb_array_elements(v2.criterii) x
                                           where v2.produs_id = p.id and v2.zi > azi - 14 and not v2.ok and not (x ->> 'ok')::boolean) as crit
            from public.std_verificari v join public.std_produse p on p.id = v.produs_id
            where v.zi > azi - 14 and not v.ok and public.std_vede(v) group by p.id, p.nume having count(*) >= 2) z), '[]'));
end $$;
revoke all on function public.std_rezumat() from public, anon;
grant execute on function public.std_rezumat() to authenticated;

-- Pozele: bucket privat. Le încarcă echipa logată (verificări) și șefii (etaloane); le vede echipa.
do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'Proiectul nu are Storage: pozele standardelor nu se pot încărca.';
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('standarde', 'standarde', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
  execute 'drop policy if exists "pozele standardelor: le încarcă echipa" on storage.objects';
  execute 'create policy "pozele standardelor: le încarcă echipa" on storage.objects for insert to authenticated
           with check (bucket_id = ''standarde'' and public.is_member() and (name not like ''etalon/%'' or public.stoc_tine_lista()))';
  execute 'drop policy if exists "pozele standardelor: le vede echipa" on storage.objects';
  execute 'create policy "pozele standardelor: le vede echipa" on storage.objects for select to authenticated
           using (bucket_id = ''standarde'' and public.is_member())';
end $$;
