#!/usr/bin/env bash
# Shared helpers for the hooks. Sourced, never executed directly.
#
# Contract (Claude Code hooks): the hook receives one JSON object on stdin.
# Exit 0  -> the tool call goes on.
# Exit 2  -> the tool call is blocked; what we print on stderr is shown to Claude,
#            so it must explain WHY and WHAT TO DO INSTEAD.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "hook error: jq is required (https://jqlang.org)" >&2
  # Fail closed: a guardrail that silently disappears is worse than no guardrail.
  exit 2
fi

HOOK_INPUT="$(cat)"

# json_field '.tool_input.command' -> raw string, empty if absent
json_field() {
  jq -r "$1 // empty" <<< "$HOOK_INPUT" 2>/dev/null
}

# block "reason" -> stops the tool call and tells Claude why
block() {
  printf 'BLOCKED by %s: %s\n' "$(basename "$0")" "$1" >&2
  exit 2
}

# Directory holding the rule files, next to this lib
# shellcheck disable=SC2034  # used by the hooks that source this file
RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../rules" && pwd)"

# check_rules <rules-file> <text> [grep-flags]
# Each non-comment line of the rules file is:  <extended regex><TAB><reason>
# grep-flags defaults to -Ei (case-insensitive); pass -E for case-sensitive rules.
# Blocks on the first match.
check_rules() {
  local file="$1" text="$2" flags="${3:--Ei}" regex reason
  [[ -f "$file" ]] || block "rules file not found: $file"
  while IFS=$'\t' read -r regex reason; do
    [[ -z "$regex" || "$regex" == \#* ]] && continue
    if grep "$flags" -q -- "$regex" <<< "$text"; then
      block "$reason"
    fi
  done < "$file"
}
