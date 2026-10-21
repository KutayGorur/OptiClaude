#!/usr/bin/env bash
# PostToolUse hook (matcher "Edit|Write"): formats only the file Claude just edited.
# It never blocks Claude: it always exits 0 and discards formatter output.
# The bootstrap step fills in the FORMATTERS section below. Until then this script does nothing.

input=$(cat)

# Read tool_input.file_path from the hook's JSON on stdin. Use jq when it's installed, otherwise sed.
if [ "${OPTICLAUDE_JSON_TOOL:-auto}" != "none" ] && command -v jq >/dev/null 2>&1; then
  file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
  file=$(printf '%s' "$input" | tr -d '\r\n' | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  file=${file//\\\\/\\}   # turn JSON-escaped Windows backslashes (\\) back into single backslashes
fi

if [ -z "$file" ] || [ ! -f "$file" ]; then
  exit 0
fi

case "$file" in
  # FORMATTERS (filled in by the bootstrap; keep only the ones this project actually uses)
  # *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.md|*.html) npx --no-install prettier --write "$file" ;;
  # *.py) ruff format "$file" ;;
  # *.go) gofmt -w "$file" ;;
  # *.rs) rustfmt "$file" ;;
  # *.cs) dotnet format --include "$file" ;;
  *) ;;
esac >/dev/null 2>&1

exit 0
