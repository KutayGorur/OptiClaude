#!/usr/bin/env bash
# OptiClaude starter kit installer for macOS, Linux and Git Bash.
#
# Project mode:  bash setup.sh --target /path/to/project
#   Copies the lean Claude Code setup into the project: CLAUDE.md template, .claude/settings.json
#   (secret-file deny rules), the log-digger and lesson-finder agents, the /go, /handoff and
#   /lesson skills, the auto-lesson skill, and a format hook script. In git repos it also adds
#   local-only files to .gitignore and *.sh line endings to .gitattributes.
# Global mode:   bash setup.sh --global [--user-dir ~/.claude]
#   Installs the status line script plus its settings entry, and the /opticlaude-setup skill
#   generated from BOOTSTRAP-PROMPT.md.
#
# Safety rules (same as setup.ps1): CLAUDE.md is never overwritten; settings.json is merged
# (permission lists unioned, existing keys kept); other existing files are skipped unless --force,
# in which case they are backed up before being replaced. --dry-run writes nothing.
# Merging JSON needs jq or python3. Without either, merges are skipped with a message.
# OPTICLAUDE_JSON_TOOL=jq|python3|python|none forces the JSON tool (used by the tests).
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""; GLOBAL=0; USER_DIR="${HOME}/.claude"; FORCE=0; DRY=0
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG=()

usage() { sed -n '2,17p' "$0"; exit "${1:-0}"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --target)   TARGET="${2:?--target needs a path}"; shift 2 ;;
    --global)   GLOBAL=1; shift ;;
    --user-dir) USER_DIR="${2:?--user-dir needs a path}"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    --dry-run)  DRY=1; shift ;;
    -h|--help)  usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done
if [ -z "$TARGET" ] && [ "$GLOBAL" -eq 0 ]; then TARGET="$(pwd)"; fi

note() { local s="$1"; [ "$DRY" -eq 1 ] && s="would-$s"; LOG+=("$(printf '%-16s %s' "$s" "$2")"); }
mk_parent() { [ "$DRY" -eq 1 ] || mkdir -p "$(dirname "$1")"; }
copy_file() { [ "$DRY" -eq 1 ] && return 0; mk_parent "$2"; cp -f "$1" "$2"; }
backup_file() { [ "$DRY" -eq 1 ] && return 0; mk_parent "$2/$3"; cp -f "$1" "$2/$3"; }
# Same content, ignoring CR characters (so CRLF and LF checkouts of a file compare equal).
same_file() { cmp -s <(tr -d '\r' < "$1") <(tr -d '\r' < "$2"); }

JSON_TOOL=""
case "${OPTICLAUDE_JSON_TOOL:-auto}" in
  auto)
    if command -v jq >/dev/null 2>&1; then JSON_TOOL="jq"
    elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then JSON_TOOL="python3"
    elif command -v python >/dev/null 2>&1 && python -c 'import json, sys; sys.exit(sys.version_info[0] < 3)' >/dev/null 2>&1; then JSON_TOOL="python"
    fi ;;
  none) JSON_TOOL="" ;;
  *) JSON_TOOL="$OPTICLAUDE_JSON_TOOL" ;;
esac

