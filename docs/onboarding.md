# Keeper — Onboarding: canonical implementation spec (M2)

<!-- CANON. Transcribed 1:1 from whitepaper §4 (the source of truth for scope) with the affirmly
     onboarding engine as the structural reference (day-zero/M-ONBOARDING-CONTRACTS.md: linear
     @Observable step machine, scaffold + progress bar, resumable draft store, RootView gate,
     post-sign-in sync). All quoted copy is VERBATIM and ships as written (F5 rename pass may touch
     "Pom"/"Keeper" tokens only). The interview IS the product demo. -->

## 0. The engine (affirmly pattern, adapted)

- **`OnboardingStep`** — linear `@Observable` state machine (C8):
  `splash → meetPom → themePicker → iconPicker → aiConsent → interview → worldGenerating →
  worldContents → privacyPledge → faceID → signIn → reveal`.
  The **interview** step hosts its own scripted sub-machine (§6 below). The deep-dive is part of the
  interview script (fork-dependent), not a separate step.
- **`OnboardingScaffold` + progress bar** — progress segments across the top **from screen 3
  (themePicker) onward**. One segment per remaining step; interview advances its segment
  fractionally by script position.
- **`OnboardingDraftStore`** — every answer persists locally the moment it's given (resumable; kill
  the app mid-interview → resume at the same script node). Keeper difference from affirmly: the
  draft is not synced-then-consumed at sign-in — the local encrypted store IS primary (C2/C7);
  sign-in at the end attaches the account and starts ciphertext backup.
- **RootView gate:** `!hasCompletedOnboarding` → onboarding; else app (Face ID lock per its setting).
- **Everything skippable; skips are graceful.** Every screen with input has a quiet skip path; a
  skipped answer writes nothing, queues nothing punitive, and Pom never comments on skips.
- **Transitions:** chat-style screens push messages with typing cadence (short delay per bubble);
  full-screen steps cross-fade; the reveal is chat sliding away → globe expanding (§12).
- **AI boundary rule:** no utterance leaves the device before the consent checkbox (screen 4.5) is
  checked. Screens 4.1–4.4 collect name/theme/icon locally only — no AI calls, no extraction.

## 1. Splash (`4.1`)
- Pom floats with the golden orb (gentle bob; respect Reduce Motion). App name. Tagline:
  **"a little world for your whole life, kept by someone who never forgets"**. Line: **"Sealed ·
  private · yours"**. CTA: **"Come in →"**.
- Writes nothing. → meetPom.

## 2. Meet Pom + name (`4.2`)
- Chat-style, four Pom bubbles in order:
  1. **"I'm so happy you're here :)"**
  2. **"Quick intro — I'm fully private. I keep everything you tell me, sealed, and I help you with
     any part of your life. The messy parts especially."**
  3. **"I'm Pom :) Nice to virtually meet!"**
  4. **"And you are…?"**
- Name field, placeholder **"your name (or a name you like)"**; note under it: **"only Pom ever sees
  this"**. ⟶ `user.name`. Skip allowed (Pom uses no name until Q1 re-asks). → themePicker.

