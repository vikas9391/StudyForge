-- ══════════════════════════════════════════════════════════════════
-- Studyforge V2 — Additional SQL (run AFTER supabase_setup.sql)
-- Paste in Supabase Dashboard → SQL Editor → New Query → Run
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Profiles table ────────────────────────────────────────────────────────
create table if not exists profiles (
    id          uuid primary key references auth.users(id) on delete cascade,
    email       text,
    full_name   text default '',
    avatar_url  text default '',
    bio         text default '',
    is_admin    boolean default false,
    created_at  timestamptz default now(),
    updated_at  timestamptz default now()
);

-- Enable RLS
alter table profiles enable row level security;

-- Users can read their own profile
create policy "Users read own profile"
    on profiles for select
    using (auth.uid() = id);

-- Users can update their own profile
create policy "Users update own profile"
    on profiles for update
    using (auth.uid() = id);

-- Admins can read ALL profiles
create policy "Admins read all profiles"
    on profiles for select
    using (
        exists (
            select 1 from profiles
            where id = auth.uid() and is_admin = true
        )
    );

-- ── 2. Auto-create profile on new signup ─────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, email)
    values (new.id, new.email);
    return new;
end;
$$ language plpgsql security definer;

-- Attach the trigger to auth.users
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- ── 3. Make yourself admin ────────────────────────────────────────────────────
-- Replace with YOUR email address, then run this:
-- update profiles set is_admin = true where email = 'your@email.com';

-- ── 4. Index for fast admin queries ──────────────────────────────────────────
create index if not exists profiles_email_idx on profiles (email);
create index if not exists results_created_at_idx on results (created_at desc);
