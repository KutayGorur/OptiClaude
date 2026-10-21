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

PROJECT_FILES=(CLAUDE.md .claude/settings.json .claude/agents/log-digger.md .claude/hooks/format-edited.sh
  .claude/skills/go/SKILL.md .claude/skills/handoff/SKILL.md .claude/skills/lesson/SKILL.md)

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
  check "fresh project gets all 7 files" test "$missing" -eq 0
  check "CLAUDE.md comes from the template" cmp -s "$W/fresh/CLAUDE.md" "$ROOT/templates/project/CLAUDE.template.md"
  check "hook script is LF-only" bash -c "! grep -q \$'\\r' '$W/fresh/.claude/hooks/format-edited.sh'"

  # Re-run is idempotent
  before="$(snapshot "$W/fresh")"; out="$(setup --target "$W/fresh")"
  check "re-run changes nothing" test "$before" = "$(snapshot "$W/fresh")"
  check "re-run reports nothing created" bash -c "! printf '%s' \"\$1\" | grep -q 'created'" _ "$out"

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
  check ".gitattributes forces LF for hooks" grep -qx '.claude/hooks/\*.sh text eol=lf' "$P/.gitattributes"

  # Global install into a fake user folder
  U="$W/home"; setup --global --user-dir "$U" >/dev/null
  check "global: status line script installed" test -f "$U/$SL"
  check "global: skill installed" test -f "$U/skills/opticlaude-setup/SKILL.md"
  check "global: skill has this kit's path" grep -qxF "Kit folder: $KIT_PATH" "$U/skills/opticlaude-setup/SKILL.md"
  check "global: skill has no placeholder path" bash -c "! grep -qx 'Kit folder: <path to this repo>' '$U/skills/opticlaude-setup/SKILL.md'"
  check "global: skill is manual-only" grep -qx 'disable-model-invocation: true' "$U/skills/opticlaude-setup/SKILL.md"
  if [ -n "$PY" ]; then
    check "global: settings.json has statusLine" json_eval "$U/settings.json" '"statusline" in d["statusLine"]["command"]'
  fi
  before="$(snapshot "$U")"; setup --global --user-dir "$U" >/dev/null
  check "global: re-run changes nothing" test "$before" = "$(snapshot "$U")"

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

echo "== syntax"
for f in "$ROOT/setup.sh" "$SLS" "$HOOK" "$ROOT/tests/test.sh"; do check "bash -n $(basename "$f")" bash -n "$f"; done

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
