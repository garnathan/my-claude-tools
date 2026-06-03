"""Resolve the effective review decision for a feature — provider-agnostic.

Pure function, no I/O. The caller reads the project's `.feature-workflow.yml`
(`review.mode` + `review.provider`) and the feature's `idea.md` (`review:`),
and this module decides *how* the feature gets reviewed.

Two orthogonal axes:

  mode      WHO performs the review
            - internal : a local Claude subagent runs templates/review-prompt-*.md
                         and posts the verdict (no CI, no API keys, works anywhere)
            - external : an external CI bot reviews (GitHub Actions / Bitbucket
                         Pipelines / OCI DevOps). A documented extension point —
                         the skills describe how to wire it; nothing here assumes it.
            - skip     : no review (doc fixes, typo corrections)

  provider  WHERE the PR + review comments live
            - github    : gh CLI
            - bitbucket : bitbucket CLI / REST
            - none      : no PR; review (if any) is recorded only in the
                          feature's reviews/review-status.md side-channel

Precedence for mode:
    1. Feature's `review:` frontmatter (if set and recognized)
    2. Project's `review.mode` config
    3. INTERNAL (review by default — the local reviewer needs no setup)

Nothing in this module is GitHub-specific. The original plugin hard-coded
Gemini/Codex CI modes here; this seam replaces that with the two clean axes
above so the same lifecycle works on GitHub, Bitbucket, or no remote at all.
"""

import sys
from dataclasses import dataclass
from enum import Enum
from typing import Optional


class ReviewMode(Enum):
    """WHO reviews."""

    INTERNAL = "internal"
    EXTERNAL = "external"
    SKIP = "skip"


class ReviewProvider(Enum):
    """WHERE the PR + review live."""

    GITHUB = "github"
    BITBUCKET = "bitbucket"
    NONE = "none"


@dataclass(frozen=True)
class ReviewDecision:
    """The resolved review channel for a feature/phase."""

    mode: ReviewMode
    provider: ReviewProvider

    @property
    def runs(self) -> bool:
        """True if a review actually happens (mode is not skip)."""
        return self.mode != ReviewMode.SKIP

    @property
    def posts_to_pr(self) -> bool:
        """True if the verdict is posted on a PR (vs. only the side-channel file)."""
        return self.runs and self.provider != ReviewProvider.NONE


_FEATURE_VALUES = {"internal", "external", "skip"}
_MODE_VALUES = {"internal", "external", "skip"}
_PROVIDER_VALUES = {"github", "bitbucket", "none"}

_DEFAULT_MODE = ReviewMode.INTERNAL
_DEFAULT_PROVIDER = ReviewProvider.GITHUB


def resolve_review(
    feature_review: Optional[str],
    project_mode: Optional[str],
    project_provider: Optional[str],
) -> ReviewDecision:
    """Compute the effective review decision (mode + provider)."""
    f = (feature_review or "").strip().lower()
    pm = (project_mode or "").strip().lower()
    pp = (project_provider or "").strip().lower()

    # Provider comes from project config only (a feature doesn't move its own PR host).
    provider = ReviewProvider(pp) if pp in _PROVIDER_VALUES else _DEFAULT_PROVIDER

    # Mode: feature override wins if recognized; else project default; else INTERNAL.
    if f in _FEATURE_VALUES:
        mode = ReviewMode(f)
    else:
        if f:
            print(
                f"[review_resolve] Unknown feature review value '{feature_review}', "
                "falling back to project default",
                file=sys.stderr,
            )
        mode = ReviewMode(pm) if pm in _MODE_VALUES else _DEFAULT_MODE

    return ReviewDecision(mode=mode, provider=provider)
