#!/usr/bin/env bash
# Deploys the extract Edge Function (C5). Always regenerates prompts.gen.ts from prompts/extract/
# — the versioned source of truth — so the deployed prompt can never drift from the repo.
#
#   scripts/deploy-extract.sh                 # regenerate + deploy
#   scripts/deploy-extract.sh --generate-only # regenerate prompts.gen.ts, no deploy
#
# One-time server config (Xavier, provisioning item 2 — C2: the key exists ONLY here):
#   supabase secrets set ANTHROPIC_API_KEY=<key> EXTRACT_MODEL_ID=claude-haiku-4-5 \
#     --project-ref biwwvntcofpjjbqvfkby
set -euo pipefail
cd "$(dirname "$0")/.."

PROMPTS_DIR="prompts/extract"
GEN="supabase/functions/extract/prompts.gen.ts"
VERSION="v001"

esc() { sed -e 's/\\/\\\\/g' -e 's/`/\\`/g' -e 's/\${/\\${/g' "$1"; }

{
  echo "// GENERATED from ${PROMPTS_DIR}/ by scripts/deploy-extract.sh — do not edit by hand."
  echo "// Bumping a prompt = edit ${PROMPTS_DIR}/, regenerate, PR (M1-CONTRACTS §6)."
  echo "export const PROMPT_VERSION = \"${VERSION}\";"
  printf 'export const PERSONA = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-persona.md")"
  printf 'export const SURFACE_ONBOARDING = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-surface-onboarding.md")"
  printf 'export const SURFACE_CHAPTER_CHAT = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-surface-chapterchat.md")"
  printf 'export const SURFACE_VENT = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-surface-vent.md")"
  printf 'export const SCHEMA_INSTRUCTIONS = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-schema.md")"
} > "$GEN"
echo "generated $GEN"

if [[ "${1:-}" == "--generate-only" ]]; then
  exit 0
fi

# verify_jwt stays ON (default) — the function serves authenticated users only (C5).
supabase functions deploy extract --project-ref "${SUPABASE_PROJECT_REF:-biwwvntcofpjjbqvfkby}"
