#!/usr/bin/env bash
# PreToolUse hook, matcher "Edit|Write".
# 1. Refuses to create or edit secret files (.env, private keys, keystores, credential files).
# 2. Refuses content that contains a secret (API keys, tokens, private keys, passwords in URLs).
# 3. In config files, refuses hard-coded passwords/keys: values must be placeholders like ${DB_PASSWORD}.
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

file_path="$(json_field '.tool_input.file_path')"
# Write sends "content", Edit sends "new_string"
content="$(json_field '.tool_input.content // .tool_input.new_string')"

if [[ -n "$file_path" ]]; then
  # Templates are meant to be committed: .env.example, application-secret.yml.sample...
  if ! grep -Eiq '\.(example|sample|template|dist)$' <<< "$file_path"; then
    check_rules "$RULES_DIR/protected-files.tsv" "$file_path"
  fi
fi

[[ -z "$content" ]] && exit 0

check_rules "$RULES_DIR/secret-patterns.tsv" "$content" -E

if grep -Eiq '\.(properties|ya?ml|conf|toml|json|xml|ini)$|\.env\.[a-z]+$' <<< "$file_path"; then
  # Lines whose value is a placeholder are fine: ${VAR}, <value>, changeme, ****
  filtered="$(grep -Eiv '[:=][[:space:]]*["'\'']?(\$\{|<|changeme|change-me|\*{3,}|xxx+|your[-_])' <<< "$content")"
  check_rules "$RULES_DIR/config-secrets.tsv" "$filtered"
fi
exit 0
