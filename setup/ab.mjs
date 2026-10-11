// Runs inside the Actual Budget container for the DSM package: piped to
// `node --input-type=module -` with one line in front setting ACT and ARG
// (base64 JSON) — so passwords travel on stdin, never in argv or env.
// Passwords go through Actual's own account functions (the ones its
// reset-password script uses, found through that script's import line, so a
// new build's renamed chunks don't matter); the rest reads its SQLite files.
// Prints one JSON line: {"ok":…, "msg":…, …}.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire('/app/package.json');
const Database = require('better-sqlite3');

const out = (o) => { process.stdout.write(JSON.stringify(o) + '\n'); process.exit(o.ok ? 0 : 1); };
const DATA = process.env.ACTUAL_DATA_DIR || '/data';
const SERVER = process.env.ACTUAL_SERVER_FILES || path.join(DATA, 'server-files');
const USER = process.env.ACTUAL_USER_FILES || path.join(DATA, 'user-files');

async function accounts() {   // Actual's own changePassword / needsBootstrap / bootstrap
  const src = fs.readFileSync('/app/scripts/reset-password.js', 'utf8');
  const m = src.match(/import\s*\{([^}]*)\}\s*from\s*"(\.\.\/chunks\/account-db-[^"]+)"/);
  if (!m) throw new Error("this Actual build's reset-password script looks different; the package needs an update");
  const names = Object.fromEntries(m[1].split(',').map((s) => s.trim().split(/\s+as\s+/)).filter((p) => p.length === 2).map(([a, b]) => [b, a]));
  const mod = await import(new URL(m[2], 'file:///app/scripts/'));
  const fn = (n) => { const f = mod[names[n]]; if (typeof f !== 'function') throw new Error(`Actual's ${n} wasn't found`); return f; };
  return { changePassword: fn('changePassword'), needsBootstrap: fn('needsBootstrap'), bootstrap: fn('bootstrap') };
}
const db = () => new Database(path.join(SERVER, 'account.sqlite'));
const stat = (f) => { try { const s = fs.statSync(f); return { size: s.size, mtime: Math.floor(s.mtimeMs / 1000) }; } catch { return null; } };

try {
  switch (ACT) {
    case 'bootstrap': {   // the first password, when the server has none yet
      const a = await accounts();
      if (!a.needsBootstrap()) out({ ok: false, msg: 'already' });
      const r = await a.bootstrap({ password: ARG.password });
      out(r && r.error ? { ok: false, msg: r.error } : { ok: true });
    }
    case 'setpw': {       // a new server password; optionally every device signs in again
      const a = await accounts();
      if (a.needsBootstrap()) { const r = await a.bootstrap({ password: ARG.password }); if (r && r.error) out({ ok: false, msg: r.error }); }
      else { const r = await a.changePassword(ARG.password); if (r && r.error) out({ ok: false, msg: r.error === 'no-password-method' ? 'This server signs in with OpenID, not a password.' : r.error }); }
      let n = 0; if (ARG.signout) { const d = db(); n = d.prepare('DELETE FROM sessions').run().changes; d.close(); }
      out({ ok: true, signedOut: n });
    }
    case 'signout': {
      const d = db(); const n = d.prepare('DELETE FROM sessions').run().changes; d.close();
      out({ ok: true, signedOut: n });
    }
    case 'status': {
      const d = db(); const now = Math.floor(Date.now() / 1000);
      const auth = d.prepare('SELECT method, active FROM auth').all();
      const sessions = d.prepare('SELECT expires_at FROM sessions').all()
        .filter((s) => s.expires_at == null || s.expires_at < 0 || s.expires_at > now * 1000 || s.expires_at > now).length;
      const files = d.prepare('SELECT id, group_id, name, deleted, encrypt_keyid FROM files ORDER BY name').all().map((f) => {
        const blob = stat(path.join(USER, `file-${f.id}.blob`)), group = f.group_id ? stat(path.join(USER, `group-${f.group_id}.sqlite`)) : null;
        return { id: f.id, name: f.name || '(no name)', deleted: !!f.deleted, encrypted: !!f.encrypt_keyid,
                 size: (blob ? blob.size : 0) + (group ? group.size : 0), changed: Math.max(blob ? blob.mtime : 0, group ? group.mtime : 0) };
      });
      const users = d.prepare('SELECT COUNT(*) n FROM users').get().n;
      d.close();
      out({ ok: true, bootstrapped: auth.length > 0, method: (auth.find((x) => x.active) || {}).method || '', sessions, users, budgets: files });
    }
    default: out({ ok: false, msg: 'unknown action' });
  }
} catch (e) { out({ ok: false, msg: String(e && e.message || e).slice(0, 300) }); }
