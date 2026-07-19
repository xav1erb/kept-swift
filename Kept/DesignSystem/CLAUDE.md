# DesignSystem — tokens + fidelity protocol

> REQUIRED reading before any UI work (root CLAUDE.md).

- **The token table lives in `Theme.swift`** (M0, live): `ThemePalette` (hex source of truth,
  test-asserted) → `ThemeTokens` (semantic colors + radius band 18–26pt) → `ThemeModel`
  (@Observable engine; switching `theme` re-skins live — proven by the Theme Lab screen and the
  M0 snapshot/theme tests). Views consume tokens only — no ad-hoc colors or `Font.custom` outside
  `ThemeTokens`/`KeptFont`.
- **Cloud Cream is the only final palette** (whitepaper §2.2 exact values; its background gradient
  endpoints are derived and swap at F7). The other five are **STUB** (`palette.isStub`) — replaced
  when the designer's file lands.
- **Fonts:** Fraunces (display) + Quicksand (UI), bundled variable TTFs, OFL licenses alongside.
  Weights via variable axes are not wired yet — default instances only until F7 typography specs.
- The affirmly Figma 1:1 fidelity protocol (metadata-first, per-node, token-first, screenshot-diff
  deltas table) **activates when F7's design file lands**. Until then: structure + tokens only,
  **no "1:1" claims** anywhere.
- Snapshot tests are pinned to the greenlight simulator (M0-CONTRACTS §8 ruling); stub-palette
  references will be re-recorded at F7 — expected churn, not a regression.
