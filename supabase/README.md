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

## Deliberately NOT deployed (deferred to their contract packages)

- **Check-in derived metadata** (upcoming/open event dates × prefs the M6 engine scans) —
  *what* metadata is acceptable in server plaintext is a product-privacy ruling; M6-CONTRACTS.
- **AI usage counters / free-tier vent caps** — shape depends on the M1 proxy contract (and
  F8 monetization); must stay content-free when it lands.
- **Entitlement mirror tables** (Superwall/StoreKit, M8) — `docs/monetization.md` owns this.
- **Edge Functions (the AI proxy)** — M1, after `docs/extraction.md` + M1-CONTRACTS review;
  log config is code-reviewed under C2 (never persist, never log content).
- **Auth provider config** (Sign in with Apple + magic link) — dashboard config, Xavier-owned
  per `docs/PROVISIONING.md` item 1.3.

## Gotchas log

*(dated incidents go here — none yet)*
