#!/usr/bin/env bash
# Tests for setup.sh, the bash status line and the format hook.
# Usage: bash tests/test.sh   (exit status is non-zero if any check fails)
# Runs every JSON-tool mode available on this machine: jq, python3/python, and none.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok    $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $1"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }
strip_ansi() { sed "s/$(printf '\033')\[[0-9;]*m//g" | tr -d '\r'; }
snapshot() { (cd "$1" && find . -type f ! -path './.git/*' -print | LC_ALL=C sort | while read -r f; do cksum "$f"; done); }
# Byte-exact helpers: grep and awk on Git Bash for Windows silently drop CR characters, so use tr and printf.
count_cr() { tr -cd '\r' < "$1" | wc -c | tr -d ' '; }
# Write $1's content to $2 with the opposite line endings (CRLF <-> LF), so the bytes differ but the text doesn't.
flip_eol() {
  if [ "$(count_cr "$1")" -gt 0 ]; then tr -d '\r' < "$1" > "$2"
  else
    local line out=""
    while IFS= read -r line || [ -n "$line" ]; do out="$out$line"$'\r\n'; done < "$1"
    printf '%s' "$out" > "$2"
  fi
}
has_line() { printf '%s' "$1" | grep -q -E "$2"; }
# Skill text must contain no "$": Claude Code expands $ARGUMENTS, $1 and ${VARS} in it when the skill runs.
no_dollar() { ! grep -q '[$]' "$1"; }

PY=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1 && python -c 'import json' >/dev/null 2>&1; then PY=python; fi
# json_eval FILE EXPR: evaluates a Python expression against the parsed JSON file `d`; succeeds if truthy.
json_eval() { "$PY" -c 'import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if eval(sys.argv[2]) else 1)' "$1" "$2"; }

case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) SL=statusline.ps1 ;; *) SL=statusline.sh ;; esac
KIT_PATH="$(cygpath -m "$ROOT" 2>/dev/null || echo "$ROOT")"

MODES=()
command -v jq >/dev/null 2>&1 && MODES+=(jq)
[ -n "$PY" ] && MODES+=("$PY")
MODES+=(none)
[ -n "$PY" ] || echo "note: python not found, JSON content checks are skipped"

PROJECT_FILES=(CLAUDE.md .claude/settings.json .claude/agents/log-digger.md .claude/agents/lesson-finder.md
  .claude/hooks/format-edited.sh .claude/skills/go/SKILL.md .claude/skills/handoff/SKILL.md
  .claude/skills/lesson/SKILL.md .claude/skills/lesson/find-mistakes.sh .claude/skills/auto-lesson/SKILL.md)

