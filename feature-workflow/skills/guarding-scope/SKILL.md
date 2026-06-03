---
name: guarding-scope
description: The rule for keeping an in-flight implementation inside the boundaries of its approved plan — new functionality that isn't in the feature's requirements is scope creep, and the move is to capture it as its own feature, not quietly fold it in. Use when, mid-implementation, the user requests new functionality, asks to add something tangential, proposes a change that isn't in the plan, or says "while we're at it, let's also…". Litmus: nothing lands in the current feature that the approved plan didn't ask for.
---

# Guarding scope

Advisory standard — fires on the situation in the description. No command to invoke. Lead with the rule, then why, then how to apply.

## The rule

**An in-flight implementation stays inside the boundaries of its approved plan.** When a request would add functionality the current feature's `idea.md` / `plan.md` never asked for, that's scope creep — name it, and offer to track it as its own feature with `/feature-capture` rather than silently expanding the one in progress.

This is not a blanket "say no." Bug fixes in the feature's code, refactors that stay within scope, clarifying an existing requirement, and the ordinary implementation details of a planned step are all *in scope* — proceed without ceremony. The rule fires only on genuinely new work.

## Why

A plan is the agreement about what "done" means. Every unplanned addition that slips into the current feature pushes that finish line back, inflates the diff a reviewer has to reason about, and blurs what the feature actually delivered. "While we're at it…" is how a one-day change becomes a one-week change with no decision ever consciously made.

Capturing the extra idea as its own feature loses nothing — it's recorded, prioritisable, and reachable via `/feature-plan` later — while the current feature ships on the scope it was approved for. The discipline is structural: a cheap `/feature-capture` keeps the backlog honest *and* the current work shippable.

## How to apply (this is guidance for *you*, the agent)

When a request arrives mid-implementation:

1. **Anchor on the active feature.** Read its `plan.md` (and `idea.md` for the problem statement) to recall what was actually agreed. The dashboard's *In Progress* section names the active feature if it's unclear; if there's genuinely no active feature, skip the check — don't block the user.
2. **Classify the request** against that plan:
   - **In scope** — implements the problem statement, a reasonable extension of a planned step, or a bug fix in the feature's code. Just do it.
   - **Scope creep** — new functionality unrelated to the problem statement, touches areas the plan never listed, or would force a significant plan rewrite.
3. **Respond proportionately.** In scope → proceed silently. Creep → surface it and offer options: include it now (and note the plan grows), capture it for later with `/feature-capture`, or skip it. Out of scope entirely → recommend `/feature-capture` as its own feature.
4. **Respect the decision.** Be a guardrail, not a gate. If the user chooses to include it, fold it in *and* update `plan.md` so the Progress Log reflects the widened scope.

Phrase it as a choice, e.g.:

```
That's outside the current feature's plan.

  Current feature: Dark Mode Toggle  —  scope: light/dark theme switching
  Your request:    Notification preferences

Options:
  1. Include it now — current feature scope grows
  2. Capture it for later — /feature-capture (track separately)
  3. Skip for now — finish dark mode first

Which would you like?
```

## Litmus

Nothing lands in the current feature that its approved plan didn't ask for. Every genuinely new idea is either a conscious, plan-updating decision to widen scope or a fresh `/feature-capture` — never an unannounced "while we're at it."
