# kept-swift — Keeper (working title)

A private, character-led life-keeper for iOS: you talk to Pom; the app files your life into chapters
orbiting a little world, and never forgets. Swift 6 · SwiftUI · encrypted local-first store · AI via
backend proxy only. **Placeholder names throughout (F5).**

**STATUS: GRADUATED 2026-07-19.** The fight is done: prime directive ruled, contracts C1–C10
approved, all decision gates F1–F12 closed (`day-zero/FIGHT-LIST.md` is the record). Zero feature
code yet — next: first commit (docs + scaffold), then M0 once `docs/PROVISIONING.md` items land.

## The map (reading order)

| File | Job |
|---|---|
| `CLAUDE.md` | The constitution (DRAFT): prime directive, non-negotiables, locked contracts C1–C10, stack, anti-slop |
| `AGENTS.md` | SDK tripwires — this is NOT the Swift/iOS in your training data |
| `WORKSTYLE.md` | How changes get made (Tier-1, verbatim house rules) |
| `LOOP.md` | What an unattended agent may do (DRAFT) |
| `LEXICON.md` | Controlled vocabulary + graveyard |
| `day-zero/VISION.md` | What Keeper is and the prime-directive candidates |
| `day-zero/APPROACH.md` | Where contracts C1–C10 get decided, with reasoning |
| `day-zero/FIGHT-LIST.md` | Open decisions F1–F12, ⛔ = blocking |
| `day-zero/ROADMAP.md` | Milestones M0–M8, decision log, standing organs |
| `docs/onboarding.md` | Canonical M2 spec — verbatim copy + script + acceptance (copy source of truth) |
| `docs/monetization.md` | Superwall + pricing contract (REQUIRED before paywall work) |
| `docs/PROVISIONING.md` | Xavier-owned account setup (Supabase, Anthropic, Apple) |

Source of truth for product scope: **KEEPER-whitepaper-final v1.0** (§ references throughout the docs
point at it). Screens referenced by the whitepaper live in `./screens/` once design (F7) lands.

## The process from here

1. **First commit** — docs + XcodeGen scaffold, zero feature code. ROADMAP hoists to root.
2. **Provisioning** — Xavier runs `docs/PROVISIONING.md` (Supabase project, Anthropic key with
   written no-training confirmation, Apple Developer setup).
3. **M0 → M8** — per milestone: `day-zero/M<n>-CONTRACTS.md` written and approved before code;
   done = green tests on real data + device-verify on a confirmed build number.
4. **Human checkpoints that remain:** contract-package approvals, device-verify passes, Pom's voice
   copy rulings, F5 naming + F8 price confirm before M8, and the merge to `main` (WORKSTYLE #2).
