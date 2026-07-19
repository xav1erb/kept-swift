# Keeper — Monetization (Superwall + pricing)

<!-- REQUIRED reading before any paywall work. Sources: F8 ruling 2026-07-19; Superwall lessons
     extracted from affirmly (the reference implementation), smyle, and mens-mental-health;
     pricing research 2026-07-19 (comps + RevenueCat benchmarks). Placement rules come from the
     whitepaper §17 and are not renegotiated here. -->

## The architecture (ported from affirmly — clone, don't re-derive)

**Superwall presents; the StoreKit 2 mirror is entitlement truth.** Superwall's default purchase
controller runs the buy flow and renders campaigns; the app re-derives entitlement from
`Transaction.currentEntitlements` and never trusts the wall.

Reference files to port (read before writing any paywall code):
- `affirmly/Affirmly/Services/Purchase/{PurchaseModel,StoreKitPurchaseService,PurchaseService}.swift`
- `affirmly/Affirmly/Services/Paywall/{PaywallPlacements,PaywallPersonalization}.swift`
- `affirmly/Affirmly/Features/Paywall/PaywallGateView.swift`
- `affirmly/Affirmly/Services/Superwall/SuperwallAnalyticsBridge.swift`
- `affirmly/Affirmly/App/AffirmlyApp.swift` (configure + scenePhase wiring)
- `smyle/docs/store/pricing-aso-research.md` (strategy evidence)

Skills: copy `mens-mental-health/.agents/skills/superwall/` and `superwall-editor/` into
`.agents/skills/` (SKILL.md + references + scripts ONLY — **never the bundled `.env` /
`.superwall/state.json` secret files**; re-auth with Keeper's own key).

## The do / never checklist (each rule traces to a shipped incident)

**Configure**
- Configure once at launch, guarded by `hasKey && !isRunningTests` + a QA launch-arg; expose one
  `Paywall.isConfigured` flag (Superwall hard-crashes if used before configure).
- Set the delegate immediately after configure; delegate is a singleton (held weakly).

**Entitlement truth**
- One `PurchaseModel` mirror: sync-init from persisted state, then `Transaction.currentEntitlements`
  + `Transaction.updates`. One `StoreKitPurchaseService` = the only StoreKit importer. Verify every
  transaction; unverified throws. Money is `Decimal`/minor units, never `Double`.
- The mirror is the ONLY writer of `is_subscriber` (two writers disagree mid-launch).
- After purchased/restored, re-confirm against the mirror (`confirmEntitledAfterPurchase()`) — the
  smyle TF26 SKU-drift incident stranded a paying user; on mismatch **fail open** + emit an
  `entitlement_mismatch` breadcrumb.
- **Never** treat Superwall's `subscriptionStatus` as truth in a native app.

**Outcomes**
- Settle outcomes ONLY from `PaywallPresentationHandler.onDismiss/onSkip/onError`; only `onDismiss`'s
  `PaywallResult` distinguishes purchased/restored/declined.
- **Never** derive outcome from `register()`'s completion — a Non-Gated decline resolves it too.

**Fail-open discipline**
- Skipped/error (holdout, no campaign, offline, keyless) → fail OPEN; latch per-launch
  (`gateFailedOpenThisLaunch`) so a second wall stands down; **never persist the latch.**
- Branded holding surface while evaluating; never a blank screen.

**Personalization (the affirmly build-50 lesson)**
- Params are per-placement, NOT durable: merge the personalization snapshot into EVERY `register()`
  that can present a wall, AND set durable `setUserAttributes` (`{{user.x}}`) before register.
- Snapshot captured at onboarding completion, persisted independently of anything that gets deleted.
- **Never** send empty strings — omit absent values (empty renders as a hole in the sentence).

**Identity**
- `identify(userId:)` with the Supabase UUID on sign-in; `reset()` on logout/erase; one call per auth
  transition, keyed on uid.

**Placements**
- Centralize placement names as constants; case-sensitive; must exist as active campaigns.
- Delays are built in app code — a dashboard time filter cannot delay a placement (audiences
  evaluate once at fire time). Affirmly's dwell went 20s → 12s because 20s felt like 25 and users bailed.
- Wire `Superwall.handleDeepLink(url)` first in `onOpenURL`.
- Keep a hidden `/test-paywall` debug screen with a button per placement.

**Compliance (3.1.2 / smyle C6 honest-monetization, inherited)**
- Privacy Policy + Terms links **in the binary** on the gate screen (dashboard links aren't ours).
- Restore always reachable outside the wall; a restore that finds nothing says so.
- `.storekit`, ASC, and the store-description subscription block state identical prices — change all
  three together. Any countdown offer is a real single offer (the Cal AI April-2026 takedown).
- **Keeper-specific (C3):** the paywall never gates safety (crisis routing), never gates reading your
  own history, and cosmetic streak rewards stay free (whitepaper §17).

## Pricing (F8 ruling, 2026-07-19 — re-confirm exact points before M8 ASC config)

| SKU | Price (US) | Notes |
|---|---|---|
| Monthly | **$12.99** | Rosebud-parity; AI-heavy product signals above Finch's $9.99. |
| Annual | **$69.99** (~$5.83/mo, 55% off) | THE category anchor (Finch/Tolan/Replika/Youper/Headspace all $69.99). 7-day trial on annual only. AI-app churn data (RevenueCat: 21% 12-mo retention for AI apps) says capture the year. |
| Weekly | **$4.99 — built but dark** | Tolan-parity CAC-payback instrument. Enable per-campaign via Superwall for paid-TikTok cohorts only; organic stays monthly/annual. |

**Free tier:** 3 chapters · ~5 vents/day soft cap (in-character: "I'll be here tomorrow 🤍" — never a
hard error) · first prep-mode use free · first monthly recap free (the recap is then the best
proven-value paywall trigger) · starter cosmetics free, catalog gated · **reading your own history is
never paywalled** (locking someone's life story would poison the sealed brand — Rosebud/Finch both
keep history/core free).

**Placement (whitepaper §17, unchanged):** no paywall in onboarding; triggers at proven-value moments
(answering the first post-event check-in; first "end this chapter"; recap #2).

**Category evidence (full report in session notes):** companion band $9.99–12.99/mo, modal annual
$69.99; TikTok-acquired apps (Cal AI, Tolan, Breeze, Earkick) all carry a $3.99–8.49/wk SKU; trials
are near-universally 7 days; H&F revenue is 68% annual. Smyle's own pricing research refuted
"go cheap" (higher prices convert better, ~6-7× Y1 LTV) and "lifetime-first" (secondary upsell only).
Caveat: comp figures ±20% (heavy A/B + regional testing) — verify Finch/Rosebud/Tolan in-app before
finalizing. Regional pricing via App Store equalization; don't fight the 30–60% non-US discount.
