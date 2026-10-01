-- =============================================================================
-- Ghidul echipei Madame Magnifique · Pasul 2: accesul pe rol (RBAC)
--
-- Se rulează după 0001, în Supabase → SQL Editor.
--
-- Fiecare utilizator primește din baza de date DOAR rândurile rolului lui:
--   - spațiile din role_space_access (și tot ce ține de ele: fișă, note, abateri);
--   - procedurile și task-urile rolului lui și ale rolurilor din role_role_access;
--   - procesele care apar în spațiile lui sau pe care le conduce un rol vizibil.
-- Adminii (roles.is_admin, implicit GM) văd tot.
-- Matricea se schimbă din panoul de admin (pasul 3) sau direct în tabele.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Matricea de acces
-- ---------------------------------------------------------------------------
create table public.role_space_access (            -- ce spații vede un rol
  role_code text not null references public.roles (code) on delete cascade,
  space_id  text not null references public.spaces (id) on delete cascade,
  primary key (role_code, space_id)
);

create table public.role_role_access (             -- ale cui proceduri le mai vede
  viewer_role text not null references public.roles (code) on delete cascade,
  sees_role   text not null references public.roles (code) on delete cascade,
  primary key (viewer_role, sees_role),
  check (viewer_role <> sees_role)
);

create table public.role_section_access (          -- ce pagini apar în meniu
  role_code text not null references public.roles (code) on delete cascade,
  section   text not null check (section in ('roluri', 'proceduri', 'ghid')),
  primary key (role_code, section)
);

