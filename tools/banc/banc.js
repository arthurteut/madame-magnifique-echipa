// Bancul de probă: pagina reală, vorbind cu baza locală „ghid” ca un cont anume (RLS activ).
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { execFileSync } = require('child_process');
const fs = require('fs'), path = require('path');
const DIR = __dirname, TMP = '/tmp/ghiddb';
const SETOF = new Set(['oameni_de_programat', 'echipa_mea', 'autori_jurnal']);
const ident = c => { if (!/^[a-z_][a-z0-9_]*$/.test(c)) throw new Error('nume nepermis: ' + c); return '"' + c + '"'; };
const lit = v => v === null || v === undefined ? 'null' : typeof v === 'number' || typeof v === 'boolean' ? String(v)
  : Array.isArray(v) && v.every(x => typeof x === 'number' || (typeof x === 'string' && /^[\w-]+$/.test(x))) ? `'{${v.join(',')}}'`
  : typeof v === 'object' ? `'${JSON.stringify(v).replace(/'/g, "''")}'` : `'${String(v).replace(/'/g, "''")}'`;
const unde = f => !f.length ? '' : ' where ' + f.map(([c, op, v]) => op === 'in' ? (v.length ? `${ident(c)} in (${v.map(lit).join(',')})` : 'false')
  : op === 'is' ? `${ident(c)} is ${v === null ? 'null' : v}` : `${ident(c)} ${op} ${lit(v)}`).join(' and ');
