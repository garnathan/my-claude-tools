#!/usr/bin/env bash
#
# review.sh — a local copy of the gandolf review gate.
#
# In CI the review is claude-code-review.yml, whose whole prompt is "run the
# repo's /full-review skill". About three hundred of that workflow's lines are
# GitHub plumbing — the runner-pool choice, the App token, the rate-limit
# backoff, the once-per-pull-request label. None of it is the review. This script
# is the review, run before a push instead of after one.
#
# Four reviewers, one per lens, as four separate operating-system processes
# rather than four sub-agents inside one session. That is deliberate: the CI
# skill carries a warning that firing sub-agents and then ending the turn kills
# the session with every reviewer still running and nothing posted, which is what
# happened on pull request #11303. Four independent processes cannot fail that
# way, and they are genuinely concurrent.
#
#   review.sh                    Full gate: pre-gate, four reviewers, report.
#   review.sh --check            Is there a valid receipt for this exact tree?
#                                Exit 0 yes, 1 no. Used by the pre-push hook.
#   review.sh --status           Print what the last review decided.
#
#   --base <ref>            Compare against this ref. Default origin/main.
#   --include-worktree      Also review uncommitted changes. Off by default: a
#                           push carries commits, so the hook must judge commits.
#   --quick-pregate         Pass --quick to the pre-gate (skip clippy and tests).
#   --skip-pregate          Skip the deterministic checks entirely.
#   --lens <name>           Run one lens only (code|security|memory|concurrency).
#
# A receipt is written under the repository's git directory, keyed by the hash of
# the diff it reviewed. This is the local counterpart of CI's
# `gandolf-full-reviewed` label, with the flaw removed: that label sticks to a
# pull request across later commits, so a green review can sit over a diff nobody
# read — which is the normal case, because gandolf pushes its own fix commits
# after reviewing. Keying on the content means a receipt stops being valid the
# moment the tree changes.
#
# Written for bash 3.2, which is what macOS ships. There is no `timeout` on
# macOS, so the reviewer deadline is enforced by polling.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LENS_DIR="$HERE/lenses"

MODEL="${GANDOLF_LOCAL_MODEL:-opus}"
REVIEWER_TIMEOUT="${GANDOLF_LOCAL_TIMEOUT:-1800}"
BASE_REF="${GANDOLF_LOCAL_BASE:-origin/main}"
INCLUDE_WORKTREE=0
PREGATE_ARGS=""
RUN_PREGATE=1
MODE="review"
ONLY_LENS=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check)            MODE="check"; shift ;;
        --status)           MODE="status"; shift ;;
        --base)             BASE_REF="${2:-}"; [ -n "$BASE_REF" ] || { echo "--base needs a ref" >&2; exit 2; }; shift 2 ;;
        --include-worktree) INCLUDE_WORKTREE=1; shift ;;
        --quick-pregate)    PREGATE_ARGS="--quick"; shift ;;
        --skip-pregate)     RUN_PREGATE=0; shift ;;
        --lens)             ONLY_LENS="${2:-}"; [ -n "$ONLY_LENS" ] || { echo "--lens needs a name" >&2; exit 2; }; shift 2 ;;
        -h|--help)          sed -n '2,40p' "$0"; exit 0 ;;
        *)                  echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

