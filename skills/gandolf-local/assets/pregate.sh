#!/usr/bin/env bash
#
# pregate.sh — the deterministic half of the local gandolf gate.
#
# Runs the checks a machine can decide, before any language model is spent on the
# change. Order matters: clippy answers in seconds what a reviewer would take
# minutes to notice, and the four reviewers are the expensive part of the gate.
#
# Every check here mirrors one that blocks a merge in CI, so a clean run means
# the corresponding CI job will also be clean:
#
#   Rule 0 no-AI-attribution      compliance.yml  "No AI-attributed commit author"
#   compliance.py                 compliance.yml  "CLAUDE.md rule compliance"
#   env_defaults.py               compliance.yml  "Documented-vs-shipped env defaults"
#   test_env_defaults.py          compliance.yml  "Env-default extractor shape tests"
#   make lint (clippy)            clippy.yml      "Static analysis"
#   make shear (unused deps)      clippy.yml      "Static analysis"
#   cargo check / cargo test      ci.yml          build-and-test, scoped to touched crates
#
#   pregate.sh [--base <ref>] [--quick] [--no-test] [--report <file>]
#
#     --base <ref>   Compare against this ref. Default: origin/main.
#     --quick        Skip clippy, shear, and the tests. Keeps the build-free
#                    checks, which take seconds.
#     --no-test      Run clippy and shear, skip cargo test.
#     --report <f>   Append a markdown summary to this file.
#
# Exit status: 0 when every check that ran passed, 1 when any failed, 2 on a
# usage error. A check that cannot run (a tool missing, a path absent) is
# reported as SKIPPED and does not pass the gate silently — the summary names it.
#
# Written for bash 3.2, which is what macOS ships.

set -uo pipefail

BASE_REF="origin/main"
QUICK=0
RUN_TEST=1
REPORT=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --base)    BASE_REF="${2:-}"; [ -n "$BASE_REF" ] || { echo "--base needs a ref" >&2; exit 2; }; shift 2 ;;
        --quick)   QUICK=1; RUN_TEST=0; shift ;;
        --no-test) RUN_TEST=0; shift ;;
        --report)  REPORT="${2:-}"; [ -n "$REPORT" ] || { echo "--report needs a path" >&2; exit 2; }; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *)         echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not inside a git work tree" >&2; exit 2; }
cd "$TOP" || exit 2

# Resolve the comparison base. A missing origin/main is a hard stop rather than a
# fallback to HEAD: comparing a branch against itself yields an empty diff, which
# would report a clean gate over unreviewed work.
if ! BASE_SHA="$(git rev-parse --verify --quiet "$BASE_REF^{commit}")"; then
    echo "cannot resolve base ref '$BASE_REF' — fetch it first (git fetch origin main)" >&2
    exit 2
fi
MERGE_BASE="$(git merge-base "$BASE_SHA" HEAD 2>/dev/null)" || MERGE_BASE="$BASE_SHA"

CHANGED="$(git diff --name-only "$MERGE_BASE" HEAD 2>/dev/null)"

# ── result accounting ────────────────────────────────────────────────────────
# Parallel newline-delimited lists rather than an associative array: bash 3.2 has
# no `declare -A`.
PASSED=""; FAILED=""; SKIPPED=""
# Absolute — see the note in review.sh: `--git-common-dir` is relative in a main
# clone, and a relative log path in a printed failure message is useless to anyone
# reading it from elsewhere.
LOGDIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)/gandolf-local/pregate"
mkdir -p "$LOGDIR"

record() {  # record <status> <name>
    case "$1" in
        pass) PASSED="${PASSED}$2
" ;;
        fail) FAILED="${FAILED}$2
" ;;
        skip) SKIPPED="${SKIPPED}$2
" ;;
    esac
}

say() { printf '%s\n' "$*"; }

