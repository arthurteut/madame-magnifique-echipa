-- =============================================================================
-- Ghidul echipei Madame Magnifique · Ghidul brutarului (pâinea cu maia)
--
-- Se rulează după 0006, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Capitolele ghidului de producție stau în handbook_chapters (conținut intern,
-- încărcat separat, nu stă în repo). Le vede cine are pagina „brutar” în
-- role_section_access: implicit producția (DP, SP, GD), plus GM și AE.
-- Calculatorul de pâine e în pagină și apare pentru aceleași roluri.
-- =============================================================================

create table if not exists public.handbook_chapters (
  slug     text primary key,                         -- cap01 … cap12
  position int not null default 0,
  title    text not null check (length(trim(title)) > 0),
  body     text not null default '',                 -- text simplu: ##, ###, 1., -, | tabel |, > casetă
  updated_at timestamptz not null default now()
);

-- Pagina „brutar” în meniu.
alter table public.role_section_access drop constraint if exists role_section_access_section_check;
alter table public.role_section_access add constraint role_section_access_section_check
  check (section in ('roluri', 'proceduri', 'ghid', 'cursuri', 'brutar'));
insert into public.role_section_access (role_code, section)
select r, 'brutar' from (values ('DP'), ('SP'), ('GD'), ('GM'), ('AE')) v (r)
where exists (select 1 from public.roles where code = r)
on conflict do nothing;

create or replace function public.can_see_section(s text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or (public.is_member() and exists (
    select 1 from public.role_section_access where role_code = public.my_role() and section = s))
$$;
revoke all on function public.can_see_section(text) from public, anon;
grant execute on function public.can_see_section(text) to authenticated;

alter table public.handbook_chapters enable row level security;
revoke all on public.handbook_chapters from anon, authenticated;
grant select on public.handbook_chapters to authenticated;
grant all on public.handbook_chapters to service_role;
drop policy if exists "brutarii citesc ghidul" on public.handbook_chapters;
create policy "brutarii citesc ghidul" on public.handbook_chapters for select to authenticated
  using (public.can_see_section('brutar'));

-- Rețetele casei pentru calculator (procente de brutar față de făina adăugată, ca în
-- fișele tehnologice). Conținut intern: se încarcă separat, nu stă în repo.
create table if not exists public.bread_recipes (
  slug     text primary key,
  position int not null default 0,
  name     text not null,
  data     jsonb not null,                           -- {fainuri, hidratare, sare, maia, extra, starter, ...}
  updated_at timestamptz not null default now()
);
alter table public.bread_recipes enable row level security;
revoke all on public.bread_recipes from anon, authenticated;
grant select on public.bread_recipes to authenticated;
grant all on public.bread_recipes to service_role;
drop policy if exists "brutarii citesc rețetele" on public.bread_recipes;
create policy "brutarii citesc rețetele" on public.bread_recipes for select to authenticated
  using (public.can_see_section('brutar'));
