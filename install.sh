#!/usr/bin/env bash
# Install the guardrail hooks into another project.
#
#   ./install.sh [--dry-run] [--force] <target-project-dir>
#
# - copies .claude/hooks/ (scripts, lib, rules) into <target>/.claude/hooks/
# - merges the "hooks" section and the permissions.deny rules into <target>/.claude/settings.json
#   (keeps everything already there, adds only what is missing, backs the file up first)
# - safe to run again: it is also how you update
#
#   --dry-run   show what would change, change nothing
#   --force     also overwrite rule files (.tsv) you may have customized
#
# Run it from a clone of this repository. Do not pipe it from the network into a shell.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dry_run=false
force=false
target=""

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --force)   force=true ;;
    -h|--help) usage 0 ;;
    -*)        echo "unknown option: $1" >&2; usage 1 ;;
    *)         [[ -n "$target" ]] && { echo "only one target directory" >&2; usage 1; }; target="$1" ;;
  esac
  shift
done

[[ -n "$target" ]] || usage 1
command -v jq >/dev/null || { echo "jq is required (https://jqlang.org)" >&2; exit 1; }
[[ -d "$target" ]] || { echo "target directory not found: $target" >&2; exit 1; }
target="$(cd "$target" && pwd)"
[[ "$target" != "$SRC" ]] || { echo "target is this repository itself" >&2; exit 1; }

settings="$target/.claude/settings.json"
if [[ -f "$settings" ]] && ! jq empty "$settings" 2>/dev/null; then
  echo "$settings is not valid JSON: fix it first, nothing was changed." >&2
  exit 1
fi

say() { if $dry_run; then echo "[dry-run] $*"; else echo "$*"; fi; }
run() { $dry_run || "$@"; }

# --- 1. copy the hooks
dest="$target/.claude/hooks"
run mkdir -p "$dest/lib" "$dest/rules"

copy() {  # <relative path> <overwrite: always|keep>
  local rel="$1" mode="$2" from="$SRC/.claude/hooks/$1" to="$dest/$1"
  if [[ -f "$to" ]]; then
    if cmp -s "$from" "$to"; then return; fi
    if [[ "$mode" == keep ]] && ! $force; then
      say "kept     .claude/hooks/$rel (customized; --force to overwrite)"
      return
    fi
    say "updated  .claude/hooks/$rel"
  else
    say "added    .claude/hooks/$rel"
  fi
  run cp "$from" "$to"
}

for f in "$SRC"/.claude/hooks/*.sh; do copy "$(basename "$f")" always; done
copy lib/common.sh always
for f in "$SRC"/.claude/hooks/rules/*.tsv; do copy "rules/$(basename "$f")" keep; done
run chmod +x "$dest"/*.sh
# .claude/hooks/test-command is specific to this repository: not copied.
# The commit hook auto-detects ./mvnw, mvn, ./gradlew and gradle.

# --- 2. merge settings.json
backup=""
current='{}'
[[ -f "$settings" ]] && current="$(cat "$settings")"

merged="$(jq --argjson ours "$(jq '.hooks' "$SRC/.claude/settings.json")" \
             --argjson deny "$(jq '.permissions.deny // []' "$SRC/.claude/settings.json")" '
  # permissions.deny: add the missing rules, keep the existing ones (and their order)
  (if ($deny | length) > 0 then
     .permissions.deny = ((.permissions.deny // []) as $d | $d + ($deny | map(select(. as $r | $d | index($r) | not))))
   else . end)
  | .hooks = (.hooks // {})
  | reduce ($ours | keys_unsorted[]) as $event (.;
      .hooks[$event] = (.hooks[$event] // [])
      | reduce $ours[$event][] as $group (.;
          # the same script can be registered under several matchers: compare within the same matcher only
          [ .hooks[$event][] | select(.matcher == $group.matcher) | .hooks[]? | .command ] as $existing
          | ($group.hooks | map(select(.command as $c | $existing | index($c) | not))) as $missing
          | if ($missing | length) == 0 then .
            else
              ([ .hooks[$event][] | .matcher ] | index($group.matcher)) as $i
              | if $i == null then .hooks[$event] += [ $group | .hooks = $missing ]
                else .hooks[$event][$i].hooks += $missing end
            end))
' <<< "$current")"

if [[ "$(jq -S . <<< "$current")" == "$(jq -S . <<< "$merged")" ]]; then
  say "settings .claude/settings.json already has the hooks"
else
  if [[ -f "$settings" ]]; then
    backup="$settings.bak-$(date +%Y%m%d-%H%M%S)"
    say "backup   .claude/settings.json -> $(basename "$backup")"
    run cp "$settings" "$backup"
    say "merged   hooks and deny rules into .claude/settings.json"
  else
    say "created  .claude/settings.json"
  fi
  if ! $dry_run; then printf '%s\n' "$merged" > "$settings"; fi
fi

note=""; $dry_run && note=" (dry run: nothing changed)"
cat <<EOF

Done$note. Next steps in $target:
  - optional: put your test command in .claude/hooks/test-command (default: auto-detect Maven/Gradle)
  - review the rules in .claude/hooks/rules/*.tsv
  - start Claude Code and run /hooks to check they are loaded
  - commit .claude/hooks/ and .claude/settings.json so the whole team gets them
EOF
if [[ -n "$backup" ]] && ! $dry_run; then
  echo "  - check the merge, then delete $(basename "$backup") (do not commit it)"
fi
