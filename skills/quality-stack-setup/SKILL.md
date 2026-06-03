---
name: quality-stack-setup
description: Use when setting up a repo's lint / static-analysis / test tooling — wiring lefthook git hooks (pre-commit auto-fixers + pre-push full verify) and a justfile that is the single source of truth both the hooks and CI call, so local checks and CI can't drift. Language-agnostic (ruff/skylos for Python, prettier/eslint/fallow for TS/JS, clippy/rustfmt for Rust) and CI-agnostic (ships both a GitHub Actions and a Bitbucket Pipelines backstop). Litmus: pre-push and CI run the byte-identical `just verify`, so "passed locally → passes in CI" holds by construction.
allowed-tools: Read, Write, Bash
---

# quality-stack-setup — one definition, three callers, no drift

The point of this stack is **AI-slop resistance**: deterministic guardrails so generated code can't land unformatted, untyped, dead, duplicated, or untested. The tools change per language; the guardrail categories don't.

In this skill's directory:

- **`assets/justfile`** — the single source of truth for checks (`verify`, `fix`, and the `format-check`/`lint`/`typecheck`/`test` sub-recipes). Auto-detects Python/TS-JS/Rust by root manifest.
- **`assets/lefthook.yml`** — the git-hook dispatcher (pre-commit fixers + staged-file scan; pre-push `just verify`).
- **`assets/ci-github.yml`** — GitHub Actions backstop (→ `.github/workflows/ci.yml`), runs the same `just verify`.
- **`assets/bitbucket-pipelines.yml`** — Bitbucket Pipelines backstop (→ repo-root `bitbucket-pipelines.yml`), same `just verify`.
- **`assets/fallowrc.example.json`** — sane fallow ignores for the TS scan.

## The stack (language-agnostic)

| Guardrail | Python | TS/JS | Rust | Catches the slop symptom |
|---|---|---|---|---|
| **Format** | ruff format | prettier | rustfmt | inconsistent style (auto-fixed) |
| **Lint** | ruff | eslint | clippy | error-prone patterns, unused code |
| **Type-check** | mypy | tsc `--noEmit` | (clippy/`cargo check`) | hallucinated APIs, wrong shapes |
| **Static analysis** | skylos | fallow | clippy lints | dead code, complexity, clones, secrets, AI regressions |
| **Test + coverage** | pytest `--cov` | vitest/jest `--coverage` | cargo test | untested generated code |

Other languages wire the same categories (golangci-lint + gofmt, …). skylos/fallow are the worked examples here — substitute your project's scanner; the *pattern* is what matters.

## The architecture: one definition, three callers

The checks are defined **once**, in a **`justfile`**. Everything else just calls those recipes, so local and CI run identical commands with the project's own pinned tools — parity is structural, not maintained.

- **`just verify`** = `format-check` + `lint` + `typecheck` + `test` (+coverage). The full gate.
- **`just fix`** = auto-format + lint-`--fix`. The fast pre-commit layer.

Three callers, earliest first:

