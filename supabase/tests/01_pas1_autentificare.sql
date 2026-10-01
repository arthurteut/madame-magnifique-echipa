\pset footer off
select 'roles' t, count(*) from roles union all select 'processes',count(*) from processes
union all select 'subprocesses',count(*) from subprocesses union all select 'procedures',count(*) from procedures
union all select 'tasks',count(*) from tasks union all select 'spaces',count(*) from spaces
union all select 'space_facts',count(*) from space_facts union all select 'overrides',count(*) from space_task_overrides;

-- utilizatori de test
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000a1','ana.gm@echipa.madamemagnifique.ro'),
 ('00000000-0000-0000-0000-0000000000b2','ion.vt@echipa.madamemagnifique.ro'),
 ('00000000-0000-0000-0000-0000000000c3','fost.v@echipa.madamemagnifique.ro'),
 ('00000000-0000-0000-0000-0000000000d4','fara.profil@echipa.madamemagnifique.ro');
insert into profiles (user_id, username, full_name, role_code, active) values
 ('00000000-0000-0000-0000-0000000000a1','ana.gm','Ana','GM',true),
 ('00000000-0000-0000-0000-0000000000b2','ion.vt','Ion','VT',true),
 ('00000000-0000-0000-0000-0000000000c3','fost.v','Fost angajat','V',false);

-- anonim: nu vede nimic
set role anon;
select 'anon procedures' t, (select count(*) from procedures) n;
reset role;
\pset footer off
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false);
select 'VT: procedures' t, count(*) from procedures union all select 'VT: profiles vizibile', count(*) from profiles
union all select 'VT: is_admin', public.is_admin()::int union all select 'VT: my_role=VT', (public.my_role()='VT')::int;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',false);
select 'GM: profiles vizibile' t, count(*) from profiles union all select 'GM: is_admin', public.is_admin()::int;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c3',false);
select 'inactiv: procedures' t, count(*) from procedures union all select 'inactiv: profil propriu', count(*) from profiles;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d4',false);
select 'fara profil: procedures' t, count(*) from procedures;
-- scrierea e interzisă din pagină
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',false);