for MODE in "${MODES[@]}"; do
  echo "== setup.sh (JSON tool: $MODE)"
  W="$TMP/$MODE"; mkdir -p "$W"
  setup() { OPTICLAUDE_JSON_TOOL="$MODE" bash "$ROOT/setup.sh" "$@"; }

  # Dry run writes nothing
  mkdir -p "$W/dry"; setup --target "$W/dry" --dry-run >/dev/null
  check "dry run writes nothing" test -z "$(ls -A "$W/dry")"

  # Fresh project
  mkdir -p "$W/fresh"; setup --target "$W/fresh" >/dev/null
  missing=0; for f in "${PROJECT_FILES[@]}"; do [ -f "$W/fresh/$f" ] || missing=1; done
  check "fresh project gets all ${#PROJECT_FILES[@]} files" test "$missing" -eq 0
  check "CLAUDE.md comes from the template" cmp -s "$W/fresh/CLAUDE.md" "$ROOT/templates/project/CLAUDE.template.md"
  check "hook script is LF-only" test "$(count_cr "$W/fresh/.claude/hooks/format-edited.sh")" -eq 0

  # Re-run is idempotent
  before="$(snapshot "$W/fresh")"; out="$(setup --target "$W/fresh")"
  check "re-run changes nothing" test "$before" = "$(snapshot "$W/fresh")"
  check "re-run reports nothing created" bash -c "! printf '%s' \"\$1\" | grep -q 'created'" _ "$out"

  # Line endings: a kit file differing only in CRLF/LF is unchanged; a real edit is skipped, or replaced with --force
  E="$W/eol"; mkdir -p "$E"; setup --target "$E" >/dev/null
  TPL_GO="$ROOT/templates/project/.claude/skills/go/SKILL.md"; GO="$E/.claude/skills/go/SKILL.md"
  flip_eol "$TPL_GO" "$GO"
  check "eol: precondition, file differs byte-wise" bash -c "! cmp -s '$TPL_GO' '$GO'"
  out="$(setup --target "$E" --force)"
  check "eol: line-ending-only difference is unchanged" has_line "$out" 'unchanged +\.claude/skills/go/SKILL\.md'
  check "eol: line-ending-only file is not rewritten" bash -c "! cmp -s '$TPL_GO' '$GO'"
  printf '\nlocal edit\n' >> "$GO"
  out="$(setup --target "$E")"
  check "eol: real edit is skipped without --force" has_line "$out" 'skipped +\.claude/skills/go/SKILL\.md'
  out="$(setup --target "$E" --force)"
  check "eol: real edit is replaced with --force" has_line "$out" 'replaced +\.claude/skills/go/SKILL\.md'
  check "eol: --force restored the template" cmp -s "$TPL_GO" "$GO"
  check "eol: --force kept a backup of the edit" test -n "$(grep -rl 'local edit' "$E/.claude/backup" 2>/dev/null)"

  # Existing git project: CLAUDE.md kept, settings merged, git files appended once
  P="$W/existing"; mkdir -p "$P/.claude"
  (cd "$P" && git init -q)
  printf '# My notes\nKeep me.\n' > "$P/CLAUDE.md"
  printf '{"permissions":{"allow":["Bash(make test *)"],"deny":["Read(.env)"]},"model":"opus"}\n' > "$P/.claude/settings.json"
  printf 'node_modules/' > "$P/.gitignore"
  cp "$P/.claude/settings.json" "$TMP/orig-settings.json"
  out="$(setup --target "$P")"; setup --target "$P" >/dev/null
  check "existing CLAUDE.md untouched" test "$(cat "$P/CLAUDE.md")" = "$(printf '# My notes\nKeep me.')"
  if [ "$MODE" = "none" ]; then
    check "no JSON tool: settings left as is" cmp -s "$P/.claude/settings.json" "$TMP/orig-settings.json"
    check "no JSON tool: says why it skipped" bash -c "printf '%s' \"\$1\" | grep -q 'install jq or python3'" _ "$out"
  elif [ -n "$PY" ]; then
    S="$P/.claude/settings.json"
    check "merge keeps existing allow rule" json_eval "$S" '"Bash(make test *)" in d["permissions"]["allow"]'
    check "merge adds all template deny rules" json_eval "$S" 'len(d["permissions"]["deny"]) == 6 and "Read(secrets/**)" in d["permissions"]["deny"]'
    check "merge keeps other keys" json_eval "$S" 'd.get("model") == "opus"'
    check "merge wrote a backup" test -n "$(find "$P/.claude/backup" -name settings.json 2>/dev/null)"
  fi
  check ".gitignore keeps old lines" grep -qx 'node_modules/' "$P/.gitignore"
  check ".gitignore gets kit lines once" test "$(grep -cx '.claude/handoff.md' "$P/.gitignore")" -eq 1
  check ".gitattributes forces LF for .claude scripts" grep -qxF '.claude/**/*.sh text eol=lf' "$P/.gitattributes"

  # Global install into a fake user folder
  U="$W/home"; setup --global --user-dir "$U" >/dev/null
  check "global: status line script installed" test -f "$U/$SL"
  check "global: skill installed" test -f "$U/skills/opticlaude-setup/SKILL.md"
  check "global: skill has this kit's path" grep -qxF "Kit folder: $KIT_PATH" "$U/skills/opticlaude-setup/SKILL.md"
  check "global: skill has no placeholder path" bash -c "! grep -qx 'Kit folder: <path to this repo>' '$U/skills/opticlaude-setup/SKILL.md'"
  check "global: skill is manual-only" grep -qx 'disable-model-invocation: true' "$U/skills/opticlaude-setup/SKILL.md"
  check "global: skill has no \$ tokens to expand" no_dollar "$U/skills/opticlaude-setup/SKILL.md"
  if [ -n "$PY" ]; then
    check "global: settings.json has statusLine" json_eval "$U/settings.json" '"statusline" in d["statusLine"]["command"]'
  fi
  before="$(snapshot "$U")"; setup --global --user-dir "$U" >/dev/null
  check "global: re-run changes nothing" test "$before" = "$(snapshot "$U")"

  # Global files that differ only in line endings count as unchanged (no backup, no rewrite)
  U3="$W/home-eol"; setup --global --user-dir "$U3" >/dev/null
  flip_eol "$ROOT/templates/user/$SL" "$U3/$SL"
  SK="$U3/skills/opticlaude-setup/SKILL.md"; flip_eol "$SK" "$TMP/skill.flipped"; mv -f "$TMP/skill.flipped" "$SK"
  out="$(setup --global --user-dir "$U3" --force)"
  check "global eol: status line is unchanged" has_line "$out" "unchanged +$SL"
  check "global eol: skill is unchanged" has_line "$out" 'unchanged +skills/opticlaude-setup/SKILL\.md'
  check "global eol: no backup made" test ! -d "$U3/backup"

  # Existing status line is kept unless --force
  U2="$W/home2"; mkdir -p "$U2"
  printf '{"statusLine":{"type":"command","command":"echo mine"},"theme":"dark"}\n' > "$U2/settings.json"
  setup --global --user-dir "$U2" >/dev/null
  check "global: existing statusLine kept" grep -q 'echo mine' "$U2/settings.json"
  if [ "$MODE" != "none" ] && [ -n "$PY" ]; then
    setup --global --user-dir "$U2" --force >/dev/null
    check "global --force: statusLine replaced" json_eval "$U2/settings.json" '"statusline" in d["statusLine"]["command"]'
    check "global --force: other keys kept" json_eval "$U2/settings.json" 'd.get("theme") == "dark"'
  fi
