---
name: feature-review-plan
description: Open a PR for a feature's plan and run a plan review through the configured channel (local subagent by default; GitHub or Bitbucket; or skip), or respond to review feedback with --respond. Use after /feature-plan to get the plan reviewed before implementing, or to address reviewer findings. Litmus: the plan is on a PR (or recorded locally) with a PASS/CONDITIONAL/FAIL verdict, and every Blocking finding is resolved or answered.
allowed-tools: Read, Write, Edit, Bash, Agent
---

# feature-review-plan — review the plan, provider-agnostically

Submit a feature's `plan.md` for review, or respond to feedback. The reviewer and PR host come from config — nothing here assumes GitHub. Read [../shared/config.md](../shared/config.md) (branch + `review.mode`/`review.provider`) and [../shared/review-channel.md](../shared/review-channel.md) (the provider operations + the internal-review procedure) first.

## Arguments

`$ARGUMENTS`: `<feature-id>` (required), optional `--respond`.

## Step 0 — Resolve the review decision

Read `review.mode` + `review.provider` from `.feature-workflow.yml` and the feature's `idea.md` `review:`, then resolve with `lib/review_resolve.py` (see review-channel.md "Resolve the decision"). You get `mode` (internal/external/skip), `provider` (github/bitbucket/none), `runs`, `posts_to_pr`.

## Step 1 — Load context

Read `docs/features/<id>/plan.md` (must exist — else stop and suggest `/feature-plan <id>`) and `idea.md` (the problem statement the review judges against).

## Step 2 — Route

- **`--respond`** → follow [../shared/respond.md](../shared/respond.md) (any mode/provider).
- **`mode == skip`** → tell the user review is opted out for this feature; open the PR if they still want one, then stop. Don't fabricate a verdict.
- **otherwise** → submit (below).

## Step 3 — Submit the plan

Using `branch.prefix`/`branch.target` from config:

1. **Branch + push.** Create/checkout `<prefix><id>` from `<target>`, commit `idea.md` + `plan.md`, push. (If parallel work is live, isolate per the `worktree-isolation` skill.)
2. **Open (or reuse) the PR** for the branch via the provider's "open draft PR" operation in review-channel.md. Skip entirely if `provider == none`.
3. **Run the review** for `phase = plan`:
   - `mode == internal` → follow review-channel.md "Mode: internal" (load `templates/review-prompt-plan.md`, dispatch a `general-purpose` reviewer subagent, post the verdict via the provider's comment op, mirror to `docs/features/<id>/reviews/`).
   - `mode == external` → if a CI reviewer is wired, let it run; otherwise note that none is configured and fall back to the internal procedure (review still happens — see review-channel.md).
4. **Read the verdict.** PASS → proceed to `/feature-implement <id>`. CONDITIONAL/FAIL with Blocking findings → `/feature-review-plan <id> --respond`.

## Guidelines

- Stay on the feature branch; commit per round.
- The PR (when there is one) is the review artifact; the `reviews/` side-channel is the offline mirror.
- After dispatching an internal reviewer, **don't also self-review** — take the subagent's verdict as the review.
- Validate a finding before disagreeing with it.
