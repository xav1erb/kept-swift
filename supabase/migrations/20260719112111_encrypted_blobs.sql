-- The C2/F3 sync substrate: client-encrypted blobs the server cannot open.
--
-- Stored = ciphertext always. The payload is an opaque envelope (nonce + ciphertext + tag)
-- produced on device with the iCloud-Keychain master key; the server never sees plaintext
-- and never holds a key.
--
-- Deliberately ABSENT (minimum-leak posture, pending M1-CONTRACTS sync-seam review):
--   * no kind/collection/entity-type column — even record-type counts are story-shape
--     metadata. If the reviewed M1 sync design needs per-collection sync, it adds the
--     column through contract review, not here.
--   * no payload size cap — envelope granularity (per-record vs snapshot) is an M1 decision.
--
-- envelope_version versions the ENVELOPE FORMAT (crypto framing), not the content schema —
-- content schema lives inside the ciphertext where the server can't see it.
--
-- deleted_at is a sync tombstone so record deletions propagate across devices. Hard erase
-- ("gone means gone") is row deletion — via auth-user cascade or explicit purge, never a
-- tombstone pretending to be erasure (C2).

create table public.encrypted_blobs (
  user_id          uuid not null references auth.users (id) on delete cascade,
  blob_id          uuid not null,
  payload          bytea not null,
  envelope_version smallint not null default 1,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  primary key (user_id, blob_id)
);

-- Delta pulls: "everything of mine changed since <cursor>".
create index encrypted_blobs_user_updated_idx
  on public.encrypted_blobs (user_id, updated_at);

create trigger encrypted_blobs_set_updated_at
  before update on public.encrypted_blobs
  for each row execute function public.set_updated_at();

alter table public.encrypted_blobs enable row level security;

create policy "encrypted_blobs: owner select"
  on public.encrypted_blobs for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "encrypted_blobs: owner insert"
  on public.encrypted_blobs for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "encrypted_blobs: owner update"
  on public.encrypted_blobs for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "encrypted_blobs: owner delete"
  on public.encrypted_blobs for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.encrypted_blobs from anon;
