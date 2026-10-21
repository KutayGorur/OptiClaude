---
name: go
description: Finish the current change. Verify it end to end, simplify it, and report evidence. Pass "pr" to also commit and open a pull request.
disable-model-invocation: true
argument-hint: "[pr]"
---
Finish the current change in four steps.

1. **Verify.** Run the checks listed under "Verification" in CLAUDE.md, starting with the narrowest one. If the app can be run and the /verify skill is available, use it to exercise the changed behavior. Otherwise start the app or call the code yourself. Fix any failure and re-run the check. If the same problem fails 3 times, stop and report it instead of continuing.
2. **Simplify.** Run /simplify on the changed code. If it changed anything, re-run the checks from step 1.
3. **Report evidence.** List the files you changed, each command you ran with its pass or fail result, and anything you could not verify, with the reason.
4. **Ship (only if the argument is `pr`).** Create a branch, commit with a descriptive message, and open a pull request with `gh pr create`. Without `pr`, do not commit.

Argument: $ARGUMENTS
