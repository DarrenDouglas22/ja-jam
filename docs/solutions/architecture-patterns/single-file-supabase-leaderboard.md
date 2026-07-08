---
title: Global leaderboard for a single-file game — Supabase append-only RLS with a mock fallback
date: 2026-07-08
category: architecture-patterns
module: leaderboard
problem_type: architecture_pattern
component: database
related_components: ["frontend_stimulus"]
severity: medium
applies_when:
  - "Adding persistence to a single-file, zero-build static page without new infra"
  - "Accepting public writes (scores, guestbook-style rows) with no auth or accounts"
  - "Shipping UI before the backend exists, or when backend config is deliberately deferred"
tags: [supabase, rls, leaderboard, single-file, append-only, mock-fallback, canvas]
---

# Global leaderboard for a single-file game — Supabase append-only RLS with a mock fallback

## Context

JA JAM (`index.html`, vanilla JS + Canvas, zero build step, GitHub Pages) needed a global top-10 leaderboard where anonymous players post arcade initials and a score. Constraints: stay one file, no server code, mobile-first, and the client necessarily ships its database credentials.

## Guidance

**1. The anon key ships in the client; RLS is the entire security model.** Load `supabase-js` from a CDN `<script>` tag, keep URL + anon key in a visible `CONFIG` block. Then make the table append-only by *omission* — create only `select` and `insert` policies; with RLS enabled, missing `update`/`delete` policies means denied:

```sql
alter table public.scores enable row level security;
create policy "public read"   on public.scores for select using (true);
create policy "public insert" on public.scores for insert with check (true);
-- deliberately no update/delete policies: players post scores, never edit or wipe the board
```

**2. Enforce validity in the schema, mirror it in the client.** Client-side validation is UX; anyone can bypass it with curl. The CHECK constraints are the real gate:

```sql
name  text not null check (name ~ '^[A-Z0-9]{1,3}$'),
score int  not null check (score >= 0 and score <= 999)
```

The score cap belongs to the *scoring design*, not the table: when scoring changed from per-game points (max 23) to session run totals, the cap had to move 30 → 999. Revisit the cap whenever scoring rules change.

**3. Hide the backend behind a tiny interface with an in-memory mock.** `submitScore(name, score)` and `fetchTopScores(limit)` are the whole API. When `CONFIG` keys are empty (or the CDN failed), the same interface runs against a seeded in-memory array — the UI is fully buildable and demo-able before any backend exists. Deliberately *not* localStorage: a fake-persistent board is worse than one that visibly resets, so mock mode labels itself on screen ("demo board — resets on refresh").

**4. Index for the one query you run.** `create index on scores (score desc, created_at asc)` — top-N by score, earliest-first ties.

**5. Rank by runs, not games (game-design half).** The posted score is a session run total accumulated across games and posted only when a loss ends the run. With an opponent that levels up on every player win, board position measures how deep a streak survived — a strictly more interesting number than a single game score that saturates at 21.

## Why This Matters

Public-write tables without RLS discipline get wiped or spammed; the omission-based policy set makes destructive access impossible rather than merely discouraged. The interface-with-mock pattern decouples UI shipping from backend provisioning (this project shipped the full flow live in demo mode days before any Supabase project existed). Schema-level CHECKs are the only validation an attacker can't skip.

## When to Apply

- Any static/single-file page that needs shared persistence with anonymous writers
- Prototyping flows where the backend decision is deferred but the UI must ship
- Any table where clients should append but never mutate history (scores, logs, sign-ups)

## Examples

The interface split in `index.html` — same call sites, two backends:

```js
async function submitScore(name, score) {
  if (!valid(name, score)) return { error: 'invalid score or initials' };
  if (!live) { mock.push(row); return { row }; }           // keys absent: in-memory
  const { data, error } = await client.from('scores')
    .insert({ name, score }).select().single();            // keys present: Supabase
  return error ? { error: error.message } : { row: data };
}
```

Flow: `game over (loss) → showInitialsEntry(runTotal) → submitScore() → fetchTopScores() → render top 10` — one integration point (`showInitialsEntry`) between game logic and the board.

## Related

- `leaderboard-setup.sql` — the full table/RLS/index setup at repo root
- `docs/solutions/ui-bugs/ios-webkit-emoji-canvas-text-layout.md` — why the board renders rows as pure-ASCII canvas text
