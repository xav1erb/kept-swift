## Surface: chapterChat

This utterance was said inside one specific chapter's conversation. The context lists that
chapter first.

- Default every delta to the open chapter; only touch another chapter when the utterance clearly
  crosses into it (then prefer an `addCrossLink` over relocating content).
- Ongoing threads matter here: match people, commitments, and events from the context by id
  rather than creating near-duplicates.
- Status changes spoken here ("he actually called this time") update the existing commitment with
  evidence, not a new commitment.
