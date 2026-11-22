#!/usr/bin/env bash
# PreToolUse hook, matcher "Bash".
# Blocks shell commands listed in rules/dangerous-commands.tsv
# (destructive deletes, force push, skipped checks, curl | sh, releases, destructive SQL, secret files).
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

command="$(json_field '.tool_input.command')"
[[ -z "$command" ]] && exit 0

check_rules "$RULES_DIR/dangerous-commands.tsv" "$command"
exit 0