command -v claude >/dev/null 2>&1 || { echo "gandolf-local: the 'claude' CLI is not on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1     || { echo "gandolf-local: 'jq' is not on PATH" >&2; exit 2; }

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not inside a git work tree" >&2; exit 2; }
cd "$TOP" || exit 2
STATE="$(git rev-parse --git-common-dir)/gandolf-local"
mkdir -p "$STATE/receipts" "$STATE/reports" "$STATE/runs"

# ── what is being reviewed ───────────────────────────────────────────────────
if ! BASE_SHA="$(git rev-parse --verify --quiet "$BASE_REF^{commit}")"; then
    echo "gandolf-local: cannot resolve base ref '$BASE_REF'." >&2
    echo "  Fetch it first:  git fetch origin main" >&2
    exit 2
fi
MERGE_BASE="$(git merge-base "$BASE_SHA" HEAD 2>/dev/null)" || MERGE_BASE="$BASE_SHA"
HEAD_SHA="$(git rev-parse HEAD)"

diff_text() {
    if [ "$INCLUDE_WORKTREE" -eq 1 ]; then
        git diff "$MERGE_BASE"          # committed range plus the dirty tree
    else
        git diff "$MERGE_BASE" HEAD
    fi
}

DIFF_SHA="$(diff_text | shasum -a 256 | cut -d' ' -f1)"
# The base is part of the identity: the same patch reviewed against a different
# base is a different review, because the surrounding code differs.
REVIEW_KEY="$(printf '%s\n%s\n' "$MERGE_BASE" "$DIFF_SHA" | shasum -a 256 | cut -d' ' -f1)"
KEY_SHORT="$(printf '%s' "$REVIEW_KEY" | cut -c1-12)"
RECEIPT="$STATE/receipts/$REVIEW_KEY.json"

# ── --status ─────────────────────────────────────────────────────────────────
if [ "$MODE" = "status" ]; then
    echo "gandolf-local status"
    echo "  base          $BASE_REF ($(git rev-parse --short "$MERGE_BASE"))"
    echo "  head          $(git rev-parse --short "$HEAD_SHA")"
    echo "  review key    $KEY_SHORT"
    if [ -f "$RECEIPT" ]; then
        echo "  receipt       $RECEIPT"
        jq -r '"  verdict       \(.verdict)\n  reviewed at   \(.reviewed_at)\n  blocking      \(.blocking)\n  should_fix    \(.should_fix)\n  report        \(.report)"' "$RECEIPT"
    else
        echo "  receipt       none for this tree — the review has not run on it"
    fi
    exit 0
fi

# ── --check (the hook's question) ────────────────────────────────────────────
if [ "$MODE" = "check" ]; then
    [ -f "$RECEIPT" ] || exit 1
    v="$(jq -r '.verdict // "MISSING"' "$RECEIPT" 2>/dev/null)"
    case "$v" in
        PASS) exit 0 ;;
        "CONDITIONAL PASS")
            if [ "${GANDOLF_LOCAL_STRICT:-0}" = "1" ]; then exit 1; fi
            exit 0 ;;
        *) exit 1 ;;
    esac
fi

# ── full review ──────────────────────────────────────────────────────────────
CHANGED_COUNT="$(git diff --name-only "$MERGE_BASE" HEAD | grep -c . || true)"
if [ "$INCLUDE_WORKTREE" -eq 1 ]; then
    CHANGED_COUNT="$(git diff --name-only "$MERGE_BASE" | grep -c . || true)"
fi
if [ "$CHANGED_COUNT" -eq 0 ]; then
    echo "gandolf-local: nothing changed against $BASE_REF — no review to run."
    exit 0
fi

RUN="$STATE/runs/$KEY_SHORT"
rm -rf "$RUN"; mkdir -p "$RUN"
DIFF_FILE="$RUN/diff.patch"
FILES_FILE="$RUN/files.txt"
PREGATE_REPORT="$RUN/pregate.md"
REPORT="$STATE/reports/$REVIEW_KEY.md"

diff_text >"$DIFF_FILE"
if [ "$INCLUDE_WORKTREE" -eq 1 ]; then
    git diff --name-only "$MERGE_BASE" >"$FILES_FILE"
else
    git diff --name-only "$MERGE_BASE" HEAD >"$FILES_FILE"
fi

echo "gandolf-local — local review gate"
echo "  repository      $TOP"
echo "  base            $BASE_REF ($(git rev-parse --short "$MERGE_BASE"))"
echo "  head            $(git rev-parse --short "$HEAD_SHA")"
echo "  changed files   $CHANGED_COUNT"
echo "  diff            $(wc -l <"$DIFF_FILE" | tr -d ' ') lines → $DIFF_FILE"
echo "  review key      $KEY_SHORT"
echo "  model           $MODEL"
echo ""

