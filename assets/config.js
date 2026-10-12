// Conexiunea ghidului la Supabase. Ambele valori sunt PUBLICE prin design:
// cheia „anon / publishable” nu dă acces la nimic fără logare, iar ce vede
// fiecare utilizator decide Row Level Security în baza de date.
// Le găsești în Supabase → Project Settings → API (sau „Connect”).
// NU pune aici cheia „service_role” / „secret”.
window.MM_CONFIG = {
  supabaseUrl: 'https://dwldusjpjhylvvbskamx.supabase.co',
  supabaseAnonKey: 'sb_publishable_RnNcRBNGwgNhULcUBfeKXA_tBXL3el1',
  // Numele funcției Edge cu codul din supabase/functions/admin-users (dat de Supabase la publicare).
  adminFunction: 'smooth-handler',
};
