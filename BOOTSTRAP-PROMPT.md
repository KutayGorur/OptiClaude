# Bootstrap prompt

This is the source of the `/opticlaude-setup` command. `setup.ps1 -Global` (or `setup.sh --global`) turns it into a skill and fills in the `Kit folder:` line.

To use it without installing anything:
1. Replace `<path to this repo>` below with the folder you cloned this repo to.
2. Paste everything between the two marker lines into a new Claude Code session opened in your project.

<!-- PROMPT START -->
Set up this project for efficient Claude Code work using the OptiClaude starter kit.

Kit folder: <path to this repo>
Target project: the current working directory.
If the Kit folder line above still says `<path to this repo>`, ask the user where they cloned OptiClaude before you do anything else.

## Ground rules (follow every one)
- **Keep the setup itself cheap.** Read manifests, configs and docs, not the source tree. About 15 file reads should be enough. Use a subagent only if the repo has several independent packages.
- **Install nothing.** No dependencies, plugins, MCP servers or third-party frameworks. Put recommendations in the final report instead.
- **Never lose existing content.** Merge into files that already exist, and back up any existing file before you change it (copy it into `.claude/backup/`).
- **Only write facts you checked in this repo.** If you can't determine something, write `TODO(verify): ...` instead of guessing.
- **Don't commit, push, or change git config.** The user reviews the result and commits it.
- **Keep CLAUDE.md short:** aim for under 80 lines, with a hard limit of 200. Each line must pass the test "would Claude make a mistake without this?" Leave out anything Claude can learn by reading the code, and generic advice like "write clean code."
- **Don't run anything risky.** No commands that deploy, publish, migrate or seed databases, call paid or external services, or write outside the repo. Don't run tests that need services which aren't running. Mark those commands as unverified instead.

## Steps
1. **Install the templates.** Run the kit's setup script against this project:
   - Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File "<Kit folder>/setup.ps1" -Target "<project path>"`
   - macOS or Linux: `bash "<Kit folder>/setup.sh" --target "<project path>"`

   Read the summary it prints. It lists what it created, what it skipped because the file already existed, and what it merged. It never overwrites CLAUDE.md.
2. **Look around, cheaply.** Read only these:
   - The top-level file listing.
   - Manifests: package.json, pyproject.toml, requirements*.txt, Cargo.toml, go.mod, pom.xml or build.gradle, *.csproj or *.sln, Makefile, justfile, Taskfile, docker-compose*.
   - README and CONTRIBUTING (the first ~150 lines).
   - CI config: .github/workflows/*, .gitlab-ci.yml.
   - Lint and format configs.
   - Existing agent instructions: CLAUDE.md, AGENTS.md, .cursorrules, .github/copilot-instructions.md.
3. **Fill in CLAUDE.md** using the template at `<Kit folder>/templates/project/CLAUDE.template.md`.
   - **If the script created CLAUDE.md:** replace every `{{...}}` placeholder, and delete lines and sections that don't apply. No `{{` may remain.
   - **If CLAUDE.md already existed:**
     - First copy it to `.claude/backup/CLAUDE.md.orig`.
     - Reorganize its project-specific content into the template's sections.
     - Move long workflow instructions (releases, migrations, PR review) into a skill at `.claude/skills/<name>/SKILL.md`, and leave a one-line pointer in CLAUDE.md.
     - Drop only generic advice, and list everything you dropped in your report.
   - **If AGENTS.md exists:** add the line `@AGENTS.md` to import it rather than copying its content.
   - **Commands:** take them exactly from the manifests and CI, and prefer the narrowest form (one test file, one package).
   - **Gotchas:** include only real traps you saw evidence of, such as generated files, unusual layouts, required env vars or ports, or the order commands must run in. If you found none, delete the line; the user will add them over time with `/lesson`.
4. **Verify every command you wrote.** Run each one in the cheapest form that proves it works, such as the single-test command on one small test or the linter on one file. Give each a timeout of about 2 minutes. If a command needs dependencies that aren't installed, don't install them; append `(unverified: deps not installed)`. Fix or mark any command that fails.
5. **Set permissions.** In `.claude/settings.json`, add the verified, non-destructive project commands to `permissions.allow` in the form `Bash(<command> *)`, for example `Bash(npm run test *)`, `Bash(pytest *)` or `Bash(ruff check *)`.
   - Never allow deploy, publish or release commands, `git push`, `rm`, package installs, or anything that touches production.
   - Keep the existing `deny` rules. If you saw other places that hold secrets, add deny rules for them, for example `Read(config/credentials/**)`.
6. **Add a format hook, but only if the project has a formatter configured.**
   - In `.claude/hooks/format-edited.sh`, uncomment and adapt only the `case` lines for formatters this project actually uses. Call the project's own binaries, for example `npx --no-install prettier`, or `uv run ruff format` / `poetry run black` when that's how the project runs its tools.
   - Read `<Kit folder>/templates/snippets/format-hook.json` and merge its `hooks` entry into `.claude/settings.json`. Copy the `command` string **exactly as it is in that file**: it refers to the project folder through a variable, so teammates and other machines can use it. Never replace it with an absolute path.
   - Test the hook: pipe `{"tool_input":{"file_path":"<absolute path of an already-formatted source file>"}}` into the script. Confirm it exits 0 and leaves the file unchanged.
   - On Windows without bash, write an equivalent PowerShell script instead, and set `"shell": "powershell"` on the hook.
   - If the project has no formatter, delete `format-edited.sh` and add no hook.
7. **Leave the skills mostly alone.** `/go`, `/handoff`, `/lesson` and the `log-digger` agent work as installed. Only edit `.claude/skills/go/SKILL.md` if this project has a special verification step, such as an e2e command, and keep that edit to a line or two.
8. **Validate.**
   - Parse `.claude/settings.json` as JSON, with `python -m json.tool` or PowerShell `Get-Content -Raw .claude/settings.json | ConvertFrom-Json`.
   - Confirm no `{{` remains in CLAUDE.md, and report its line count.
9. **Report in chat, in 30 lines or fewer:**
   - A table of files created or changed.
   - Which commands you verified and which are unverified.
   - Anything you dropped or moved.
   - TODOs for the user.
   - These next steps:
     - Run `/clear`, or start a new session, so the new CLAUDE.md loads. Then run `/context` to check the startup size and `/doctor` to audit the setup.
     - After a few sessions, run `/fewer-permission-prompts`.
     - For a typed language, consider the language's code-intelligence (LSP) plugin from `/plugin`.
     - Review the diff, then commit `CLAUDE.md` and `.claude/`. The setup script already gitignored the local-only files.
<!-- PROMPT END -->
