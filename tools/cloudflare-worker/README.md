# DayMate summary endpoint (Cloudflare Worker)

A tiny private mailbox for your daily Teams summary:

```
Claude routine ──POST (write key)──▶ Cloudflare Worker + KV ◀──GET (read key)── DayMate app
```

- Two different secret keys: the routine can only **write**, the app can only **read**.
- Every summary is deleted automatically after **10 days**.
- Fits easily in Cloudflare's free plan (one small write a day).

## 1. Create the Worker (about 10 minutes, all in the browser)

1. Sign up / log in at **dash.cloudflare.com** (free plan is fine).
2. **Storage & databases → KV → Create** (in some accounts: Workers & Pages → KV). Name it `daymate-summaries`. Create.
3. **Workers & Pages → Create → Create Worker** (start from "Hello World"). Name it `daymate-summary` → **Deploy**.
4. Click **Edit code**, delete everything, paste the whole of [`worker.js`](worker.js), then **Deploy**.
5. Back on the Worker page → **Settings → Bindings → Add → KV namespace**:
   - Variable name: `SUMMARIES` (exactly)
   - KV namespace: `daymate-summaries` → **Save / Deploy**.
6. **Settings → Variables and Secrets → Add**, type **Secret**, twice:
   - `WRITE_KEY` = a long random value (for the Claude routine)
   - `READ_KEY`  = a different long random value (for the DayMate app)

   Make each key 32+ characters, e.g. from a password manager's generator. Never reuse one for the other.
7. Note your Worker address, shown on its page: `https://daymate-summary.<your-subdomain>.workers.dev`

## 2. Check it works

Open `https://daymate-summary.<your-subdomain>.workers.dev/health` in a browser → `{"ok":true}`.

Optional, from a computer:

```bash
curl -X POST "https://daymate-summary.<your-subdomain>.workers.dev/summaries" -H "Authorization: Bearer <WRITE_KEY>" -H "Content-Type: application/json" --data '{"date":"2026-11-24","highlights":["Test summary"],"actions":[],"chats":[]}'
```

```bash
curl "https://daymate-summary.<your-subdomain>.workers.dev/summaries" -H "Authorization: Bearer <READ_KEY>"
```

## 3. Connect DayMate

Team summary → Connection: **Summaries from my endpoint (Claude routine)** → paste the Worker address and the
**READ_KEY** → **Connect**. DayMate checks automatically when you open the tab (at most every 30 minutes), or tap
**Check now**.

## 4. Set up the Claude routine

See [ROUTINE_PROMPT.md](ROUTINE_PROMPT.md).

## Privacy notes

- In this mode your Teams chats are read and summarised by Claude (cloud) through the Microsoft 365 connector your
  company approved; the summaries are stored on your Cloudflare account for up to 10 days.
  Check this fits your company's rules for work data.
- Keep both keys secret. If one leaks: change it in Cloudflare (Settings → Variables and Secrets) and update the
  routine (WRITE_KEY) or DayMate (READ_KEY).
- To delete everything now: Storage & databases → KV → `daymate-summaries` → delete the keys (or the namespace).
