#!/usr/bin/env bash
# PreToolUse hook, matchers "Edit|Write" and "Read|Grep".
# 0. Read/Grep: refuses to read secret files (their content would enter the conversation).
# 1. Refuses to create or edit secret files (.env, private keys, keystores, credential files).
# 2. Refuses content that contains a secret (API keys, tokens, private keys, passwords in URLs).
# 3. In config files, refuses hard-coded passwords/keys: values must be placeholders like ${DB_PASSWORD}.
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

tool="$(json_field '.tool_name')"
is_template() { grep -Eiq '\.(example|sample|template|dist)$' <<< "$1"; }

if [[ "$tool" == Read || "$tool" == Grep ]]; then
  read_reason="reading it would put the secrets it holds into the conversation (sent to the model, kept in the session transcript). The application reads it at runtime: you do not need the values. Read .env.example for the variable names, or ask the human."
  for p in "$(json_field '.tool_input.file_path')" "$(json_field '.tool_input.path')"; do
    [[ -n "$p" ]] && ! is_template "$p" && rule_matches "$RULES_DIR/protected-files.tsv" "$p" && block "$p: $read_reason"
  done
  # Grep with a glob such as ".env*" or "*.pem" targets secret files too
  glob="$(json_field '.tool_input.glob')"
  if [[ -n "$glob" ]] && ! is_template "$glob" \
     && grep -Eiq '(^|[/{,*])\.env|\.(pem|key|p12|pfx|jks|keystore)([},]|$)|id_(rsa|dsa|ecdsa|ed25519)' <<< "$glob"; then
    block "glob $glob: $read_reason"
  fi
  exit 0
fi

file_path="$(json_field '.tool_input.file_path')"
# Write sends "content", Edit sends "new_string"
content="$(json_field '.tool_input.content // .tool_input.new_string')"

if [[ -n "$file_path" ]]; then
  # Templates are meant to be committed: .env.example, application-secret.yml.sample...
  if ! is_template "$file_path"; then
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