# ── stage 1: the deterministic pre-gate ──────────────────────────────────────
PREGATE_OK=1
if [ "$RUN_PREGATE" -eq 1 ]; then
    # shellcheck disable=SC2086
    if bash "$HERE/pregate.sh" --base "$BASE_REF" --report "$PREGATE_REPORT" $PREGATE_ARGS; then
        PREGATE_OK=1
    else
        PREGATE_OK=0
    fi
    echo ""
else
    echo "  (pre-gate skipped)" ; echo "## Deterministic pre-gate" >"$PREGATE_REPORT"
    echo "" >>"$PREGATE_REPORT"; echo "Skipped by \`--skip-pregate\`." >>"$PREGATE_REPORT"
fi

# The pre-gate result does NOT short-circuit the reviewers. A clippy failure and
# a design defect are independent, and the point of running the review before the
# push is to learn about both in one pass rather than fixing lint, pushing, and
# only then hearing about the design.

# ── stage 2: four reviewers, in parallel ─────────────────────────────────────
# Five lenses. The first four are the ones the continuous-integration reviewer
# runs; the fifth predicts that reviewer directly, so a comment it would post has
# a chance of being answered before the pull request exists.
if [ -n "$ONLY_LENS" ]; then
    LENSES="$ONLY_LENS"
else
    LENSES="code security memory concurrency gandolf"
fi

for l in $LENSES; do
    [ -f "$LENS_DIR/$l.md" ] || { echo "gandolf-local: no lens file for '$l'" >&2; exit 2; }
done

# Read-only tool set. No Edit, no Write, no `git commit`, no `gh` — a reviewer
# that can change the code stops being a reviewer, and the CI verify job makes
# the same restriction explicit for the same reason.
REVIEW_TOOLS='Read,Grep,Glob,Bash(git log:*),Bash(git diff:*),Bash(git show:*),Bash(git blame:*),Bash(git rev-parse:*),Bash(rg:*),Bash(grep:*),Bash(ls:*),Bash(cat:*),Bash(sed:*),Bash(wc:*),Bash(find:*)'

build_prompt() {  # build_prompt <lens>
    local lens="$1"
    cat "$LENS_DIR/_common.md"
    echo
    echo '---'
    echo
    cat "$LENS_DIR/$lens.md"
    echo
    echo '---'
    echo
    echo "# This change"
    echo
    echo "Repository root: \`$TOP\` (you are already in it — read any file you need)."
    echo "Base: \`$BASE_REF\` at \`$(git rev-parse --short "$MERGE_BASE")\`. Head: \`$(git rev-parse --short "$HEAD_SHA")\`."
    if [ "$INCLUDE_WORKTREE" -eq 1 ]; then
        echo "The diff includes uncommitted working-tree changes."
    fi
    echo
    echo "- Full diff: \`$DIFF_FILE\`"
    echo "- Changed files: \`$FILES_FILE\`"
    echo
    echo "Read the diff first, then read the surrounding code for every hunk that"
    echo "matters. There is no pull request description to lean on, and no other"
    echo "reviewer's report to see. Emit only the markdown the output format"
    echo "section specifies."
    echo
    # Point every lens at the repository's own reviewer definition rather than at
    # a copy of it. The continuous-integration reviewer's entire prompt is "run
    # the repo's /full-review skill", so that file is the authority on what it
    # looks for; reading it live means this gate tracks any change to it instead
    # of drifting from a paraphrase kept somewhere else.
    if [ -f "$TOP/.claude/skills/full-review/SKILL.md" ]; then
        echo "## The reviewer you are standing in for"
        echo
        echo "Read \`.claude/skills/full-review/SKILL.md\`. That skill *is* the"
        echo "continuous-integration reviewer for this repository — its whole"
        echo "prompt in \`.github/workflows/claude-code-review.yml\` is \"run the"
        echo "repo's /full-review skill\". Find the lens paragraph in it that"
        echo "matches yours and treat it as binding, in addition to the brief"
        echo "above. Where the two differ in scope, cover both."
        echo
    fi
    echo "## Commits in this change"
    echo
    git log --format='- %h %s' "$MERGE_BASE..HEAD" 2>/dev/null | head -40
}

