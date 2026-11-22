-- =============================================================================
-- Ghidul echipei Madame Magnifique · Standarde: verificarea pe grupe, cu o singură poză
--
-- Se rulează după 0027, în Supabase → SQL Editor. Se poate rula de mai multe ori.
--
-- Magazinul verifică o secție întreagă dintr-o dată: o singură poză cu toate produsele (de sus, tăiate
-- și netăiate) și, doar la produsul care are o problemă, criteriile picate și o explicație.
-- Fiecare produs își păstrează verificarea lui (pentru decizie, cauză și istoric), cu aceeași poză.
-- =============================================================================
-- p_produse: [{"id": 12, "criterii": {"Formă": true, …}, "nota": "…"}]. Produsele care au deja o decizie azi sunt sărite.
create or replace function public.std_verifica_grup(p_space text, p_produse jsonb, p_poza text default '', p_fara_poza text default '')
returns int language plpgsql security definer set search_path = public as $$
declare azi date := (now() at time zone 'Europe/Bucharest')::date; x jsonb; n int := 0;
begin
  if jsonb_typeof(p_produse) is distinct from 'array' or jsonb_array_length(p_produse) = 0 then raise exception 'Nimic de verificat.'; end if;
  for x in select * from jsonb_array_elements(p_produse) loop
    if exists (select 1 from public.std_verificari v where v.produs_id = (x ->> 'id')::bigint and v.space_id = p_space and v.zi = azi and v.decizie is not null) then continue; end if;
    perform public.std_verifica(p_space, (x ->> 'id')::bigint, x -> 'criterii', coalesce(x ->> 'nota', ''), p_poza, p_fara_poza);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.std_verifica_grup(text, jsonb, text, text) from public, anon;
grant execute on function public.std_verifica_grup(text, jsonb, text, text) to authenticated;
