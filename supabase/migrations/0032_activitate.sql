-- 0032 · Jurnalul de activitate și rezumatul pentru șefi
--
-- Tot ce face echipa în aplicație se scrie într-un jurnal: bifele din agendă, încasările, nota zilei,
-- stocul, comenzile și răspunsurile la ele, livrările, verificările de standard, testele.
-- Șefii (cei de deasupra în organigramă, pe locațiile lor, și cine vede tot):
--   · văd jurnalul întreg în pagina Activitate;
--   · primesc de trei ori pe zi (11:00, 15:00, 21:00) un rezumat cu ce s-a făcut de la ultimul;
--   · primesc seara, pe loc, ce a rămas nefăcut din agenda fiecărui magazin.
-- Problemele (întârzieri, pași nefăcuți, semnalări, livrări cu probleme, produse sub standard)
-- vin pe loc, ca până acum.
-- Se poate rula de mai multe ori.

create table if not exists public.activitate (
  id       bigint generated always as identity primary key,
  user_id  uuid not null,
  space_id text,
  fel      text not null,          -- agenda, incasari, nota, stoc, comanda, raspuns, livrare, standard, test
  text     text not null,
  url      text not null default '',
  la       timestamptz not null default now()
);
create index if not exists activitate_la on public.activitate (la desc);
alter table public.activitate enable row level security;
revoke all on public.activitate from anon, authenticated;
grant all on public.activitate to service_role;

create table if not exists public.activitate_stare (id int primary key default 1 check (id = 1), ultim bigint not null default 0);
insert into public.activitate_stare (id) values (1) on conflict do nothing;
alter table public.activitate_stare enable row level security;
revoke all on public.activitate_stare from anon, authenticated;

-- Scrie un rând în jurnal. p_rar = nu repeta același fel, de la același om, pe aceeași locație, în 10 minute
-- (un stoc salvat înseamnă multe rânduri în tabelă, dar o singură acțiune).
create or replace function public.act(p_user uuid, p_space text, p_fel text, p_text text, p_url text, p_rar boolean default false)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null then return; end if;
  if p_rar and exists (select 1 from public.activitate a where a.user_id = p_user and a.fel = p_fel and a.space_id is not distinct from p_space
                       and a.text = p_text and a.la > now() - interval '10 minutes') then return; end if;
  insert into public.activitate (user_id, space_id, fel, text, url) values (p_user, p_space, p_fel, left(p_text, 300), coalesce(p_url, ''));
exception when others then
  raise warning 'activitate: %', sqlerrm;       -- jurnalul nu are voie să oprească acțiunea omului
end $$;
revoke all on function public.act(uuid, text, text, text, text, boolean) from public, anon, authenticated;

