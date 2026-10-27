// Ghidul echipei Madame Magnifique · funcția Edge `trimite-push`
//
// Trimite pe telefon (Web Push) o notificare din tabela notifications. O cheamă
// baza de date (triggerul trimite_push, prin pg_net) la fiecare notificare nouă:
//   POST { "id": 123 }   cu antetul x-push-secret = push_config.secret
//
// Cheile VAPID și secretul stau în public.push_config (o citește doar service_role).
// URL-ul și cheia service_role sunt injectate automat de Supabase.
// La publicare: dezactivează „Verify JWT” (verificarea o face secretul de mai sus).
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "doar POST" }, 405);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: cfg, error } = await admin.from("push_config").select("*").eq("id", 1).single();
  if (error || !cfg) return json({ error: "push_config lipsește" }, 500);
  if (!cfg.secret || req.headers.get("x-push-secret") !== cfg.secret) return json({ error: "acces refuzat" }, 403);
  if (!cfg.vapid_public || !cfg.vapid_private) return json({ error: "cheile VAPID lipsesc" }, 500);

  const { id } = await req.json().catch(() => ({ id: null }));
  const { data: n } = await admin.from("notifications").select("*").eq("id", id).maybeSingle();
  if (!n) return json({ error: "notificarea nu există" }, 404);
  const { data: telefoane } = await admin.from("push_subscriptions").select("*").eq("user_id", n.user_id);

  webpush.setVapidDetails("https://echipa.madamemagnifique.ro", cfg.vapid_public, cfg.vapid_private);
  const payload = JSON.stringify({ id: n.id, title: n.title, body: n.body, url: n.url || "#/", tag: `${n.kind}-${n.id}` });
  let trimise = 0;
  const expirate: string[] = [];
  await Promise.all((telefoane ?? []).map(async (t) => {
    try {
      await webpush.sendNotification({ endpoint: t.endpoint, keys: { p256dh: t.p256dh, auth: t.auth } }, payload,
        { TTL: 6 * 3600, urgency: n.kind === "memento" || n.kind === "intarziere" ? "high" : "normal" });
      trimise++;
    } catch (e) {
      // deno-lint-ignore no-explicit-any
      const cod = (e as any)?.statusCode;
      if (cod === 404 || cod === 410) expirate.push(t.endpoint);   // telefonul a renunțat la notificări
      else console.error("push", cod, (e as Error)?.message);
    }
  }));
  if (expirate.length) await admin.from("push_subscriptions").delete().in("endpoint", expirate);
  return json({ trimise, expirate: expirate.length });
});
