#!/usr/bin/env bash
# Prints a short digest of the recent mistakes in a Claude Code session transcript, for /lesson:
# the last failed tool calls (each with the call that failed and the next calls after it) and the
# last messages the user typed. One run replaces many grep calls, which keeps lesson-finder cheap.
# Usage: bash find-mistakes.sh [session-id | path/to/transcript.jsonl]
# Without a usable session ID it reads the newest transcript. Needs only grep, sed, awk and cut.
# The transcript format is internal to Claude Code and can change; the patterns below match it as of v2.1.
set -u
export LC_ALL=C
MAX_ERRORS=6
MAX_USER=10

src="${1:-}"
root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
f=""
if [ -n "$src" ] && [ -f "$src" ]; then
  f="$src"
else
  case "$src" in
    "" | *[!0-9A-Za-z-]*) ;;  # not an ID (empty, or a placeholder that wasn't expanded)
    *) f="$(ls "$root"/*/"$src".jsonl 2>/dev/null | head -n 1)" ;;
  esac
  if [ -z "$f" ]; then
    [ -n "$src" ] && echo "note: no transcript found for '$src', so this is the newest transcript instead"
    f="$(ls -t "$root"/*/*.jsonl 2>/dev/null | head -n 1)"
  fi
fi
if [ -z "$f" ] || [ ! -f "$f" ]; then
  echo "No transcript found under $root"
  exit 1
fi

# Keep only the main conversation's records: skip request copies and subagent (sidechain) lines.
main_only() { grep -v -e '^[0-9]*:{"type":"api-' -e '"isSidechain":true'; }
# Keep only what a person typed: skip injected text (skill bodies, image notes) and messages from agents or tasks.
typed_only() { grep -v -e '"isMeta":true' | grep -v -E '"origin":\{"kind":"([^h]|h[^u])'; }
# Turn JSON string escapes into readable text on one line. Escaped backslashes go first, so C:\\repo stays C:\repo.
clean() { sed -e 's/\\\\/@BS@/g' -e 's/\\r//g' -e 's/\\n/ | /g' -e 's/\\t/ /g' -e 's/\\"/"/g' -e 's/@BS@/\\/g'; }
# "name":"Bash","input":{...}  ->  Bash: {...}, without the JSON that follows the input
call_text() {
  grep -o '"name":"[^"]*","input":.*' | head -n 1 | cut -c1-"$1" \
    | sed -e 's/^"name":"\([^"]*\)","input":/\1: /' -e 's/},"caller":.*$/}/' -e 's/}],"[a-z_]*":.*$/}/' | clean
}
# Tool calls that only track progress; they are never the fix.
BOOKKEEPING='"name":"(TodoWrite|TaskCreate|TaskUpdate|TaskList|TaskGet|mcp__ccd_[a-z_]*)"'

echo "Transcript: $f ($(wc -l < "$f" | tr -d ' ') lines)"
echo

errors="$(grep -n '"is_error":true' "$f" | main_only)"
total=0; [ -n "$errors" ] && total="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
shown=$total; [ "$shown" -gt "$MAX_ERRORS" ] && shown=$MAX_ERRORS
echo "## Failed tool calls: $total in the session, the last $shown below, oldest first"
[ "$total" -eq 0 ] && echo "(none)"
printf '%s\n' "$errors" | tail -n "$MAX_ERRORS" | while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  n="${hit%%:*}"
  id="$(printf '%s\n' "$hit" | grep -o '"is_error":true,"tool_use_id":"[^"]*"' | head -n 1 | sed 's/.*"tool_use_id":"//; s/"$//')"
  [ -n "$id" ] || id="$(printf '%s\n' "$hit" | grep -o '"tool_use_id":"[^"]*"' | head -n 1 | sed 's/.*:"//; s/"$//')"
  call=""
  [ -n "$id" ] && call="$(grep -m 1 -F "\"id\":\"$id\"" "$f" | call_text 230)"
  err="$(printf '%s\n' "$hit" | grep -o '"type":"tool_result","content":.*' | head -n 1 | cut -c1-350 \
    | sed -e 's/^"type":"tool_result","content":"//' -e 's/^"type":"tool_result","content":\[{"type":"text","text":"//' \
          -e 's/","is_error":.*$//' -e 's/"}],"is_error":.*$//' | clean)"
  echo "[line $n] ${call:-(call not found)}"
  echo "  error: $err"
  awk -v n="$n" -v skip="$BOOKKEEPING" 'NR > n && index($0, "\"type\":\"tool_use\"") && index($0, "{\"type\":\"api-") != 1 && !index($0, "\"isSidechain\":true") && $0 !~ skip { print; if (++c == 2) exit }' "$f" \
    | while IFS= read -r next; do echo "  then: $(printf '%s\n' "$next" | call_text 170)"; done
done
echo

echo "## What the user typed: the last $MAX_USER messages, oldest first"
{
  # Plain-text messages
  grep -n '"type":"user","message":{"role":"user","content":"' "$f" | main_only | typed_only \
    | sed 's/^\([0-9]*\):.*"type":"user","message":{"role":"user","content":"/\1 /'
  # Messages stored as blocks (for example text with an image), but not tool results
  grep -n '"type":"user","message":{"role":"user","content":\[' "$f" | main_only | typed_only | grep -v '"type":"tool_result"' \
    | while IFS= read -r line; do
        t="$(printf '%s\n' "$line" | grep -o '"type":"text","text":".*' | head -n 1 | cut -c1-320 | sed 's/^"type":"text","text":"//')"
        [ -n "$t" ] && echo "${line%%:*} $t"
      done
} | sed -e 's/^\([0-9]*\) \(\\n\)*/\1 /' | grep -v -E '^[0-9]+ <([^p]|p[^a])' | sort -n | tail -n "$MAX_USER" \
  | cut -c1-320 | sed 's/\([^\\]\)"}.*$/\1/' | clean | sed 's/^\([0-9]*\) /[line \1] /'
