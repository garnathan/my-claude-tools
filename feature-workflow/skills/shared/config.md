# Project configuration (`.feature-workflow.yml`)

Every skill that creates branches, opens PRs, reviews, or merges **reads this file first**. If it doesn't exist, use the defaults below.

```yaml
branch:
  prefix: "feature/"    # default — branch naming: <prefix><feature-id>
  target: "dev"         # default — base branch for checkout, PR base, and merge target

review:
  mode: "internal"      # internal | external | skip   (WHO reviews — default: internal)
  provider: "github"    # github | bitbucket | none    (WHERE the PR + comments live — default: github)
```

## Branch config

| Setting | Used for | Example |
|---|---|---|
| `branch.prefix` | Branch naming: `<prefix><feature-id>` | `feat/auth-system` |
| `branch.target` | Base branch for `git checkout`, PR base, and merge target | `dev` |

Substitutions throughout the skill instructions:
- `feature/<id>` → `<prefix><id>`
- `dev` (as a branch name) → `<target>`

If config says `prefix: "feat/"` and `target: "main"`:
- `git checkout -b feature/auth-system` → `git checkout -b feat/auth-system`
- PR base `dev` → PR base `main`

## Review config — the two axes

The review system has two orthogonal axes; see [review-channel.md](review-channel.md) for the operations each implies.

| Axis | Values | Meaning |
|---|---|---|
| `review.mode` | `internal` · `external` · `skip` | **WHO** reviews. `internal` = a local Claude subagent runs the review prompt and posts the verdict (no CI, no API keys — works anywhere). `external` = an external CI bot reviews (documented extension; you wire it). `skip` = no review. |
| `review.provider` | `github` · `bitbucket` · `none` | **WHERE** the PR and review comments live. `none` = no PR; the verdict is recorded only in the feature's `reviews/` side-channel. |

A feature can override the **mode** in its `idea.md` frontmatter: `review: internal | external | skip`. The provider is project-wide (you don't move a single feature's PR host). Resolution is implemented in `lib/review_resolve.py` (`resolve_review(feature_review, project_mode, project_provider) → ReviewDecision`). Precedence for mode: per-feature `review:` wins → else `review.mode` → else `internal`.

**Legacy note:** older configs used a flat `reviewer: gemini|codex|none`. This port replaces that GitHub-Actions-specific field with the `review.mode` / `review.provider` pair. If you see a bare `reviewer:`, treat `none` → `mode: skip`, anything else → `mode: external, provider: github`.
