# KEEPER — Vision

<!-- DAY-ZERO DOC. Lives outside the graduated repo. Source of truth for scope/intent is
     KEEPER-whitepaper-final (v1.0, July 2026). This file distills it into the shape the
     constitution graduates from. STATUS: DRAFT — to be fought. Names "Keeper" and "Pom"
     are placeholders (see FIGHT-LIST F5). -->

## One-liner

A private, character-led life-keeper: the user talks to a small creature (Pom) and the app silently
files their entire life — people, events, promises, feelings — into persistent chapters orbiting a
little world, so nothing is ever forgotten and nothing is ever used against them.

## The enemy behavior

- **The notes-app graveyard.** Journaling apps make the user do the filing; entries pile up unread,
  unstructured, unremembered. Keeper's user talks; the extraction pipeline files.
- **The generic-therapist chatbot.** "As an AI…" empathy with no memory, no receipts, no follow-up.
  Pom remembers the promise from July 6 and asks how the talk went.
- **The case file.** Any tool that turns a relationship into evidence-against. Keeper holds receipts
  to *prepare* the user, never to adjudicate, and folds healed moments so the story leads with the good.

## Prime-directive candidates — RULED 2026-07-19: candidate 3, "Sealed, soft, and on your side" (graduated into CLAUDE.md)

1. **"Kept, never weaponized."** The unit of Keeper is a life story held safely. If a choice makes the
   app feel like a case file being built against someone, it is wrong. If it makes it feel like a
   gentle keeper who remembers so the user doesn't have to, it is right.
2. **"You talk. She keeps."** Every burden of structure (filing, dating, linking, remembering) belongs
   to the app, never the user. If a choice makes the user do the filing, it is wrong.
3. **"Sealed, soft, and on your side."** The three product laws compressed: privacy true in the
   architecture, softness enforced in code, preparation never adjudication.

Test each against the whitepaper's hard cases: folded moments (never surfaced unprompted → #1 decides),
the vent filing confirmation (proof-of-listening → #2 decides), prep mode's boundary ("fair to hold him
to it" in-bounds, "reason to break up" out-of-bounds → #3 decides). The winner must decide all three alone.

## The three product laws (override everything else; verbatim from the whitepaper)

1. **Privacy is the brand.** "Sealed — never trained on, never sold, never seen." On-device-first,
   encrypted, deletable, disguisable icon. Every privacy claim in the UI must be true in the architecture.
2. **Softness by design.** Negative memories never weaponized. Healed = folded, not deleted. Pom never
   raises a folded moment unprompted. Achievements celebrate courage/consistency/closure/self-care —
   never drama. Streaks are soft. Reconciliation never has a timer.
3. **Prepare, don't adjudicate.** Pom arms the user with clarity, receipts, and likely scenarios — but
   never makes relationship decisions for them.

## The core loop

Talk/vent to Pom → extraction pipeline files it (people, events, commitments, states, awareness) →
world/chapters/River update visibly → Pom follows up at the right moment ("How did the talk go?") →
the user comes back because someone remembered. The filing confirmation after a vent is the daily
proof-of-listening; the post-event check-in is the retention hook; prep mode is the flagship value.

## Target user (v1)

Women ~18–35, emotionally rich lives, cozy/aesthetic app taste, acquired via the founder's TikTok
network. English UI. 18+ at launch (age-gate decision pending, F6).

## The 10-year question

Does this compound? Yes by construction: the moat is the accumulated, structured, private life story —
switching costs grow with every chapter kept. The product gets *better* with time (awareness deepens,
patterns emerge, recaps get richer) rather than staler. The risk to guard: growth features (streaks,
wins, paywall) drifting toward engagement-farming and violating law 2 — the never-list (§19) exists
so growth pressure cannot bend softness.
