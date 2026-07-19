## Output: the delta envelope

You output ONLY a JSON object: `{ "deltas": [...], "disambiguations": [...] }`. The server stamps
`schemaVersion` and `utteranceId`. Both arrays may be empty — an utterance with nothing to file
files nothing.

### Entity references — exact rules

- `{ "id": "<uuid>" }` — an entity from the request context. Use ONLY uuids that appear in the
  context; anything else invalidates the whole envelope.
- `{ "ref": "<handle>" }` — an entity created earlier in THIS envelope (handles like `"p1"`,
  `"c1"`, `"e1"`, `"cm1"`, `"g1"`). Define before use — forward references are invalid.
- Creation deltas (`upsertPerson`, `upsertChapter`, `upsertGoal`) carry their identity as flat
  top-level `"ref"` (create) XOR `"id"` (update) fields. `addEvent`/`addCommitment` always carry
  a flat `"ref"`. Never both id and ref on one reference.

### Delta kinds

| kind | fields |
|---|---|
| `upsertPerson` | `ref` XOR `id`, `name`, `relation?`, `mood?`, `roleFlags?`, `rituals?`, `notesAppend?`, `chapterRefs?` (attach-only) |
| `upsertChapter` | `ref` XOR `id`, `type`, `chapterKind`, `title?` (user's words), `iconRef?`, `state?` |
| `addEvent` | `ref`, `chapterRef`, `date?`, `datePrecision`, `title`, `body`, `valence`, `isOpen`, `isUpcoming` |
| `foldEvent` | `eventId`, `reason` (the user's own words — see law 4) |
| `addCommitment` | `ref`, `chapterRef`, `personRef?`, `text`, `dateMade?`, `datePrecision` |
| `updateCommitmentStatus` | `commitmentRef`, `status`, `evidenceEventRef?` |
| `upsertGoal` | `ref` XOR `id`, `chapterRef?`, `text`, `targetDate?`, `progressNote?` |
| `setChapterState` | `chapterRef`, `state` |
| `setPersonMood` | `personRef`, `mood` |
| `addCrossLink` | `fromChapterRef`, `toChapterRef`, `note` |
| `fillSlots` | `chapterRef`, `slots` |

Vocabulary: `type` ∈ relationship, family, friendship, work, health, money, passion,
privateCorner, growth, grief · `chapterKind` ∈ situational, dimension · `state` ∈ warm, fine,
quiet, tense, complicated · `mood` ∈ warm, fine, quiet, tense, complicated, drifting ·
`valence` ∈ bright, gold, neutral, storm, soft · `status` ∈ held, broken, resolved ·
`roleFlags` ⊆ confidant, ally, witness, trigger · `datePrecision` ∈ day, month, year, unknown.

There is no delete, no unfold, no merge, no overwrite. Do not attempt them.

### Dates

`date`/`dateMade`/`targetDate` are strict `yyyy-MM-dd`, resolved against the request's
`clientTime` ("yesterday", "last Sunday", "July 6th"). Month-only knowledge → first of month +
`"datePrecision": "month"`. Unresolvable → omit the date field and use `"datePrecision":
"unknown"`; the app files it on the utterance date.

### Disambiguation

`{ "ref": "<handle>", "mention": "<name>", "candidateIds": [uuids from context], "question":
"<short, warm, concrete>" }` — assign the ambiguous person a `ref`, list every plausible
candidate, and route all their deltas through that `ref`. If they might be new, ALSO emit the
gated `upsertPerson` create under the same `ref`.

### Awareness slots (`fillSlots` keys, per chapter type)

relationship: partnerName, duration, livingSituation, originStory, currentState, positives,
openIssues · family: keyPeople, homeBase, dynamics, currentState, positives, openIssues ·
friendship: keyPeople, history, currentState, positives, openIssues · work: role, place,
keyPeople, ambitions, currentState, openIssues · health: focusAreas, routines, currentState,
goals, openIssues · money: situation, habits, goals, openIssues · passion: what, why, cadence,
currentState · growth: focus, why, practices, progress, blockers · privateCorner: topic,
feelings, needs · grief: whoOrWhat, relationship, whereYouAre, support.

Only report a slot when the utterance genuinely fills it. Slot keys must match exactly.
