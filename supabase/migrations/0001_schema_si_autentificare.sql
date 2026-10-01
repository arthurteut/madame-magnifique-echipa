-- =============================================================================
-- Ghidul echipei Madame Magnifique · Pasul 1: schema și autentificarea
--
-- Se rulează o singură dată, în Supabase → SQL Editor (sau `supabase db push`).
-- Conținutul (harta de operațiuni) se încarcă separat, cu tools/import_supabase.py.
--
-- Pasul 1: orice utilizator autentificat și activ poate CITI conținutul.
-- Filtrarea pe rol vine în 0002 (RBAC), iar scrierea pentru admin în 0003.
-- Nimeni nu scrie din pagină: importul și adminul folosesc cheia de serviciu,
-- care ocolește RLS și nu ajunge niciodată în browser.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Conținut: harta de operațiuni
-- ---------------------------------------------------------------------------
create table public.roles (
  code             text primary key,                 -- GM, VT, PP + B …
  name             text not null,
  responsibilities text not null default '',
  main_processes   text[] not null default '{}',
  is_admin         boolean not null default false,   -- poate administra ghidul
  position         int not null default 0
);

create table public.domains (
  code     text primary key,                         -- D1 … D7
  name     text not null,
  stake    text not null default '',
  position int not null default 0
);

create table public.processes (
  code        text primary key,                      -- P01 … P53
  domain_code text not null references public.domains (code),
  name        text not null,
  lead_role   text references public.roles (code),
  wave        text,                                  -- Val 1 / 2 / 3
  stake       text not null default '',
  position    int not null default 0
);

create table public.subprocesses (
  process_code text not null references public.processes (code) on delete cascade,
  position     int not null,
  name         text not null,                        -- „15.1 Centralizarea comenzilor …”
  primary key (process_code, position)
);

create table public.procedures (
  code         text primary key,                     -- PR-01.1
  title        text not null,
  process_code text not null references public.processes (code),
  role_code    text not null references public.roles (code),
  trigger      text not null default '',
  trigger_type text not null default '',             -- Dată / Eveniment / Procedură
  priority     text not null default '',             -- Critică / Înaltă / Medie
  wave         text not null default '',
  steps        int,
  field_update boolean not null default false,       -- actualizat pe teren
  original     text not null default '',             -- textul din harta inițială
  position     int not null default 0
);

create table public.tasks (
  id             int primary key,                    -- ordinea din hartă
  process_code   text not null references public.processes (code),
  subprocess     text not null,
  text           text not null,
  role_code      text not null references public.roles (code),
  minutes        int,
  schedule       text not null default '',           -- „Zilnic, 06:00”
  verification   text not null default '',
  procedure_code text references public.procedures (code),
  field_update   boolean not null default false,
  original       text not null default ''
);

create table public.deviations (                     -- abateri per locație
  id       int primary key,
  location text not null,                            -- Porumbescu / Dumbrăvița / Fructus
  area     text not null,                            -- „P03 Expunere”, „Profil” …
  text     text not null,
  reason   text not null default ''
);

create table public.guide_sections (                 -- „Cum funcționează”
  id       int primary key,
  title    text not null,
  lines    text[] not null default '{}'
);

-- ---------------------------------------------------------------------------
-- Spațiile: magazine, laboratoare, B2B, birou
-- ---------------------------------------------------------------------------
create table public.spaces (
  id                  text primary key,              -- porumbescu, peciu-nou, b2b …
  type                text not null check (type in ('magazin', 'productie', 'b2b', 'birou')),
  name                text not null,
  title               text not null,
  subtitle            text not null default '',
  deviations_location text,                          -- toate abaterile unei locații
  deviations_filter   jsonb not null default '{}',   -- sau doar unele: {"Fructus": ["D3 B2B"]}
  domains             text[] not null default '{}',  -- biroul: domeniile afișate
  deliveries_note     text not null default '',
  equipment_note      text not null default '',
  position            int not null default 0
);

create table public.space_processes (
  space_id     text not null references public.spaces (id) on delete cascade,
  process_code text not null references public.processes (code) on delete cascade,
  position     int not null default 0,
  is_specific  boolean not null default false,       -- „Specific acestui laborator”
  primary key (space_id, process_code)
);

create table public.space_roles (                    -- „Cine lucrează aici”
  space_id  text not null references public.spaces (id) on delete cascade,
  role_code text not null references public.roles (code) on delete cascade,
  position  int not null default 0,
  primary key (space_id, role_code)
);

create table public.space_notes (                    -- „Ce e diferit aici”
  space_id text not null references public.spaces (id) on delete cascade,
  position int not null,
  title    text not null,
  text     text not null,
  primary key (space_id, position)
);

create table public.space_facts (                    -- fișa spațiului
  space_id  text not null references public.spaces (id) on delete cascade,
  section   text not null check (section in ('program', 'livrari', 'contacte', 'echipamente')),
  position  int not null,
  label     text not null,                           -- rând / funcție / echipament
  value     text not null default '',                -- valoare / pe cine anunți la defecțiune
  role_code text,                                    -- contacte: rolul
  person    text not null default '',                -- contacte: numele
  phone     text not null default '',                -- contacte: telefonul
  primary key (space_id, section, position)
);

create table public.space_task_overrides (           -- ajustări locale peste standard
  space_id  text not null references public.spaces (id) on delete cascade,
  task_id   int  not null references public.tasks (id) on delete cascade,
  schedule  text not null default '',
  role_code text references public.roles (code),
  text      text not null default '',
  primary key (space_id, task_id)
);

-- ---------------------------------------------------------------------------
-- Utilizatori
-- Contul de autentificare (auth.users) are un email intern, nefolosit pentru
-- mesaje: <utilizator>@echipa.madamemagnifique.ro. Angajatul scrie doar
-- numele de utilizator; parola o resetează adminul.
-- ---------------------------------------------------------------------------
create table public.profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  username   text not null unique check (username ~ '^[a-z0-9._-]{3,40}$'),
  full_name  text not null,
  role_code  text not null references public.roles (code),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Funcții ajutătoare (security definer: citesc profilul fără să treacă prin RLS)
-- ---------------------------------------------------------------------------
create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role_code from public.profiles where user_id = auth.uid() and active
$$;

create or replace function public.is_member()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and active)
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select r.is_admin from public.profiles p join public.roles r on r.code = p.role_code
    where p.user_id = auth.uid() and p.active
  ), false)
$$;

revoke all on function public.my_role(), public.is_member(), public.is_admin() from public, anon;
grant execute on function public.my_role(), public.is_member(), public.is_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'roles', 'domains', 'processes', 'subprocesses', 'procedures', 'tasks',
    'deviations', 'guide_sections', 'spaces', 'space_processes', 'space_roles',
    'space_notes', 'space_facts', 'space_task_overrides', 'profiles'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;

  -- Pasul 1: orice membru activ citește conținutul. (0002 restrânge pe rol.)
  foreach t in array array[
    'roles', 'domains', 'processes', 'subprocesses', 'procedures', 'tasks',
    'deviations', 'guide_sections', 'spaces', 'space_processes', 'space_roles',
    'space_notes', 'space_facts', 'space_task_overrides'
  ] loop
    execute format(
      'create policy "membrii citesc" on public.%I for select to authenticated using (public.is_member())', t);
  end loop;
end $$;

-- Profiluri: fiecare își vede profilul; adminul le vede pe toate.
create policy "profilul propriu sau admin" on public.profiles
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