-- ---------------------------------------------------------------------------
-- Funcții de acces (security definer: citesc matricea fără să treacă prin RLS)
-- ---------------------------------------------------------------------------
create or replace function public.can_see_role(r text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or r = public.my_role()
      or exists (select 1 from public.role_role_access
                 where viewer_role = public.my_role() and sees_role = r)
$$;

create or replace function public.can_see_space(s text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or exists (select 1 from public.role_space_access
                 where role_code = public.my_role() and space_id = s)
$$;

create or replace function public.can_see_process(p text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin()
      -- apare într-un spațiu vizibil (lista lui de procese)…
      or exists (select 1 from public.space_processes sp
                 where sp.process_code = p and public.can_see_space(sp.space_id))
      -- …sau în domeniile unui spațiu vizibil (biroul central)…
      or exists (select 1 from public.spaces s join public.processes pr on pr.code = p
                 where pr.domain_code = any (s.domains) and public.can_see_space(s.id))
      -- …sau îl conduce un rol vizibil (fișa rolului)
      or exists (select 1 from public.processes pr
                 where pr.code = p and pr.lead_role is not null and public.can_see_role(pr.lead_role))
$$;

-- Un task e vizibil dacă e al unui rol vizibil, sau dacă într-un spațiu vizibil
-- o ajustare locală îl dă unui rol vizibil (ex.: PP + B descuie la Porumbescu).
create or replace function public.can_see_task(t int)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.tasks where id = t and public.can_see_role(role_code))
      or exists (select 1 from public.space_task_overrides o
                 where o.task_id = t and o.role_code is not null
                   and public.can_see_space(o.space_id) and public.can_see_role(o.role_code))
$$;

create or replace function public.can_see_deviation(loc text, zona text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.spaces s
    where public.can_see_space(s.id)
      and (s.deviations_location = loc
           or coalesce(s.deviations_filter -> loc, '[]'::jsonb) ? zona)
  )
$$;

revoke all on function public.can_see_role(text), public.can_see_space(text), public.can_see_process(text),
  public.can_see_task(int), public.can_see_deviation(text, text) from public, anon;
grant execute on function public.can_see_role(text), public.can_see_space(text), public.can_see_process(text),
  public.can_see_task(int), public.can_see_deviation(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Regulile de citire: înlocuiesc „membrii citesc” din 0001
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'roles', 'domains', 'processes', 'subprocesses', 'procedures', 'tasks', 'deviations',
    'spaces', 'space_processes', 'space_roles', 'space_notes', 'space_facts', 'space_task_overrides'
  ] loop
    execute format('drop policy if exists "membrii citesc" on public.%I', t);
  end loop;
end $$;

create policy "rolul vede rolurile lui" on public.roles for select to authenticated
  using (public.is_member() and public.can_see_role(code));

create policy "spațiile rolului" on public.spaces for select to authenticated
  using (public.is_member() and public.can_see_space(id));

create policy "procesele rolului" on public.processes for select to authenticated
  using (public.is_member() and public.can_see_process(code));

create policy "sub-procesele rolului" on public.subprocesses for select to authenticated
  using (public.is_member() and public.can_see_process(process_code));

create policy "domeniile rolului" on public.domains for select to authenticated
  using (public.is_member() and exists (
    select 1 from public.processes p where p.domain_code = domains.code and public.can_see_process(p.code)));

create policy "procedurile rolului" on public.procedures for select to authenticated
  using (public.is_member() and public.can_see_role(role_code));

create policy "task-urile rolului" on public.tasks for select to authenticated
  using (public.is_member() and public.can_see_task(id));

create policy "abaterile spațiilor rolului" on public.deviations for select to authenticated
  using (public.is_member() and public.can_see_deviation(location, area));

do $$
declare t text;
begin
  foreach t in array array['space_processes', 'space_roles', 'space_notes', 'space_facts'] loop
    execute format(
      'create policy "datele spațiilor rolului" on public.%I for select to authenticated
         using (public.is_member() and public.can_see_space(space_id))', t);
  end loop;
end $$;

-- Ajustările locale: doar în spațiile vizibile și doar pentru task-urile vizibile.
create policy "ajustările task-urilor vizibile" on public.space_task_overrides for select to authenticated
  using (public.is_member() and public.can_see_space(space_id) and public.can_see_task(task_id));

-- guide_sections („Cum funcționează”) rămâne vizibil tuturor membrilor (0001).

-- Matricea: fiecare își vede rândurile rolului; adminul le vede pe toate.
do $$
declare t text;
begin
  foreach t in array array['role_space_access', 'role_section_access'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format(
      'create policy "matricea rolului" on public.%I for select to authenticated
         using (public.is_admin() or (public.is_member() and role_code = public.my_role()))', t);
  end loop;
end $$;
alter table public.role_role_access enable row level security;
revoke all on public.role_role_access from anon, authenticated;
grant select on public.role_role_access to authenticated;
grant all on public.role_role_access to service_role;
create policy "matricea rolului" on public.role_role_access for select to authenticated
  using (public.is_admin() or (public.is_member() and viewer_role = public.my_role()));

-- ---------------------------------------------------------------------------
-- Matricea inițială (confirmată pe 1 octombrie 2026)
-- ---------------------------------------------------------------------------
insert into public.role_space_access (role_code, space_id)
select r, s from (values
  ('GM', 'porumbescu'), ('GM', 'dumbravita'), ('GM', 'fructus'), ('GM', 'peciu-nou'),
  ('GM', 'laborator-fructus'), ('GM', 'b2b'), ('GM', 'birou'),
  ('RL', 'porumbescu'), ('RL', 'dumbravita'), ('RL', 'fructus'),
  ('VT', 'porumbescu'), ('VT', 'dumbravita'), ('VT', 'fructus'),
  ('V', 'porumbescu'), ('V', 'dumbravita'), ('V', 'fructus'),
  ('BAR', 'porumbescu'), ('BAR', 'dumbravita'), ('BAR', 'fructus'),
  ('PP + B', 'porumbescu'), ('PP + B', 'dumbravita'), ('PP + B', 'fructus'),
  ('DP', 'peciu-nou'), ('DP', 'laborator-fructus'),
  ('SP', 'peciu-nou'), ('SP', 'laborator-fructus'),
  ('GD', 'peciu-nou'), ('GD', 'laborator-fructus'),
  ('LOG', 'peciu-nou'), ('LOG', 'laborator-fructus'), ('LOG', 'porumbescu'),
  ('LOG', 'dumbravita'), ('LOG', 'fructus'), ('LOG', 'b2b'),
  ('CB2B', 'b2b'), ('CB2B', 'laborator-fructus'),
  ('MKT', 'birou'), ('ADM', 'birou'), ('EC', 'birou')
) v (r, s)
where exists (select 1 from public.roles where code = r)
  and exists (select 1 from public.spaces where id = s)
on conflict do nothing;

insert into public.role_role_access (viewer_role, sees_role)
select v, s from (values
  ('RL', 'VT'), ('RL', 'V'), ('RL', 'BAR'), ('RL', 'PP + B'),
  ('VT', 'V'), ('VT', 'BAR'), ('VT', 'PP + B'),
  ('DP', 'SP'), ('DP', 'GD')
) x (v, s)
where exists (select 1 from public.roles where code = v)
  and exists (select 1 from public.roles where code = s)
on conflict do nothing;

insert into public.role_section_access (role_code, section)
select r.code, s.section from public.roles r
cross join (values ('roluri'), ('proceduri'), ('ghid')) s (section)
on conflict do nothing;