pids=""; names=""
for lens in $LENSES; do
    build_prompt "$lens" >"$RUN/prompt-$lens.md"
    printf '  starting reviewer: %-14s' "$lens"
    # The prompt goes in on standard input, NOT as a positional argument.
    # `--allowedTools` is variadic, so a trailing argument after it is read as one
    # more tool pattern: the whole prompt was consumed as tool names, and every
    # reviewer died instantly on "Input must be provided either through stdin or
    # as a prompt argument". Standard input also removes any argument-length
    # ceiling on a long brief.
    MAX_THINKING_TOKENS=32000 claude -p \
        --model "$MODEL" \
        --allowedTools "$REVIEW_TOOLS" \
        <"$RUN/prompt-$lens.md" \
        >"$RUN/report-$lens.md" 2>"$RUN/stderr-$lens.log" &
    p=$!
    pids="$pids $p"; names="$names $lens"
    echo "pid $p"
done

echo ""
echo "  lenses running concurrently; deadline ${REVIEWER_TIMEOUT}s"
START="$(date +%s)"
while :; do
    live=0
    for p in $pids; do kill -0 "$p" 2>/dev/null && live=$((live + 1)); done
    [ "$live" -eq 0 ] && break
    now="$(date +%s)"
    if [ "$((now - START))" -ge "$REVIEWER_TIMEOUT" ]; then
        echo "  deadline reached with $live reviewer(s) still running — terminating them"
        for p in $pids; do kill -TERM "$p" 2>/dev/null; done
        sleep 5
        for p in $pids; do kill -KILL "$p" 2>/dev/null; done
        break
    fi
    printf '\r  %ds elapsed, %d reviewer(s) running ' "$((now - START))" "$live"
    sleep 5
done
printf '\r%-60s\r' ' '

# Collect each reviewer's status. `wait` still reports it after the process ended.
set -- $names
FAILED_LENSES=""
for p in $pids; do
    lens="$1"; shift
    if wait "$p"; then rc=0; else rc=$?; fi
    if [ "$rc" -ne 0 ] || [ ! -s "$RUN/report-$lens.md" ]; then
        FAILED_LENSES="$FAILED_LENSES $lens"
        echo "  reviewer $lens did not produce a report (exit $rc) — see $RUN/stderr-$lens.log"
    else
        v="$(grep -m1 -oE 'Verdict: *(PASS|CONDITIONAL PASS|FAIL)' "$RUN/report-$lens.md" | sed 's/Verdict: *//')"
        echo "  reviewer $lens: ${v:-no verdict line} ($(wc -l <"$RUN/report-$lens.md" | tr -d ' ') lines)"
    fi
done

# A reviewer that produced nothing is a gate failure, not a pass. This is the
# whole point of CI's reconcile-review.sh: a run that finishes "successfully"
# having posted nothing is indistinguishable from being ignored, and on pull
# request #11139 that produced a green check over a review nobody had done.
if [ -n "$FAILED_LENSES" ]; then
    echo ""
    echo "gandolf-local: FAILED — no report from:$FAILED_LENSES"
    echo "  The gate refuses to record a verdict on a partial review."
    # Trim the leading space the accumulator leaves, or the hint prints a bare
    # `--lens` with no name and cannot be pasted.
    first_failed="$(printf '%s' "$FAILED_LENSES" | tr ' ' '\n' | grep . | head -1)"
    echo "  Re-run, or run one lens to see its error:  review.sh --lens $first_failed"
    echo "  Reviewer stderr: $RUN/stderr-<lens>.log"
    exit 1
fi

# ── stage 3: consolidate, and drop the findings that do not meet the bar ─────
echo ""
echo "  consolidating"

