# Tutorial

## 1. Install once

From the folder where you cloned this repo:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Global     # Windows
```
```bash
bash setup.sh --global                                                         # macOS / Linux
```
Restart Claude Code. You now have the `/opticlaude-setup` command, and a status line in the terminal version of Claude Code (see [The status line](#the-status-line)).

If you move the repo later, run the command again. It rewrites the path inside `/opticlaude-setup`.

## 2. Set up a project

1. Open a **new** Claude Code session in the project folder. If Claude Code asks whether to trust the folder, say yes. Allowlisted commands only take effect in trusted folders.
2. Type `/opticlaude-setup`.
3. Claude installs the templates, reads the manifests, CI config and README, and fills in CLAUDE.md. It **runs each command** to confirm it works and marks any it couldn't run as `(unverified)`. Then it updates the allowlist, adds the format hook if the project has a formatter, and prints a short report.
4. Run `/clear` so the new CLAUDE.md loads. Run `/context` to check the startup cost and `/doctor` for an audit. Then review the diff and commit `CLAUDE.md` and `.claude/`.

If the project already has a CLAUDE.md, Claude first backs it up to `.claude/backup/CLAUDE.md.orig`, then reorganizes it into the template's sections. It moves long workflow sections into skills and lists anything it dropped.

## 3. Day to day

### Starting a task
- Pick the model and effort before you start (`/model`, `/effort`). Switching mid-task rebuilds the prompt cache at full price.
- Put the goal, constraints, relevant files (`@path`) and the definition of done in your **first** message.

### The status line
It appears at the bottom of the **terminal** version of Claude Code: run `claude` in a terminal such as PowerShell or Windows Terminal. The Claude desktop app doesn't show it.
```text
myapp | Opus (high) | ctx 23% 234k | $0.41 | cache 91% | 5h 24%
```
| Part | What to do |
|---|---|
| `ctx … 234k`: green below 200k tokens, yellow below 350k, red above that | Yellow: `/compact` at the next natural break. Red: `/handoff`, then `/clear` |
| `$0.41`: estimated session cost at list price | Gives a sense of scale |
| `cache 91%`: prompt-cache hit rate | If it drops, you probably switched model or effort, or toggled MCP servers |
| `5h 24%`: your 5-hour usage window (subscriptions) | Pace parallel sessions accordingly |

**In the desktop app**, use its built-in displays instead ([Desktop docs](https://code.claude.com/docs/en/desktop)):

| What | Where |
|---|---|
| Context used | The **Context** card in the session details panel (percentage in its header; open it for a breakdown). In the earlier layout, click the usage ring next to the model picker |
| Plan usage (your limits) | Click the usage ring next to the model picker |
| What fills the context | Type `/context` in the prompt box |

The desktop docs don't describe a per-session dollar readout. On a subscription, plan usage is what counts against your limits.

### When things go wrong
- Press **Esc Esc** to rewind, then re-prompt. Rewinding beats piling corrections on top.
- After two failed corrections, run `/handoff`, then `/clear`, then `@.claude/handoff.md continue from this handoff`.
- For large logs or test output, ask Claude to *"use log-digger on …"*.
- When Claude fixes a mistake worth remembering, it saves a one-line lesson by itself (the `auto-lesson` skill) and tells you where. Check it with `git diff`, and undo it if you disagree.

### Finishing
```text
/go             verify end to end, run /simplify, report evidence
/go pr          the same, then commit and open a pull request
/lesson <what went wrong>   record a mistake so it doesn't happen again (applies after /clear)
/lesson         no argument: a Haiku subagent finds the recent mistakes and their fixes in the transcript
```

### Weekly
- Run `/usage` to see what your tokens went to and your cache hit rate.
- Run `/insights` and `/doctor`.
- After a few sessions in a project, run `/fewer-permission-prompts`.

## 4. Troubleshooting

| Problem | Fix |
|---|---|
| No status line | In the desktop app this is expected; run `claude` in a terminal to see it. In the terminal: restart Claude Code and check that `~/.claude/settings.json` has `statusLine`. To test the script, pipe sample JSON into it: `'{"model":{"display_name":"Opus"}}' \| powershell -NoProfile -ExecutionPolicy Bypass -File $HOME\.claude\statusline.ps1` |
| `/opticlaude-setup` not listed | Restart Claude Code or run `/reload-skills` |
| Still prompted for allowed commands | Accept the folder's trust dialog |
| Format hook does nothing | Check that `/hooks` lists it, that the formatter is installed locally, and that the file's extension is in the hook's `case` list |
| `$'\r': command not found` from a hook or `/lesson` | The `.sh` file has CRLF line endings. Convert it to LF; the kit's `.gitattributes` line prevents this on new clones |
