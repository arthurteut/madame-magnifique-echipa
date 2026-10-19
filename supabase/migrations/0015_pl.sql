-- =============================================================================
-- Ghidul echipei Madame Magnifique · P&L (profit și pierdere)
--
-- Se rulează după 0014, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Pagina „P&L” (modelul ATC P&L Toolkit): completezi lunar veniturile și costurile,
-- pagina calculează venitul net, marjele, prime cost, pragul de rentabilitate și
-- semnalele față de ținte.
--
-- Acces: DOAR rolurile GM, AE, EC și ADM. Lista e fixată în can_use_pl(): chiar
-- dacă cineva bifează pagina „pl” pentru alt rol, datele nu ajung la el. Rândul
-- din role_section_access doar o arată în meniu; dacă îl scoți, rolul pierde accesul.
--
--   pl_books   un P&L = o entitate (firma, o locație) pe un an, cu setările lui
--   pl_months  sumele introduse pentru fiecare lună (jsonb: linie → lei)
--   pl_guide   ghidul de interpretare, benchmark-urile, glosarul (conținut intern,
--              se încarcă separat, nu stă în repo)
-- =============================================================================

-- Pagina „pl” în meniu.
alter table public.role_section_access drop constraint if exists role_section_access_section_check;
alter table public.role_section_access add constraint role_section_access_section_check
  check (section in ('roluri', 'proceduri', 'ghid', 'cursuri', 'brutar', 'pl'));
insert into public.role_section_access (role_code, section)
select r, 'pl' from (values ('GM'), ('AE'), ('EC'), ('ADM')) v (r)
where exists (select 1 from public.roles where code = r)
on conflict do nothing;

create or replace function public.can_use_pl()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member()
     and public.my_role() in ('GM', 'AE', 'EC', 'ADM')
     and public.can_see_section('pl')
$$;
revoke all on function public.can_use_pl() from public, anon;
grant execute on function public.can_use_pl() to authenticated;

create table if not exists public.pl_books (
  id         bigint generated always as identity primary key,
  name       text not null check (length(trim(name)) > 0),
  year       int not null check (year between 2000 and 2100),
  settings   jsonb not null default '{}' check (jsonb_typeof(settings) = 'object'),
  position   int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique (name, year)
);

create table if not exists public.pl_months (
  book_id    bigint not null references public.pl_books (id) on delete cascade,
  month      int not null check (month between 1 and 12),
  data       jsonb not null default '{}' check (jsonb_typeof(data) = 'object'),
  note       text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key (book_id, month)
);

create table if not exists public.pl_guide (
  slug     text primary key,
  position int not null default 0,
  title    text not null check (length(trim(title)) > 0),
  body     text not null default '',                 -- text simplu: ##, ###, 1., -, | tabel |, > casetă
  updated_at timestamptz not null default now()
);

-- Cine a modificat ultimul și când.
create or replace function public.pl_touch()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;
drop trigger if exists pl_books_touch on public.pl_books;
create trigger pl_books_touch before insert or update on public.pl_books
  for each row execute function public.pl_touch();
drop trigger if exists pl_months_touch on public.pl_months;
create trigger pl_months_touch before insert or update on public.pl_months
  for each row execute function public.pl_touch();

alter table public.pl_books enable row level security;
alter table public.pl_months enable row level security;
alter table public.pl_guide enable row level security;
revoke all on public.pl_books, public.pl_months, public.pl_guide from anon, authenticated;
grant select, insert, update, delete on public.pl_books, public.pl_months to authenticated;
grant select on public.pl_guide to authenticated;
grant all on public.pl_books, public.pl_months, public.pl_guide to service_role;

drop policy if exists "P&L: citire" on public.pl_books;
drop policy if exists "P&L: adăugare" on public.pl_books;
drop policy if exists "P&L: modificare" on public.pl_books;
drop policy if exists "P&L: ștergere doar admin" on public.pl_books;
create policy "P&L: citire" on public.pl_books for select to authenticated using (public.can_use_pl());
create policy "P&L: adăugare" on public.pl_books for insert to authenticated with check (public.can_use_pl());
create policy "P&L: modificare" on public.pl_books for update to authenticated
  using (public.can_use_pl()) with check (public.can_use_pl());
create policy "P&L: ștergere doar admin" on public.pl_books for delete to authenticated
  using (public.can_use_pl() and public.is_admin());

drop policy if exists "P&L: citire" on public.pl_months;
drop policy if exists "P&L: adăugare" on public.pl_months;
drop policy if exists "P&L: modificare" on public.pl_months;
drop policy if exists "P&L: golire" on public.pl_months;
create policy "P&L: citire" on public.pl_months for select to authenticated using (public.can_use_pl());
create policy "P&L: adăugare" on public.pl_months for insert to authenticated with check (public.can_use_pl());
create policy "P&L: modificare" on public.pl_months for update to authenticated
  using (public.can_use_pl()) with check (public.can_use_pl());
create policy "P&L: golire" on public.pl_months for delete to authenticated using (public.can_use_pl());

drop policy if exists "P&L: ghidul" on public.pl_guide;
create policy "P&L: ghidul" on public.pl_guide for select to authenticated using (public.can_use_pl());

-- Primul P&L: firma întreagă, anul curent. Setările goale = valorile implicite din
-- pagină (TVA 11/11/11/21%, CAM 2,25%, ținte 30/30/30/10, prag prime cost 65%).
insert into public.pl_books (name, year)
values ('Madame Magnifique', extract(year from now())::int)
on conflict (name, year) do nothing;
