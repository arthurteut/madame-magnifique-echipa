// Ghidul echipei Madame Magnifique · funcția Edge `admin-users`
//
// Operațiile care cer cheia secretă: crearea unui cont, resetarea parolei,
// ștergerea unui cont. Rulează în Supabase (Edge Functions), unde URL-ul și
// cheia secretă sunt injectate automat. Verifică întâi că apelantul e un
// admin activ (roles.is_admin).
//
// Cerere (POST, JSON, cu sesiunea utilizatorului în Authorization):
//   { "action": "create", "username": "ana.vt", "full_name": "Ana", "role_code": "VT", "password": "…" }
//   { "action": "reset_password", "user_id": "…", "password": "…" }
//   { "action": "delete", "user_id": "…" }
import { createClient } from "npm:@supabase/supabase-js@2";

export const DOMENIU_CONTURI = "echipa.madamemagnifique.ro";
const USERNAME = /^[a-z0-9._-]{3,40}$/;

type Deps = {
  // deno-lint-ignore no-explicit-any
  admin: any; // client Supabase cu cheia secretă (SupabaseClient)
  allowedOrigins: string[];
};

function cors(req: Request, allowed: string[]) {
  const origin = req.headers.get("origin") ?? "";
  const ok = allowed.includes("*") || allowed.includes(origin);
  return {
    "Access-Control-Allow-Origin": ok ? origin || "*" : allowed[0] ?? "",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const headers = { ...cors(req, deps.allowedOrigins), "Content-Type": "application/json" };
  const raspuns = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });
  const eroare = (status: number, mesaj: string) => raspuns(status, { error: mesaj });

  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return eroare(405, "Doar POST.");

  // 1) Cine cere? Sesiunea utilizatorului vine în Authorization.
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return eroare(401, "Lipsește sesiunea.");
  const { data: u, error: eu } = await deps.admin.auth.getUser(token);
  if (eu || !u?.user) return eroare(401, "Sesiune invalidă. Loghează-te din nou.");
  const apelant = u.user.id;

  // 2) E admin activ?
  const { data: prof } = await deps.admin.from("profiles")
    .select("active, role_code, roles(is_admin)").eq("user_id", apelant).maybeSingle();
  // deno-lint-ignore no-explicit-any
  const esteAdmin = !!prof && (prof as any).active && !!(prof as any).roles?.is_admin;
  if (!esteAdmin) return eroare(403, "Doar administratorii pot gestiona conturile.");

  let body: Record<string, string>;
  try { body = await req.json(); } catch { return eroare(400, "Cerere invalidă."); }
  const parolaOk = (p?: string) => typeof p === "string" && p.length >= 8;

  // 3) Operația
  if (body.action === "create") {
    const username = (body.username ?? "").trim().toLowerCase();
    const full_name = (body.full_name ?? "").trim();
    const role_code = body.role_code ?? "";
    if (!USERNAME.test(username)) return eroare(400, "Utilizatorul: 3–40 caractere, doar litere mici, cifre, punct, cratimă.");
    if (!full_name) return eroare(400, "Completează numele.");
    if (!parolaOk(body.password)) return eroare(400, "Parola trebuie să aibă minimum 8 caractere.");
    const { data: rol } = await deps.admin.from("roles").select("code").eq("code", role_code).maybeSingle();
    if (!rol) return eroare(400, "Rol necunoscut.");
    const { data: exista } = await deps.admin.from("profiles").select("user_id").eq("username", username).maybeSingle();
    if (exista) return eroare(409, `Utilizatorul „${username}” există deja.`);

    const { data: creat, error: ec } = await deps.admin.auth.admin.createUser({
      email: `${username}@${DOMENIU_CONTURI}`, password: body.password, email_confirm: true,
      user_metadata: { username, full_name },
    });
    if (ec || !creat?.user) {
      const dublura = /already|exists|registered/i.test(ec?.message ?? "");
      return eroare(dublura ? 409 : 500, dublura ? `Utilizatorul „${username}” există deja.` : "Contul nu a putut fi creat.");
    }
    const { error: ep } = await deps.admin.from("profiles")
      .insert({ user_id: creat.user.id, username, full_name, role_code });
    if (ep) {
      await deps.admin.auth.admin.deleteUser(creat.user.id); // nu lăsăm conturi fără profil
      return eroare(500, "Profilul nu a putut fi creat.");
    }
    return raspuns(200, { ok: true, user_id: creat.user.id, username });
  }

  if (body.action === "reset_password" || body.action === "delete") {
    const tinta = body.user_id ?? "";
    if (!tinta) return eroare(400, "Lipsește contul.");
    if (tinta === apelant) return eroare(400, "Nu îți poți modifica propriul cont de aici.");
    const { data: p } = await deps.admin.from("profiles").select("user_id").eq("user_id", tinta).maybeSingle();
    if (!p) return eroare(404, "Contul nu există.");

    if (body.action === "reset_password") {
      if (!parolaOk(body.password)) return eroare(400, "Parola trebuie să aibă minimum 8 caractere.");
      const { error } = await deps.admin.auth.admin.updateUserById(tinta, { password: body.password });
      if (error) return eroare(500, "Parola nu a putut fi schimbată.");
      return raspuns(200, { ok: true });
    }
    const { error } = await deps.admin.auth.admin.deleteUser(tinta); // profilul se șterge în cascadă
    if (error) return eroare(500, "Contul nu a putut fi șters.");
    return raspuns(200, { ok: true });
  }

  return eroare(400, "Operație necunoscută.");
}

// În teste (ADMIN_USERS_TEST=1) doar exportăm handle(); în Supabase pornim serverul.
if (!Deno.env.get("ADMIN_USERS_TEST")) {
  const url = Deno.env.get("SUPABASE_URL")!;
  const cheie = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, cheie, { auth: { persistSession: false, autoRefreshToken: false } });
  const allowedOrigins = (Deno.env.get("ALLOWED_ORIGIN") ?? "*").split(",").map((s) => s.trim()).filter(Boolean);
  Deno.serve((req) => handle(req, { admin, allowedOrigins }));
}