CONSOL_PROMPT="$RUN/prompt-consolidate.md"
{
    cat <<'EOF'
You are consolidating several independent specialist reviews of one code change
into a single work list, and you are the last check before it reaches the author.

This report exists so that the repository's automated reviewer, gandolf, has
nothing left to comment on when the pull request opens. That sets your bias: keep
every finding that is TRUE, at whatever severity fits. Do not trim the list for
elegance. A small finding you drop here becomes a comment on the pull request, a
fix commit from a bot, and another review round.

Read these files:

EOF
    for lens in $LENSES; do echo "- \`$RUN/report-$lens.md\` — the $lens lens"; done
    echo "- \`$PREGATE_REPORT\` — the deterministic pre-gate, including the mechanical rule sweep"
    echo "- \`$DIFF_FILE\` — the diff every lens reviewed"
    cat <<'EOF'

Do three things, in order.

**One: merge.** Where two lenses found the same thing, keep one entry and name
both lenses. Keep every finding's file:line, its concrete failure, and its fix.
Where the `gandolf` lens predicted a comment that another lens also found as a
defect, merge them and keep the defect's wording — it is more actionable.

**Two: verify, and cut only what is false.** You are accountable for every
finding that survives, so check each against the diff and the surrounding code.
Delete a finding ONLY when one of these holds, and record it in the Filtered
section with the reason:

- The claimed code is not what the file actually contains at that line.
- The failure cannot be reached: the value is a compile-time constant, the caller
  contract excludes the input, or a guard upstream already handles it.
- It requests no change — it concludes "no change required", "just confirming",
  or "already handled correctly".
- It duplicates another finding you have already kept.

Do NOT delete a finding because it is small, cosmetic, a naming quibble, or a
matter of taste. Those belong under LOW or NIT. That is the difference between
this report and an ordinary review: the low tiers are the point, because they are
what comes back as pull-request comments.

Do not invent findings of your own. Merge, verify, and tier.

**Three: decide one overall verdict.** A CRITICAL or HIGH finding, a failed
deterministic check, or a certain rule violation from the mechanical sweep each
make the verdict FAIL — a failed check will go red in continuous integration
regardless of how the code reads.

Emit exactly this markdown and nothing else:

```
## gandolf-local review

### Verdict: PASS | CONDITIONAL PASS | FAIL

### Summary
Two or three sentences: the overall read, and what has to happen next.

### CRITICAL
- **`path/to/file.rs:LINE`** (lens) — what is wrong, what it breaks, the fix.

### HIGH
- **`path/to/file.rs:LINE`** (lens) — what is wrong, what it breaks, the fix.

### MEDIUM
- **`path/to/file.rs:LINE`** (lens) — what is wrong, why it matters, the fix.

### LOW
- **`path/to/file.rs:LINE`** (lens) — the issue and the exact fix.

### NIT
- **`path/to/file.rs:LINE`** (lens) — the issue and the exact replacement.

### Deterministic pre-gate
One line per failed or skipped check, and what to run to clear it. Omit the
section when every check passed.

### Predicted pull-request comments
Every finding from the `gandolf` lens that no other lens raised, with its
confidence word. These are the comments expected on the pull request; each one
fixed now is one review round saved. Omit the section if that lens found nothing.

### Residual risks
- What stays true even once every finding above is fixed.

### Filtered
- What you dropped, and which of the four permitted reasons applied.

### Lenses
One line per lens: its verdict, and how many findings of its survived.
```

Omit a section that would be empty, except `### Lenses`, which is always present.
EOF
} >"$CONSOL_PROMPT"

MAX_THINKING_TOKENS=32000 claude -p \
    --model "$MODEL" \
    --allowedTools "Read,Grep,Glob,Bash(git diff:*),Bash(git show:*),Bash(cat:*),Bash(sed:*),Bash(rg:*)" \
    <"$CONSOL_PROMPT" \
    >"$RUN/consolidated.md" 2>"$RUN/stderr-consolidate.log"
CONSOL_RC=$?

if [ "$CONSOL_RC" -ne 0 ] || [ ! -s "$RUN/consolidated.md" ]; then
    echo "gandolf-local: FAILED — consolidation produced no report (exit $CONSOL_RC)."
    echo "  The four lens reports are intact in $RUN — read them directly."
    exit 1
fi

# ── stage 4: verdict, report, receipt ────────────────────────────────────────
VERDICT="$(grep -m1 -oE 'Verdict: *(PASS|CONDITIONAL PASS|FAIL)' "$RUN/consolidated.md" | sed 's/Verdict: *//')"
# No parsable verdict means no verdict. Refuse rather than assume the good one.
if [ -z "$VERDICT" ]; then
    echo "gandolf-local: FAILED — the consolidated report carries no verdict line."
    echo "  Report: $RUN/consolidated.md"
    exit 1
