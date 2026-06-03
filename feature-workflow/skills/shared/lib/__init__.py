"""Shared library for feature-workflow plugin.

This module provides common utilities for:
- Dashboard generation from feature directories
- YAML frontmatter parsing
- Feature status models
- Provider-agnostic review resolution
"""

from .models import FeatureStatus, FeatureContext
from .frontmatter import parse_frontmatter
from .run_dashboard import generate_dashboard
from .review_resolve import resolve_review, ReviewDecision, ReviewMode, ReviewProvider

__all__ = [
    "FeatureStatus",
    "FeatureContext",
    "parse_frontmatter",
    "generate_dashboard",
    "resolve_review",
    "ReviewDecision",
    "ReviewMode",
    "ReviewProvider",
]
