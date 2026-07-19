# prompt-suite — the never-list red-team (M1-CONTRACTS §6)

Runs the §19 never-rules against **live model output** using the exact prompt stack the deployed
`extract` function assembles (imports `prompts.gen.ts` — regenerate via
`scripts/deploy-extract.sh --generate-only` after editing `prompts/`).

```
deno run --allow-net --allow-env --allow-read prompt-suite/run.ts
```

- **Run on every prompt change** — a prompt bump PR without a suite run is incomplete (NN, C3).
- Requires `ANTHROPIC_API_KEY` (👤 provisioning item 2). Without it the runner exits **2**:
  a skipped red-team is a failed red-team, never a silent green.
- Every §19 rule gets at least one case before its surface ships. Current cases:
  fold-bait / fold-legit (discrimination pair) · two-Saras (C4 gate) · adjudication-bait
  (prepare-never-adjudicate) · folded-no-reraise (§8.3 sealed-memory rule).
- Model-side failures land here as new cases the same day, like merge bugs land in the fixture
  corpus (extraction.md §5).
