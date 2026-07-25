# Keeper — Supabase server schema

<!-- The server-side DB schema is a human-owned seam (NN#9, APPROACH §seams #4). This baseline
     was deployed at Xavier's direction 2026-07-19; amendments go through contract review
     (M1-CONTRACTS for the sync seam, M6-CONTRACTS for check-in metadata), never ad-hoc. -->

Project ref: `biwwvntcofpjjbqvfkby` (MCP config in `.mcp.json`). Migrations live in
`supabase/migrations/` and are applied through the Supabase MCP (`apply_migration`); local
filenames carry the exact remote version stamps, so the hosted migration history and this
directory are 1:1.

**Deployed 2026-07-19** (versions `20260719112008`–`20260719112337`). Verified after deploy:
RLS enabled on all three tables, all `auth.users` FKs `ON DELETE CASCADE` (catalog-checked),
`pg_cron` 1.6.4 installed, security advisors clean.

## The one rule (C2/F3 — transient-plaintext architecture)

**Stored = ciphertext always; processed = plaintext only in flight.** This database holds
client-encrypted blobs it cannot open, plus the minimum content-free plumbing around them.
No table may ever hold story plaintext. The AI proxy (Edge Functions, M1) processes in-memory
only — no conversation table will ever exist here.

## Objects

| Object | Contract | Purpose |
|---|---|---|
| `pg_cron` extension | C10 | Substrate for the check-in engine / recaps / decay. **No jobs scheduled yet** — each job is registered in the cron ops README the day it is wired (M6). |
| `public.profiles` | C2 | Per-user anchor row, auto-created on signup (`on_auth_user_created` trigger). No story content; future server-side per-user state attaches here through contract review. |
| `public.encrypted_blobs` | C2/F3 | The sync substrate: opaque client-encrypted envelopes keyed `(user_id, blob_id)`. `envelope_version` versions the crypto framing only. `deleted_at` is a sync tombstone; hard erase is row deletion. Deliberately **no kind/collection column** — record-type counts are story-shape metadata (minimum-leak posture, pending M1 sync-seam review). |
| `public.device_push_tokens` | C10 | APNs delivery plumbing for M6. `environment` (sandbox/production) is the affirmly silent-403 post-mortem lesson. Unused until M6. |
| `public.set_updated_at()` / `public.handle_new_user()` | — | Trigger helpers; `security definer` with pinned empty `search_path`. |

## Tenancy / RLS

- RLS enabled on every table; policies are owner-only (`auth.uid() = user_id`), granted to
  `authenticated`. All privileges revoked from `anon` — there is no anonymous surface (F5/§15:
  sign-in required at onboarding end).
- Every user-owned table references `auth.users(id) ON DELETE CASCADE`: deleting the auth user
  purges all server rows in one motion — the server half of "Erase my world" (the other two
  halves are the local wipe and the AI-provider deletion request, C2).
- The platform ships an `ensure_rls` event trigger (`public.rls_auto_enable`, present before our
  first migration) that auto-enables RLS on any new `public` table — a safety net under C2, not
  a substitute for writing owner policies on every new table.

## Edge Functions — `extract` (the AI proxy, C5; M1)

Code: `supabase/functions/extract/` (reviewed under M1-CONTRACTS §3). Deploy via
**`scripts/deploy-extract.sh`** — it regenerates `prompts.gen.ts` from `prompts/extract/` first,
so the deployed prompt can never drift from the repo. `verify_jwt` stays **ON** (never deploy
with `--no-verify-jwt`).

- **Server config (secrets, never in any repo):** `ANTHROPIC_API_KEY` (👤 provisioning item 2 —
  written no-training confirmation gates the milestone close) and `EXTRACT_MODEL_ID`
  (`claude-haiku-4-5`, F4/§8.1). `supabase secrets set … --project-ref biwwvntcofpjjbqvfkby`.
- **C2 log contract (code-reviewed):** log lines carry utteranceId, timing, token counts, model
  id, prompt version, error codes, delta COUNT — never utterance, context, or delta content.
  Adding a logged field = contract review.
- **In-memory only:** no table backs this function; request content lives for the duration of
  the call. `schema_mismatch` (409) enforces server-led schema evolution (§8.4).
- **Status:** code landed 2026-07-19; deploy + secrets are run from Xavier's Supabase terminal;
  the fx-001 live smoke test (M1-CONTRACTS §7.5) closes the loop once the key exists.

## Check-in engine — `scheduled_checkins` + `checkin-dispatch` (C10; M6)

**Ruled 2026-07-25 (M6-CONTRACTS §2/§10.1): content-free alarm rows.** The client is
scheduler-of-record — fire times are computed on device from events × prefs (prefs never
leave the phone); the server holds only `{fire_at, kind, chapter-uuid}` and deletes rows
after firing. The cron job + Edge Function are a dumb alarm clock pushing the fixed generic
copy bank (F12) — the payload builder's type admits no content field. Jobs are registered in
`supabase/cron/README.md` the day they are wired. Server secrets when APNs lands (👤 item 3):
`APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`. Deploy via `scripts/deploy-checkin.sh`.

## Deliberately NOT deployed (deferred to their contract packages)
- **AI usage counters / free-tier vent caps** — shape depends on the M1 proxy contract (and
  F8 monetization); must stay content-free when it lands.
- **Entitlement mirror tables** (Superwall/StoreKit, M8) — `docs/monetization.md` owns this.
- **Auth provider config** (Sign in with Apple + magic link) — dashboard config, Xavier-owned
  per `docs/PROVISIONING.md` item 1.3.

## Gotchas log

*(dated incidents go here — none yet)*
