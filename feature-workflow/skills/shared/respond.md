# Respond to review feedback

Shared by `/feature-review-plan --respond` and `/feature-review-impl --respond`. Read review feedback, validate each finding, implement fixes, reply on each thread, and push updates. Provider-agnostic — all PR operations go through the provider table in [review-channel.md](review-channel.md). Resolve `provider` from `.feature-workflow.yml` first.

## Step 1 — Find the PR (or the side-channel)

Using review-channel.md's "get PR for branch" op for the resolved provider, find the open PR for `<prefix><id>`. If `provider == none`, there's no PR — read the latest `docs/features/<id>/reviews/review-*.md` instead and treat its findings as the feedback set.

If no PR and no review file exist, suggest running `/feature-review-plan <id>` or `/feature-review-impl <id>` first.

## Step 2 — Collect feedback

Fetch the review comments/threads via review-channel.md's "fetch review threads" op (GitHub: review comments + thread IDs; Bitbucket: PR activities/comments; `none`: the review file body). Skip threads already resolved.

## Step 3 — Synthesize findings

Build one consolidated list. Per finding record: source (reviewer), origin (inline thread vs top-level), severity (Blocking / Should-fix), location (`path:line`), a one-line summary, the full body, and — for inline threads — the identifiers the provider needs to reply and resolve.

## Step 4 — Present to the user

Group by severity (Blocking, Should-fix, Already-resolved-for-context) and ask: **"Which findings should we address? Any to push back on or mark already handled?"**

## Step 5 — Classify each finding

| Classification | When | Action |
|---|---|---|
| **Agree** | Correct and within the feature's scope | Fix → reply with what changed → resolve thread |
| **Disagree** | Wrong, or the code already guarantees it | Reply with reasoning → leave thread open |
| **Already addressed** | Reviewer missed existing handling | Reply pointing to the code/test → resolve thread |
| **Defer to backlog** | Valid but expands scope beyond this feature's `idea.md` | `/feature-capture` a new item → reply with the new ID → resolve thread |
| **Deferred (other)** | Valid but blocked externally / needs owner | Reply explaining where it's tracked → resolve thread |

**Defer-to-backlog** is the escape valve for *adjacent good ideas* — don't silently grow one feature into three. But if a finding is truly required for this feature to be correct (security bug, data-loss, plan drift), classify **Agree** and fix it; don't defer required work. When capturing a deferral, give the new `idea.md` an `## Origin` section naming the source feature + finding.

## Step 6 — Implement (Agree findings, Blocking first)

Plan reviews → edit `plan.md`. Impl reviews → edit code + tests. Keep a `finding → files → one-line summary` map for the replies. Commit + push in one batch:

```bash
git add -A && git commit -m "fix(<id>): address review feedback" && git push
```

## Step 7 — Reply on each thread

For every inline finding, post one reply via review-channel.md's "reply on thread" op. Lead with the commit SHA + a one-sentence description; point to the changed line when useful. For **Disagree**, give the 1–2 sentence reasoning. Keep replies ≤3 sentences — detail belongs in the commit. One reply per thread.

## Step 8 — Resolve the threads you addressed

For **Agree / Already addressed / Deferred**, resolve the thread (review-channel.md "reply/resolve" op) after replying. Leave **Disagree** threads open so the reviewer can respond. (If `provider == none`, there are no threads — just note the dispositions in the next review-file round.)

## Step 9 — Top-level summary comment

Post one summary comment for the round (skip if `provider == none`):

```
## Review Response (round N)
Addressed in <sha>:
**Blocking resolved** — …
**Should-fix resolved** — …
**Disagreed (open)** — …
**Deferred to backlog** — captured as <new-id> (<sha>)
Ready for another look.
```

Only include sections with entries.

## Step 10 — Next steps

Re-run the review for another pass (internal review re-runs when you invoke the review skill again; a wired external CI reviewer re-runs on push). Then:
- `/feature-review-plan <id> --respond` / `/feature-review-impl <id> --respond` — next round
- `/feature-implement <id>` — start coding (plan satisfactory)
- `/feature-ship <id>` — merge + ship (implementation satisfactory)

## Pitfalls

- Reply to the **first** comment of a thread, not a later one.
- Replying ≠ resolving — resolve is a separate op.
- Don't resolve a thread you disagree with — leave it open.
- Skip already-resolved threads; re-replying is noise.
