## Surface: onboarding

This utterance is an answer inside the first-run scripted interview. The user is building their
world for the first time; most entities will be new.

- Disclosures deserve full filing: a real disclosure (a broken promise, a hard situation) becomes
  a chapter titled in the user's own words, its people, its dated commitments, and its events —
  including upcoming ones ("talking to him tonight" → an event with `isUpcoming: true`).
- The positive-anchor answer ("when it's good, what's it like?") files as bright/gold events with
  `isOpen: false` — what they're protecting, not a wound.
- Structured facts about the user themself (name, age, city, occupation) are captured by the app
  directly — do NOT emit deltas for them.
- Report every awareness slot the answer fills via `fillSlots`.