create or replace function public.act_din_tabel()
returns trigger language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); t text;
begin
  if tg_table_name = 'agenda_bife' then
    perform public.act(new.user_id, new.space_id, 'agenda', 'a bifat: ' || (select titlu from public.agenda_sarcini where id = new.sarcina_id)
      || case when new.nota <> '' then ' · „' || new.nota || '”' else '' end, '#/agenda?s=' || new.space_id, true);
  elsif tg_table_name = 'incasari_zi' then
    perform public.act(coalesce(eu, new.scris_de), new.space_id, 'incasari', 'a scris încasările din ' || to_char(new.zi, 'DD.MM') || ': '
      || replace(to_char(new.incasari, 'FM999G999G990'), ',', '.') || ' lei, ' || new.bonuri || ' bonuri', '#/zi?s=' || new.space_id || '&zi=' || new.zi, true);
  elsif tg_table_name = 'nota_zilei' then
    perform public.act(coalesce(eu, new.scris_de), new.space_id, 'nota', 'a scris nota zilei', '#/zi?s=' || new.space_id || '&zi=' || new.zi, true);
  elsif tg_table_name = 'stoc_zi' then
    select space_id into t from public.stoc_produse where id = new.produs_id;
    perform public.act(coalesce(eu, new.scris_de), t, 'stoc', 'a scris stocul de azi', '#/zi?s=' || t, true);
  elsif tg_table_name = 'cmd_comenzi' then
    if tg_op = 'INSERT' then
      perform public.act(coalesce(eu, new.created_by), new.space_id, 'comanda', 'a trimis o comandă pentru ' || to_char(new.zi, 'DD.MM')
        || coalesce(' · ' || nullif(new.client_nume, ''), ''), '#/comenzi?zi=' || new.zi);
    elsif new.stare is distinct from old.stare and new.stare = 'anulata' then
      perform public.act(eu, new.space_id, 'comanda', 'a anulat comanda pentru ' || to_char(new.zi, 'DD.MM') || coalesce(' · ' || nullif(new.client_nume, ''), ''), '#/comenzi?zi=' || new.zi);
    elsif new.updated_at is distinct from old.updated_at and new.stare = 'trimisa' then
      perform public.act(eu, new.space_id, 'comanda', 'a modificat comanda pentru ' || to_char(new.zi, 'DD.MM') || coalesce(' · ' || nullif(new.client_nume, ''), ''), '#/comenzi?zi=' || new.zi, true);
    end if;
  elsif tg_table_name = 'cmd_linii' then
    if new.stare is distinct from old.stare and new.stare in ('confirmata', 'refuzata') then
      perform public.act(coalesce(new.raspuns_de, eu), (select space_id from public.cmd_comenzi where id = new.comanda_id), 'raspuns',
        case new.stare when 'confirmata' then 'a confirmat' else 'a refuzat' end || ' la ' || (select nume from public.cmd_sectii where cod = new.sectie)
        || ' comanda pentru ' || (select to_char(zi, 'DD.MM') || coalesce(' · ' || nullif(client_nume, ''), '') from public.cmd_comenzi where id = new.comanda_id),
        '#/comenzi?zi=' || (select zi from public.cmd_comenzi where id = new.comanda_id), true);
    end if;
  elsif tg_table_name = 'livrari' then
    if new.stare is distinct from old.stare and new.stare in ('pe_drum', 'livrat', 'problema') then
      perform public.act(coalesce(eu, new.facut_de, new.sofer), new.space_id, 'livrare',
        case new.stare when 'pe_drum' then 'a plecat cu livrarea: ' when 'livrat' then 'a predat livrarea: ' else 'a semnalat o problemă la livrarea: ' end || new.titlu
        || case when new.stare = 'livrat' and coalesce(new.primit_de, '') <> '' then ' · primit de ' || new.primit_de else '' end, '#/livrari?zi=' || new.zi);
    end if;
  elsif tg_table_name = 'std_verificari' then
    perform public.act(new.user_id, new.space_id, 'standard', 'a verificat ' || (select nume from public.std_produse where id = new.produs_id)
      || case when new.ok then ': în standard' else ': sub standard' end, '#/standarde');
  elsif tg_table_name = 'quiz_attempts' then
    perform public.act(new.user_id, null, 'test', 'a dat testul la „' || (select title from public.courses where id = new.course_id) || '”: '
      || case when new.passed then 'trecut' else 'picat' end || ' (' || new.score || ' din ' || new.total || ')', '#/echipa?tab=oameni');
  end if;
  return new;
exception when others then
  raise warning 'activitate (%): %', tg_table_name, sqlerrm;
  return new;
end $$;
revoke all on function public.act_din_tabel() from public, anon, authenticated;

do $$
declare r record;
begin
  for r in select * from (values ('agenda_bife', 'insert'), ('incasari_zi', 'insert or update'), ('nota_zilei', 'insert or update'), ('stoc_zi', 'insert or update'),
                                 ('cmd_comenzi', 'insert or update'), ('cmd_linii', 'update'), ('livrari', 'update'), ('std_verificari', 'insert'), ('quiz_attempts', 'insert')) v(t, cand) loop
    if to_regclass('public.' || r.t) is null then raise notice 'Tabela % nu există încă: jurnalul o sare.', r.t; continue; end if;
    execute format('drop trigger if exists act_jurnal on public.%I', r.t);
    execute format('create trigger act_jurnal after %s on public.%I for each row execute function public.act_din_tabel()', r.cand, r.t);
  end loop;
end $$;

-- Vede șeful u acțiunea omului o, pe locația s? (deasupra în organigramă pe locațiile lui, sau vede tot)
create or replace function public.act_il_vede(u uuid, o uuid, s text)
returns boolean language sql stable security definer set search_path = public as $$
  select u <> o and exists (select 1 from public.profiles p join public.roles r on r.code = p.role_code
    where p.user_id = u and p.active
      and (r.is_admin or r.sees_all
           or (p.role_code in (select public.sefii((select role_code from public.profiles where user_id = o)))
               and (s is null or public.vede_locatia(u, s)))))
$$;
revoke all on function public.act_il_vede(uuid, uuid, text) from public, anon, authenticated;

-- Pagina Activitate: tot ce a făcut echipa mea într-o zi.
create or replace function public.activitate_echipa(p_zi date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare zi date := coalesce(p_zi, (now() at time zone 'Europe/Bucharest')::date);
begin
  if not public.vede_echipa() then raise exception 'Activitatea echipei e pentru șefi.'; end if;
  return jsonb_build_object('zi', zi, 'azi', (now() at time zone 'Europe/Bucharest')::date,
    'randuri', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'om', public.nume_om(a.user_id), 'space_id', a.space_id, 'fel', a.fel, 'text', a.text, 'url', a.url, 'la', a.la) order by a.la desc)
      from public.activitate a where (a.la at time zone 'Europe/Bucharest')::date = zi and public.act_il_vede(auth.uid(), a.user_id, a.space_id)), '[]'));
end $$;
revoke all on function public.activitate_echipa(date) from public, anon;
grant execute on function public.activitate_echipa(date) to authenticated;

