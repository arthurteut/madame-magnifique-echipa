-- =============================================================================
-- Ghidul echipei Madame Magnifique · Procedurile verificate
--
-- Se rulează după 0005, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Textul procedurilor verificate pe teren (documentele din „Madame Verificate”),
-- legat de procedura din registru (PR-xx.y) și, unde diferă, de o locație.
-- Fișele unei locații (deschidere, închidere) au rol gol: le vede oricine vede
-- locația. PDF-ul original stă în bucketul privat „proceduri”.
-- Legătura cu registrul e doar prin cod (fără cheie străină): importul hărții
-- reface tabelul procedures și nu trebuie să șteargă documentele.
-- =============================================================================

create table if not exists public.procedure_docs (
  id             bigint generated always as identity primary key,
  procedure_code text,                                  -- PR-10.1; gol = fișă a locației
  role_code      text references public.roles (code) on delete cascade on update cascade,
  space_id       text references public.spaces (id) on delete cascade,  -- gol = toate locațiile
  title          text not null check (length(trim(title)) > 0),
  module         text not null default '',             -- „Modulul 25 · Vânzător de tură”
  body           text not null default '',             -- text simplu: „## ” titlu, „1. ” pas, „- ” listă
  source_file    text not null unique,                 -- numele PDF-ului din Drive
  pdf_path       text,                                 -- calea din bucketul „proceduri”
  position       int not null default 0,
  updated_at     timestamptz not null default now(),
  check (procedure_code is not null or space_id is not null or role_code is not null)
);
create index if not exists procedure_docs_code on public.procedure_docs (procedure_code);

-- Cine vede un document: rolul lui (sau cine îi vede procedurile) și, dacă e
-- legat de o locație, doar cine vede locația.
create or replace function public.can_see_procedure_doc(r text, s text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member()
     and (r is null or public.can_see_role(r))
     and (s is null or public.can_see_space(s))
$$;
revoke all on function public.can_see_procedure_doc(text, text) from public, anon;
grant execute on function public.can_see_procedure_doc(text, text) to authenticated;

alter table public.procedure_docs enable row level security;
revoke all on public.procedure_docs from anon, authenticated;
grant select, insert, update, delete on public.procedure_docs to authenticated;
grant all on public.procedure_docs to service_role;
drop policy if exists "cine vede rolul citește" on public.procedure_docs;
drop policy if exists "adminul editează procedurile verificate" on public.procedure_docs;
create policy "cine vede rolul citește" on public.procedure_docs for select to authenticated
  using (public.can_see_procedure_doc(role_code, space_id));
create policy "adminul editează procedurile verificate" on public.procedure_docs for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- PDF-urile: bucket privat; descarcă cine vede documentul.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('proceduri', 'proceduri', false, 20971520, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "proceduri: cine vede documentul descarcă" on storage.objects;
drop policy if exists "proceduri: adminul încarcă" on storage.objects;
drop policy if exists "proceduri: adminul modifică" on storage.objects;
drop policy if exists "proceduri: adminul șterge" on storage.objects;
create policy "proceduri: cine vede documentul descarcă" on storage.objects for select to authenticated
  using (bucket_id = 'proceduri' and exists (
    select 1 from public.procedure_docs d
    where d.pdf_path = storage.objects.name and public.can_see_procedure_doc(d.role_code, d.space_id)));
create policy "proceduri: adminul încarcă" on storage.objects for insert to authenticated
  with check (bucket_id = 'proceduri' and public.is_admin());
create policy "proceduri: adminul modifică" on storage.objects for update to authenticated
  using (bucket_id = 'proceduri' and public.is_admin()) with check (bucket_id = 'proceduri' and public.is_admin());
create policy "proceduri: adminul șterge" on storage.objects for delete to authenticated
  using (bucket_id = 'proceduri' and public.is_admin());
