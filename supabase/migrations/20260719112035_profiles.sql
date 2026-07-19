-- Per-user anchor row. Holds NO story content (C2) — server-side per-user state only.
-- Every user-owned table references auth.users(id) ON DELETE CASCADE so that deleting the
-- auth user is the server half of "Erase my world" (C2: erase = ciphertext blobs + derived
-- metadata + AI-provider deletion).

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create table public.profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create the anchor row on signup (Sign in with Apple / magic link both land here).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;

create policy "profiles: owner select"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- Self-heal path if the signup trigger ever failed for an existing user.
create policy "profiles: owner insert"
  on public.profiles for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

revoke all on table public.profiles from anon;
