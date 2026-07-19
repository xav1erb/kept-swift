# LOOP.md — the autonomy policy

> Read every session that runs unattended. Governs what an autonomous agent may do on Keeper without a
> human in the chair. Sits under `CLAUDE.md` (what Keeper is), `WORKSTYLE.md` (how we work), and
> `AGENTS.md` (SDK truths); on any conflict they win and the loop stops and flags.
> **STATUS: DRAFT — inherits the ratified house policy; Keeper-specific items marked.**

## THE ONE RULE

**The loop trusts exactly one signal: `scripts/greenlight.sh` exiting `0`.**

Not "it compiles," not "looks done," not "the diff seems right." Green or red, nothing between. Every
claim of progress in an unattended session cites a green run's log path. A green light bought by
weakening a contract or a test is a red light.

## WHAT THE LOOP MAY DO UNATTENDED (loop-safe)

A task is loop-safe only if ALL hold: (1) provable by `greenlight.sh` alone; (2) touches no human-owned
seam (NN#9) with an open gate; (3) needs no device and no 1:1 fidelity ruling; **(4, Keeper-specific)
changes no prompt artifact and no §19-adjacent behavior without the prompt suite + never-tests in the
green gate.**

Concretely: the deterministic merge engine against transcript fixtures (once the D-gate for the
extraction schema is ratified) · awareness scoring vs schema tables · decoders / `Codable` boundaries ·
streak/rest-day math vs reference tables · GlobeKit orbit math vs golden values · River layout
(bank-assignment/no-overlap property tests) · `@Observable` state machines driven by the faked capture
engine · refactors, coverage, migrations with green-or-red outcomes.

## WHAT STAYS HUMAN (never done unattended)

- **Device-verify** — mic capture, Face ID, alternate icons, notifications, StoreKit. The loop
  produces "ready for device-verify" + the exact checklist; it never ticks a box.
- **The seams** — extraction schema/merge design, encryption & sync design, the prompt stack + safety
  routing, server schema, awareness schemas, auth/entitlements, paywall. Ratified specs may be
  implemented-to unattended; open ones stop-and-flag.
- **Anything Pom says** — new/changed prompt text, check-in copy, notification strings. Drafting is
  fine; shipping voice is a human ruling (softness is judged, then encoded as tests).
- **1:1 Figma fidelity rulings** (post-F7) and **the commit to `main`** (WORKSTYLE #2).

## PER-TASK PROTOCOL

1. Pull next task; skip-and-log if not loop-safe.
2. Branch `loop/<milestone>-<slug>` off `main`. Never work on `main`.
3. Contract first: types + decode boundary + acceptance test before implementation.
4. Implement the vertical slice against the real store/pipeline (transcript fixtures count as real for
   M1-era work; a mock may not outlive its slice).
5. Run `greenlight.sh`; bounded retries; stop-and-flag rather than thrash.
6. On green: commit to the loop branch only (plain message, no AI trailers), write the handoff note
   (what changed, green log path, human follow-ups).
7. Ping with branch + note. Stop-and-flag on any unlocked decision.

### The commit boundary (house-ratified 2026-07-01)
The loop MAY commit on its `loop/*` branch as review checkpoints. It MUST NEVER commit to `main`,
merge, or push. Landing on `main` remains Xavier's, after review.

## STOP-AND-FLAG CONDITIONS

Red after the attempt budget · a task touches a seam with an open gate or contradicts C1–C10 · an
external boundary changed shape or credentials are unavailable · blast radius exceeds the task ·
**any §19 never-rule would be weakened to go green** · backlog empty or next task human-only.

## GUARDRAILS

Never weaken a contract or test for green. Never touch `main`/push/merge unattended. Never bump the
build number on loop branches. Bounded retries, spend/time ceiling, hard stop after two consecutive
failed tasks — better three clean branches than thrashing on a fourth.
