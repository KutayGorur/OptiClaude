---
name: auto-lesson
description: Use on your own, right after you resolve a mistake worth remembering - the user corrected you, the same approach failed twice before another one worked, or you hit a repo-specific trap. Saves the trap and its fix as one line, following the /lesson rules.
user-invocable: false
---
You just resolved a mistake. Save it as a lesson, so the user doesn't have to run /lesson.

1. **Is it worth saving?** Only if a future session in this repo would likely repeat the mistake without the line. Skip typos, one-off network errors, anything CLAUDE.md already covers, and preferences that apply only to the current task. If it isn't worth saving, stop here.
2. **Save it.** Read `.claude/skills/lesson/SKILL.md` and follow its "Saving a lesson" section, except showing the diff. You already know the problem and its fix, so don't start the lesson-finder subagent.
3. **Tell the user** in one line what you saved and where, so they can undo it. For example: "Saved to CLAUDE.md Gotchas: ...".

Save at most one lesson per mistake. If you're in the middle of the user's task, finish it first, then save the lesson.
