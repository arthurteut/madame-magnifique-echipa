// Conexiunea ghidului la Supabase. Ambele valori sunt PUBLICE prin design:
// cheia „anon / publishable” nu dă acces la nimic fără logare, iar ce vede
// fiecare utilizator decide Row Level Security în baza de date.
// Le găsești în Supabase → Project Settings → API (sau „Connect”).
// NU pune aici cheia „service_role” / „secret”.
window.MM_CONFIG = {
  supabaseUrl: null,      // ex.: 'https://abcdefghijkl.supabase.co'
  supabaseAnonKey: null,  // ex.: 'eyJhbGciOi…' sau 'sb_publishable_…'
};
