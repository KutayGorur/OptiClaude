---
name: lesson
description: Record a correction so the same mistake doesn't happen again. Adds one line to the right place and keeps CLAUDE.md lean.
disable-model-invocation: true
argument-hint: "[what went wrong]"
---
The user just corrected you. What went wrong: $ARGUMENTS. If that's empty, work it out from the last few turns.

1. Write the lesson as one specific, imperative line that says what to do. Leave out the story of what happened.
2. Put the line in the right place:
   - A trap that applies across the repo goes under "Gotchas" in CLAUDE.md.
   - A lesson that only matters for one workflow goes in that skill's SKILL.md.
   - If a lint rule, test or hook could enforce it, propose that instead, because tools are deterministic and cost no tokens.
3. Before you add the line, look for an existing line that duplicates or contradicts it, and merge them.
4. If CLAUDE.md is longer than 100 lines, propose 1 to 3 lines to cut, such as things Claude already does without being told.
5. Show the diff. Remind the user that CLAUDE.md changes take effect after `/clear` or in a new session.
