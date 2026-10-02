-- =============================================================================
-- Ghidul echipei Madame Magnifique · Cursurile de onboarding
--
-- Se rulează după 0004, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Un curs are lecții (text, video din link, fișiere) și, opțional, un test la
-- final. Cine îl vede:
--   - cursurile comune (is_common): toți angajații;
--   - celelalte: rolurile bifate în course_roles;
--   - GM și AE (sees_all) văd toate cursurile publicate;
--   - adminul vede și ciornele (published = false) și le editează.
-- Răspunsurile corecte stau într-un tabel separat (quiz_answers), pe care îl
-- citește doar adminul. Testul se corectează în baza de date (submit_quiz),
-- așa că angajatul nu poate vedea și nu poate trimite singur un scor.
-- Fișierele stau în Storage, în bucketul privat „cursuri”, la
-- <id curs>/<id lecție>/<fișier>: le descarcă doar cine vede cursul.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Tabele
-- ---------------------------------------------------------------------------
create table if not exists public.courses (
  id           bigint generated always as identity primary key,
  title        text not null check (length(trim(title)) > 0),
  description  text not null default '',
  is_common    boolean not null default false,      -- pentru toată echipa
  published    boolean not null default false,      -- ciornele le vede doar adminul
  pass_percent int not null default 80 check (pass_percent between 0 and 100),
  position     int not null default 0,
  created_at   timestamptz not null default now()
);

create table if not exists public.course_roles (
  course_id bigint not null references public.courses (id) on delete cascade,
  role_code text not null references public.roles (code) on delete cascade on update cascade,
  primary key (course_id, role_code)
);

create table if not exists public.lessons (
  id        bigint generated always as identity primary key,
  course_id bigint not null references public.courses (id) on delete cascade,
  position  int not null default 0,
  title     text not null check (length(trim(title)) > 0),
  body      text not null default '',               -- text simplu: paragrafe, „- ” listă, „## ” titlu
  video_url text not null default '' check (video_url = '' or video_url ~ '^https://')
);