# run_check <name> <logfile> <command...>
# Streams nothing; keeps the output in the log so a failure can be quoted exactly.
run_check() {
    local name="$1" log="$2"; shift 2
    printf '  %-46s' "$name"
    if "$@" >"$log" 2>&1; then
        say "PASS"
        record pass "$name"
        return 0
    fi
    say "FAIL"
    record fail "$name"
    say ""
    say "    ── $name — last 25 lines of $log ──"
    tail -25 "$log" | sed 's/^/    /'
    say ""
    return 1
}

say "gandolf-local deterministic pre-gate"
say "  base            $BASE_REF ($(git rev-parse --short "$MERGE_BASE"))"
say "  head            $(git rev-parse --short HEAD)"
say "  changed files   $(printf '%s' "$CHANGED" | grep -c . || true)"
say ""

# ── Rule 0: no AI attribution on any commit being pushed ─────────────────────
# The CI script deliberately reads the pull request's commit list from the GitHub
# API, because that is the exact set the merge-queue squash collects authors from.
# There is no pull request yet here, so walk the local range instead. Same rule,
# earlier: catch it while the commits can still be amended cheaply.
AI_RE='claude|anthropic|\[bot\]'
rule0_check() {
    local bad=0 line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if printf '%s' "$line" | grep -qiE "$AI_RE"; then
            echo "AI identity on commit: $line"
            bad=1
        fi
    done <<EOF
$(git log --format='%H author=%an <%ae> committer=%cn <%ce>' "$MERGE_BASE..HEAD" 2>/dev/null)
EOF
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if printf '%s' "$line" | grep -qiE "$AI_RE"; then
            echo "AI co-author trailer: $line"
            bad=1
        fi
    done <<EOF
$(git log --format='%H %(trailers:key=Co-authored-by,valueonly)' "$MERGE_BASE..HEAD" 2>/dev/null | grep -i 'co\|claude\|anthropic' || true)
EOF
    # The generated-with marker is forbidden in the message body as well.
    if git log --format='%B' "$MERGE_BASE..HEAD" 2>/dev/null \
        | grep -qiE 'generated with .*claude|claude\.com/claude-code|co-authored-by:.*(claude|anthropic|noreply@anthropic)'; then
        echo "commit message body carries an AI attribution marker"
        bad=1
    fi
    return "$bad"
}
run_check "Rule 0 — no AI attribution on commits" "$LOGDIR/rule0.log" rule0_check

# ── DFL-specific checks ──────────────────────────────────────────────────────
if [ ! -f "dfl/Makefile" ]; then
    say ""
    say "  not the DFL workspace (no dfl/Makefile) — DFL-specific checks skipped"
    record skip "DFL checks (not the DFL workspace)"
else
    DFL_TOUCHED=0
    printf '%s' "$CHANGED" | grep -q '^dfl/' && DFL_TOUCHED=1

    # The mechanical rule sweep runs whatever changed, including a docs-only or
    # scripts-only change: Rule 0, the error-ID catalogue, and the environment
    # variable documentation duty all live outside dfl/crates.
    BAIT="$(cd "$(dirname "$0")" && pwd)/gandolf-bait.sh"
    if [ -n "$REPORT" ]; then
        run_check "gandolf-bait (rule violations by grep)" "$LOGDIR/bait.log" \
            bash "$BAIT" --base "$BASE_REF" --report "$REPORT"
    else
        run_check "gandolf-bait (rule violations by grep)" "$LOGDIR/bait.log" \
            bash "$BAIT" --base "$BASE_REF"
    fi

    if [ "$DFL_TOUCHED" -eq 0 ]; then
        say "  nothing under dfl/ changed — DFL build gates skipped"
        record skip "DFL build gates (no dfl/ change)"
    else
        # Build-free, a few seconds each. Always worth running.
        run_check "compliance.py (env vars, dep hoist)" "$LOGDIR/compliance.log" \
            sh -c 'cd dfl && python3 scripts/ci/compliance.py'
        run_check "env_defaults.py (documented vs shipped)" "$LOGDIR/env_defaults.log" \
            sh -c 'cd dfl && python3 scripts/ci/env_defaults.py'
        run_check "test_env_defaults.py (extractor shape)" "$LOGDIR/test_env_defaults.log" \
            sh -c 'cd dfl && python3 scripts/ci/test_env_defaults.py'

        # Which crates did this change touch? Read the name out of each
        # Cargo.toml rather than assuming it matches the directory.
        CRATES=""
        while IFS= read -r p; do
            [ -z "$p" ] && continue
            case "$p" in
                dfl/crates/*)
                    d="$(printf '%s' "$p" | cut -d/ -f3)"
                    mani="dfl/crates/$d/Cargo.toml"
                    if [ -f "$mani" ]; then
                        n="$(grep -m1 '^name *= *"' "$mani" | sed 's/.*"\(.*\)".*/\1/')"
                        [ -n "$n" ] && CRATES="${CRATES}${n}
