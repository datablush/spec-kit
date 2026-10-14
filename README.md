# Datablush for Spec Kit

A [GitHub Spec Kit](https://github.com/github/spec-kit) extension. After every Spec Kit command, the files it wrote
go to Datablush, where the team reads, discusses and approves the spec, and its work is tracked: the feature is a
task, each tasks.md phase a sub-task with its T### lines as the checklist, and each clarification a decision.
`/speckit.implement` waits until the feature's plan is approved in Datablush.

Works with any agent Spec Kit supports. The files are uploaded by a script, straight from disk, so the agent spends
no tokens on them.

## Install

In a Spec Kit project (Spec Kit 1.0 or later):

```bash
specify extension add datablush --from https://github.com/datablush/spec-kit/archive/refs/heads/main.zip
```

The first sync shows a link and a code: open it, check the code and click Allow, once per computer.

| Part | What it does |
|---|---|
| `speckit.datablush.sync` | Runs after constitution, specify, clarify, plan, checklist, tasks and implement: sends the feature's folder (or the constitution) and says what needs doing next (the plan to submit, answers and ticks from Datablush to write into the files). |
| `speckit.datablush.gate` | Runs before implement: stops until the feature's plan is approved in Datablush. |
| `scripts/datablush.sh` | `login`, `sync`, `gate`, `status`, `logout`. Plain bash and curl. |

Settings: `DATABLUSH_API_URL` (default `https://api-dev.datablush.com` while Datablush is in development).

## Releasing

Published as the public [`datablush/spec-kit`](https://github.com/datablush/spec-kit) repository, a copy of
`integrations/spec-kit` in the Datablush monorepo, where it's developed.

1. Change the extension here (a normal PR to the monorepo), and raise `version` in `extension.yml`.
2. Merge. `.github/workflows/publish-spec-kit.yml` publishes this folder to `datablush/spec-kit` as one commit.

Teams update with `specify extension add datablush --from …` again. The workflow pushes with the `PLUGIN_REPO_TOKEN`
secret, the same fine-grained token as the Claude Code plugin's, with access to both public repositories
(Contents: Read and write).

## Develop

`scripts/datablush.sh` is the same file as the Claude Code plugin's (`integrations/claude-code/plugin/scripts/`);
CI checks they match. Try it in a Spec Kit project with `specify extension add --dev <path to this folder>`.
