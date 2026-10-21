#!/usr/bin/env bash
# Claude Code status line for macOS and Linux (bash). Claude Code pipes session JSON to stdin.
# Prints: folder | model (effort) | ctx % and tokens | session cost | cache hit % | 5-hour limit %
# The context figure is green below 200k tokens, yellow below 350k, and red above that.
# Uses jq if installed, then python3. If neither is available, it falls back to a minimal grep parser.
# OPTICLAUDE_JSON_TOOL=jq|python3|none forces the parser (used by the tests).
input=$(cat)

tool="${OPTICLAUDE_JSON_TOOL:-auto}"
if [ "$tool" = "auto" ]; then
  if command -v jq >/dev/null 2>&1; then tool="jq"
  elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then tool="python3"
  else tool="none"; fi
fi

fields=""
if [ "$tool" = "jq" ]; then
  fields=$(printf '%s' "$input" | jq -r '[
      (.workspace.current_dir // .cwd // ""),
      (.model.display_name // ""),
      (.effort.level // ""),
      (.context_window.used_percentage // ""),
      (.context_window.context_window_size // ""),
      (.cost.total_cost_usd // ""),
      (if .prompt_cache.caching_observed == false then "" else (.prompt_cache.hit_ratio // "") end),
      (.rate_limits.five_hour.used_percentage // "")
    ] | map(tostring) | join("\u001f")' 2>/dev/null)
elif [ "$tool" = "python3" ]; then
  fields=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def g(*keys):
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or cur.get(k) is None:
            return ""
        cur = cur[k]
    return str(cur)
pc = d.get("prompt_cache") or {}
hit = "" if pc.get("caching_observed") is False else g("prompt_cache", "hit_ratio")
print("\x1f".join([
    g("workspace", "current_dir") or g("cwd"), g("model", "display_name"), g("effort", "level"),
    g("context_window", "used_percentage"), g("context_window", "context_window_size"),
    g("cost", "total_cost_usd"), hit, g("rate_limits", "five_hour", "used_percentage"),
]))
' 2>/dev/null)
fi

if [ -z "$fields" ]; then
  # Minimal fallback: model name and context % only.
  flat=$(printf '%s' "$input" | tr -d '\r\n')
  model=$(printf '%s' "$flat" | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  pct=$(printf '%s' "$flat" | sed -n 's/.*"context_window"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p')
  fields=$(printf '%s\037%s\037\037%s\037\037\037\037' "" "$model" "$pct")
fi

printf '%s' "$fields" | awk '
function paint(code, text) { return sprintf("\033[%sm%s\033[0m", code, text) }
BEGIN { FS = sprintf("%c", 31) }
{
  out = ""
  dir = $1; sub(/.*[\/\\]/, "", dir)
  if (dir != "") out = dir
  model = $2; if ($3 != "") model = model " (" $3 ")"
  if (model != "") out = out (out == "" ? "" : " | ") model
  if ($4 != "") {
    label = sprintf("ctx %d%%", $4 + 0.5); color = "32"
    if ($5 != "") {
      used = $4 * $5 / 100
      label = sprintf("%s %dk", label, used / 1000 + 0.5)
      if (used >= 350000) color = "31"; else if (used >= 200000) color = "33"
    } else if ($4 >= 80) color = "31"; else if ($4 >= 50) color = "33"
    out = out " | " paint(color, label)
  }
  if ($6 != "") out = out sprintf(" | $%.2f", $6)
  if ($7 != "") out = out sprintf(" | cache %d%%", $7 * 100 + 0.5)
  if ($8 != "") out = out sprintf(" | 5h %d%%", $8 + 0.5)
  print out
}'