create or replace function public.act_eticheta(p_fel text, n bigint)
returns text language sql immutable as $$
  select case p_fel when 'agenda' then case when n = 1 then 'o bifă în agendă' else n || ' bife în agendă' end
    when 'incasari' then 'încasările scrise' when 'nota' then 'nota zilei scrisă' when 'stoc' then 'stocul scris'
    when 'comanda' then case when n = 1 then 'o comandă' else n || ' comenzi' end
    when 'raspuns' then case when n = 1 then 'un răspuns la comenzi' else n || ' răspunsuri la comenzi' end
    when 'livrare' then case when n = 1 then 'o livrare' else n || ' livrări' end
    when 'standard' then case when n = 1 then 'o verificare de standard' else n || ' verificări de standard' end
    when 'test' then case when n = 1 then 'un test' else n || ' teste' end else n || ' ' || p_fel end
$$;

-- Rezumatul: un singur mesaj pe șef, cu ce s-a făcut de la rezumatul trecut, pe locații.
create or replace function public.rezumat_sefi()
returns int language plpgsql security definer set search_path = public as $$
declare de_la bigint; pana bigint; n int := 0; k int;
begin
  select ultim into de_la from public.activitate_stare where id = 1 for update;
  select coalesce(max(id), de_la) into pana from public.activitate;
  if pana > de_la then
    insert into public.notifications (user_id, kind, title, body, url)
    select z.user_id, 'rezumat', 'Rezumat: ' || case when sum(z.n) = 1 then 'o acțiune' else sum(z.n) || ' acțiuni' end || ' de la echipă',
           left(string_agg(z.loc || ': ' || z.ce, ' · ' order by z.loc), 400), '#/activitate'
    from (select y.user_id, y.loc, sum(y.n) as n, string_agg(public.act_eticheta(y.fel, y.n), ', ' order by y.fel) as ce
          from (select p.user_id, coalesce(public.nume_loc(a.space_id), 'Fără locație') as loc, a.fel, count(*) as n
                from public.activitate a join public.profiles p on p.active and public.act_il_vede(p.user_id, a.user_id, a.space_id)
                where a.id > de_la and a.id <= pana group by 1, 2, 3) y group by 1, 2) z
    group by z.user_id;
    get diagnostics n = row_count;
    update public.activitate_stare set ultim = pana where id = 1;
  end if;
  delete from public.activitate where la < now() - interval '60 days';
  return n;
end $$;
revoke all on function public.rezumat_sefi() from public, anon, authenticated;

-- Seara: ce a rămas nefăcut din agenda fiecărui magazin, pe loc, către șefii responsabilului.
create or replace function public.agenda_nefacute()
returns int language plpgsql security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; l record; t text; c int; n int := 0; k int;
begin
  for l in select sp.id, sp.name from public.spaces sp where sp.type = 'magazin' loop
    select count(*), string_agg(s.titlu, ' · ' order by s.position) into c, t from public.agenda_sarcini s
     where s.activ and public.agenda_stare(s, l.id, azi) ->> 'stare' in ('azi', 'intarziata');
    if c > 0 then
      insert into public.notifications (user_id, kind, title, body, url, space_id)
      select p.user_id, 'agenda', 'Agenda ' || l.name || ': ' || case when c = 1 then 'o sarcină nefăcută' else c || ' sarcini nefăcute' end || ' azi', left(t, 400), '#/agenda?s=' || l.id, l.id
      from public.profiles p join public.roles r on r.code = p.role_code
      where p.active and (r.is_admin or r.sees_all or (p.role_code in (select public.sefii('RL')) and public.vede_locatia(p.user_id, l.id)));
      get diagnostics k = row_count; n := n + k;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.agenda_nefacute() from public, anon, authenticated;

-- Rulează la 5 minute; trimite doar în ferestrele 11:00, 15:00 și 21:00 (ora României), o dată fiecare.
create or replace function public.rezumat_la_ora()
returns void language plpgsql security definer set search_path = public as $$
declare acum timestamp := now() at time zone 'Europe/Bucharest'; o time;
begin
  foreach o in array array['11:00', '15:00', '21:00']::time[] loop
    if acum::time >= o and acum::time < o + interval '30 minutes' and public.o_data('rezumat:' || o || ':' || acum::date) then
      perform public.rezumat_sefi();
      if o = '21:00' and to_regclass('public.agenda_sarcini') is not null then perform public.agenda_nefacute(); end if;
    end if;
  end loop;
end $$;
revoke all on function public.rezumat_la_ora() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('rezumat-sefi') where exists (select 1 from cron.job where jobname = 'rezumat-sefi');
  perform cron.schedule('rezumat-sefi', '*/5 * * * *', 'select public.rezumat_la_ora()');
exception when undefined_table or undefined_function or invalid_schema_name then
  raise notice 'pg_cron nu e disponibil: rezumatul nu pleacă singur';
end $$;

notify pgrst, 'reload schema';