done

echo "== statusline.sh"
SLS="$ROOT/templates/user/statusline.sh"
SL_MODES=(); command -v jq >/dev/null 2>&1 && SL_MODES+=(jq)
command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1 && SL_MODES+=(python3)
for M in ${SL_MODES[@]+"${SL_MODES[@]}"}; do   # (empty-array safe on bash 3.2)
  full="$(OPTICLAUDE_JSON_TOOL=$M bash "$SLS" < "$FIX/session-full.json")"
  check "$M: full session line" test "$(printf '%s' "$full" | strip_ansi)" = 'myapp | Opus (high) | ctx 23% 234k | $0.41 | cache 91% | 5h 24%'
  check "$M: 234k is yellow" bash -c "printf '%s' \"\$1\" | grep -q '\[33m'" _ "$full"
  check "$M: minimal session line" test "$(OPTICLAUDE_JSON_TOOL=$M bash "$SLS" < "$FIX/session-min.json" | strip_ansi)" = 'proj | Sonnet'
  red="$(OPTICLAUDE_JSON_TOOL=$M bash "$SLS" < "$FIX/session-red.json")"
  check "$M: 410k is red, no cache part" test "$(printf '%s' "$red" | strip_ansi)" = 'big | Opus | ctx 41% 410k'
  check "$M: red color code" bash -c "printf '%s' \"\$1\" | grep -q '\[31m'" _ "$red"
done
check "fallback parser: model and context" test "$(OPTICLAUDE_JSON_TOOL=none bash "$SLS" < "$FIX/session-full.json" | strip_ansi)" = 'Opus | ctx 23%'
check "empty input exits 0" bash -c "printf '' | bash '$SLS'"

echo "== format-edited.sh"
HOOK="$ROOT/templates/project/.claude/hooks/format-edited.sh"
H="$TMP/hook"; mkdir -p "$H/src"; echo "x" > "$H/src/a.ts"
# A copy of the hook with one formatter line that records the file it was given.
awk -v m="$H/marker" '/^  \*\) ;;/ { print "  *.ts) printf \"%s\" \"$file\" > \"" m "\" ;;" } { print }' "$HOOK" > "$H/hook.sh"
# On Windows, Claude Code sends native paths, so test both C:/ and C:\ forms (Git Bash would rewrite /tmp/... anyway).
if command -v cygpath >/dev/null 2>&1; then paths=("$(cygpath -m "$H/src/a.ts")" "$(cygpath -w "$H/src/a.ts")")
else paths=("$H/src/a.ts"); fi
for HM in auto none; do
  for p in "${paths[@]}"; do
    rm -f "$H/marker"
    if [ -n "$PY" ]; then
      "$PY" -c 'import json, sys; print(json.dumps({"tool_name": "Write", "tool_input": {"file_path": sys.argv[1]}}))' "$p" > "$H/in.json"
    else
      printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$p" > "$H/in.json"
    fi
    OPTICLAUDE_JSON_TOOL=$HM bash "$H/hook.sh" < "$H/in.json"; rc=$?
    check "hook ($HM) exits 0 for $p" test "$rc" -eq 0
    check "hook ($HM) formats exactly that file" test "$(cat "$H/marker" 2>/dev/null)" = "$p"
  done
