-- ══════════════════════════════════════════════════════════════════
-- Studyforge — Supabase SQL Setup
-- Run this ONCE in Supabase Dashboard → SQL Editor → New Query
-- ══════════════════════════════════════════════════════════════════

-- 1. Create the results table
create table if not exists results (
    id          uuid primary key default gen_random_uuid(),
    user_id     text not null,
    file_url    text,
    summary     text,
    quiz        jsonb default '[]',
    flashcards  jsonb default '[]',
    created_at  timestamptz default now()
);

-- 2. Enable Row Level Security (users only see their own data)
alter table results enable row level security;

-- 3. Policy: users can read/write/update/delete their own rows only
create policy "Users manage own results"
    on results
    for all
    using  (auth.uid()::text = user_id)
    with check (auth.uid()::text = user_id);

-- 4. Index for fast user queries
create index if not exists results_user_id_idx
    on results (user_id, created_at desc);

-- Done! Now create a Storage bucket:
-- Supabase Dashboard → Storage → New bucket
-- Name: studyforge-files
-- Toggle: Public bucket ON
