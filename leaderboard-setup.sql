-- JA JAM leaderboard — run this in the Supabase SQL editor.
-- Public read + public insert only; no client update/delete (RLS has no policies for them).

create table public.scores (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (name ~ '^[A-Z0-9]{1,3}$'),
  score      int  not null check (score >= 0 and score <= 999), -- session run total across games; cap blocks spoofed scores
  created_at timestamptz not null default now()
);

-- fast top-N: score desc, earliest first on ties
create index scores_top_idx on public.scores (score desc, created_at asc);

alter table public.scores enable row level security;

create policy "public read"   on public.scores for select using (true);
create policy "public insert" on public.scores for insert with check (true);
-- deliberately no update/delete policies: players can post scores, never edit or wipe the board

-- After running this, paste your project URL and anon key into the CONFIG block in index.html.