done
rm -f "$H/marker"
check "unconfigured hook does nothing and exits 0" bash -c "bash '$HOOK' < '$H/in.json' && test ! -e '$H/marker'"
check "hook ignores bad input" bash -c "echo 'not json' | bash '$H/hook.sh'"
check "hook ignores missing files" bash -c "printf '{\"tool_input\":{\"file_path\":\"/nope/x.ts\"}}' | bash '$H/hook.sh' && test ! -e '$H/marker'"

echo "== bootstrap prompt and hook snippet"
BODY="$TMP/prompt-body.txt"
awk '/<!-- PROMPT END -->/{on=0} on{print} /<!-- PROMPT START -->/{on=1}' "$ROOT/BOOTSTRAP-PROMPT.md" > "$BODY"
check "prompt body was extracted" test -s "$BODY"
check "prompt body has no \$ tokens to expand" no_dollar "$BODY"
SNIP="$ROOT/templates/snippets/format-hook.json"
check "prompt points to the hook snippet" grep -q 'templates/snippets/format-hook.json' "$BODY"
check "hook snippet exists" test -f "$SNIP"
check "hook template the snippet runs exists" test -f "$ROOT/templates/project/.claude/hooks/format-edited.sh"
if [ -n "$PY" ]; then
  check "hook snippet is valid JSON" json_eval "$SNIP" 'isinstance(d, dict)'
  check "hook snippet matches Edit|Write" json_eval "$SNIP" 'd["hooks"]["PostToolUse"][0]["matcher"] == "Edit|Write"'
  check "hook snippet keeps the project-dir variable" json_eval "$SNIP" '"${CLAUDE_PROJECT_DIR}/.claude/hooks/format-edited.sh" in d["hooks"]["PostToolUse"][0]["hooks"][0]["command"]'
fi

