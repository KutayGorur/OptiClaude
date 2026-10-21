---
name: lesson
description: Record a mistake and its fix as one line in the right place, so it doesn't happen again. With no argument, a cheap Haiku subagent finds the recent mistakes in this session's transcript.
disable-model-invocation: true
argument-hint: "[what went wrong]"
---
Record a lesson. What went wrong: $ARGUMENTS

## Finding the mistake
- **If nothing follows "What went wrong:" above**, don't reconstruct the mistakes yourself. Start the `lesson-finder` subagent with this as its whole prompt: `Run: bash "${CLAUDE_SKILL_DIR}/find-mistakes.sh" ${CLAUDE_SESSION_ID}`
  - It returns up to 3 candidate lessons. Check each against what you remember of this session, and drop any that are wrong or not worth keeping.
  - If it found nothing worth keeping, say so and stop.
- **Otherwise** the user told you the problem. Work out its fix from the last few turns.

## Saving a lesson
1. Write each lesson as one line that names the trap and says what to do instead, for example "On Git Bash, `grep` and `awk` drop CR characters: use `tr` and `printf` for byte-exact checks." Leave out the story of what happened.
2. Put the line in the right place:
   - A trap that applies across the repo goes under "Gotchas" in CLAUDE.md.
   - A lesson that only matters for one workflow goes in that skill's SKILL.md.
   - If a lint rule, test or hook could enforce it, propose that instead, because tools are deterministic and cost no tokens.
3. Before you add the line, look for an existing line that duplicates or contradicts it, and merge them.
4. If CLAUDE.md is longer than 100 lines, propose 1 to 3 lines to cut, such as things Claude already does without being told.
5. Show the diff. Remind the user that CLAUDE.md changes take effect after `/clear` or in a new session.
