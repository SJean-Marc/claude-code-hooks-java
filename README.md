# Claude Code guardrail hooks for Java/Spring projects

> A rule written in `CLAUDE.md` is a request. A hook is a rule.
> What must be respected 100% of the time belongs in code, not in a prompt.

Three [Claude Code hooks](https://code.claude.com/docs/en/hooks) that stop a coding agent **before** it does something you cannot undo, and tell it what to do instead.

*Résumé en français [en bas de page](#en-français).*

## The problem

Coding agents are fast and usually right. "Usually" is the issue on a real project:

- one `git push --force` or `git reset --hard` and someone's work is gone;
- one API key pasted in `application.yml`, committed, and it is in the history for good;
- one "quick fix" committed with red tests, and the next person inherits a broken build.

You can ask the agent to be careful in `CLAUDE.md`. It will comply most of the time. Guardrails exist for the other times.

## What is inside

| Hook | Runs on | Blocks |
|---|---|---|
| [`block-dangerous-commands.sh`](.claude/hooks/block-dangerous-commands.sh) | every shell command (`Bash`) | deletes outside the project, `sudo`, `chmod 777`, force push, `reset --hard`, `clean -f`, `commit --no-verify`, `curl \| sh`, `mvn deploy` / `gradle publish`, `docker push`, `kubectl delete`, destructive SQL, reading or writing `.env` and private keys |
| [`protect-secrets.sh`](.claude/hooks/protect-secrets.sh) | every file write (`Edit`, `Write`) | creating `.env`, keys and keystores; API keys, tokens, private keys and passwords in URLs in any file; hard-coded passwords in `application.properties` / `application.yml` (placeholders like `${DB_PASSWORD}` are fine) |
| [`require-tests-before-commit.sh`](.claude/hooks/require-tests-before-commit.sh) | `git commit` run by the agent | the commit, while the tests are red. The last 40 lines of the test output go back to the agent so it can fix the code |

When a hook blocks, Claude sees the reason and the alternative, for example:

```
BLOCKED by block-dangerous-commands.sh: force push rewrites shared history.
Use --force-with-lease on your own branch, or ask the human.
```

The agent then adapts on its own: it uses `--force-with-lease`, writes `.env.example` instead of `.env`, or fixes the failing test.

## Use it in your project

Requirements: `bash` and [`jq`](https://jqlang.org). Nothing else.

```bash
git clone https://github.com/SJean-Marc/claude-code-hooks-java.git
cd claude-code-hooks-java
./install.sh --dry-run ~/code/my-spring-app   # shows what would change
./install.sh ~/code/my-spring-app
```

`install.sh` copies `.claude/hooks/` into your project and **merges** the hooks into its `.claude/settings.json`:

- what is already there stays (permissions, your own hooks, other settings); only the missing hook commands are added;
- `settings.json` is backed up before any change (`settings.json.bak-<date>`: delete it once you have checked the merge, do not commit it), and an invalid one is left untouched;
- rule files you have customized are kept (`--force` to overwrite them);
- running it again changes nothing, so it is also how you update.

It runs from a clone on purpose: piping a script from the network into a shell is exactly what these hooks block.

Then:

1. Optional: tell the commit hook how to run your tests. By default it detects `./mvnw`, `mvn`, `./gradlew` or `gradle`. To override, put a command in `.claude/hooks/test-command` (or set `CLAUDE_HOOKS_TEST_CMD`):

   ```
   ./mvnw -q -B verify -Dgroups=unit
   ```

2. Start Claude Code in the project and run `/hooks` to check the hooks are loaded.
3. Commit `.claude/hooks/` and `.claude/settings.json` so the whole team gets the same guardrails.

### Adapt the rules

The rules are plain text, one per line: a regular expression, a tab, and the message Claude will see. No code to change.

| File | Checked against |
|---|---|
| [`rules/dangerous-commands.tsv`](.claude/hooks/rules/dangerous-commands.tsv) | shell commands |
| [`rules/protected-files.tsv`](.claude/hooks/rules/protected-files.tsv) | paths of written files |
| [`rules/secret-patterns.tsv`](.claude/hooks/rules/secret-patterns.tsv) | content of any written file |
| [`rules/config-secrets.tsv`](.claude/hooks/rules/config-secrets.tsv) | content of config files (`.properties`, `.yml`, `.json`, `.xml`...) |

Write the message for the agent: say **why** it is blocked and **what to do instead**. A bare "forbidden" makes it retry the same thing another way.

## How it is tested

- [`tests/run-tests.sh`](tests/run-tests.sh): 101 checks. For the hooks, each case sends the same JSON Claude Code sends, then checks the hook blocks or allows. For the installer: fresh project, merge into existing settings, rerun, customized rules, dry run, invalid JSON. About a third of the cases check that normal commands still pass: a guardrail that blocks `rm -rf target` gets switched off by the team within a day.
- CI on Linux and macOS (GNU and BSD `grep` differ), plus ShellCheck.
- This repo uses its own hooks: its `.claude/hooks/test-command` runs the test suite before every commit Claude makes here.
- End-to-end checks with a real Claude Code session (2.1.330). The first run found a hole: with the `Write` tool blocked on `.env`, the agent simply ran `printf 'DB_PASSWORD=...' > .env` in the shell. The shell rules now cover writes to secret files too, and the same session is blocked both ways.

That last point is the main lesson: **an agent that is blocked looks for another path.** Every protection needs to cover every tool that can reach the same result.

## Limits

- These hooks are **guardrails against mistakes, not a sandbox**. Regular expressions on command lines can be bypassed by an agent (or a person) that really tries: encoded commands, scripts written then run, etc. For untrusted code, add an OS-level sandbox and [permission rules](https://code.claude.com/docs/en/settings).
- Secret detection is pattern-based. It catches the common token formats and hard-coded config values, not every secret. Keep a secret scanner in your CI as well.
- False positives happen. When one does, change the rule in the `.tsv` file and add a test case for it.

## Repository layout

```
.claude/
  settings.json            hook registration
  hooks/
    lib/common.sh          JSON input, block(), rule matching
    rules/*.tsv            the rules (regex <TAB> message)
    *.sh                   the three hooks
    test-command           test command for this repo
install.sh                 installer: copy hooks + merge settings.json
tests/run-tests.sh         test suite (bash + jq)
.github/workflows/ci.yml   ShellCheck + tests on Linux and macOS
```

---

## En français

**Problème :** un agent de code va vite et se trompe rarement, mais une seule erreur peut coûter cher : un `git push --force`, une clé API commitée, un commit avec des tests rouges. Une consigne dans `CLAUDE.md` est une demande. Un hook est une règle.

**Solution :** trois hooks Claude Code, en bash + jq, qui bloquent l'action **avant** qu'elle se produise et expliquent à l'agent quoi faire à la place :
- commandes dangereuses (suppressions hors du projet, force push, `reset --hard`, `curl | sh`, déploiement, SQL destructif, fichiers de secrets) ;
- secrets dans les fichiers (clés API, tokens, mots de passe en dur dans `application.yml`) ;
- pas de commit tant que les tests sont rouges.

**Utilisation :** `./install.sh <projet>` copie les hooks et fusionne `.claude/settings.json` sans rien écraser (sauvegarde, `--dry-run`, relançable pour mettre à jour). Les règles s'adaptent dans les fichiers `.tsv`. 101 tests, CI sous Linux et macOS, et des essais avec une vraie session Claude Code. Le premier essai a montré qu'un agent bloqué sur l'outil `Write` passe par le shell : chaque protection doit couvrir tous les chemins.