fi
# A failed pre-gate is Blocking by definition; do not let a reviewer's optimism
# outrank a check that will go red in continuous integration.
if [ "$PREGATE_OK" -eq 0 ] && [ "$VERDICT" != "FAIL" ]; then
    echo "  pre-gate failed — forcing the verdict to FAIL (it will fail CI regardless)"
    VERDICT="FAIL"
fi

# Count the bullets in one severity section. The sed range ends at the next
# "### " heading, and because the start line matches that pattern too, sed begins
# looking for the end on the following line.
count_tier() {
    sed -n "/^### $1\$/,/^### /p" "$RUN/consolidated.md" | grep -c '^- *\*\*\|^- [^ ]' 2>/dev/null || true
}
N_CRIT="$(count_tier CRITICAL)"; N_HIGH="$(count_tier HIGH)"
N_MED="$(count_tier MEDIUM)";   N_LOW="$(count_tier LOW)"; N_NIT="$(count_tier NIT)"
N_BLOCK="$(( ${N_CRIT:-0} + ${N_HIGH:-0} ))"
N_SHOULD="$(( ${N_MED:-0} + ${N_LOW:-0} + ${N_NIT:-0} ))"

{
    cat "$RUN/consolidated.md"
    echo
    echo '---'
    echo
    echo "Reviewed \`$(git rev-parse --short "$MERGE_BASE")..$(git rev-parse --short "$HEAD_SHA")\` on $(date '+%Y-%m-%d %H:%M:%S %Z')."
    echo "Lenses: $(printf '%s' "$LENSES" | tr ' ' ',' ). Model \`$MODEL\`. Review key \`$KEY_SHORT\`. Working files in \`$RUN\`."
} >"$REPORT"
cp "$REPORT" "$STATE/latest.md"

jq -n \
    --arg key "$REVIEW_KEY" --arg base "$MERGE_BASE" --arg head "$HEAD_SHA" \
    --arg verdict "$VERDICT" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg report "$REPORT" --arg model "$MODEL" \
    --argjson blocking "${N_BLOCK:-0}" --argjson should_fix "${N_SHOULD:-0}" \
    --argjson critical "${N_CRIT:-0}" --argjson high "${N_HIGH:-0}" \
    --argjson medium "${N_MED:-0}" --argjson low "${N_LOW:-0}" --argjson nit "${N_NIT:-0}" \
    --argjson pregate "$PREGATE_OK" \
    '{review_key:$key, base:$base, head:$head, verdict:$verdict, reviewed_at:$at,
      report:$report, model:$model, blocking:$blocking, should_fix:$should_fix,
      findings:{critical:$critical, high:$high, medium:$medium, low:$low, nit:$nit},
      pregate_passed:($pregate==1)}' >"$RECEIPT"

echo ""
cat "$REPORT"
echo ""
echo "─────────────────────────────────────────────────────────────"
echo "  verdict   $VERDICT"
echo "  findings  ${N_CRIT:-0} critical, ${N_HIGH:-0} high, ${N_MED:-0} medium, ${N_LOW:-0} low, ${N_NIT:-0} nit"
echo "  report    $REPORT"
echo "  receipt   $RECEIPT"
case "$VERDICT" in
    FAIL) echo "  the pre-push hook will block this tree until the critical and high items are fixed" ;;
    "CONDITIONAL PASS") echo "  the hook will allow the push (GANDOLF_LOCAL_STRICT=1 requires the lower tiers cleared too)" ;;
    PASS) echo "  the hook will allow the push" ;;
esac
if [ "$N_SHOULD" -gt 0 ]; then
    echo ""
    echo "  $N_SHOULD medium, low and nit finding(s) remain. Each one left unfixed is a"
    echo "  comment the CI reviewer is likely to post, and a fix commit it will push."
    echo "  Sweep them before opening the pull request."
fi
echo "─────────────────────────────────────────────────────────────"

[ "$VERDICT" != "FAIL" ]
