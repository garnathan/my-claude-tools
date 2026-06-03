---
name: feature-implement
description: Execute an approved plan.md from a clean context — load the plan, work the implementation steps in order, keep the plan.md Progress Log and checkboxes current, guard against scope creep, and verify real user-facing behavior before claiming any step done. Use when starting implementation after planning, resuming an in-progress feature, or when the user names a feature ID to build. Litmus: every Implementation Step is checked off in plan.md with a Progress Log trail, and the feature's behavior has been verified by observation (not just a green test run).
allowed-tools: Read, Write, Edit, Bash, Agent
---

# feature-implement — build an approved feature

Pick up a `plan.md` and execute it. `$ARGUMENTS` is the target feature ID.

## Step 1 — Load the plan

- **ID given** — read `docs/features/<id>/plan.md` and `docs/features/<id>/idea.md` (problem statement + context).
- **No ID** — read `docs/features/DASHBOARD.md`, show the In Progress features, and ask which to implement.

If no `plan.md` exists, stop and suggest `/feature-plan <id>` first.

## Step 2 — State guard

Read `idea.md` `state:`. If it's `paused`, `replaced`, or `abandoned`, stop the same way `/feature-plan` does and do **not** start new implementation work. Exception: checking off already-completed steps in `plan.md` is allowed even for a paused feature, so progress can be recorded when work later resumes.

## Step 3 — Branch

Branch settings (prefix, target) come from `.feature-workflow.yml` — see [../shared/config.md](../shared/config.md) (default `feature/<id>` off `dev`). Create or switch to the feature branch before editing code.

## Step 4 — Confirm before starting

Summarize: feature name + ID, total steps, which are already checked off (if resuming), and the first uncompleted step. Ask: **"Ready to start? Any changes to the plan first?"**

## Step 5 — Work the steps in order

For each Implementation Step in `plan.md`:

1. State what you're about to do.
2. Implement it, matching the conventions of the files you're touching.
3. Verify it — run the relevant tests **and** confirm the actual behavior (load the page, hit the endpoint, run the command). Passing unit tests is never sufficient evidence on its own; observe the real result.
4. Tick the checkbox in `plan.md` (Edit) and append a dated line to the **Progress Log** (what was done, what's next).

Keep scope tight. If something looks like new, unplanned work, invoke the `guarding-scope` skill before expanding — capture out-of-scope ideas as fresh backlog items rather than folding them in silently. On a real blocker, explain it, offer alternatives, and ask how to proceed.

For a heavy, self-contained sub-task you may dispatch a `general-purpose` subagent via the Agent tool, but keep step tracking and verification in this session.

## Step 6 — Completion

When every step is checked off:

1. Run the full test suite and show the output.
2. **Verify user-facing behavior end to end** — the litmus is observed behavior, not a green test run. Capture the concrete evidence (command output, response body, screenshot of the working UI).
3. Make sure the Progress Log reflects the final state.
4. Summarize what was implemented and the evidence backing "done".

Then hand off to review per [../shared/config.md](../shared/config.md) and [../shared/review-channel.md](../shared/review-channel.md) — that's where the PR opens and the verdict is recorded. Do not merge here; shipping is a later, separate step run after review is satisfied.
