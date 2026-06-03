---
name: quality-verify-hook
description: Verify that a project's static-analysis git hooks actually fire on bad code — works with lefthook or the pre-commit framework. Use after installing the quality stack (lefthook install), after editing lefthook.yml / .pre-commit-config.yaml, after upgrading a scanner, or whenever the user asks "is the hook working?" / "test the hooks" / "verify hooks". Stages a known-bad fixture and asserts a non-zero exit; stages a known-good fixture and asserts exit 0. Litmus: a hook that doesn't fail on a known-bad input is not a hook — prove it fails before you trust it.
allowed-tools: Read, Bash
---

# quality-verify-hook — prove the git hooks actually fire

A hook can be configured to scan zero files (wrong path argument), to silently skip (broken interpreter or missing tool), or to find findings but never fail. None of those show up in normal commits — the user sees "Passed" every time and assumes the hook works, until a manual audit reveals a grade of F. **Hook silence ≠ hook working.** This skill is the safety net: stage a deliberate violation, run the hook, assert it fails; then a clean file, assert it passes.

In this skill's directory:

1. **`assets/verify_hook.py`** — the shipped verifier (stdlib-only, zero-dependency, manager-agnostic). Runnable as a CLI; locates its own fixtures and infers the fixture pair from the hook id. Also importable as a library (`verify_hook(...)` → `VerifyResult`).
2. **`assets/fixtures/`** — known-bad/good fixture pairs: `skylos-bad.py`/`skylos-good.py` (Python complexity) and `fallow-bad.ts`/`fallow-good.ts` (TS complexity). Add a pair to support a new scanner.

## Step 1 — Detect the hook manager and the scan hooks

```bash
ls lefthook.yml lefthook.yaml .pre-commit-config.yaml 2>/dev/null
```

- `lefthook.yml` / `lefthook.yaml` present → **lefthook** (the static-scan commands live under `pre-commit:`, typically `py-scan` for skylos and `ts-scan` for fallow). Read it: `cat lefthook.yml`.
- only `.pre-commit-config.yaml` → **pre-commit framework** (hook IDs like `skylos-agent`, `fallow-audit-*`). Read it: `cat .pre-commit-config.yaml`.

The verifier auto-detects the same way (lefthook preferred, then pre-commit), so you don't pass the manager explicitly unless you want to force it.

If neither exists, tell the user:
> "No `lefthook.yml` or `.pre-commit-config.yaml` found — the quality stack isn't installed. The quickest path is the **`quality-stack-setup`** skill, which drops in `lefthook.yml` + `justfile`. Then `brew install just lefthook && lefthook install` and re-run this skill."

| Hook runs… | Typical ID (lefthook / pre-commit) | Fixture pair (inferred automatically) |
|---|---|---|
| `skylos` | `py-scan` / `skylos-agent` | `skylos-bad.py` + `skylos-good.py` |
| `fallow audit` | `ts-scan` / `fallow-audit-*` | `fallow-bad.ts` + `fallow-good.ts` |

If a hook runs a tool there's no fixture for, the verifier prints "no fixture inferred — skipping". Don't make one up; add a real fixture pair instead (see Extending, below).

## Step 2 — Run the verifier

The script is at `assets/verify_hook.py` *in this skill's directory*. Run it from the project root, passing the hook/command IDs to check. The fixture pair is inferred from each id (`py-scan`/`skylos…` → skylos; `ts-scan`/`fallow…` → fallow), or force it with `--tool`:

```bash
# from the project being verified; SKILL_DIR = this skill's directory
python3 "$SKILL_DIR/assets/verify_hook.py" py-scan ts-scan
# force a fixture pair, or point at your own fixtures:
python3 "$SKILL_DIR/assets/verify_hook.py" my-scan --tool skylos
python3 "$SKILL_DIR/assets/verify_hook.py" my-scan --bad path/to/bad.ext --good path/to/good.ext
```

It stages each fixture under `.quality-verify/`, runs the hook (`lefthook run pre-commit --commands <id>` or `pre-commit run <id>`), checks the exit code, and reverts the tree. Exit 0 iff every hook fired on bad and passed on good.

(To drive it programmatically instead, import it: `from verify_hook import verify_hook` after adding `assets/` to `sys.path`; it returns a `VerifyResult` with `.ok`, `.bad_passed`, `.good_passed`, `.bad_exit_code`, `.error`.)

## Step 3 — Interpret the result

| Result | Meaning | Action |
|---|---|---|
| `ok` / both ✅ | Fires on bad, passes on good — working | "✅ `<id>` verified." |
| bad **NOT caught** | Accepted a known violation — **silently broken** | "❌ `<id>` did NOT fail on the known-bad fixture. Misconfigured — likely a wrong glob/path, a missing tool, or the wrong command. This is the exact silent-misconfig class this skill exists to catch." |
| good **rejected** | Failed on clean input — overzealous | "⚠️ `<id>` failed on the known-good fixture. The fixture drifted, or thresholds are too tight." |
| `error` set | Verification itself failed | Report verbatim. Common: the manager binary missing (`brew install lefthook`) or a tool dep absent (`uvx` / `npx`). |

## Step 4 — Refuse to consider hooks "installed" until they pass

If any hook fails verification, surface the verifier's banner and stop:

```
⚠️ Git hooks NOT VERIFIED — fix the configuration and re-run before trusting them.
```

Until fixed, commits/pushes will *appear* to pass but may not actually be scanned. Edit `lefthook.yml` (or `.pre-commit-config.yaml`), re-run, fix until every hook reports OK.

## Step 5 — Cleanup spot-check

The verifier reverts the working tree on its own, but confirm:

```bash
git status --short
```

If anything unexpected remains (a leftover staged fixture, a `.quality-verify/` dir), surface it but DO NOT auto-clean — the user may want to inspect.

## When to run

- **After `lefthook install`** (or `pre-commit install`) — first-time setup.
- **After editing `lefthook.yml` / `.pre-commit-config.yaml`** — any change to a command's glob or args.
- **After upgrading a scanner** (skylos/fallow/etc.) — tool versions can shift exit-code semantics.
- **In CI** — wire it in for ongoing assurance that the gate still bites.

## Extending to a new scanner

Add a `<name>-bad.<ext>` / `<name>-good.<ext>` pair under `assets/fixtures/`, then add a row to `_FIXTURE_PAIRS` (and, if the id won't infer cleanly, the `_infer_tool` map) in `assets/verify_hook.py`. The bad fixture must contain a violation the scanner is configured to fail on; the good one must be clean.

## Notes

- **Idempotent** and **non-destructive** — always cleans up; re-running is safe.
- This verifies the **scan** hooks that BLOCK on findings (skylos/fallow/etc.). The pre-commit *fixers* (format, lint `--fix`) auto-fix rather than fail, so they aren't verified this way; the full `just verify` (lint/typecheck/test) is verified by CI running the identical recipe — see `quality-stack-setup`.

## Litmus

Every blocking scan hook has been shown to exit non-zero on a known-bad input and zero on a known-good one — so "Passed" on a real commit means *scanned and clean*, not *silently skipped*.
