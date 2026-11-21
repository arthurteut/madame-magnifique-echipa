// Imitație supabase-js care trimite fiecare operație către baza locală adevărată (prin window.__db, din Playwright):
// aceleași RLS, triggere și funcții ca în Supabase. Timpul real (realtime) e doar un ciot.
(function () {
  const call = spec => window.__db(JSON.stringify(spec)).then(JSON.parse);
  class Q {
    constructor(t) { this.s = { table: t, op: 'select', filters: [], order: [], range: null, single: null, payload: null, onConflict: null, ret: false, cols: '*' }; }
    select(c) { if (this.s.op !== 'select') this.s.ret = true; else this.s.cols = c || '*'; return this; }
    order(c, o) { this.s.order.push([c, !(o && o.ascending === false)]); return this; }
    range(a, b) { this.s.range = [a, b]; return this; } limit(n) { this.s.range = [0, n - 1]; return this; }
    eq(c, v) { this.s.filters.push([c, '=', v]); return this; } neq(c, v) { this.s.filters.push([c, '<>', v]); return this; }
    gte(c, v) { this.s.filters.push([c, '>=', v]); return this; } lte(c, v) { this.s.filters.push([c, '<=', v]); return this; }
    gt(c, v) { this.s.filters.push([c, '>', v]); return this; } lt(c, v) { this.s.filters.push([c, '<', v]); return this; }
    in(c, v) { this.s.filters.push([c, 'in', v]); return this; } is(c, v) { this.s.filters.push([c, 'is', v]); return this; }
    maybeSingle() { this.s.single = 'maybe'; return this; } single() { this.s.single = 'one'; return this; }
    insert(x) { this.s.op = 'insert'; this.s.payload = x; return this; }
    upsert(x, o) { this.s.op = 'upsert'; this.s.payload = x; this.s.onConflict = o && o.onConflict; return this; }
    update(x) { this.s.op = 'update'; this.s.payload = x; return this; } delete() { this.s.op = 'delete'; return this; }
    then(res, rej) { return call(this.s).then(res, rej); }
  }
  const user = () => ({ id: window.__UID });
  window.supabase = { createClient() { return {
    from: t => new Q(t), rpc: (name, args) => call({ rpc: name, args: args || {} }),
    channel() { const c = { on() { return c; }, subscribe() { return c; } }; return c; }, removeChannel() {},
    auth: {
      async getSession() { return { data: { session: sessionStorage.getItem('s') ? { user: user() } : null } }; },
      async signInWithPassword() { sessionStorage.setItem('s', 1); return { data: { user: user() }, error: null }; },
      async signOut() { sessionStorage.removeItem('s'); return {}; },
    },
    functions: { invoke: async () => ({ data: null, error: null }) },
    // Stocarea de fișiere e simulată: încărcările se țin minte în pagină (window.__incarcari).
    storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }),
      upload: async (cale, blob) => { (window.__incarcari = window.__incarcari || []).push({ cale, marime: blob && blob.size, tip: blob && blob.type }); return { data: { path: cale }, error: null }; } }) },
  }; } };
})();
