# Review channel — the provider-agnostic reviewer seam

This is the seam that lets the same lifecycle review on **GitHub**, **Bitbucket**, or **no remote at all**, with the review performed by a **local subagent** (default), an **external CI bot** (extension), or **not at all**.

Resolve the channel once with `lib/review_resolve.py`, then drive the PR operations through the provider table below. Nothing above this file is provider-specific.

## Resolve the decision

```bash
python3 -c "
import sys; sys.path.insert(0, '${CLAUDE_PLUGIN_ROOT}/skills/shared/lib')
from review_resolve import resolve_review
d = resolve_review(feature_review='<idea.md review:>', project_mode='<review.mode>', project_provider='<review.provider>')
print(d.mode.value, d.provider.value, d.runs, d.posts_to_pr)
"
```

`ReviewDecision` gives you `.mode` (`internal`/`external`/`skip`), `.provider` (`github`/`bitbucket`/`none`), `.runs` (mode ≠ skip), and `.posts_to_pr` (runs **and** provider ≠ none).

## Provider operations

Every PR-touching step maps to one of these operations. Use the column for the resolved provider. `<base>` = `branch.target`; `<branch>` = `<prefix><id>`.

| Operation | `github` (gh CLI) | `bitbucket` (MCP if present, else REST) |
|---|---|---|
| Open **draft PR** (head `<branch>` → base `<base>`) | `gh pr create --draft --base <base> --head <branch> --title "<t>" --body "<b>"` | `mcp__bitbucket__create_pull_request` (title, source `<branch>`, dest `<base>`); REST `POST /rest/api/latest/projects/{P}/repos/{R}/pull-requests`. Bitbucket has no "draft" — open as normal and prefix the title `[WIP]`. |
| Get PR number/URL for `<branch>` | `gh pr view <branch> --json number,url` | `mcp__bitbucket__list_pull_requests` filtered by source branch; REST `GET .../pull-requests?at=refs/heads/<branch>` |
| Post a **top-level comment** (verdict) | `gh pr comment <PR> --body-file -` | `mcp__bitbucket__add_pr_comment` (pr id, text); REST `POST .../pull-requests/{id}/comments` |
| Fetch open review threads/comments (for `--respond`) | `gh api graphql` (reviewThreads) or `gh pr view <PR> --json comments,reviews` | `mcp__bitbucket__get_pr_activities` / `get_pull_request`; REST `GET .../pull-requests/{id}/activities` |
| Reply on a thread / resolve it | `gh api graphql` (`addPullRequestReviewThreadReply`, `resolveReviewThread`) | `mcp__bitbucket__add_pr_comment` with `parentId`; REST comment with `parent.id` (DC resolves via thread state) |
| Merge the PR into `<base>` | `gh pr merge <PR> --squash --delete-branch` | `mcp__bitbucket__merge_pr` (pr id, strategy); REST `POST .../pull-requests/{id}/merge` |
| Mark ready (drop draft/WIP) | `gh pr ready <PR>` | strip the `[WIP]` title prefix via `mcp__bitbucket__update`/REST PUT |

Notes:
- **Detect the provider from config, not from the remote.** A repo can have both remotes; `review.provider` is the source of truth.
- **`provider: none`** → skip every row above. Open no PR. The review (if `mode` runs) is recorded only in the side-channel file (below), and `/feature-ship` merges locally (`git merge --no-ff <branch>` into `<base>`) instead of via a PR.
- GitHub labels (`plan-review`/`impl-review`) were part of the original CI-trigger flow. They are **not required** here — the internal reviewer posts directly. Apply them only if you wire an external CI reviewer that triggers on labels.

## Mode: `internal` (default) — local subagent review

Works identically across providers; the only provider-specific parts are "open PR" and "post comment" above.

1. **Open (or reuse) the PR** for `<branch>` via the provider's "open draft PR" op. Skip if `provider: none`.
2. **Load the review prompt:** read `${CLAUDE_PLUGIN_ROOT}/templates/review-prompt-<phase>.md` (`<phase>` = `plan` or `impl`) — the full file.
3. **Dispatch a reviewer subagent** (Agent tool):
   - `subagent_type: general-purpose`; `model: sonnet` (bump to `opus` if the feature is `category: security`, touches auth/crypto, or the plan exceeds ~500 lines).
   - `prompt`: the full review-prompt content **plus** a "Working directory / feature ID / PR number" section.
   - Mandate: read-only; emit the standard `## Plan Review` / `## Implementation Review` markdown ending in `### Verdict: PASS | CONDITIONAL PASS | FAIL`. It does **not** post — you post in step 4.
   - Capture its stdout = the review markdown.
4. **Post the verdict.** If `posts_to_pr`: provider "post top-level comment" op with the captured markdown. Always also mirror to the side-channel (below).
5. **Record the verdict** in the side-channel so the dashboard hook surfaces it (see below).
6. **Return control.** The caller reads the verdict and proceeds (PASS → continue; FAIL/CONDITIONAL with Blocking → `--respond`).

Verdict rule (matches the review prompts): `CONDITIONAL PASS` must not contain Blocking findings — a Blocking finding makes it `FAIL`.

## Mode: `external` — CI bot review (extension point, not built-in)

This port ships the **internal** reviewer working out of the box and leaves `external` as a documented seam — deliberately, so there's no GitHub-Actions/API-key dependency baked in. To wire it:

- **GitHub Actions:** a workflow on the PR runs your reviewer (e.g. an LLM CLI) with `templates/review-prompt-<phase>.md` and posts the result via `gh pr comment`. Trigger on the `plan-review`/`impl-review` label or on `synchronize`.
- **Bitbucket Pipelines / OCI DevOps:** a pipeline step does the same and posts via the Bitbucket comment API.
- Either way the **contract is identical** to internal: a top-level PR comment whose body ends in a `### Verdict:` line. The respond loop and verdict classifier don't care who wrote it.

Until you wire one, `external` behaves like `internal` with a one-line note that no CI reviewer is configured (so review still happens rather than silently skipping).

## Mode: `skip`

No review. Open the PR if the lifecycle needs one, surface to the user that review is opted out for this feature, and continue. Use sparingly (doc/typo changes) — the audit trail is real value.

## Side-channel: `docs/features/<id>/reviews/`

Independent of provider, every review run also writes a local copy so the verdict is grep-able offline and the dashboard hook can surface it:

- `docs/features/<id>/reviews/review-<phase>-<round>.md` — the posted markdown verbatim. `<round>` increments per phase (count existing files + 1), so a FAIL → respond → re-review cycle leaves a trail.
- The `post_tool_use` hook watches `reviews/review-status.md`; write the latest verdict there as frontmatter (`verdict:`, `phase:`) if you want the dashboard to echo it.

The PR (when there is one) remains the source of truth; these files are the offline mirror.
