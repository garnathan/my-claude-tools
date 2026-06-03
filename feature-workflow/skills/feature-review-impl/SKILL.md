---
name: feature-review-impl
description: Push a feature's implementation to its PR and run an implementation review through the configured channel (local subagent by default; GitHub or Bitbucket; or skip), or respond to review feedback with --respond. Use after /feature-implement, before /feature-ship. Litmus: the diff is on a PR (or recorded locally) with a PASS/CONDITIONAL/FAIL verdict, and every Blocking finding is resolved or answered.
allowed-tools: Read, Write, Edit, Bash, Agent
---

# feature-review-impl — review the implementation, provider-agnostically

Submit a feature's implementation for review, or respond to feedback. Same channel model as `/feature-review-plan`, just the `impl` phase. Read [../shared/config.md](../shared/config.md) and [../shared/review-channel.md](../shared/review-channel.md) first.

## Arguments

`$ARGUMENTS`: `<feature-id>` (required), optional `--respond`.

## Step 0 — Resolve the review decision

As in `/feature-review-plan` Step 0: resolve `mode`/`provider`/`runs`/`posts_to_pr` via `lib/review_resolve.py`.

## Step 1 — Load context

Read `docs/features/<id>/plan.md` (the feature must be in progress — else suggest `/feature-plan <id>`) and `idea.md`.

## Step 2 — Route

- **`--respond`** → [../shared/respond.md](../shared/respond.md).
- **`mode == skip`** → push the code, surface that review is opted out, stop.
- **otherwise** → submit (below).

## Step 3 — Submit the implementation

Using `branch.prefix`/`branch.target` from config:

1. **Push the implementation.** The feature branch should already exist from `/feature-review-plan`; if not, create `<prefix><id>` from `<target>`. Commit the implementation and push to the same branch (so the existing PR updates).
2. **Reuse the PR** for the branch (provider "get PR for branch" op). Skip if `provider == none`.
3. **Run the review** for `phase = impl`:
   - `mode == internal` → review-channel.md "Mode: internal" with `templates/review-prompt-impl.md`. Post the verdict via the provider's comment op; mirror to `docs/features/<id>/reviews/`.
   - `mode == external` → CI reviewer if wired, else fall back to internal (review still happens).
4. **Read the verdict.** PASS → `/feature-ship <id>`. CONDITIONAL/FAIL with Blocking → `/feature-review-impl <id> --respond`.

## Guidelines

- Stay on the feature branch; commit per round.
- The PR is the review artifact; `reviews/` is the offline mirror.
- Don't self-review after dispatching the internal reviewer; take its verdict.
- For features touching security-critical paths, prefer a fresh-context reviewer (or bump the internal reviewer to `opus`) — see review-channel.md.
