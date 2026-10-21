---
name: handoff
description: Write a short handoff brief so the work can continue in a fresh session after /clear.
disable-model-invocation: true
---
Write `.claude/handoff.md`, replacing any existing file. Keep it to about 40 lines and use these headings:

- **Goal**: the goal and its acceptance criteria.
- **State**: what is done, what is in progress, and what has not started.
- **Key files**: paths, with one line on why each one matters.
- **Decisions and dead ends**: decisions made and approaches ruled out, each with the reason.
- **Next steps**: the exact next actions, in order.
- **How to verify**: the commands or checks that prove the work is done.

Don't paste code or logs into the brief. Point to file paths and commands instead.

When the file is written, tell the user to run `/clear` and then start the new session with: `@.claude/handoff.md continue from this handoff`.