echo "== skills and agents"
SK="$ROOT/templates/project/.claude/skills"; AG="$ROOT/templates/project/.claude/agents"
for f in "$SK"/*/SKILL.md; do
  n="$(basename "$(dirname "$f")")"
  [ "$n" = auto-lesson ] && continue
  check "skill $n is manual-only" grep -qx 'disable-model-invocation: true' "$f"
done
AUTO="$SK/auto-lesson/SKILL.md"; LESSON="$SK/lesson/SKILL.md"; FINDER="$AG/lesson-finder.md"
check "auto-lesson exists" test -f "$AUTO"
check "auto-lesson is model-invocable" bash -c "test -f '$AUTO' && ! grep -q '^disable-model-invocation: true' '$AUTO'"
check "auto-lesson is hidden from the / menu" grep -qx 'user-invocable: false' "$AUTO"
check "auto-lesson has no \$ tokens to expand" bash -c "test -f '$AUTO' && ! grep -q '[\$]' '$AUTO'"
check "auto-lesson names a section lesson has" bash -c "grep -q '\"Saving a lesson\" section' '$AUTO' && grep -qx '## Saving a lesson' '$LESSON'"
check "lesson uses lesson-finder" grep -q '`lesson-finder` subagent' "$LESSON"
check "lesson gives lesson-finder the digest command" grep -qF 'bash "${CLAUDE_SKILL_DIR}/find-mistakes.sh" ${CLAUDE_SESSION_ID}' "$LESSON"
check "lesson-finder exists" test -f "$FINDER"
check "lesson-finder name matches its file" grep -qx 'name: lesson-finder' "$FINDER"
# Cost controls: a small model, low effort, a turn cap, and no write tools.
for a in "$FINDER" "$AG/log-digger.md"; do
  n="$(basename "$a" .md)"
  check "$n runs on haiku" grep -qx 'model: haiku' "$a"
  check "$n uses low effort" grep -qx 'effort: low' "$a"
  check "$n has a turn limit" grep -qE '^maxTurns: [1-9][0-9]*$' "$a"
  check "$n can't edit files" bash -c "grep -q '^tools: ' '$a' && ! grep -E '^tools: .*(Edit|Write)' '$a'"
done
check "lesson-finder only gets Bash" grep -qx 'tools: Bash' "$FINDER"
check "lesson-finder starts without CLAUDE.md" grep -qx 'omitClaudeMd: true' "$FINDER"
check "lesson-finder runs the digest script" grep -q 'skills/lesson/find-mistakes.sh' "$FINDER"

echo "== find-mistakes.sh"
FM="$SK/lesson/find-mistakes.sh"; TR="$FIX/transcript.jsonl"; SID=11111111-2222-3333-4444-555555555555
lacks() { ! printf '%s' "$1" | grep -q -F -e "$2"; }
# macOS grep and sed reject regex repeat counts over 255 (RE_DUP_MAX), such as .\{0,320\}.
no_big_repeat() { ! grep -E '\\\{[0-9]*,?(25[6-9]|2[6-9][0-9]|[3-9][0-9][0-9]|[0-9]{4,})\\\}' "$1"; }
check "digest: no regex repeat count over 255" no_big_repeat "$FM"
d="$(bash "$FM" "$TR" 2>&1)"; rc=$?
check "digest: reads a transcript path" test "$rc" -eq 0
check "digest: counts only main-conversation errors" has_line "$d" '^## Failed tool calls: 1 in the session'
check "digest: shows the call that failed" has_line "$d" '^\[line 4\] Bash: \{"command":"npm test"\}$'
check "digest: shows the error text" has_line "$d" "error: Exit code 1 \| Error: Cannot find module 'left-pad'"
check "digest: shows the call that came next" has_line "$d" 'then: Bash: \{"command":"npm ci && npm test"\}$'
check "digest: skips bookkeeping calls" lacks "$d" 'TodoWrite'
check "digest: skips request copies and sidechains" bash -c "! printf '%s' \"\$1\" | grep -q -e 'request copy' -e 'sidechain error'" _ "$d"
check "digest: includes typed corrections" has_line "$d" "^\[line 8\] No, don't use npm ci here"
check "digest: includes text sent with an image" has_line "$d" '^\[line 13\] Still failing, see the screenshot$'
check "digest: keeps escaped Windows paths intact" has_line "$d" '^\[line 14\] The config lives in C:\\repo\\tools\\new\.json$'
check "digest: skips injected skill text" lacks "$d" 'Base directory for this skill'
check "digest: skips task notifications" lacks "$d" 'task-notification'
check "digest: skips messages from other agents" lacks "$d" 'Another session sent'
check "digest: keeps every line short" bash -c "printf '%s\n' \"\$1\" | awk 'length > 420 { bad = 1 } END { exit bad }'" _ "$d"
CFG="$TMP/claude-config"; mkdir -p "$CFG/projects/p1"; cp "$TR" "$CFG/projects/p1/$SID.jsonl"
d="$(CLAUDE_CONFIG_DIR="$CFG" bash "$FM" "$SID" 2>&1)"
check "digest: finds a transcript by session ID" has_line "$d" "^Transcript: .*/projects/p1/$SID\.jsonl "
d="$(CLAUDE_CONFIG_DIR="$CFG" bash "$FM" '${CLAUDE_SESSION_ID}' 2>&1)"
check "digest: an unexpanded placeholder falls back to the newest transcript" \
  bash -c "printf '%s' \"\$1\" | grep -q '^note: no transcript found' && printf '%s' \"\$1\" | grep -q '/projects/p1/$SID\.jsonl'" _ "$d"
CLAUDE_CONFIG_DIR="$TMP/no-config" bash "$FM" "$SID" >/dev/null 2>&1; rc=$?
check "digest: exits 1 when there is no transcript" test "$rc" -eq 1

echo "== syntax"
for f in "$ROOT/setup.sh" "$SLS" "$HOOK" "$FM" "$ROOT/tests/test.sh"; do check "bash -n $(basename "$f")" bash -n "$f"; done

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
