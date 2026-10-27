-- =============================================================================
-- Ghidul echipei Madame Magnifique · Jurnalul de croissant (Academia → Patiserie)
--
-- Se rulează după 0017, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Fiecare batch de aluat laminat: rețeta, détrempe, tururile, modelarea, dospirea,
-- coacerea și rezultatul. Jurnalul e comun: îl văd și îl completează patiseria
-- (PPT, PBP, PP + B), șefii producției (SP, DP), GM și AE. Un batch îl șterge doar
-- cine l-a scris sau adminul.
-- =============================================================================

create or replace function public.poate_jurnal()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (public.is_admin() or public.my_role() in ('PPT', 'PBP', 'PP + B', 'SP', 'DP', 'GM', 'AE'))
$$;
revoke all on function public.poate_jurnal() from public, anon;
grant execute on function public.poate_jurnal() to authenticated;

create table if not exists public.croissant_batches (
  id         bigint generated always as identity primary key,
  day        date not null default (now() at time zone 'Europe/Bucharest')::date,
  name       text not null default '',
  score      int check (score between 1 and 10),
  data       jsonb not null default '{}' check (jsonb_typeof(data) = 'object'),
  created_by uuid default auth.uid() references public.profiles (user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now()
);
create index if not exists croissant_batches_zi on public.croissant_batches (day desc, id desc);

create or replace function public.jurnal_atins()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' then new.created_by := old.created_by; new.created_at := old.created_at; end if;
  return new;
end $$;
drop trigger if exists jurnal_atins on public.croissant_batches;
create trigger jurnal_atins before insert or update on public.croissant_batches
  for each row execute function public.jurnal_atins();

alter table public.croissant_batches enable row level security;
revoke all on public.croissant_batches from anon, authenticated;
grant select, insert, update, delete on public.croissant_batches to authenticated;
grant all on public.croissant_batches to service_role;
drop policy if exists "jurnalul: patiseria și șefii citesc" on public.croissant_batches;
drop policy if exists "jurnalul: patiseria și șefii scriu" on public.croissant_batches;
drop policy if exists "jurnalul: patiseria și șefii modifică" on public.croissant_batches;
drop policy if exists "jurnalul: șterge autorul sau adminul" on public.croissant_batches;
create policy "jurnalul: patiseria și șefii citesc" on public.croissant_batches for select to authenticated
  using (public.poate_jurnal());
create policy "jurnalul: patiseria și șefii scriu" on public.croissant_batches for insert to authenticated
  with check (public.poate_jurnal() and created_by = auth.uid());
create policy "jurnalul: patiseria și șefii modifică" on public.croissant_batches for update to authenticated
  using (public.poate_jurnal()) with check (public.poate_jurnal());
create policy "jurnalul: șterge autorul sau adminul" on public.croissant_batches for delete to authenticated
  using (public.poate_jurnal() and (created_by = auth.uid() or public.is_admin()));

-- Numele autorilor (profilurile nu sunt publice în echipă).
create or replace function public.autori_jurnal()
returns table (user_id uuid, full_name text)
language sql stable security definer set search_path = public as $$
  select distinct p.user_id, p.full_name from public.profiles p
  join public.croissant_batches b on p.user_id in (b.created_by, b.updated_by)
  where public.poate_jurnal()
$$;
revoke all on function public.autori_jurnal() from public, anon;
grant execute on function public.autori_jurnal() to authenticated;
