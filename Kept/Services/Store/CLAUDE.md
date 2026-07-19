# Services/Store — the data seam (C7)

> Read before any store work. SwiftData, the encrypted store, the delta-merge engine, and E2E sync
> (C2/F3) live here and never leak past this boundary. Features consume typed read models + a typed
> command surface; `@Query` in views is banned (F11) — if SwiftData fights that hard, stop and
> propose the narrow exception, never decide alone.

Store design is a human-owned seam (NN#9): the data model lands with `M0-CONTRACTS.md`, the merge
engine with `M1-CONTRACTS.md` + `docs/extraction.md`. Nothing in this folder is generated
unsupervised while those gates are open.

## Gotchas log (dated incidents — the affirmly/smyle convention)

- **2026-07-19 — to-one relationships are optional at the SwiftData layer.** `Event.chapter`,
  `Commitment.chapter/.person`, etc. are `Chapter?`/`Person?` even though the domain requires them:
  SwiftData's insert-then-link flow and cascade-delete interact badly with non-optional inverses.
  Required-ness is enforced by the `KeptStore` command surface, which always sets them. Divergence
  noted against M0-CONTRACTS §2 ("non-optional usable") — usable ≠ worth it.
- **2026-07-19 — simulator has no file-protection classes.** `setAttributes([.protectionKey:
  .complete])` is a silent no-op on the simulator's macOS-backed filesystem; reading the attribute
  returns nil. The full `NSFileProtectionComplete` assert runs on device only (device-verify
  checklist); simulator tests prove the code path, not the attribute.
- **2026-07-19 — default-MainActor isolation vs @Model/Codable.** Under
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, synthesized `Codable` conformances on vocabulary
  types become actor-isolated and the `@Model` macro expansion rejects them ("main actor-isolated
  conformance … in nonisolated context"). Every enum/struct stored inside a model — and
  `DependencyValues` keys/accessors — must be declared `nonisolated`.