## 3. Theme picker (`4.3`) — live re-skin REQUIRED
- Six swatches: Dusk Lilac · Warm Coquette · Golden Hour · Dark Academia · Cloud Cream · Midnight.
- A live chat preview **re-skins instantly on selection** (this exact behavior is required — it is
  the M0 theming engine's proof). Sample convo in the preview: **"okay but how was the date??"** /
  **"POM. he brought flowers."** / **"writing this in the story immediately 🌷"**.
- CTA **"This one ✓"**, subtext **"you can change it anytime"**. ⟶ `user.theme`; the whole app
  re-skins from here (every subsequent onboarding screen renders in the chosen theme). → iconPicker.

## 4. App icon picker (`4.4`)
- Header: **"Pick your icon — we keep things discreet here."**
- Nine options: six themed (Pom, Midnight, Bloom, Golden, Fern, Tide) + three disguises rendering as
  "Notes", "Weather", "Utility". Note under the grid: **"The last three are disguises — the app
  shows up looking like a boring tool. Your world, hidden in plain sight."**
- CTA **"Confirm icon ✓"**. Implement with `setAlternateIconName` (async; handle failure by keeping
  default + soft retry note; the OS confirmation alert is acceptable). → aiConsent.

## 5. Private-AI consent (`4.5`) — LEGAL GATE
- **Must precede any life questions.** Header: **"One honest thing before we build."**
- Four claims, each architecturally true (C2): **processed only to power your world · never used to
  train AI models · never sold / advertised on · deletable always (including from AI processing)**.
- Explicit checkbox **"I understand and agree…"** + links to Privacy Policy & Terms (in-binary
  links). CTA **"Confirm & start building →"** — **disabled until checked**. No skip on this screen
  (it gates AI; declining = cannot proceed past it). → interview.

## 6. The interview (`4.6`) — the census. HIGH IMPORTANCE.

Scripted conversation: **fixed questions verbatim, AI fills natural acknowledgments between them.**
The script is a typed data structure (`InterviewScript`: nodes with fixed prompt, input kind
[chips | free text | field], branch rules, extraction targets) — not prompt-engineered. Pom's
acknowledgment bubbles between nodes are AI-generated in the chosen voice register; the questions
themselves never vary. Every answer streams through the extraction pipeline (C1) as it's given.

**Q1 — name (re-anchor).** **"What would you like me to call you from now on?"** → `user.name`.
Fixed reply: **"Good name for a main character :)"**

**Q2 — THE FORK.** **"We can do this in 2 ways":**
- **⚡ Focus on the most important chapter now** (~3 min, fill the rest later)
- **🗺 Fill me in on everything now** (~7 min)
⟶ `user.onboardingMode(focus|full)`. **Focus mode** loads `followupQueue` with the untouched
chapter types for day-2+ completion — **one queue question per app-open, max**; contextual capture
auto-resolves queue items (F10 spec in M2-CONTRACTS). **Full mode** runs every block below.

**Q3 — quick basics**, in order:
- Age → **age-gate runs silently** (no callout; under-18 routes to the restricted flow per F6 spec).
- **"Where in the world is your world?"** → `user.city`.
- **"What do you do: work, school, both, in between?"** — chips, including **"Living my best life
  (none)"** → follow-up on occupation → `user.occupation`.

**Q4 — relationship block (direct census):**
- **"Are you in a relationship?"** — chips: **Yes / No / I'm married / It's complicated rn**.
- → partner name → duration →
- **"How are things between you and {name} right now, today, in one word?"** — chips: **Good / Fine /
  Tense / Confusing / Fragile**.
- If negative: ONE optional open follow-up — **"what's confusing about it — one or two sentences —
  or leave it for later."** (Never more than one push. "Leave it for later" is a first-class chip.)
⟶ Person (partner), Chapter (relationship), state.

**Q5 — real-disclosure handling (behavior, not a fixed question).** When the open follow-up (or any
answer) contains a real disclosure (e.g. a broken Instagram promise), Pom must:
reflect it back **naming the pattern** → **date the commitment** ("receipts matter") → open
**Chapter 1 with an AI-generated title** in the user's words → **disambiguate people** on first
ambiguity (C4 gate) → **pin upcoming events** ("talking to him tonight" → pinned `isUpcoming` Event,
prep offered at the reveal). ⟶ Commitment (dated), Events, chapter title.

**Q6 — the positive-anchor question (REQUIRED, never skipped by the script):**
**"One more: when it's good between you two, what's it like?"** — the app must capture what she's
protecting, not only what's broken. ⟶ bright Events / keep-card material.

**Q7 — deep-dive (fork-dependent).** Focus mode: the disclosed chapter gets its type's full question
sequence now (same engine as the new-chapter flow, §6 of the whitepaper); everything else queues.
Full mode: walk the remaining census blocks (family, work, etc.) at survey depth.

**Q8 — notification pre-permission, contextually attached:**
**"One thing — my whole point is that I follow up. 'How did the talk go?' For that, I need to be
able to reach you."** — Yes/No chips → **iOS system prompt only on Yes** (pre-permission pattern,
§16). "No" is accepted gracefully; re-ask only at a later high-intent moment.

