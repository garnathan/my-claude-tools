---
name: github-api-discipline
description: Use whenever build, deploy, or background code reads files from another GitHub repo at runtime — workshop content, manifests, configs fetched from a registry. Captures the rules that keep you under the GitHub App's 15000/hr installation rate limit (zipball over per-file, respect retry-after, share fetched content, App token not PAT) and ships a drop-in reference fetcher + backoff helper. Litmus: one bulk fetch per repo, never one call per file, and a single throttled response never kills a deploy.
---

# GitHub API discipline

Advisory standard — fires on the situation in the description. The shipped reference implementation lives in this skill's directory:

1. **`assets/manifest-fetch-zipball.ts`** — `createGitHubFileFetcher`: downloads `/zipball/{ref}` once with `fflate` decompression and serves in-memory file reads. Same `FileFetcher` interface as a per-file fetcher — a drop-in replacement for a list-then-fetch-each-file loop.
2. **`assets/with-rate-limit-retry.ts`** — `withRateLimitRetry` + the `isRateLimited` classifier (handles 429 and `403 rate limit exceeded`, reads `retry-after` / `x-ratelimit-reset`).

## The rule

When build or deploy code fetches files from another GitHub repo at runtime, default to:

1. **One bulk fetch per repo, not one call per file.** Use `GET /repos/{owner}/{repo}/zipball/{ref}` (or the tarball / `/git/trees?recursive=true` endpoints) and read files from the in-memory archive. Per-file `/contents/{path}` is the trap.
2. **Honor rate-limit headers.** On `429` *or* `403 rate limit exceeded`, read `retry-after` or `x-ratelimit-reset`, sleep, retry (bounded). A single throttled response must never kill a deploy.
3. **Share fetched content within a workflow run.** Don't refetch the same files from two scripts in the same CI job; cache to disk between them.
4. **Authenticate.** Use a GitHub App installation token (15000/hr per installation, separate quota from user PATs). Don't use a user PAT for automation — it shares the user's 5000/hr quota with everything else they do on the same account.

The four are ranked by impact. The biggest single win is #1.

## Why

**Real incident.** A deploy pipeline ran two scripts that each iterated over ~8 content bundles and called `GET /repos/{o}/{r}/contents/{path}` for each of ~25 files per bundle — ~400 calls per deploy. Under any meaningful burst (multiple PRs + cutover deploys in the same hour) it blew the App installation's 15000/hr ceiling and the deploy failed with `403 API rate limit exceeded for installation ID …` mid-build.

The fix was just zipball + a `withRateLimitRetry` wrapper:

- **Before:** ~400 calls/deploy; ~3m26s; sporadic failure under bursts.
- **After:** ~16 calls/deploy (8 bundles × 2 scripts); ~1m13s (~3× faster); no rate-limit failures.

The audit also showed the *easy* best-practices items (authenticated requests, no polling, serial requests) were already done while every high-impact one (zipball, ETag, rate-limit-header backoff) was skipped. It's the high-impact items that matter.

## How to apply

### When designing a new build/deploy pipeline that fetches GitHub content

- Reach for the **zipball/tarball endpoint** first. Don't list-then-fetch-each-file. `assets/manifest-fetch-zipball.ts` is the drop-in.
- Wrap the network call in the backoff helper — `assets/with-rate-limit-retry.ts`.
- If two pipeline stages need the same content, fetch once and cache to a workspace-local dir; have the second stage read from cache.

### When auditing an existing build that hits the GitHub REST API

Walk this checklist; flag anything ❌. Tackle ❌s in the order shown — they're roughly ranked by payoff:

| Practice | Doing it? |
|---|---|
| Bulk fetch (zipball/tarball/trees) instead of per-file `/contents` | |
| Honor `retry-after` / `x-ratelimit-reset` on 429/403 | |
| Cache fetched content across stages in the same workflow | |
| Authenticated requests (App token, not PAT) | |
| Conditional requests with `If-None-Match` (ETag) for cross-run reuse | |
| Avoid polling — use webhook/dispatch triggers | |
| Serial requests (not concurrent) | |

### When someone says "we should just raise the GitHub rate limit"

Push back. The 15000/hr App installation cap is already the standard high tier. The real fix is *cutting waste*, not asking GitHub for more headroom for waste.

## Litmus

A deploy that reads N files from a GitHub repo makes O(1) API calls per repo (a single archive fetch), not O(N), and survives a throttled response by backing off rather than failing.
