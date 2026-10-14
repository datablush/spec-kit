---
description: "Send this feature's Spec Kit files to Datablush and follow what needs doing next"
---

# Sync to Datablush

## User Input

$ARGUMENTS

## Steps

1. Work out which Spec Kit command just ran: constitution, specify, clarify, plan, checklist, tasks or implement (the
   user input may name it).
2. Run the sync. It reads the files from disk and sends them itself: never paste file contents anywhere.
   - After /speckit.constitution: `bash .specify/extensions/datablush/scripts/datablush.sh sync --constitution --command constitution`
   - After any other command: `bash .specify/extensions/datablush/scripts/datablush.sh sync --command <command>`
   - If the person said which task this feature is (GEN-42), add `--task GEN-42`; if it's part of a bigger piece
     of work (GEN-10: an epic, or the same feature in another repository), add `--parent GEN-10`. Once is enough:
     Datablush remembers.
3. If it exits with code 2, this computer isn't connected yet. Run
   `bash .specify/extensions/datablush/scripts/datablush.sh login` (allow up to 10 minutes), show the person the link
   and the code it prints so they can allow it in Datablush, then run step 2 again.
4. Read what it prints and do what it says needs doing: write answers given in Datablush into spec.md's
   Clarifications, copy ticks made in Datablush into tasks.md, and, if you can use Datablush's tools (MCP), submit or
   update the plan with submit_plan and record the person's answers with record_decisions. If you changed any files,
   run step 2 again.
5. Tell the person in one line that the spec is in Datablush, and anything they need to do there (approve the plan,
   answer questions).