let nr = 0;
function psql(uid, sql) {
  const f = path.join(TMP, `q_${process.pid}_${nr++ % 50}.sql`);
  fs.writeFileSync(f, `begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub', '${uid}', true) \\g /dev/null\n${sql};\ncommit;\n`, { mode: 0o644 });
  try { return { out: execFileSync('su', ['postgres', '-c', `psql -p 54329 -d ghid -At -q -v ON_ERROR_STOP=1 -f ${f}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64e6 }).trim() }; }
  catch (e) { const m = String(e.stderr || e.message).match(/ERROR:\s+(.*)/); return { err: m ? m[1].trim() : String(e.stderr || e.message) }; }
}
function db(uid, s, log) {
  let sql;
  if (s.rpc) {
    const args = Object.entries(s.args).map(([k, v]) => `${ident(k)} => ${lit(v)}`).join(', ');
    sql = SETOF.has(s.rpc) ? `select coalesce(json_agg(x), '[]'::json) from public.${ident(s.rpc)}(${args}) x`
      : `select row_to_json(t) from (select public.${ident(s.rpc)}(${args}) as r) t`;
    const r = psql(uid, sql); log.push(['rpc', s.rpc, r.err || 'ok']);
    if (r.err) return { data: null, error: { message: r.err } };
    const j = r.out ? JSON.parse(r.out) : null;
    return { data: SETOF.has(s.rpc) ? j : (j && j.r !== '' ? j.r : null), error: null };
  }
  const t = `public.${ident(s.table)}`;
  if (s.op === 'select') {
    const cols = s.cols === '*' ? '*' : s.cols.split(',').map(c => ident(c.trim())).join(', ');
    sql = `select coalesce(json_agg(t), '[]'::json) from (select ${cols} from ${t}${unde(s.filters)}${s.order.length ? ' order by ' + s.order.map(([c, a]) => ident(c) + (a ? '' : ' desc')).join(', ') : ''}${s.range ? ` limit ${s.range[1] - s.range[0] + 1} offset ${s.range[0]}` : ''}) t`;
  } else if (s.op === 'insert' || s.op === 'upsert') {
    const rows = Array.isArray(s.payload) ? s.payload : [s.payload], cols = [...new Set(rows.flatMap(r => Object.keys(r)))].map(ident).join(', ');
    let st = `insert into ${t} (${cols}) select ${cols} from json_populate_recordset(null::${t}, ${lit(rows)}::json)`;
    if (s.op === 'upsert' && s.onConflict) { const k = s.onConflict.split(',').map(c => c.trim());
      st += ` on conflict (${k.map(ident).join(', ')}) do update set ${[...new Set(rows.flatMap(r => Object.keys(r)))].filter(c => !k.includes(c)).map(c => `${ident(c)} = excluded.${ident(c)}`).join(', ')}`; }
    sql = s.ret ? `with x as (${st} returning *) select coalesce(json_agg(x), '[]'::json) from x` : st;
  } else if (s.op === 'update') {
    const cols = Object.keys(s.payload).map(ident).join(', ');
    const st = `update ${t} set (${cols}) = (select ${cols} from json_populate_record(null::${t}, ${lit(s.payload)}::json))${unde(s.filters)}`;
    sql = s.ret ? `with x as (${st} returning *) select coalesce(json_agg(x), '[]'::json) from x` : st;
  } else sql = `delete from ${t}${unde(s.filters)}`;
  const r = psql(uid, sql);
  if (s.op !== 'select') log.push([s.op, s.table, r.err || 'ok']);
  if (r.err) return { data: null, error: { message: r.err } };
  let data = r.out ? JSON.parse(r.out) : null;
  if (s.single && Array.isArray(data)) data = data[0] || null;
  return { data: s.op === 'select' || s.ret ? data : null, error: null };
}
const U = k => '00000000-0000-0000-0000-0000000000' + k;
async function deschide(b, { k, user, vp = { width: 390, height: 844 }, mob = true, hash = '', local = {} }) {
  const ctx = await b.newContext({ viewport: vp, deviceScaleFactor: 2, isMobile: mob, hasTouch: mob });
  const log = [], err = [];
  // Pagina se servește direct din depozit, fără server web.
  await ctx.route('http://localhost:8765/**', r => { const u = new URL(r.request().url()); const f = path.join('/home/user/madame-magnifique-echipa', u.pathname === '/' ? 'index.html' : decodeURIComponent(u.pathname));
    if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) return r.fulfill({ status: 404, body: '' });
    const t = { html: 'text/html; charset=utf-8', js: 'application/javascript', css: 'text/css', json: 'application/json', svg: 'image/svg+xml', png: 'image/png', jpg: 'image/jpeg', webp: 'image/webp', woff2: 'font/woff2' }[f.split('.').pop()] || 'application/octet-stream';
    return r.fulfill({ contentType: t, body: fs.readFileSync(f) }); });
  await ctx.route('**/supabase-js@*/**', r => r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(path.join(DIR, 'dbmock.js'), 'utf8') }));
  await ctx.route('**/assets/config.js', r => r.fulfill({ contentType: 'application/javascript', body: "window.MM_CONFIG={supabaseUrl:'https://t.supabase.co',supabaseAnonKey:'a'}" }));
  await ctx.exposeFunction('__db', spec => JSON.stringify(db(U(k), JSON.parse(spec), log)));
  await ctx.addInitScript(([uid, loc]) => { window.__UID = uid; try { for (const [a, v] of Object.entries(loc)) if (localStorage.getItem(a) === null) localStorage.setItem(a, v); } catch (e) {} }, [U(k), local]);
  const p = await ctx.newPage();
  p.on('pageerror', e => err.push('pageerror: ' + String(e.stack).split('\n').slice(0, 4).join(' | '))); p.on('console', m => { if (m.type() === 'error') err.push(m.text()); });
  p.on('dialog', d => d.accept());
  await p.goto('http://localhost:8765/' + hash); await p.fill('#user', user); await p.fill('#pw', 'p'); await p.click('#unlockBtn');
  await p.waitForSelector('#app:not(.hidden)');
  return { p, ctx, log, err, mergi: async (h, sel) => { await p.evaluate(x => { location.hash = x; }, h); await p.waitForSelector(sel); await p.waitForTimeout(700); } };
}
const sqlAdmin = sql => { const f = path.join(TMP, `adm_${process.pid}.sql`); fs.writeFileSync(f, sql, { mode: 0o644 });
  return execFileSync('su', ['postgres', '-c', `psql -p 54329 -d ghid -At -q -v ON_ERROR_STOP=1 -f ${f}`], { encoding: 'utf8' }).trim(); };
module.exports = { chromium, deschide, sqlAdmin, U };
