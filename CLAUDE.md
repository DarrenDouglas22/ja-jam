# JA JAM

Single-file browser arcade basketball game — Jamaica vs Bahamas, 1v1 vs a leveling CPU. The entire game (markup, CSS, JS, procedural pixel-art sprites, Web Audio sound) lives in `index.html` with zero dependencies; open it in a browser to run it.

## Deploy

Pushing to `main` auto-deploys via GitHub Pages: https://darrendouglas22.github.io/ja-jam/

## Structure

- `index.html` — the whole game: constants → leaderboard (Supabase client + mock) → sprites (with per-name faces) → FIBA roster (25 opponents, drawn flags) → state + title menu → audio → input (keyboard + touch) → CPU opponent → scoring → persistence (guarded localStorage) → dynasty (15-game campaign, drawn schedules) → practice → hoop styles → update loop → render functions → screens. Modes: `mode` global (`arcade | dynasty | practice`); `endGame()` forks per mode; `TEAMS[1]` is a mutable opponent slot filled from `ROSTER` via `setOpponent()`
- `leaderboard-setup.sql` — Supabase table/RLS setup for the global leaderboard; paste project URL + anon key into the `CONFIG` block in `index.html` to go live (empty keys = in-memory demo board)
- `docs/solutions/` — documented solutions to past problems (bugs, best practices), organized by category with YAML frontmatter (`module`, `tags`, `problem_type`). Relevant when implementing or debugging in documented areas.

## Gotchas

- Desktop Chromium cannot reproduce iOS text-rendering bugs; every iOS browser is WebKit. Canvas text layout changes need a real-device check (see `docs/solutions/ui-bugs/`).
- Syntax check without a browser: extract the `<script>` body and run `node --check`.
- Touch controls can be forced on desktop with `?touch` in the URL.
