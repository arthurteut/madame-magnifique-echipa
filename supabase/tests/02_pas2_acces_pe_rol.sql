-- Pasul 2: ce primește fiecare rol din baza de date (RLS). Rulează după
-- 00_mediu_supabase_local.sql, 0001, importul conținutului și 0002.
\pset footer off

-- Câte un utilizator de test pentru fiecare rol.
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-' || lpad(position::text, 12, '0'))::uuid,
       'test.' || lower(replace(code, ' + ', '')) || '@echipa.madamemagnifique.ro'
from public.roles on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
select ('00000000-0000-0000-0000-' || lpad(position::text, 12, '0'))::uuid,
       'test.' || lower(replace(code, ' + ', '')), 'Test ' || code, code
from public.roles on conflict do nothing;

create or replace function pg_temp.ce_vede(u uuid)
returns table (spatii text, proceduri int, taskuri int, procese int, roluri int, abateri int, fapte int, ajustari int)
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  set local role authenticated;
  return query select
    (select coalesce(string_agg(id, ',' order by position), '-') from public.spaces),
    (select count(*)::int from public.procedures), (select count(*)::int from public.tasks),
    (select count(*)::int from public.processes), (select count(*)::int from public.roles),
    (select count(*)::int from public.deviations), (select count(*)::int from public.space_facts),
    (select count(*)::int from public.space_task_overrides);
end $$;

select r.code as rol, v.*
from public.roles r, lateral pg_temp.ce_vede(('00000000-0000-0000-0000-' || lpad(r.position::text, 12, '0'))::uuid) v
order by r.position;
