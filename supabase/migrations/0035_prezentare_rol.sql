-- 0035 · Ecranul de prezentare a rolului, la primele trei deschideri
--
-- Responsabilul de locație vede, la primele trei deschideri ale aplicației, un ecran cu rolul lui:
-- de ce răspunde, ce are de făcut și unde găsește fiecare lucru. Numărătoarea e pe cont, nu pe telefon.
-- Se poate rula de mai multe ori.

create table if not exists public.prezentari_rol (
  user_id uuid primary key,
  vazute  int not null default 0,
  ultima  timestamptz not null default now()
);
alter table public.prezentari_rol enable row level security;
revoke all on public.prezentari_rol from anon, authenticated;
grant all on public.prezentari_rol to service_role;

-- Întoarce a câta prezentare e (1, 2 sau 3) și o numără; 0 = nu se mai arată.
create or replace function public.prezentare_rol()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_member() or public.my_role() is distinct from 'RL' then return 0; end if;
  insert into public.prezentari_rol (user_id, vazute) values (auth.uid(), 1)
  on conflict (user_id) do update set vazute = public.prezentari_rol.vazute + 1, ultima = now() where public.prezentari_rol.vazute < 3
  returning vazute into n;
  return coalesce(n, 0);
end $$;
revoke all on function public.prezentare_rol() from public, anon;
grant execute on function public.prezentare_rol() to authenticated;

notify pgrst, 'reload schema';
