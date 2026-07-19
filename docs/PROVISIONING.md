# Keeper — Provisioning checklist (Xavier-owned)

<!-- The three account-level items an autonomous agent cannot create. Each has exact steps and a
     "hand to the agent" line. Secrets go in env/local config, NEVER the repo. Ruled 2026-07-19. -->

## 1. Supabase project
1. Create a new project (org: your choice) — name e.g. `kept-swift-prod` (+ `kept-swift-dev` if you
   want a staging pair; recommended).
2. Note: Project URL, `anon` key, `service_role` key, database password.
3. Enable: Auth (Sign in with Apple + email magic link providers), Edge Functions, `pg_cron`
   (Database → Extensions).
4. Hand to the agent: Project URL + anon key (client config), service-role key via
   `supabase secrets` / CI env only. The agent writes migrations, RLS, and Edge Functions from there.

## 2. Anthropic API key
1. Create a key in the Anthropic Console under a **commercial account** (not a personal/consumer plan).
2. **C2 requirement:** obtain written confirmation (support ticket or the current commercial-terms
   page snapshot, saved to your records) that API traffic on this tier is **not used for model
   training**. This is a contractual gate for M1 — the consent screen's claim depends on it.
3. Hand to the agent: the key as a Supabase Edge Function secret (`supabase secrets set
   ANTHROPIC_API_KEY=...`). It never appears in the app binary or repo (C5).

## 3. Apple Developer setup
1. Register a bundle id (placeholder fine per F5, e.g. `com.keeper.app` — renameable pre-launch but
   NOT after first ASC upload, so prefer deciding F5 naming before the first TestFlight build).
2. App Store Connect: create the app record (17+ rating), enable Sign in with Apple capability.
3. Create an **APNs auth key** (needed for M6 check-in push) — note Key ID + Team ID. The affirmly
   post-mortem lesson: verify `aps-environment` entitlement + the key lands in Supabase secrets, or
   push silently 403s with an empty device-token table.
4. Alternate app icons + Face ID (`NSFaceIDUsageDescription`) need no portal setup, just plist —
   agent handles.
5. Superwall (M8): create the Keeper app in the Superwall dashboard, note the public API key; the
   `.agents/skills/superwall` tooling drives campaign setup from there.
6. Hand to the agent: Team ID, bundle id, APNs Key ID + .p8 (as backend secret), signing via Xcode
   automatic signing on your account.

## Not provisioned (by ruling)
- Telegram loop-ping bot — the loop runs without pings for now; add later if overnight runs start.