1. **pre-commit** (lefthook) — fast **auto-fixers** on *staged files* (format, lint `--fix`) + the staged-file static scan. Fixes what it can; kept fast so nobody reaches for `--no-verify`.
2. **pre-push** (lefthook) — runs **`just verify`**: the whole-project gate (type-check + tests + coverage can't be scoped to staged files, so they belong here, not on every commit). Catches slop **before it leaves your machine**, for humans and Claude alike.
3. **CI required check** — runs the **same `just verify`** as the unbypassable backstop. Local hooks can be skipped (`--no-verify`, `lefthook install` not run); a required status check / merge restriction cannot.

Because pre-push and CI invoke the *identical* `just verify`, "passed locally → passes in CI" holds by construction. Prove the hooks actually fire (a hook that doesn't fail on bad input is not a hook) with the **`quality-verify-hook`** skill.

> **Why lefthook + just, not the pre-commit framework:** the pre-commit framework installs tools into its own pinned envs, which can drift from the versions CI uses — the exact "passed locally, failed in CI" failure we're killing. `just`-calls-`uvx`/`pnpm`/`cargo` uses the project's pinned tools everywhere. And whole-project checks (typecheck, full test suite) don't fit pre-commit's per-file model. lefthook (fast, parallel, language-agnostic, single binary) dispatches stages and calls the shared `just` recipes — the right tool for this shape.

## Why

**Real working setup.** skylos's `agent pre-commit` mode is built for AI-assisted development — it scans staged files for AI-introduced regressions (security, secrets, prompt-injection, dependency hallucinations); fallow does the equivalent for TS/JS. The gap that motivated all this: a cleanup regressed on a `merge` because the local hook never fired on that path. The fix that actually closes it is the **CI required check** running `just verify` — the merge can't complete until it's green — backed by lefthook catching it earlier on commit/push.

## How to apply

### Install the stack

1. Copy `assets/justfile` and `assets/lefthook.yml` to the repo root.
2. Adjust both to the project's languages: the recipes auto-detect Python (`pyproject.toml`), TS/JS (`package.json`), and Rust (`Cargo.toml`); delete the language commands you don't use, fix the TS scan dir/glob in `lefthook.yml`, and point `test` at your runner. The tools need their config present — `ruff`/`mypy` read `pyproject.toml`, `eslint`/`tsc` need their configs, `clippy`/`rustfmt` read `Cargo.toml`, `prettier` is configless by default.
   - **Subdir / monorepo layout (no root manifest):** the justfile's `[ -f pyproject.toml ]` guards check the *repo root*. If code lives in subdirs (each with its own manifest) and there's no root one, the guards are false and `just verify` **silently passes without checking anything** — the no-op gate this stack exists to prevent. Edit the recipes to `cd` into each subdir, then **run `quality-verify-hook`**, which stages a known-bad fixture and will catch a recipe that no-ops instead of failing.
3. Install the tools once and enable the hooks:
   ```bash
   brew install just lefthook   # or: cargo install just; npm i -D lefthook
   lefthook install             # wires .git/hooks → lefthook
   ```
   Add these to the project README so contributors do the same.
4. Add the CI backstop and make it a required check — this is the parity anchor and the only truly unbypassable layer. Pick the one matching the repo's host (or both, if you mirror):
   - **GitHub:** copy `assets/ci-github.yml` → `.github/workflows/ci.yml`, then mark the `ci` job a **required status check** in branch protection.
   - **Bitbucket:** copy `assets/bitbucket-pipelines.yml` → `bitbucket-pipelines.yml`, then require the pipeline / add a merge check in **Branch restrictions** on `dev` and `main`.
   Both run the identical `just verify`.
5. Document the rules in the project `CLAUDE.md`:
   > **Quality stack:** `lefthook` runs auto-fixers on commit and `just verify` on push; CI runs the same `just verify`. Don't bypass with `--no-verify`. Suppressions require an inline rationale — see the `suppression-discipline` skill.

### After installing — verify

- **Run `quality-verify-hook`** immediately. It stages a known-bad fixture and asserts the hook fails — the only way to know a silently-misconfigured gate isn't waving everything through.
- For the standing rule on suppressions (every `# skylos: ignore` / `# noqa` / `// eslint-disable` / `#[allow(...)]` carries a rationale), see **`suppression-discipline`**.

## Litmus

The pre-push hook and the CI required check run the byte-identical `just verify` with the project's own pinned tools, and `quality-verify-hook` confirms the scan hooks actually fail on bad input — so a green local push genuinely predicts a green CI, and a "Passed" hook genuinely means scanned.

## Related

- `quality-verify-hook` — prove the installed hooks actually fire (run it right after install).
- `suppression-discipline` — the standing rule that every static-analysis ignore carries an inline rationale.
- `project-structure` — the layout this tooling assumes (`src/`, root manifest, `justfile`, `lefthook.yml`).
