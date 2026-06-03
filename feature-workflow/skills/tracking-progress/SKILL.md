---
name: tracking-progress
description: The rule for keeping a feature's plan.md honest as work proceeds — every meaningful step forward gets a dated Progress Log entry (what was done, what's next) and its implementation checkbox ticked, because the dashboard infers status from file presence and the log is the only record of where the work actually stands. Use when the user finishes an implementation task, makes a feature-related commit, says something is done, or asks to update progress. Litmus: plan.md tells the true story of the feature's progress at any moment.
---

# Tracking progress

Advisory standard — fires on the situation in the description. No command to invoke. Lead with the rule, then why, then how to apply.

## The rule

**`plan.md` is the running record of a feature's progress — keep it true as work proceeds.** When a step is finished, add a **dated Progress Log entry** (what was done, what's next) and flip its implementation checkbox `- [ ]` → `- [x]`. Stale plans are a quality failure: the next session — you or someone else — reads the plan to know where things stand.

Because this skill writes to a tracked file, **propose the change and get a yes before editing.** Show the log entry and checkbox update, then apply.

Only `active` and `paused` features are tracked. `replaced` and `abandoned` features are tombstones — refuse to log progress against them and point the user at `/feature-state <id> active` if they mean to resume.

## Why

The dashboard derives a feature's lifecycle stage from which files exist — `idea.md` (captured), `plan.md` (planned), `shipped.md` (shipped) — so file *presence* moves the big needle automatically. What it can't infer is the granular state *inside* an in-flight feature: which steps are done, what's next, where the last session stopped. The Progress Log is that memory. Skip it and the plan rots into fiction — checkboxes unchecked on finished work, no record of decisions made — and the next person has to reverse-engineer reality from the diff.

A dated, append-only log costs seconds per step and means anyone can pick the feature up cold and know exactly where it stands.

## How to apply (this is guidance for *you*, the agent)

When the user signals a step is done ("finished X", "done with Y"), commits feature work, or asks to update progress:

1. **Identify the feature.** The dashboard's *In Progress* section names active features; if more than one fits, check context or ask which.
2. **Load `plan.md`** and find its **Progress Log** (usually at the end) and **Implementation Steps** (the checkbox list). If there's no `plan.md`, there's nothing to track yet — point the user at `/feature-plan`.
3. **Draft the update** from what the user reported: a Progress Log entry under today's date (what was done + what's next) and the matching checkbox flip. If nothing in the step list matches, offer to add a log entry only; if several match, list them and ask which to tick.
4. **Confirm, then write.** Show the proposed edit, get the yes, apply it, and report what changed plus how many steps remain.

A typical confirmation:

```
Update plan.md?

  Progress Log:
    ### 2026-06-03
    - Completed JWT token refresh logic in auth/tokens.ts
    - Next: session timeout handling

  Implementation Steps:
    - [x] Implement JWT token refresh logic

Proceed? (yes/no)
```

The dashboard regenerates itself when feature files change, so you never hand-edit it — keeping `plan.md` true is what keeps the dashboard true. Accurate progress is also what `/feature-ship` relies on when it summarises the feature for the PR.

## Litmus

`plan.md` tells the true story of the feature at any moment — finished steps are ticked, the Progress Log has a dated entry for the latest work and what's next, and someone arriving cold can read it and know precisely where the feature stands.
