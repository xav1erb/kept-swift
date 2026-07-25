#!/usr/bin/env bash
# Deploys the chat Edge Function (C5, M4-CONTRACTS §4). Always regenerates prompts.gen.ts from
# prompts/chat/ — the versioned source of truth — so the deployed prompt can never drift.
#
#   scripts/deploy-chat.sh                 # regenerate + deploy
#   scripts/deploy-chat.sh --generate-only # regenerate prompts.gen.ts, no deploy
#
# One-time server config (Xavier — the key already exists from the extract deploy):
#   supabase secrets set CHAT_MODEL_ID=claude-sonnet-5 --project-ref biwwvntcofpjjbqvfkby
set -euo pipefail
cd "$(dirname "$0")/.."

PROMPTS_DIR="prompts/chat"
GEN="supabase/functions/chat/prompts.gen.ts"
VERSION="v001"

esc() { sed -e 's/\\/\\\\/g' -e 's/`/\\`/g' -e 's/\${/\\${/g' "$1"; }

{
  echo "// GENERATED from ${PROMPTS_DIR}/ by scripts/deploy-chat.sh — do not edit by hand."
  echo "// Bumping a prompt = edit ${PROMPTS_DIR}/, regenerate, PR (M1-CONTRACTS §6 applies)."
  echo "export const PROMPT_VERSION = \"${VERSION}\";"
  printf 'export const PERSONA = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-persona.md")"
  printf 'export const MODE_CHAT = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-mode-chat.md")"
  printf 'export const STAGE_REFRAME = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-stage-reframe.md")"
  printf 'export const STAGE_LIKELYANSWERS = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-stage-likelyanswers.md")"
  printf 'export const STAGE_PERSPECTIVE = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-stage-perspective.md")"
  printf 'export const STAGE_KEEPCARD = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-stage-keepcard.md")"
  printf 'export const STAGE_OPENINGCLOSE = `%s`;\n' "$(esc "${PROMPTS_DIR}/${VERSION}-stage-openingclose.md")"
} > "$GEN"
echo "generated $GEN"

if [[ "${1:-}" == "--generate-only" ]]; then
  exit 0
fi

# verify_jwt stays ON (default) — the function serves authenticated users only (C5).
supabase functions deploy chat --project-ref "${SUPABASE_PROJECT_REF:-biwwvntcofpjjbqvfkby}"
