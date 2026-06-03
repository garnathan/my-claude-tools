#!/usr/bin/env python3
"""Manual feature ship script — write shipped.md + regenerate the dashboard.

Use this to mark a feature shipped if the interactive workflow didn't complete.
It creates a minimal shipped.md and regenerates DASHBOARD.md. It does NOT merge
a PR or touch git history — do that via /feature-ship (provider-aware) or by hand.

Usage:
    python3 ship_feature.py <project_root> <feature_id> [summary]

Example:
    python3 ship_feature.py /path/to/project my-feature "Implemented the feature"
"""

import sys
from datetime import date
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: ship_feature.py <project_root> <feature_id> [summary]")
        print('Example: ship_feature.py /path/to/project my-feature "Implemented the feature"')
        return 1

    project_root = Path(sys.argv[1])
    feature_id = sys.argv[2]
    summary = sys.argv[3] if len(sys.argv) > 3 else "Feature completed"

    feature_dir = project_root / "docs" / "features" / feature_id
    shipped_file = feature_dir / "shipped.md"
    idea_file = feature_dir / "idea.md"

    if not feature_dir.is_dir():
        print(f"Error: Feature directory not found: {feature_dir}")
        return 1
    if not idea_file.exists():
        print("Error: idea.md not found — this doesn't appear to be a valid feature")
        return 1
    if shipped_file.exists():
        print(f"Feature already has shipped.md. To re-ship, delete {shipped_file} first.")
        return 1

    # Pull the feature name from idea.md frontmatter (best-effort).
    feature_name = feature_id
    try:
        for line in idea_file.read_text().split("\n"):
            if line.startswith("name:"):
                feature_name = line.split(":", 1)[1].strip()
                break
    except Exception:
        pass

    today = date.today().isoformat()
    print(f"[ship] Creating shipped.md for: {feature_id}")
    shipped_file.write_text(
        f"""---
shipped: {today}
---

# Shipped: {feature_name}

## Summary
{summary}

## Notes
Marked as shipped via the manual ship script.
"""
    )
    print(f"[ship] Created: {shipped_file}")

    # Regenerate the dashboard from the shared engine.
    print("[ship] Regenerating DASHBOARD.md...")
    try:
        lib_dir = Path(__file__).resolve().parent.parent.parent / "shared" / "lib"
        if str(lib_dir) not in sys.path:
            sys.path.insert(0, str(lib_dir))
        from run_dashboard import generate_dashboard
        generate_dashboard(project_root)
    except Exception as e:
        print(f"[ship] Warning: Dashboard regeneration failed: {e}")

    print(f"[ship] Feature shipped: {feature_id}")
    print("")
    print("Next steps:")
    print(f"  1. Review {shipped_file} and add detail if needed")
    print(f'  2. Commit: git add docs/features/ && git commit -m "Ship: {feature_name}"')
    return 0


if __name__ == "__main__":
    sys.exit(main())
