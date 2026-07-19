-- APNs device tokens — consumed by the M6 check-in engine (C10: server-driven push).
-- Structural now, unused until M6. Content-free: a token is delivery plumbing, not story.
--
-- The environment column is the affirmly post-mortem lesson: a sandbox token pushed against
-- the production APNs host 403s silently. Recording which environment issued the token makes
-- that failure diagnosable instead of invisible.

create table public.device_push_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  token       text not null unique,
  environment text not null check (environment in ('sandbox', 'production')),
  created_at  timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index device_push_tokens_user_idx
  on public.device_push_tokens (user_id);

alter table public.device_push_tokens enable row level security;

create policy "device_push_tokens: owner select"
  on public.device_push_tokens for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "device_push_tokens: owner insert"
  on public.device_push_tokens for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "device_push_tokens: owner update"
  on public.device_push_tokens for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "device_push_tokens: owner delete"
  on public.device_push_tokens for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.device_push_tokens from anon;