**Q9 — close:** **"Perfect {name}, I hope you're ready to see your world :)"** → worldGenerating.

Every answer maps to model objects (⟶ Person, Chapter, Commitment, Event, state) via the extraction
pipeline (§3 of the whitepaper / C1). The interview's transcript-fixture test (M1 corpus) asserts
the exact expected object graph for a scripted run.

## 7. World generating (`4.7`)
- **"Pom is generating your world…"** — breathing globe, chapter icons orbiting in, checklist
  narrating **with her real data**: **"✓ planting your first chapter · ✓ remembering the people ·
  ✦ painting the sky in {theme}…"** (items reference actual extracted objects, not canned strings).
- Runs while extraction finalizes; minimum dwell for the animation, no fake progress. → worldContents.

## 8. World contents confirmation (`4.8`)
- **"What should your world include? — don't worry, rooms can always be added or removed later."**
- List: the deep-dived chapter **pinned first with a green COMPLETED tag (locked)**; remaining
  chapter types as toggle rows with type-specific one-liners. CTA **"Confirm my world ✓"**.
- Selected-but-unbuilt chapters become dotted "rooms to open" on the globe + `followupQueue`
  entries. → privacyPledge.

## 9. Privacy pledge (`4.9`)
- Visual: globe under a glass dome with a wax seal.
- **"Now, the promise I made you — you just shared a real part of your life with me. I don't take
  that lightly. So, on the record:"** four vows: **encrypted · never trained/sold/seen · lives with
  you behind your key · erase-my-world = gone means gone**. CTA **"Sealed. 🤍"**. → faceID.

## 10. Face ID (`4.10`)
- **"Only your face opens your world."** Scanning animation. CTA **"Lock with Face ID 🔒"** / ghost
  button **"not needed"**. (LocalAuthentication; app-lock on cold start + background return,
  configurable later in the seal settings.) → signIn.

## 11. Sign-in (`4.11`) — REQUIRED, LAST
- Copy **verbatim**: **"One last thing — a sign-in. Not so anyone can see your world (they can't —
  it's encrypted), but so you never lose it. New phone, lost phone — your story follows you. Still
  yours alone. Still sealed. Still deletable in one tap, forever, whenever you want."**
- Buttons: ** Continue with Apple** (primary — App Store requires it when any third-party login
  exists) · **🔑 Continue with email** (magic link).
- Footnote: **"Your sign-in is a key, not an identity — it unlocks your world, it never exposes it."**
- No anonymous path in v1 (§15). On success: account attaches, ciphertext backup begins (C2),
  `identify()` fires for analytics/paywall identity. → reveal.

## 12. Reveal & first value (`4.12`)
- Chat slides away → the globe expands, populated with her real chapters.
- Pom: **"{name}… welcome to your world. One room is lit. The rest, we'll light together."**
- **Routing rule:** if a high-stakes event was pinned during the interview (the talk tonight) →
  route **directly into prep mode** for that chapter. Else → offer a first vent.
- `hasCompletedOnboarding = true`. Onboarding never shows again.

## 13. Acceptance (M2 "done")
1. Full device click-through in both fork modes produces the exact expected object graph from
   scripted answers (extraction fixtures assert it).
2. Consent checkbox provably precedes the first AI call (test: network layer refuses pre-consent).
3. Theme selection re-skins the live preview AND all subsequent screens instantly.
4. All 9 icons apply; disguises render as Notes/Weather/Utility on the home screen.
5. Age-gate silently routes under-18 to the restricted flow (F6).
6. Kill + relaunch mid-interview resumes at the same node with prior answers intact.
7. Notification system prompt appears only after an explicit Yes chip.
8. Sign-in is unskippable and last; Apple primary; magic-link works end-to-end.
9. Reveal routes to prep mode when an event was pinned, vent offer otherwise.
10. Every skip path exits gracefully with nothing written and no comment from Pom.
11. All quoted copy matches this file character-for-character (it is the copy source of truth).
