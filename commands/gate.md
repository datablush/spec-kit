---
description: "Stop before implementing until the feature's plan is approved in Datablush"
---

# Plan approved?

## User Input

$ARGUMENTS

## Steps

1. Run `bash .specify/extensions/datablush/scripts/datablush.sh gate --command implement`. It sends the feature's
   files first, then checks the plan of its task in Datablush.
2. Exit code 0: the plan is approved. Carry on with the implementation.
3. Exit code 3: the plan isn't approved (none yet, waiting for review, or plan.md changed since). **Stop: don't write
   any code.** Tell the person what it printed: the plan must be submitted (with Datablush's submit_plan tool, if you
   have it) and approved in Datablush first. Run /speckit.implement again once it is.
4. Exit code 2: this computer isn't connected. Run `bash .specify/extensions/datablush/scripts/datablush.sh login`
   (allow up to 10 minutes), show the person the link and code, then run step 1 again.
5. Any other failure: tell the person, and ask whether to go ahead without the check.
