---
name: checking-backlog
description: The rule for looking before you leap on new work — when the user proposes a feature, asks what's planned, or debates priorities, render the live dashboard first so you don't duplicate or collide with something already captured or in flight. Use when the user says "we should add…", "it'd be nice if…", "what if we…", asks "is X in the backlog?" / "what's planned?" / "what should we work on next?", or names a feature that might already be tracked. Litmus: no new feature gets started without first confirming it isn't already in the backlog or in progress.
---

# Checking the backlog

Advisory standard — fires on the situation in the description. No command to invoke. Lead with the rule, then why, then how to apply.

## The rule

**Before starting or proposing new work, check the dashboard.** When the user floats a feature, asks what's planned, or weighs priorities, render the live dashboard and search it for a match *before* you suggest capturing or building anything. The goal is to avoid duplicating an idea that's already captured and to avoid colliding with a feature that's already in progress.

The dashboard is generated, not hand-kept — render it fresh each time rather than trusting a stale copy or memory.

## Why

Two failure modes this prevents. The first is duplication: the user describes "dark mode," you enthusiastically `/feature-capture` it, and it turns out it was captured two weeks ago — now there are two records of one idea and the backlog is lying about how much work exists. The second is collision: the user asks you to start something that's already *in progress* (perhaps in another worktree or another session), and you begin a parallel, conflicting implementation. A five-second look at the dashboard catches both before any work or noise is created.

It also makes you a better collaborator on priorities — when the user asks "what's next?", an answer grounded in the actual backlog beats one invented on the spot.

## How to apply (this is guidance for *you*, the agent)

1. **Render the dashboard.** Run the dashboard engine for the project and read its output:
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/shared/lib/run_dashboard.py" <project_root> --stdout
   ```
   If it errors or `docs/features/` doesn't exist, there's no backlog yet — say so and suggest `/feature-capture` to start tracking.
2. **Search for a match.** Scan the dashboard sections (In Progress, Backlog, Completed) for a feature whose name or problem statement matches the request. For deeper confirmation, read the candidate's `idea.md` (problem statement, priority, affected areas) — and its `plan.md` / `shipped.md` if it's already underway or done.
3. **Exclude tombstones by default.** The Archive section (collapsed) holds `replaced` and `abandoned` features. Don't surface those as things to work on — *unless* the user names a tombstoned ID explicitly, in which case mention its history (e.g. "that was replaced by X") so they know why it's parked.
4. **Respond to what you found:**
   - **Already tracked** — show its status, priority, and section. If it's in the backlog, suggest `/feature-plan <id>` to start it.
   - **Something related** — list it and ask whether the new idea is an extension of it or genuinely separate.
   - **Not tracked** — suggest `/feature-capture` to add it.

A clean hit reads like:

```
Already tracked:

  Dark Mode Toggle  (id: dark-mode-toggle)
  Status: backlog   Priority: P1

Ready to start — /feature-plan dark-mode-toggle
```

When the work is genuinely new and parallel work may be live, isolating it (see `worktree-isolation`) keeps the new line of work from colliding with what's already in flight.

## Litmus

No new feature gets started without first confirming it isn't already captured or in progress — every "we should add X" is checked against the live dashboard before it turns into a capture or a code change.
