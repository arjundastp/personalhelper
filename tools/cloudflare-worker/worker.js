/**
 * DayMate summary endpoint (Cloudflare Worker + KV).
 *
 * The Claude routine POSTs one summary per day; the DayMate app GETs them.
 * Two separate secret keys: WRITE_KEY (routine only) and READ_KEY (DayMate only).
 * Every summary expires automatically after 10 days.
 *
 * Bindings (Worker → Settings):
 *   KV namespace:  SUMMARIES
 *   Secrets:       WRITE_KEY, READ_KEY
 *
 * Routes:
 *   POST /summaries                 Authorization: Bearer <WRITE_KEY>   body: one summary (JSON)
 *   GET  /summaries?since=YYYY-MM-DD Authorization: Bearer <READ_KEY>    → [summary, …] newest first
 *   GET  /health                    → {"ok":true}   (no secrets, no data)
 */

const KEEP_SECONDS = 10 * 24 * 60 * 60; // 10 days
const MAX_BYTES = 200_000;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/health') return json({ ok: true });

      if (url.pathname === '/summaries' && request.method === 'POST') {
        if (!authorised(request, env.WRITE_KEY)) return json({ error: 'unauthorised' }, 401);
        const text = await request.text();
        if (text.length > MAX_BYTES) return json({ error: 'too large' }, 413);
        let s;
        try {
          s = JSON.parse(text);
        } catch {
          return json({ error: 'body must be JSON' }, 400);
        }
        const problem = validate(s);
        if (problem) return json({ error: problem }, 400);
        s.receivedAt = Date.now();
        await env.SUMMARIES.put(`summary:${s.date}`, JSON.stringify(s), { expirationTtl: KEEP_SECONDS });
        return json({ ok: true, date: s.date });
      }

      if (url.pathname === '/summaries' && request.method === 'GET') {
        if (!authorised(request, env.READ_KEY)) return json({ error: 'unauthorised' }, 401);
        const since = url.searchParams.get('since') || '0000-00-00';
        const keys = await env.SUMMARIES.list({ prefix: 'summary:' });
        const wanted = keys.keys.map((k) => k.name).filter((n) => n.slice(8) >= since);
        const items = await Promise.all(wanted.map((n) => env.SUMMARIES.get(n, 'json')));
        const out = items.filter(Boolean).sort((a, b) => (a.date < b.date ? 1 : -1));
        return json(out);
      }

      return json({ error: 'not found' }, 404);
    } catch (e) {
      return json({ error: 'server error' }, 500);
    }
  },
};

/** The summary format DayMate shows. Extra fields are kept but ignored by the app. */
function validate(s) {
  if (!s || typeof s !== 'object' || Array.isArray(s)) return 'summary must be an object';
  if (typeof s.date !== 'string' || !DATE.test(s.date)) return 'date must be YYYY-MM-DD';
  for (const k of ['highlights', 'actions', 'chats']) {
    if (s[k] !== undefined && !Array.isArray(s[k])) return `${k} must be a list`;
  }
  return null;
}

/** Constant-time comparison of the Bearer token with the expected secret. */
function authorised(request, secret) {
  if (!secret) return false;
  const header = request.headers.get('Authorization') || '';
  const given = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (given.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < secret.length; i++) diff |= given.charCodeAt(i) ^ secret.charCodeAt(i);
  return diff === 0;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}