create table if not exists public.lesson_files (
  id         bigint generated always as identity primary key,
  lesson_id  bigint not null references public.lessons (id) on delete cascade,
  name       text not null,                         -- numele afișat
  path       text not null unique,                  -- calea din bucketul „cursuri”
  mime       text not null default '',
  size       bigint not null default 0,
  position   int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.quiz_questions (
  id        bigint generated always as identity primary key,
  course_id bigint not null references public.courses (id) on delete cascade,
  position  int not null default 0,
  question  text not null check (length(trim(question)) > 0),
  options   text[] not null check (cardinality(options) between 2 and 6)
);

create table if not exists public.quiz_answers (     -- doar adminul
  question_id bigint primary key references public.quiz_questions (id) on delete cascade,
  correct     int not null check (correct >= 0)     -- indexul variantei corecte (de la 0)
);

create table if not exists public.lesson_progress (
  user_id   uuid not null default auth.uid() references public.profiles (user_id) on delete cascade,
  lesson_id bigint not null references public.lessons (id) on delete cascade,
  done_at   timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create table if not exists public.quiz_attempts (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (user_id) on delete cascade,
  course_id  bigint not null references public.courses (id) on delete cascade,
  answers    int[] not null,
  score      int not null,
  total      int not null,
  passed     boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists quiz_attempts_user_course on public.quiz_attempts (user_id, course_id);

-- ---------------------------------------------------------------------------
-- Cine vede un curs
-- ---------------------------------------------------------------------------
create or replace function public.can_see_course(c bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and (
    public.is_admin()
    or exists (
      select 1 from public.courses k
      where k.id = c and k.published
        and (public.sees_all() or k.is_common
             or exists (select 1 from public.course_roles cr
                        where cr.course_id = k.id and cr.role_code = public.my_role()))))
$$;

create or replace function public.can_see_lesson(l bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.lessons where id = l and public.can_see_course(course_id))
$$;

-- Primul segment din calea fișierului e id-ul cursului.
create or replace function public.curs_din_cale(p text)
returns bigint language sql immutable as $$
  select case when split_part(p, '/', 1) ~ '^[0-9]{1,18}$' then split_part(p, '/', 1)::bigint end
$$;

-- Corectarea testului. Întoarce scorul și, pentru fiecare întrebare, dacă
-- răspunsul a fost corect (fără să dezvăluie varianta corectă).
create or replace function public.submit_quiz(p_course bigint, p_answers int[])
returns table (score int, total int, passed boolean, correct boolean[])
language plpgsql volatile security definer set search_path = public as $$
declare
  v_ok boolean[];
  v_score int;
  v_total int;
  v_pass int;
begin
  if not public.can_see_course(p_course) then
    raise exception 'Cursul nu există sau nu ai acces la el.' using errcode = '42501';
  end if;
  select coalesce(array_agg(coalesce(p_answers[q.n::int] = a.correct, false) order by q.n), '{}'),
         count(*) filter (where p_answers[q.n::int] = a.correct), count(*)
    into v_ok, v_score, v_total
  from (select id, row_number() over (order by position, id) as n
        from public.quiz_questions where course_id = p_course) q
  join public.quiz_answers a on a.question_id = q.id;
  if v_total = 0 then
    raise exception 'Cursul nu are test.' using errcode = '22023';
  end if;
  select pass_percent into v_pass from public.courses where id = p_course;
  insert into public.quiz_attempts (user_id, course_id, answers, score, total, passed)
  values (auth.uid(), p_course, p_answers, v_score, v_total, v_score * 100 >= v_pass * v_total);
  return query select v_score, v_total, v_score * 100 >= v_pass * v_total, v_ok;
end $$;

revoke all on function public.can_see_course(bigint), public.can_see_lesson(bigint),
  public.submit_quiz(bigint, int[]) from public, anon;
grant execute on function public.can_see_course(bigint), public.can_see_lesson(bigint),
  public.submit_quiz(bigint, int[]) to authenticated;
grant execute on function public.curs_din_cale(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['courses', 'course_roles', 'lessons', 'lesson_files', 'quiz_questions',
                           'quiz_answers', 'lesson_progress', 'quiz_attempts'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
  -- Conținutul: citește cine vede cursul; scrie doar adminul.
  foreach t in array array['courses', 'course_roles', 'lessons', 'lesson_files', 'quiz_questions', 'quiz_answers'] loop
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop policy if exists "cine vede cursul citește" on public.%I', t);
    execute format('drop policy if exists "adminul editează cursurile" on public.%I', t);
    execute format(
      'create policy "adminul editează cursurile" on public.%I for all to authenticated
         using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

create policy "cine vede cursul citește" on public.courses for select to authenticated
  using (public.can_see_course(id));
create policy "cine vede cursul citește" on public.course_roles for select to authenticated
  using (public.can_see_course(course_id));
create policy "cine vede cursul citește" on public.lessons for select to authenticated
  using (public.can_see_course(course_id));
create policy "cine vede cursul citește" on public.lesson_files for select to authenticated
  using (public.can_see_lesson(lesson_id));
create policy "cine vede cursul citește" on public.quiz_questions for select to authenticated
  using (public.can_see_course(course_id));
-- quiz_answers: doar politica adminului.

-- Progresul: fiecare își bifează lecțiile; adminul vede progresul tuturor.
grant select, insert, delete on public.lesson_progress to authenticated;
drop policy if exists "progresul propriu" on public.lesson_progress;
drop policy if exists "bifez lecția" on public.lesson_progress;
drop policy if exists "debifez lecția" on public.lesson_progress;
create policy "progresul propriu" on public.lesson_progress for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy "bifez lecția" on public.lesson_progress for insert to authenticated
  with check (user_id = auth.uid() and public.can_see_lesson(lesson_id));
create policy "debifez lecția" on public.lesson_progress for delete to authenticated
  using (user_id = auth.uid());

-- Încercările la test se scriu doar prin submit_quiz().
grant select on public.quiz_attempts to authenticated;
drop policy if exists "încercările proprii" on public.quiz_attempts;
create policy "încercările proprii" on public.quiz_attempts for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------------------
-- Pagina „Cursuri” în meniu: o primesc toate rolurile.
-- ---------------------------------------------------------------------------
alter table public.role_section_access drop constraint if exists role_section_access_section_check;
alter table public.role_section_access add constraint role_section_access_section_check
  check (section in ('roluri', 'proceduri', 'ghid', 'cursuri'));
insert into public.role_section_access (role_code, section)
select code, 'cursuri' from public.roles
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Fișierele: bucket privat „cursuri” (max. 50 MB pe fișier)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cursuri', 'cursuri', false, 52428800, array[
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "cursuri: cine vede cursul descarcă" on storage.objects;
drop policy if exists "cursuri: adminul încarcă" on storage.objects;
drop policy if exists "cursuri: adminul modifică" on storage.objects;
drop policy if exists "cursuri: adminul șterge" on storage.objects;
create policy "cursuri: cine vede cursul descarcă" on storage.objects for select to authenticated
  using (bucket_id = 'cursuri' and public.can_see_course(public.curs_din_cale(name)));
create policy "cursuri: adminul încarcă" on storage.objects for insert to authenticated
  with check (bucket_id = 'cursuri' and public.is_admin());
create policy "cursuri: adminul modifică" on storage.objects for update to authenticated
  using (bucket_id = 'cursuri' and public.is_admin()) with check (bucket_id = 'cursuri' and public.is_admin());
create policy "cursuri: adminul șterge" on storage.objects for delete to authenticated
  using (bucket_id = 'cursuri' and public.is_admin());
