-- Cursurile (0005): cine vede ce, testul, progresul și fișierele.
-- Rulează după 02 (conturile pe rol: GM = ...000000, V = ...000007,
-- CB2B = ...000009), 0003, 0004 și 0005. Fiecare rând trebuie să aibă ok = t.
\set ON_ERROR_STOP off
\pset footer off
create or replace function pg_temp.ca(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-' || u, false); end $$;

-- Un cont AE (0004 a adăugat rolul după ce 02 a creat conturile).
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000014', 'test.ae@x') on conflict do nothing;
insert into public.profiles (user_id, username, full_name, role_code)
values ('00000000-0000-0000-0000-000000000014', 'test.ae', 'Test AE', 'AE') on conflict do nothing;

-- Date: A comun, B pentru V, C pentru CB2B, D ciornă pentru V.
truncate public.courses restart identity cascade;
insert into public.courses (title, is_common, published, pass_percent) values
  ('A comun', true, true, 80), ('B vânzare', false, true, 50), ('C B2B', false, true, 80), ('D ciornă', false, false, 80);
insert into public.course_roles values (2, 'V'), (3, 'CB2B'), (4, 'V');
insert into public.lessons (course_id, position, title) values (1, 0, 'A1'), (2, 0, 'B1'), (2, 1, 'B2'), (3, 0, 'C1'), (4, 0, 'D1');
insert into public.lesson_files (lesson_id, name, path) values (2, 'b.pdf', '2/2/b.pdf'), (4, 'c.pdf', '3/4/c.pdf');
insert into public.quiz_questions (course_id, position, question, options) values
  (2, 0, 'Q1', array['a', 'b', 'c']), (2, 1, 'Q2', array['x', 'y']), (3, 0, 'QC', array['m', 'n']);
insert into public.quiz_answers values (1, 1), (2, 0), (3, 1);
delete from storage.objects where bucket_id = 'cursuri';
insert into storage.objects (bucket_id, name, owner) values ('cursuri', '2/2/b.pdf', null), ('cursuri', '3/4/c.pdf', null);

create temp table rez (test text, ok boolean);
grant all on rez to authenticated, anon;
set role authenticated;

-- Cine vede ce
select pg_temp.ca('000000000007');
insert into rez select 'V vede A și B', array_agg(title order by id) = array['A comun', 'B vânzare'] from public.courses;
insert into rez select 'V vede lecțiile A și B', count(*) = 3 from public.lessons;
insert into rez select 'V vede întrebările lui B, nu și ale lui C', count(*) = 2 from public.quiz_questions;
insert into rez select 'V nu vede răspunsurile', count(*) = 0 from public.quiz_answers;
insert into rez select 'V vede doar fișierele lui B', array_agg(path) = array['2/2/b.pdf'] from public.lesson_files;
insert into rez select 'Storage: V descarcă doar din B', array_agg(name) = array['2/2/b.pdf'] from storage.objects;
select pg_temp.ca('000000000009');
insert into rez select 'CB2B vede A și C', array_agg(title order by id) = array['A comun', 'C B2B'] from public.courses;
select pg_temp.ca('000000000014');
insert into rez select 'AE vede toate publicate, fără ciornă', array_agg(title order by id) = array['A comun', 'B vânzare', 'C B2B'] from public.courses;
insert into rez select 'AE nu vede răspunsurile', count(*) = 0 from public.quiz_answers;
select pg_temp.ca('000000000000');
insert into rez select 'GM vede toate, inclusiv ciorna', count(*) = 4 from public.courses;
insert into rez select 'GM vede răspunsurile', count(*) = 3 from public.quiz_answers;

-- Testul
select pg_temp.ca('000000000007');
insert into rez select 'V: 1 din 2 corect, trece la 50%', score = 1 and total = 2 and passed and correct = array[true, false]
  from public.submit_quiz(2, array[1, 1]);
insert into rez select 'V: răspunsuri lipsă = greșite', score = 0 and not passed from public.submit_quiz(2, array[]::int[]);
insert into rez select 'V își vede încercările', count(*) = 2 from public.quiz_attempts;
do $$ begin perform public.submit_quiz(3, array[1]); insert into rez values ('V nu dă testul lui C', false);
exception when others then insert into rez values ('V nu dă testul lui C', true); end $$;
do $$ begin perform public.submit_quiz(4, array[0]); insert into rez values ('V nu dă testul ciornei', false);
exception when others then insert into rez values ('V nu dă testul ciornei', true); end $$;
do $$ begin insert into public.quiz_attempts (user_id, course_id, answers, score, total, passed)
  values (auth.uid(), 2, '{}', 2, 2, true); insert into rez values ('V nu-și scrie singur scorul', false);
exception when others then insert into rez values ('V nu-și scrie singur scorul', true); end $$;

-- Progresul
insert into public.lesson_progress (lesson_id) values (2);
insert into rez select 'V își bifează lecția', count(*) = 1 from public.lesson_progress;
do $$ begin insert into public.lesson_progress (lesson_id) values (4); insert into rez values ('V nu bifează lecția lui C', false);
exception when others then insert into rez values ('V nu bifează lecția lui C', true); end $$;
do $$ begin insert into public.lesson_progress (user_id, lesson_id) values ('00000000-0000-0000-0000-000000000006', 2);
  insert into rez values ('V nu bifează pentru altcineva', false);
exception when others then insert into rez values ('V nu bifează pentru altcineva', true); end $$;
select pg_temp.ca('000000000009');
insert into public.lesson_progress (lesson_id) values (1);
insert into rez select 'CB2B nu vede progresul lui V', count(*) = 1 from public.lesson_progress;
select pg_temp.ca('000000000000');
insert into rez select 'GM vede progresul și încercările tuturor',
  (select count(*) from public.lesson_progress) = 2 and (select count(*) from public.quiz_attempts) = 2;

-- Scrierea
select pg_temp.ca('000000000007');
do $$ begin insert into public.courses (title) values ('hack'); insert into rez values ('V nu creează cursuri', false);
exception when others then insert into rez values ('V nu creează cursuri', true); end $$;
update public.courses set title = 'hack' where id = 2;
delete from public.lessons where id = 2;
do $$ begin insert into storage.objects (bucket_id, name) values ('cursuri', '2/2/hack.pdf'); insert into rez values ('V nu încarcă fișiere', false);
exception when others then insert into rez values ('V nu încarcă fișiere', true); end $$;
select pg_temp.ca('000000000014');
do $$ begin insert into public.courses (title) values ('hack'); insert into rez values ('AE nu creează cursuri', false);
exception when others then insert into rez values ('AE nu creează cursuri', true); end $$;
select pg_temp.ca('000000000000');
insert into rez select 'V nu modifică și nu șterge', title = 'B vânzare' and exists (select 1 from public.lessons where id = 2)
  from public.courses where id = 2;
insert into public.courses (title, published) values ('E nou', true);
insert into public.course_roles select id, 'VT' from public.courses where title = 'E nou';
insert into public.lessons (course_id, title) select id, 'E1' from public.courses where title = 'E nou';
insert into public.quiz_questions (course_id, question, options) select id, 'QE', array['1', '2'] from public.courses where title = 'E nou';
insert into public.quiz_answers select id, 0 from public.quiz_questions where question = 'QE';
update public.courses set description = 'gata' where title = 'E nou';
insert into storage.objects (bucket_id, name) select 'cursuri', id || '/1/e.pdf' from public.courses where title = 'E nou';
insert into rez select 'GM creează curs, lecție, test, fișier',
  description = 'gata' and exists (select 1 from storage.objects where name = c.id || '/1/e.pdf')
  and exists (select 1 from public.quiz_answers a join public.quiz_questions q on q.id = a.question_id where q.course_id = c.id)
  from public.courses c where title = 'E nou';
delete from public.courses where title = 'E nou';
insert into rez select 'GM șterge cursul cu tot cu lecții', not exists (select 1 from public.lessons where title = 'E1');

reset role;
insert into rez select 'Pagina Cursuri pentru toate rolurile (în afară de BRT, după 0008)',
  (select count(*) from public.roles where code <> 'BRT') = (select count(*) from public.role_section_access where section = 'cursuri' and role_code <> 'BRT');
insert into rez select 'Bucketul e privat', not public from storage.buckets where id = 'cursuri';
set role anon;
do $$ begin perform 1 from public.courses; insert into rez values ('Anonimul nu citește cursuri', false);
exception when others then insert into rez values ('Anonimul nu citește cursuri', true); end $$;
reset role;

select * from rez;
select count(*) filter (where ok) || ' din ' || count(*) as rezultat from rez;
