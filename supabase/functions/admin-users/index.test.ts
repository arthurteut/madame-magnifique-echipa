// Teste pentru funcția admin-users, cu un client Supabase simulat.
// Rulare: ADMIN_USERS_TEST=1 deno test --allow-env supabase/functions/admin-users/
import { assertEquals } from "jsr:@std/assert@1";
Deno.env.set("ADMIN_USERS_TEST", "1");
const { handle } = await import("./index.ts");

const GM = "u-gm", VT = "u-vt";
function fals() {
  const db = {
    users: new Map<string, { id: string; email: string; password: string }>([
      [GM, { id: GM, email: "ana.gm@echipa.madamemagnifique.ro", password: "x" }],
      [VT, { id: VT, email: "ion.vt@echipa.madamemagnifique.ro", password: "x" }],
    ]),
    profiles: [
      { user_id: GM, username: "ana.gm", full_name: "Ana", role_code: "GM", active: true },
      { user_id: VT, username: "ion.vt", full_name: "Ion", role_code: "VT", active: true },
    ] as Record<string, unknown>[],
    roles: [{ code: "GM", is_admin: true }, { code: "VT", is_admin: false }, { code: "V", is_admin: false }],
    tokens: { "tok-gm": GM, "tok-vt": VT } as Record<string, string>,
    failProfileInsert: false,
  };
  const q = (table: string) => {
    let f: [string, unknown][] = [];
    const rows = () => (db as any)[table].filter((r: any) => f.every(([c, v]) => r[c] === v));
    const b: any = {
      select: () => b,
      eq: (c: string, v: unknown) => { f.push([c, v]); return b; },
      maybeSingle: async () => {
        const r = rows()[0];
        if (r && table === "profiles") return { data: { ...r, roles: db.roles.find((x) => x.code === r.role_code) }, error: null };
        return { data: r ?? null, error: null };
      },
      insert: async (row: Record<string, unknown>) => {
        if (db.failProfileInsert) return { error: { message: "fail" } };
        (db as any)[table].push({ active: true, ...row }); return { error: null };
      },
    };
    return b;
  };
  const admin: any = {
    from: q,
    auth: {
      getUser: async (t: string) => db.tokens[t] ? { data: { user: { id: db.tokens[t] } }, error: null } : { data: { user: null }, error: { message: "bad" } },
      admin: {
        createUser: async ({ email, password }: any) => {
          if ([...db.users.values()].some((u) => u.email === email)) return { data: { user: null }, error: { message: "User already registered" } };
          const id = "u-" + email.split("@")[0]; db.users.set(id, { id, email, password }); return { data: { user: { id } }, error: null };
        },
        updateUserById: async (id: string, { password }: any) => { db.users.get(id)!.password = password; return { error: null }; },
        deleteUser: async (id: string) => { db.users.delete(id); db.profiles = db.profiles.filter((p) => p.user_id !== id); return { error: null }; },
      },
    },
  };
  return { db, deps: { admin, allowedOrigins: ["https://arthurteut.github.io"] } };
}
const cerere = (tok: string | null, body: unknown, method = "POST") => new Request("https://x/functions/v1/admin-users", {
  method, headers: { "content-type": "application/json", origin: "https://arthurteut.github.io", ...(tok ? { authorization: "Bearer " + tok } : {}) },
  body: method === "POST" ? JSON.stringify(body) : undefined,
});

Deno.test("CORS preflight", async () => {
  const { deps } = fals();
  const r = await handle(cerere(null, null, "OPTIONS"), deps);
  assertEquals(r.status, 200);
  assertEquals(r.headers.get("access-control-allow-origin"), "https://arthurteut.github.io");
});
Deno.test("fără sesiune: 401", async () => {
  const { deps } = fals();
  assertEquals((await handle(cerere(null, { action: "create" }), deps)).status, 401);
});
Deno.test("non-admin: 403", async () => {
  const { deps } = fals();
  assertEquals((await handle(cerere("tok-vt", { action: "create", username: "x.y", full_name: "X", role_code: "V", password: "12345678" }), deps)).status, 403);
});
Deno.test("admin creează cont + profil", async () => {
  const { db, deps } = fals();
  const r = await handle(cerere("tok-gm", { action: "create", username: "Maria.V", full_name: "Maria", role_code: "V", password: "parola123" }), deps);
  assertEquals(r.status, 200);
  assertEquals((await r.json()).username, "maria.v");
  assertEquals([...db.users.values()].some((u) => u.email === "maria.v@echipa.madamemagnifique.ro"), true);
  assertEquals(db.profiles.some((p) => p.username === "maria.v" && p.role_code === "V"), true);
});
Deno.test("validări: utilizator, parolă, rol, dublură", async () => {
  const { deps } = fals();
  const c = (b: unknown) => handle(cerere("tok-gm", { action: "create", ...b as object }), deps).then((r) => r.status);
  assertEquals(await c({ username: "a b", full_name: "X", role_code: "V", password: "12345678" }), 400);
  assertEquals(await c({ username: "abc.d", full_name: "X", role_code: "V", password: "123" }), 400);
  assertEquals(await c({ username: "abc.d", full_name: "X", role_code: "NU", password: "12345678" }), 400);
  assertEquals(await c({ username: "ion.vt", full_name: "X", role_code: "V", password: "12345678" }), 409);
});
Deno.test("profil eșuat: contul de autentificare e anulat", async () => {
  const { db, deps } = fals();
  db.failProfileInsert = true;
  const r = await handle(cerere("tok-gm", { action: "create", username: "nou.v", full_name: "Nou", role_code: "V", password: "12345678" }), deps);
  assertEquals(r.status, 500);
  assertEquals([...db.users.values()].some((u) => u.email.startsWith("nou.v@")), false);
});
Deno.test("resetare parolă și ștergere", async () => {
  const { db, deps } = fals();
  assertEquals((await handle(cerere("tok-gm", { action: "reset_password", user_id: VT, password: "noua-parola" }), deps)).status, 200);
  assertEquals(db.users.get(VT)!.password, "noua-parola");
  assertEquals((await handle(cerere("tok-gm", { action: "reset_password", user_id: VT, password: "scurt" }), deps)).status, 400);
  assertEquals((await handle(cerere("tok-gm", { action: "delete", user_id: GM }), deps)).status, 400); // nu pe sine
  assertEquals((await handle(cerere("tok-gm", { action: "delete", user_id: VT }), deps)).status, 200);
  assertEquals(db.profiles.some((p) => p.user_id === VT), false);
  assertEquals((await handle(cerere("tok-gm", { action: "delete", user_id: VT }), deps)).status, 404);
});
