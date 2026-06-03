#!/usr/bin/env python3
"""Self-verification for git hooks — manager-agnostic, zero-dependency (stdlib only).

The "hook silence ≠ hook working" lesson, codified. Given a hook ID, this
module copies a known-bad fixture into a temp staged location, runs the
project's hook (via whichever manager is wired — lefthook or the pre-commit
framework), and asserts a non-zero exit. Then a known-good fixture, asserts
exit 0. Always reverts the working tree.

A hook that doesn't fail on the bad fixture isn't a hook — it's a placebo.

Manager detection (override with `manager=` / `--manager`):
  lefthook.yml / lefthook.yaml present → "lefthook"   → `lefthook run pre-commit --commands <id>`
  .pre-commit-config.yaml present      → "pre-commit"  → `pre-commit run <id>`

CLI:
  python3 verify_hook.py py-scan                 # infer fixtures (py-scan/skylos → skylos pair)
  python3 verify_hook.py ts-scan --tool fallow   # force the fixture pair
  python3 verify_hook.py py-scan ts-scan         # verify several hooks
  python3 verify_hook.py --bad path/to/bad.py --good path/to/good.py my-hook
Fixtures default to this script's sibling `fixtures/` directory.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class VerifyResult:
    """Outcome of a hook verification round."""

    hook_id: str
    bad_passed: bool  # True if the bad fixture correctly triggered a non-zero exit
    good_passed: bool  # True if the good fixture correctly triggered exit 0
    manager: str = ""  # which hook manager was used ("lefthook" / "pre-commit")
    bad_stdout: str = ""
    bad_stderr: str = ""
    good_stdout: str = ""
    good_stderr: str = ""
    bad_exit_code: int = 0
    good_exit_code: int = 0
    error: Optional[str] = None  # non-empty if the verification itself failed

    @property
    def ok(self) -> bool:
        """True iff both phases behaved as expected."""
        return self.bad_passed and self.good_passed and self.error is None


def detect_manager(project_root: Path, override: Optional[str] = None) -> str:
    """Resolve which git-hook manager the project uses.

    Explicit `override` wins. Otherwise lefthook is preferred (the current
    standard), then the pre-commit framework. Raises FileNotFoundError if
    neither is configured.
    """
    if override:
        return override
    if (project_root / "lefthook.yml").exists() or (project_root / "lefthook.yaml").exists():
        return "lefthook"
    if (project_root / ".pre-commit-config.yaml").exists():
        return "pre-commit"
    raise FileNotFoundError(
        "no hook manager found (looked for lefthook.yml / .pre-commit-config.yaml)"
    )


def verify_hook(
    hook_id: str,
    project_root: Path,
    bad_fixture: Path,
    good_fixture: Path,
    *,
    manager: Optional[str] = None,
    staged_target: Optional[Path] = None,
    timeout: int = 60,
) -> VerifyResult:
    """Verify that `hook_id` fails on bad_fixture and passes on good_fixture.

    Args:
        hook_id: the hook/command ID to run. For lefthook this is the command
            name under `pre-commit:` (e.g. "py-scan", "ts-scan"); for the
            pre-commit framework it's the hook ID (e.g. "skylos-agent").
        project_root: the repo where the hooks are installed
        bad_fixture: path to a file with a deliberate violation
        good_fixture: path to a file with no violations
        manager: force "lefthook" or "pre-commit"; auto-detected if None
        staged_target: optional path inside project_root where the fixture
            should be staged (defaults to `<project_root>/.quality-verify/<basename>`)
        timeout: per-phase subprocess timeout

    Returns:
        VerifyResult. Caller checks `result.ok` for the overall outcome.
    """
    if staged_target is None:
        staged_target = project_root / ".quality-verify" / bad_fixture.name

    result = VerifyResult(hook_id=hook_id, bad_passed=False, good_passed=False)

    try:
        resolved_manager = detect_manager(project_root, manager)
        result.manager = resolved_manager

        # Phase 1: bad fixture should make the hook fail
        staged_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(bad_fixture, staged_target)
        _stage(staged_target, project_root)
        bad_run = _run_hook(hook_id, project_root, manager=resolved_manager, timeout=timeout)
        result.bad_exit_code = bad_run.returncode
        result.bad_stdout = bad_run.stdout
        result.bad_stderr = bad_run.stderr
        result.bad_passed = bad_run.returncode != 0  # any non-zero = caught the violation
        _unstage_and_remove(staged_target, project_root)

        # Phase 2: good fixture should make the hook pass
        good_target = staged_target.parent / good_fixture.name
        shutil.copy2(good_fixture, good_target)
        _stage(good_target, project_root)
        good_run = _run_hook(hook_id, project_root, manager=resolved_manager, timeout=timeout)
        result.good_exit_code = good_run.returncode
        result.good_stdout = good_run.stdout
        result.good_stderr = good_run.stderr
        result.good_passed = good_run.returncode == 0
        _unstage_and_remove(good_target, project_root)

        # Clean up the staged dir if empty
        try:
            staged_target.parent.rmdir()
        except OSError:
            pass

    except subprocess.TimeoutExpired:
        result.error = f"hook {hook_id} timed out after {timeout}s"
    except FileNotFoundError as e:
        result.error = f"required tool missing: {e}"
    except Exception as e:  # noqa: BLE001 — surface anything else to the caller
        result.error = f"verification error: {e}"

    return result


def _stage(path: Path, project_root: Path) -> None:
    """git add <path> relative to project_root."""
    subprocess.run(
        ["git", "add", "--", str(path.relative_to(project_root))],
        cwd=project_root,
        check=False,
        capture_output=True,
    )


def _unstage_and_remove(path: Path, project_root: Path) -> None:
    """Unstage and delete the file. Best-effort; safe if file already gone."""
    try:
        subprocess.run(
            ["git", "reset", "HEAD", "--", str(path.relative_to(project_root))],
            cwd=project_root,
            check=False,
            capture_output=True,
        )
    except Exception:
        pass
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def _run_hook(
    hook_id: str, project_root: Path, *, manager: str, timeout: int
) -> subprocess.CompletedProcess:
    """Run the project's hook against the currently-staged files.

    lefthook:   `lefthook run pre-commit --commands <id>`
    pre-commit: `pre-commit run <id>`
    """
    if manager == "lefthook":
        cmd = ["lefthook", "run", "pre-commit", "--commands", hook_id]
    elif manager == "pre-commit":
        cmd = ["pre-commit", "run", hook_id]
    else:
        raise ValueError(f"unknown hook manager: {manager!r}")
    return subprocess.run(
        cmd,
        cwd=project_root,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


# --------------------------------------------------------------------------- CLI

# Fixture pairs shipped alongside this script. Add a row when you add a scanner.
_FIXTURE_PAIRS = {
    "skylos": ("skylos-bad.py", "skylos-good.py"),
    "fallow": ("fallow-bad.ts", "fallow-good.ts"),
}


def _infer_tool(hook_id: str) -> Optional[str]:
    """Best-effort map from a hook id to a shipped fixture pair."""
    h = hook_id.lower()
    if "skylos" in h or h.startswith("py") or "python" in h:
        return "skylos"
    if "fallow" in h or h.startswith("ts") or h.startswith("js") or "fallow" in h:
        return "fallow"
    return None


def _fixtures_for(tool: str, fixtures_dir: Path) -> tuple[Path, Path]:
    bad_name, good_name = _FIXTURE_PAIRS[tool]
    return fixtures_dir / bad_name, fixtures_dir / good_name


def main(argv: Optional[list[str]] = None) -> int:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Verify git hooks actually fire on bad code.")
    parser.add_argument("hook_ids", nargs="+", help="hook/command IDs to verify (e.g. py-scan ts-scan)")
    parser.add_argument("--tool", choices=sorted(_FIXTURE_PAIRS), help="force the fixture pair (else inferred from the hook id)")
    parser.add_argument("--bad", type=Path, help="explicit known-bad fixture (overrides --tool)")
    parser.add_argument("--good", type=Path, help="explicit known-good fixture (overrides --tool)")
    parser.add_argument("--manager", choices=["lefthook", "pre-commit"], help="force the hook manager (else auto-detected)")
    parser.add_argument("--project-root", type=Path, default=Path("."), help="repo root (default: cwd)")
    parser.add_argument("--fixtures-dir", type=Path, default=script_dir / "fixtures", help="where the fixture pairs live")
    args = parser.parse_args(argv)

    project_root = args.project_root.resolve()
    all_ok = True

    for hook_id in args.hook_ids:
        if args.bad and args.good:
            bad, good = args.bad, args.good
        else:
            tool = args.tool or _infer_tool(hook_id)
            if tool is None:
                print(f"⚠️  {hook_id}: no fixture inferred — pass --tool or --bad/--good. Skipping.")
                continue
            bad, good = _fixtures_for(tool, args.fixtures_dir)
            if not bad.exists() or not good.exists():
                print(f"⚠️  {hook_id}: fixtures for '{tool}' not found under {args.fixtures_dir}. Skipping.")
                continue

        r = verify_hook(hook_id, project_root, bad, good, manager=args.manager)
        print(f"\n── {hook_id} (manager={r.manager or 'unknown'}) ──")
        if r.error:
            print(f"  ❌ verification error: {r.error}")
            all_ok = False
            continue
        print(f"  bad fixture  → exit {r.bad_exit_code}  ({'caught ✅' if r.bad_passed else 'NOT caught ❌'})")
        print(f"  good fixture → exit {r.good_exit_code}  ({'passed ✅' if r.good_passed else 'rejected ⚠️'})")
        if r.ok:
            print(f"  ✅ {hook_id} verified — fails on known-bad, passes on known-good.")
        else:
            all_ok = False
            if not r.bad_passed:
                print(f"  ❌ {hook_id} did NOT fail on the known-bad fixture — silently broken "
                      "(wrong glob/path, missing tool, or wrong command).")
            if not r.good_passed:
                print(f"  ⚠️  {hook_id} failed on the known-good fixture — fixture drifted or thresholds too tight.")

    if not all_ok:
        print("\n⚠️  Git hooks NOT VERIFIED — fix the configuration and re-run before trusting them.")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
