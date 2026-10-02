-- Pasul 3: cine poate scrie. Rulează după 02 (care creează câte un cont pe rol:
-- GM = ...000000, VT = ...000006, V = ...000007).
\set ON_ERROR_STOP off
\pset footer off
create or replace function pg_temp.ca(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-' || u, false); end $$;

set role authenticated;

-- GM schimbă rolul unui V în BAR și îl dezactivează: permis
select pg_temp.ca('000000000000');
update public.profiles set role_code = 'BAR', active = false where username = 'test.v';
reset role; select 'GM modifică alt cont' as test, role_code = 'BAR' and not active as ok from public.profiles where username = 'test.v';
update public.profiles set role_code = 'V', active = true where username = 'test.v';

-- GM își schimbă propriul rol: blocat (0 rânduri)
set role authenticated; select pg_temp.ca('000000000000');
update public.profiles set role_code = 'V' where username = 'test.gm';
reset role; select 'GM nu se poate retrograda' as test, role_code = 'GM' as ok from public.profiles where username = 'test.gm';

-- GM nu poate schimba username-ul (coloană fără drept de update)
set role authenticated; select pg_temp.ca('000000000000');
update public.profiles set username = 'altul' where username = 'test.v';
reset role; select 'username nemodificabil' as test, exists (select 1 from public.profiles where username = 'test.v') as ok;

-- GM dă acces VT la B2B și îl scoate: permis
set role authenticated; select pg_temp.ca('000000000000');
insert into public.role_space_access values ('VT', 'b2b');
reset role; select 'GM adaugă acces' as test, exists (select 1 from public.role_space_access where role_code = 'VT' and space_id = 'b2b') as ok;
set role authenticated; select pg_temp.ca('000000000000');
delete from public.role_space_access where role_code = 'VT' and space_id = 'b2b';
reset role; select 'GM scoate acces' as test, not exists (select 1 from public.role_space_access where role_code = 'VT' and space_id = 'b2b') as ok;

-- VT încearcă să-și dea acces la B2B: refuzat
set role authenticated; select pg_temp.ca('000000000006');
insert into public.role_space_access values ('VT', 'b2b');
reset role; select 'VT nu-și poate da acces' as test, not exists (select 1 from public.role_space_access where role_code = 'VT' and space_id = 'b2b') as ok;

-- VT încearcă să se facă GM: 0 rânduri
set role authenticated; select pg_temp.ca('000000000006');
update public.profiles set role_code = 'GM' where username = 'test.vt';
reset role; select 'VT nu se poate promova' as test, role_code = 'VT' as ok from public.profiles where username = 'test.vt';

-- VT încearcă să șteargă accesul altui rol: 0 rânduri
set role authenticated; select pg_temp.ca('000000000006');
delete from public.role_space_access where role_code = 'V';
reset role; select 'VT nu poate scoate drepturi' as test, (select count(*) from public.role_space_access where role_code = 'V') = 3 as ok;
