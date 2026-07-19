# LEXICON.md — Keeper's controlled vocabulary

> Every entry: what the thing **is**, what it is **not** (the nearest confusable), and **why this word
> won**. When a term is renamed, move the old word to the graveyard — old words live on in code and
> heads. Started day zero because smyle proved naming drift is cheaper to prevent than repair.
> ⚠️ "Keeper" and "Pom" are themselves placeholders (F5) — the graveyard is expecting them.

## Terms

**Chapter** — One persistent storyline of the user's life (a relationship, the conflict with mom,
health), typed (10 fixed types) and either *situational* or a *dimension*. It is **not** a folder the
user files into — chapters are created and fed by extraction, and it is **not** a chat thread (each
chapter *has* a chat). "Chapter" won because the product metaphor is a kept story, not a database.

**The World / the globe** — The homepage: a 2.5D globe with chapter pins orbiting it. **Not** a map
and **not** SceneKit 3D (v1 is the illusion — see C9). "World" won because Pom keeps "her world," and
onboarding literally generates it.

**The River** — The master timeline weaving all chapters into one S-curve stream. **Not** a feed
(nothing infinite, nothing algorithmic) and **not** a log (positives are deliberately
over-represented). "River" won over "timeline" because chapters have timelines; the master one flows.

**Extraction** — The single pipeline: utterance → AI-proposed structured deltas → deterministic
validation + merge → store (C1). **Not** "sync," **not** "import," **not** a chat feature — it runs on
every utterance from every surface. The word is internal; the user-facing word is *filing*.

**Filing / the filing confirmation** — The user-visible face of extraction: "filed to Mom 🏠, Work 💼
— want to open any?" after a vent. **Not** a system notification — it is the daily proof-of-listening
and ships v1. "Filed" won because Pom is an archivist, not an algorithm.

**Folded (healed)** — An `isHealed` event: rendered as a small mint 🌱 pill, expands only on tap,
refolds, excluded from Pom's unprompted references, still available to pattern analysis. **Not**
deleted, **not** hidden, **not** archived. "Folded" won because the story keeps it — quietly. The verb
matters: *fold*, *refold*, never "dismiss."

**Awareness (%)** — Per-chapter coverage score of that type's question schema, computed by typed code
at merge (C4/C6). **Not** a model's opinion of how well it knows you, and **not** engagement. Grades:
≥90 mint "fully aware," 55–89 gold, <55 lilac "tell me more." May decay after long inactivity — by
scheduled write, never at read.

**Commitment** — A dated promise extracted from conversation ("no following girls," dated July 6),
with status held/broken/resolved and evidence refs. **Not** a task, **not** a goal. Internally also
"receipts" — but *receipts* is Pom's voice word for prep mode, never a UI label.

**Prep mode** — The flagship chapter-chat mode before a hard conversation: reframe, likely-answers
card, perspective calibration, keep-card, opening sentence, post-event check-in armed. **Not** advice
and **not** adjudication — "fair to hold him to it" is in bounds, "reason to break up" is out.

**Keep-card** — The gold "worth remembering tonight" card of stored positives in prep mode. **Not** a
memory list — it exists to protect what's good ("this talk is about protecting that, not putting it
on trial").

**Tell Pom / vent** — The center-button capture sheet: fresh each session, voice-first, multi-topic,
absorbed into chapters via filing. **Not** a persistent chat (chapter chats are the memory) and
**not** a journal entry.

**Check-in** — A server-generated, user-facing push in Pom's voice tied to a real event ("How did the
talk go?"). **Not** a reminder (user-authored, local — different word, different mechanism, C10) and
**never** app-guilt ("we miss you" is banned copy).

**Wins** — Achievements celebrating courage / consistency / closure / self-care / milestones. **Not**
gamification of drama: no badge can be earned by a conflict (C3 never-test). *Blooming* = in-progress;
*secret wins* are noticed, never chased; share cards are stripped by default.

**Soft streak** — Consecutive tending days with one protected rest day per week (🌙); milestones are
cosmetic only. **Not** a pressure mechanic — a missed day doesn't burn the fire.

**State / weather** — The warm / fine / quiet / tense / complicated grading on chapters and people,
rendered as the weather metaphor (mood dots, glows, rainclouds). **Not** sentiment analysis shown as
numbers — always the soft vocabulary.

**The seal / sealed** — The privacy posture as brand: encrypted, never trained on, never sold, never
seen, deletable, disguisable. **Not** marketing copy — every sealed claim is an architectural fact
(C2). Footer mark: SEALED · KEPT ONLY FOR YOU.

**Disguise icons** — The three alternate app icons that make Keeper look like a boring utility.
**Not** a security feature (the lock is Face ID) — a discretion feature: "your world, hidden in
plain sight."

**Resting** — A chapter closed via the closing ceremony (letter written, 📖 win unlocked). **Not**
deleted, **not** archived-forever — rooms can reopen. "Resting" won for softness.

**followupQueue** — The day-2+ question queue created by Focus-mode onboarding; one question per
app-open max, auto-resolved by contextual capture (F10). **Not** a checklist shown to the user.

**Voice (Pom's)** — The user-selected register (Soft / Real with me / Sunshine / Calm) applied as a
system-prompt layer, changeable anytime, even per chapter. **Not** a TTS voice.

## Graveyard

*(empty — F5 renames will land here with dates and reasoning)*