"
                    fi
                    ;;
            esac
        done <<EOF
$CHANGED
EOF
        CRATES="$(printf '%s' "$CRATES" | grep . | sort -u)"

        if [ -z "$CRATES" ]; then
            say "  no crate source changed — clippy, shear and tests skipped"
            record skip "clippy / shear / tests (no crate source change)"
        elif [ "$QUICK" -eq 1 ]; then
            say "  --quick — clippy, shear and tests skipped for: $(printf '%s' "$CRATES" | tr '\n' ' ')"
            record skip "clippy / shear / tests (--quick)"
        else
            # Pin CARGO_TARGET_DIR to this checkout's own target directory. The
            # Makefile otherwise points every clone at ~/.cargo-shared-target,
            # where two worktrees on different branches thrash a path dependency
            # and clippy reports phantom "cannot find function" errors that
            # `cargo test` does not. Pinning here reproduces CI's single-branch
            # build, so a finding is real.
            say ""
            for c in $CRATES; do
                run_check "clippy — $c" "$LOGDIR/clippy-$c.log" \
                    env CARGO_TARGET_DIR="$TOP/dfl/target" \
                    make -C dfl lint CRATE="$c"
            done

            run_check "cargo-shear (unused dependencies)" "$LOGDIR/shear.log" \
                env CARGO_TARGET_DIR="$TOP/dfl/target" make -C dfl shear

            if [ "$RUN_TEST" -eq 1 ]; then
                for c in $CRATES; do
                    run_check "cargo test — $c" "$LOGDIR/test-$c.log" \
                        env CARGO_TARGET_DIR="$TOP/dfl/target" \
                        cargo test --manifest-path dfl/Cargo.toml -p "$c" --lib
                done
            else
                say "  --no-test — cargo test skipped"
                record skip "cargo test (--no-test)"
            fi
        fi
    fi
fi

# ── summary ──────────────────────────────────────────────────────────────────
n_pass="$(printf '%s' "$PASSED" | grep -c . || true)"
n_fail="$(printf '%s' "$FAILED" | grep -c . || true)"
n_skip="$(printf '%s' "$SKIPPED" | grep -c . || true)"

say ""
say "pre-gate: $n_pass passed, $n_fail failed, $n_skip skipped"
if [ "$n_skip" -gt 0 ]; then
    printf '%s' "$SKIPPED" | grep . | sed 's/^/  skipped: /'
fi
if [ "$n_fail" -gt 0 ]; then
    printf '%s' "$FAILED" | grep . | sed 's/^/  FAILED:  /'
fi

if [ -n "$REPORT" ]; then
    {
        echo "## Deterministic pre-gate"
        echo
        echo "\`$n_pass\` passed, \`$n_fail\` failed, \`$n_skip\` skipped. Logs in \`$LOGDIR\`."
        echo
        if [ "$n_fail" -gt 0 ]; then
            echo "### Failed"
            printf '%s' "$FAILED" | grep . | sed 's/^/- /'
            echo
        fi
        if [ "$n_skip" -gt 0 ]; then
            echo "### Skipped"
            printf '%s' "$SKIPPED" | grep . | sed 's/^/- /'
            echo
        fi
        if [ "$n_pass" -gt 0 ]; then
            echo "### Passed"
            printf '%s' "$PASSED" | grep . | sed 's/^/- /'
            echo
        fi
    } >>"$REPORT"
fi

[ "$n_fail" -eq 0 ]