# Print the merged settings JSON (existing + template permission lists) to stdout.
# Exit status 3 means nothing changed.
merge_settings() {
  local existing="$1" template="$2"
  if [ "$JSON_TOOL" = "jq" ]; then
    local out
    out=$(jq -s '
      .[0] as $e | .[1] as $t
      | reduce ("allow","deny","ask") as $k ($e;
          if ($t.permissions[$k] // []) | length > 0 then
            .permissions[$k] = (((.permissions[$k]) // []) as $cur
              | $cur + [ $t.permissions[$k][] | select(. as $x | ($cur | any(. == $x)) | not) ])
          else . end)' "$existing" "$template")
    if [ "$(jq -S . "$existing")" = "$(printf '%s' "$out" | jq -S .)" ]; then return 3; fi
    printf '%s\n' "$out"
  else
    "$JSON_TOOL" - "$existing" "$template" <<'PY'
import json, sys
existing_path, template_path = sys.argv[1], sys.argv[2]
with open(existing_path, encoding="utf-8") as f:
    raw = f.read().strip()
e = json.loads(raw) if raw else {}
with open(template_path, encoding="utf-8") as f:
    t = json.load(f)
changed = False
for k in ("allow", "deny", "ask"):
    tv = (t.get("permissions") or {}).get(k) or []
    if not tv:
        continue
    perms = e.setdefault("permissions", {})
    cur = perms.get(k) or []
    add = [x for x in tv if x not in cur]
    if add:
        perms[k] = cur + add
        changed = True
if not changed:
    sys.exit(3)
print(json.dumps(e, indent=2))
PY
  fi
}

# Set statusLine in a settings file (created if missing). Prints the new JSON.
# Exit status 3 means skipped (one already exists and --force not given); 4 means unchanged.
set_statusline() {
  local path="$1" cmd="$2" force="$3"
  if [ "$JSON_TOOL" = "jq" ]; then
    local cur='{}'
    if [ -s "$path" ]; then cur=$(cat "$path"); fi
    local existing_cmd
    existing_cmd=$(printf '%s' "$cur" | jq -r '.statusLine.command // empty')
    if [ -n "$existing_cmd" ] && [ "$existing_cmd" = "$cmd" ]; then return 4; fi
    if [ -n "$(printf '%s' "$cur" | jq -r '.statusLine // empty')" ] && [ "$force" -eq 0 ]; then return 3; fi
    printf '%s' "$cur" | jq --arg c "$cmd" '.statusLine = {type: "command", command: $c, padding: 0}'
  else
    "$JSON_TOOL" - "$path" "$cmd" "$force" <<'PY'
import json, os, sys
path, cmd, force = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
d = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        raw = f.read().strip()
    d = json.loads(raw) if raw else {}
sl = d.get("statusLine")
if sl and sl.get("command") == cmd:
    sys.exit(4)
if sl and not force:
    sys.exit(3)
d["statusLine"] = {"type": "command", "command": cmd, "padding": 0}
print(json.dumps(d, indent=2))
PY
  fi
}

add_lines() { # file label line...
  local file="$1" label="$2"; shift 2
  local missing=()
  local line
  for line in "$@"; do
    if [ ! -f "$file" ] || ! grep -qxF -- "$line" "$file"; then missing+=("$line"); fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then note unchanged "$label"; return 0; fi
  if [ "$DRY" -eq 0 ]; then
    if [ -s "$file" ] && [ -n "$(tail -c1 "$file")" ]; then printf '\n' >> "$file"; fi
    { echo "# Claude Code (OptiClaude starter kit)"; printf '%s\n' "${missing[@]}"; } >> "$file"
  fi
  note appended "$label (+${#missing[@]} lines)"
}

install_project() {
  local target="$1"
  [ -d "$target" ] || { echo "Target folder not found: $target" >&2; exit 1; }
  target="$(cd "$target" && pwd)"
  local tpl="$KIT/templates/project" backup_root="$target/.claude/backup/$STAMP"
  LOG+=("Project: $target")
  local src rel dest merged rc
  while IFS= read -r -d '' src; do
    rel="${src#"$tpl"/}"
    # Stored as CLAUDE.template.md so Claude Code doesn't load it as instructions inside this repo.
    if [ "$rel" = "CLAUDE.template.md" ]; then rel="CLAUDE.md"; fi
    dest="$target/$rel"
    if [ ! -e "$dest" ]; then
      copy_file "$src" "$dest"; note created "$rel"
    elif [ "$rel" = "CLAUDE.md" ]; then
      note kept "CLAUDE.md (exists: merge it with the bootstrap prompt)"
    elif [ "$rel" = ".claude/settings.json" ]; then
      if [ -z "$JSON_TOOL" ]; then note skipped "$rel (exists; install jq or python3 to merge)"; continue; fi
      rc=0; merged=$(merge_settings "$dest" "$src") || rc=$?
      if [ "$rc" -eq 3 ]; then note unchanged "$rel"
      elif [ "$rc" -ne 0 ]; then note error "$rel (could not parse; left as is)"
      else
        backup_file "$dest" "$backup_root" "$rel"
        [ "$DRY" -eq 1 ] || printf '%s\n' "$merged" > "$dest"
        note merged "$rel (backup in .claude/backup/$STAMP)"
      fi
    elif same_file "$src" "$dest"; then
      note unchanged "$rel"
    elif [ "$FORCE" -eq 1 ]; then
      backup_file "$dest" "$backup_root" "$rel"; copy_file "$src" "$dest"; note replaced "$rel (backup in .claude/backup/$STAMP)"
    else
      note skipped "$rel (exists; use --force to replace)"
    fi
  done < <(find "$tpl" -type f -print0 | sort -z)

  [ "$DRY" -eq 1 ] || chmod +x "$target/.claude/hooks/format-edited.sh" 2>/dev/null || true

  if [ -e "$target/.git" ]; then
    add_lines "$target/.gitignore" ".gitignore" ".claude/settings.local.json" ".claude/handoff.md" ".claude/backup/"
    add_lines "$target/.gitattributes" ".gitattributes" ".claude/hooks/*.sh text eol=lf"
  else
    LOG+=("note             not a git repo: skipped .gitignore and .gitattributes")
  fi
}

install_global() {
  local user_dir="$1"
  [ "$DRY" -eq 1 ] || mkdir -p "$user_dir"
  user_dir="$(cd "$user_dir" 2>/dev/null && pwd || echo "$user_dir")"
  local backup_root="$user_dir/backup/opticlaude-$STAMP"
  LOG+=("User folder: $user_dir")

  # 1. Status line. On Git Bash for Windows, use the PowerShell version (it parses JSON without extra tools).
  local sl_name="statusline.sh" sl_cmd
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) sl_name="statusline.ps1" ;; esac
  local sl_src="$KIT/templates/user/$sl_name" sl_dest="$user_dir/$sl_name"
  if [ ! -e "$sl_dest" ]; then copy_file "$sl_src" "$sl_dest"; note created "$sl_name"
  elif same_file "$sl_src" "$sl_dest"; then note unchanged "$sl_name"
  elif [ "$FORCE" -eq 1 ]; then backup_file "$sl_dest" "$backup_root" "$sl_name"; copy_file "$sl_src" "$sl_dest"; note replaced "$sl_name"
  else note skipped "$sl_name (exists; use --force to replace)"; fi
  if [ "$sl_name" = "statusline.ps1" ]; then
    local win_path; win_path="$(cygpath -m "$sl_dest" 2>/dev/null || echo "$sl_dest")"
    sl_cmd="powershell -NoProfile -ExecutionPolicy Bypass -File \"$win_path\""
  else
    [ "$DRY" -eq 1 ] || chmod +x "$sl_dest" 2>/dev/null || true
    sl_cmd="bash \"$sl_dest\""
  fi

  # 2. statusLine entry in settings.json
  local settings="$user_dir/settings.json" out rc
  if [ -z "$JSON_TOOL" ] && [ -e "$settings" ]; then
    note skipped "settings.json statusLine (install jq or python3 to merge, or add it by hand: $sl_cmd)"
  elif [ -z "$JSON_TOOL" ]; then
    if [ "$DRY" -eq 0 ]; then
      local esc_cmd=${sl_cmd//\\/\\\\}; esc_cmd=${esc_cmd//\"/\\\"}
      printf '{\n  "statusLine": {\n    "type": "command",\n    "command": "%s",\n    "padding": 0\n  }\n}\n' "$esc_cmd" > "$settings"
    fi
    note created "settings.json (statusLine)"
  else
    rc=0; out=$(set_statusline "$settings" "$sl_cmd" "$FORCE") || rc=$?
    if [ "$rc" -eq 4 ]; then note unchanged "settings.json (statusLine)"
    elif [ "$rc" -eq 3 ]; then note skipped "settings.json statusLine (you already have one; use --force to replace)"
    elif [ "$rc" -ne 0 ]; then note error "settings.json (could not parse; left as is)"
    elif [ -e "$settings" ]; then
      backup_file "$settings" "$backup_root" "settings.json"
      [ "$DRY" -eq 1 ] || printf '%s\n' "$out" > "$settings"
      note merged "settings.json (statusLine; backup in backup/opticlaude-$STAMP)"
    else
      [ "$DRY" -eq 1 ] || printf '%s\n' "$out" > "$settings"
      note created "settings.json (statusLine)"
    fi
  fi

  # 3. /opticlaude-setup skill, generated from BOOTSTRAP-PROMPT.md
  local kit_path="$KIT"; kit_path="$(cygpath -m "$KIT" 2>/dev/null || echo "$KIT")"
  local tmp; tmp="$(mktemp)"
  {
    printf -- '---\nname: opticlaude-setup\ndescription: Set up the current project with the OptiClaude starter kit (lean CLAUDE.md, permissions, /go /handoff /lesson skills, format hook).\ndisable-model-invocation: true\n---\n'
    awk -v kit="$kit_path" '
      /<!-- PROMPT END -->/ { on = 0 }
      on { sub(/\r$/, ""); if ($0 ~ /^Kit folder: /) $0 = "Kit folder: " kit; print }
      /<!-- PROMPT START -->/ { on = 1 }' "$KIT/BOOTSTRAP-PROMPT.md"
  } > "$tmp"
  local skill_dest="$user_dir/skills/opticlaude-setup/SKILL.md"
  if [ ! -e "$skill_dest" ]; then copy_file "$tmp" "$skill_dest"; note created "skills/opticlaude-setup/SKILL.md"
  elif same_file "$tmp" "$skill_dest"; then note unchanged "skills/opticlaude-setup/SKILL.md"
  else
    backup_file "$skill_dest" "$backup_root" "skills/opticlaude-setup/SKILL.md"
    copy_file "$tmp" "$skill_dest"; note updated "skills/opticlaude-setup/SKILL.md (regenerated from BOOTSTRAP-PROMPT.md)"
  fi
  rm -f "$tmp"
}

[ "$GLOBAL" -eq 1 ] && install_global "$USER_DIR"
[ -n "$TARGET" ] && install_project "$TARGET"

echo
if [ "$DRY" -eq 1 ]; then echo "OptiClaude starter kit (dry run: nothing was written)"; else echo "OptiClaude starter kit"; fi
for l in "${LOG[@]}"; do echo "  $l"; done
echo
[ -n "$TARGET" ] && echo "Next: in a Claude Code session in that project, run /opticlaude-setup (or paste BOOTSTRAP-PROMPT.md) to fill in CLAUDE.md, permissions and the format hook."
[ "$GLOBAL" -eq 1 ] && echo "Restart Claude Code (or start a new session) to see the status line and the /opticlaude-setup skill."
exit 0
