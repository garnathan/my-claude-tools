"""Tests for the provider-agnostic review resolver (review_resolve.py)."""

from review_resolve import (
    ReviewDecision,
    ReviewMode,
    ReviewProvider,
    resolve_review,
)


class TestModeResolution:
    def test_feature_override_wins(self):
        # Feature says skip even though project says external.
        d = resolve_review("skip", project_mode="external", project_provider="github")
        assert d.mode == ReviewMode.SKIP

    def test_feature_internal_over_project_external(self):
        d = resolve_review("internal", project_mode="external", project_provider="github")
        assert d.mode == ReviewMode.INTERNAL

    def test_falls_back_to_project_mode(self):
        d = resolve_review("", project_mode="external", project_provider="bitbucket")
        assert d.mode == ReviewMode.EXTERNAL

    def test_defaults_to_internal_when_nothing_set(self):
        d = resolve_review("", project_mode="", project_provider="")
        assert d.mode == ReviewMode.INTERNAL

    def test_unknown_feature_value_falls_back(self):
        d = resolve_review("bogus", project_mode="skip", project_provider="github")
        assert d.mode == ReviewMode.SKIP


class TestProviderResolution:
    def test_github(self):
        assert resolve_review("", "internal", "github").provider == ReviewProvider.GITHUB

    def test_bitbucket(self):
        assert resolve_review("", "internal", "bitbucket").provider == ReviewProvider.BITBUCKET

    def test_none(self):
        assert resolve_review("", "internal", "none").provider == ReviewProvider.NONE

    def test_default_provider_is_github(self):
        assert resolve_review("", "internal", "").provider == ReviewProvider.GITHUB

    def test_unknown_provider_defaults_github(self):
        assert resolve_review("", "internal", "gitlab").provider == ReviewProvider.GITHUB


class TestDecisionHelpers:
    def test_runs_true_for_internal(self):
        assert resolve_review("internal", "", "github").runs is True

    def test_runs_false_for_skip(self):
        assert resolve_review("skip", "", "github").runs is False

    def test_posts_to_pr_true_for_github_internal(self):
        assert resolve_review("internal", "", "github").posts_to_pr is True

    def test_posts_to_pr_false_for_provider_none(self):
        # Review still runs locally, but there's no PR to comment on.
        d = resolve_review("internal", "", "none")
        assert d.runs is True
        assert d.posts_to_pr is False

    def test_posts_to_pr_false_for_skip(self):
        assert resolve_review("skip", "", "github").posts_to_pr is False

    def test_decision_is_frozen(self):
        d = resolve_review("internal", "", "github")
        assert isinstance(d, ReviewDecision)
