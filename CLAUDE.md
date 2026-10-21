# OptiClaude

Starter kit for Claude Code projects. It has two installers, `setup.ps1` (Windows PowerShell 5.1 and 7) and `setup.sh` (bash 3.2+), which copy `templates/` into projects or into `~/.claude`. `BOOTSTRAP-PROMPT.md` is the source of the `/opticlaude-setup` skill.

## Commands
<!-- Only commands you ran and confirmed work. -->
- Install deps: none. The bash tests use python3 or jq if they're present, and skip modes they can't run.
- Run all bash tests (setup.sh, statusline.sh, format hook): `bash tests/test.sh`
- Run all PowerShell tests (setup.ps1, statusline.ps1, plus a byte-for-byte comparison against setup.sh): `powershell -NoProfile -ExecutionPolicy Bypass -File tests/test.ps1`
- Try an installer without writing anything: `powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Target <dir> -DryRun`
- CI (`.github/workflows/test.yml`) runs `tests/test.sh` on Ubuntu, macOS and Windows, and `tests/test.ps1` under both `powershell` and `pwsh`.

## Verification (before saying "done")
- Run **both** test suites and show the `passed: N  failed: 0` lines.
- If you add a check, make sure it would fail against the old code. Run it once against `git stash`ed or `git archive HEAD` sources.
- If something could not be verified, say exactly what and why.

## Gotchas
- `setup.ps1` and `setup.sh` must behave identically. `tests/test.ps1` compares their output trees byte for byte, so change both together.
- Never point a test or manual run at the real `~/.claude`. Use `-UserDir` / `--user-dir` with a temp folder.
- `setup.ps1` must stay Windows PowerShell 5.1 compatible: no `??`, ternaries or `&&`.
- `setup.sh` must run on macOS bash 3.2. Empty arrays under `set -u` need `${arr[@]+"${arr[@]}"}`.
- macOS `grep` and `sed` reject regex repeat counts over 255, such as `.\{0,320\}`, even though GNU tools accept them. Use `.*` piped to `cut -c` instead.
- On Git Bash for Windows, `grep` and `awk` silently drop CR characters. Use `tr` and `printf` for byte-exact checks.
- `templates/project/CLAUDE.template.md` is installed as `CLAUDE.md`. It's named `.template` so Claude Code doesn't load it as instructions here.
- `BOOTSTRAP-PROMPT.md` is the source of truth for `/opticlaude-setup`. After editing it, re-run `setup.ps1 -Global` to regenerate the installed skill.
- Keep every `$` out of the `BOOTSTRAP-PROMPT.md` body. Claude Code expands `$ARGUMENTS`, `$1` and `${...}` in skill text when the skill runs, so put such text in a template file (as `templates/snippets/format-hook.json` does). `tests/test.sh` enforces this.
- `.sh` files must keep LF line endings (`.gitattributes`). The installers treat CRLF-only differences as unchanged.
- `find-mistakes.sh` parses Claude Code's internal, undocumented transcript format. `tests/fixtures/transcript.jsonl` mirrors that format, so if real transcripts change shape, update the fixture along with the script.
- In Git Bash, an argument that starts with `/` gets rewritten into a Windows path before a native program sees it, so `claude -p "/lesson"` arrives as `C:/Program Files/Git/lesson`. Prefix such commands with `MSYS_NO_PATHCONV=1`.
- To measure what a subagent costs, run it under `claude -p --output-format json` and read the Haiku entry in `modelUsage`. Pass `--no-session-persistence`, so the test sessions don't become the newest transcript.

## Conventions that differ from the defaults
- No personal paths, names or emails in the repo. Examples use placeholders like `C:\code\myapp`.
- Skills in `templates/` stay manual-only (`disable-model-invocation: true`) so they cost no context. The one exception is `auto-lesson`, which Claude has to start itself.
- Claude Code also loads the skills under `templates/project/.claude/skills/` while you edit files there, so `auto-lesson` can fire in this repo's own sessions.

# Compact instructions
When compacting, keep: modified files, failing tests and commands, decisions made, and open TODOs.
