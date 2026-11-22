#!/usr/bin/env bash
# PreToolUse hook, matcher "Bash".
# When the agent runs `git commit`, run the project's tests first and refuse the commit if they fail.
#
# Test command, first found wins:
#   1. $CLAUDE_HOOKS_TEST_CMD
#   2. the first non-comment line of .claude/hooks/test-command
#   3. auto-detected: ./mvnw, mvn (pom.xml), ./gradlew, gradle (build.gradle[.kts])
# No test command found -> the commit is allowed (nothing to enforce).
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

command="$(json_field '.tool_input.command')"

# Re-entrancy guard: a test suite that itself runs `git commit` must not trigger the tests again.
[[ -n "${CLAUDE_HOOKS_TESTS_RUNNING:-}" ]] && exit 0

# `git commit`, also `git -C dir commit` and `git -c key=value commit`; not `git commit --dry-run`
commit_re='(^|[;&|(][[:space:]]*|[[:space:]])git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'
grep -Eq -- "$commit_re" <<< "$command" || exit 0
grep -Eq -- '--dry-run' <<< "$command" && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(json_field '.cwd')}"
project_dir="${project_dir:-$PWD}"
cd "$project_dir" || block "cannot enter project directory $project_dir"

test_cmd="${CLAUDE_HOOKS_TEST_CMD:-}"
if [[ -z "$test_cmd" && -f .claude/hooks/test-command ]]; then
  test_cmd="$(grep -Ev '^[[:space:]]*(#|$)' .claude/hooks/test-command | head -n 1)"
fi
if [[ -z "$test_cmd" ]]; then
  if   [[ -x ./mvnw ]];                                  then test_cmd="./mvnw -q -B test"
  elif [[ -f pom.xml ]] && command -v mvn >/dev/null;    then test_cmd="mvn -q -B test"
  elif [[ -x ./gradlew ]];                               then test_cmd="./gradlew test --quiet"
  elif [[ -f build.gradle || -f build.gradle.kts ]] && command -v gradle >/dev/null; then test_cmd="gradle test --quiet"
  fi
fi
[[ -z "$test_cmd" ]] && exit 0

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if CLAUDE_HOOKS_TESTS_RUNNING=1 bash -c "$test_cmd" >"$log" 2>&1; then
  exit 0
fi

{
  echo "Tests failed, commit refused. Command: $test_cmd"
  echo "--- last 40 lines of output ---"
  tail -n 40 "$log"
  echo "--- fix the code (not the tests, unless the test is wrong) and commit again."
} >&2
exit 2
