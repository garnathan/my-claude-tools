#!/usr/bin/env bash
#
# learn-from-pr.sh — close the loop. Pull what gandolf ACTUALLY posted on a pull
# request, compare it against what the local gate found for the same commit, and
# report the misses.
#
# A local review that is merely good does not reduce the comment count on its own.
# What reduces it is knowing which comments the local gate failed to predict, and
# amending the lens that should have caught each one. That is what this script
# produces: a list of misses, and a concrete edit for each lens file.
#
#   learn-from-pr.sh <pr-number> [--repo owner/repo] [--bot <login>] [--no-suggest]
#
#     --repo        Default: the repository the current directory belongs to.
#     --bot         Only count this login. Default: every "...[bot]" login found,
#                   which is reported so it can be narrowed.
#     --no-suggest  Collect and compare only; skip the amendment pass.
#
# The identity rule matches the repository's own gate scripts: count artifacts
# across the three surfaces a review lands on — the conversation, formal reviews,
# and inline diff comments — and exclude any body carrying a hidden
# "<!-- gandolf-* -->" marker, because that marks the bot's own acknowledgements
# and the sibling automations rather than a review. See
# .github/scripts/gandolf-artifacts-lib.sh.
#
# Written for bash 3.2, which is what macOS ships.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LENS_DIR="$HERE/lenses"
MARKER_RE='<!--\s*gandolf-'

PR=""; REPO=""; BOT=""; SUGGEST=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)       REPO="${2:-}"; shift 2 ;;
        --bot)        BOT="${2:-}"; shift 2 ;;
        --no-suggest) SUGGEST=0; shift ;;
        -h|--help)    sed -n '2,26p' "$0"; exit 0 ;;
        *)            if [ -z "$PR" ]; then PR="$1"; shift; else echo "unexpected argument: $1" >&2; exit 2; fi ;;
    esac
done

case "$PR" in
    ''|*[!0-9]*) echo "usage: learn-from-pr.sh <pr-number> [--repo owner/repo] [--bot login]" >&2; exit 2 ;;
esac
command -v gh >/dev/null 2>&1 || { echo "gh is not on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is not on PATH" >&2; exit 2; }

if [ -z "$REPO" ]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" \
        || { echo "cannot determine the repository — pass --repo owner/repo" >&2; exit 2; }
fi

STATE="$(git rev-parse --git-common-dir 2>/dev/null)/gandolf-local"
OUT="$STATE/learn/pr-$PR"
mkdir -p "$OUT"

echo "learn-from-pr — what gandolf said on $REPO#$PR, against what we predicted"
echo ""

# ── the pull request's head, so the right local report can be found ──────────
HEAD_SHA="$(gh api "repos/$REPO/pulls/$PR" --jq '.head.sha' 2>/dev/null)"
[ -n "$HEAD_SHA" ] || { echo "cannot read $REPO#$PR — is gh authenticated?" >&2; exit 2; }
echo "  pull request head   $HEAD_SHA"

# ── collect gandolf's artifacts across the three surfaces ───────────────────
# A failed read must not read as "gandolf said nothing", which would score the
# local gate as perfect. Any surface that cannot be read aborts.
collect() {  # collect <surface> <label>
    local surface="$1" label="$2" out
    out="$(MARKER_RE="$MARKER_RE" FILTER_LOGIN="$BOT" gh api --paginate "repos/$REPO/$surface" --jq '
        .[]
        | select((.user.login // "") | test("\\[bot\\]$"))
        | select(env.FILTER_LOGIN == "" or .user.login == env.FILTER_LOGIN)
        | select(((.body // "") | test(env.MARKER_RE)) | not)
        | select((.body // "") != "")
        | "@@GANDOLF-ARTIFACT@@\t" + (.user.login) + "\t'"$label"'\t" + (.created_at)
          + "\t" + (if .path then .path + ":" + ((.line // .original_line // 0) | tostring) else "-" end)
          + "\n\n" + .body + "\n"
    ' 2>/dev/null)" || return 1
    printf '%s\n' "$out"
}

ARTIFACTS="$OUT/gandolf-said.md"
: >"$ARTIFACTS"
FAILED_READ=0
for pair in "issues/$PR/comments|conversation comment" "pulls/$PR/reviews|review" "pulls/$PR/comments|inline comment"; do
    surface="${pair%%|*}"; label="${pair##*|}"
    if body="$(collect "$surface" "$label")"; then
        printf '%s\n' "$body" >>"$ARTIFACTS"
    else
        echo "  WARNING could not read $surface — the comparison would understate what gandolf said"
        FAILED_READ=1
    fi
done

if [ "$FAILED_READ" -eq 1 ]; then
    echo ""
    echo "  Refusing to score the local gate against an incomplete list of comments."
    echo "  Re-run when the GitHub API is readable."
    exit 2
fi

# Count on a sentinel that cannot occur in a comment body. The obvious delimiter
# — a markdown heading — collides with gandolf's own review format, whose bodies
# carry "### Blockers", "### Nits" and so on: those headings were counted as
# separate artifacts and their words reported as logins, so the headline number
# was inflated and meaningless.
N_ART="$(grep -c '^@@GANDOLF-ARTIFACT@@' "$ARTIFACTS" || true)"
LOGINS="$(grep '^@@GANDOLF-ARTIFACT@@' "$ARTIFACTS" | cut -f2 | sort -u | tr '\n' ' ')"
echo "  gandolf artifacts   ${N_ART:-0}  (logins: ${LOGINS:-none})"
echo "  saved to            $ARTIFACTS"

if [ "${N_ART:-0}" -eq 0 ]; then
    echo ""
    echo "gandolf posted no marker-free review artifact on this pull request."
    echo "  Either the review has not run yet, or it found nothing — which is the goal."
    exit 0
fi

# ── find the local report for the same head ─────────────────────────────────
LOCAL=""
if [ -d "$STATE/receipts" ]; then
    for r in "$STATE/receipts"/*.json; do
        [ -f "$r" ] || continue
        if [ "$(jq -r '.head // ""' "$r" 2>/dev/null)" = "$HEAD_SHA" ]; then
            LOCAL="$(jq -r '.report // ""' "$r" 2>/dev/null)"
            break
        fi
    done
fi
if [ -n "$LOCAL" ] && [ -f "$LOCAL" ]; then
    echo "  local report        $LOCAL"
else
    echo "  local report        none for $HEAD_SHA"
    echo ""
    echo "  Without a local report for the same commit, every comment counts as a miss."
    echo "  That is still useful — it says what the lenses do not cover — but it cannot"
    echo "  distinguish a lens gap from a review that simply never ran on this commit."
    LOCAL=""
fi

[ "$SUGGEST" -eq 0 ] && { echo ""; echo "Collected only (--no-suggest)."; exit 0; }

# ── the amendment pass ─────────────────────────────────────────────────────
PROMPT="$OUT/prompt.md"
{
    echo "You are improving a local pre-push review so that the repository's"
    echo "automated reviewer, gandolf, has less to say next time."
    echo
    echo "Read these:"
    echo
    echo "- \`$ARTIFACTS\` — every review comment gandolf actually posted on pull"
    echo "  request #$PR, across the conversation, its formal reviews, and inline"
    echo "  diff comments. Each record starts with a line reading"
    echo "  \`@@GANDOLF-ARTIFACT@@\` followed by tab-separated login, kind, date and"
    echo "  file:line; everything until the next such line is that comment's body."
    echo "  Treat each SECTION of a review body (blockers, should-fix, nits) as a"
    echo "  separate comment for scoring, because each one is a separate ask."
    if [ -n "$LOCAL" ]; then
        echo "- \`$LOCAL\` — what the local gate found for the SAME commit ($HEAD_SHA)."
    else
        echo "- There is no local report for this commit, so treat every gandolf"
        echo "  comment as unpredicted."
    fi
    echo "- The lens files the local gate uses:"
    for f in "$LENS_DIR"/*.md; do echo "  - \`$f\`"; done
    echo
    cat <<'EOF'
Produce this, and nothing else:

```
## Learning from pull request #<N>

### Predicted
Comments gandolf made that the local report already contained. One line each.
This is the score — say what fraction of gandolf's comments were predicted.

### Missed
Every comment gandolf made that the local report did not. For each one:
- the comment, in one line;
- which lens SHOULD have caught it (code, security, memory, concurrency, or
  gandolf), and why that lens as written did not;
- whether it is mechanically detectable — if a grep over added lines would find
  this class reliably, say so, because it belongs in gandolf-bait.sh rather than
  in a lens.

### Suggested lens amendments
For each miss, the exact edit: which file, which section, and the sentence or
bullet to add. Write the replacement text out in full so it can be applied
directly. Add nothing speculative — one amendment per real miss, and where two
misses share a cause, one amendment covering both.

### Suggested gandolf-bait.sh checks
For each mechanically-detectable miss, the grep pattern and the severity it
should carry (CERTAIN only when a numbered rule in CLAUDE.md or dfl/CLAUDE.md
covers it; ADVISORY otherwise). State the false-positive risk — a check that
fires on correct code costs more trust than the comment it prevents.

### Over-prediction
Anything the local report raised that gandolf did NOT, and that on reflection was
not worth raising. These are the findings to make the lenses less likely to
produce. Leave the section out if there were none — a local finding gandolf
missed is usually a win, not noise.
```

Judge a comment as predicted only when the local report names the same file and
the same problem. The same file with a different problem is a miss.
EOF
} >"$PROMPT"

REPORT="$OUT/learning.md"
echo ""
echo "  comparing"
MAX_THINKING_TOKENS=32000 claude -p \
    --model "${GANDOLF_LOCAL_MODEL:-opus}" \
    --allowedTools "Read,Grep,Glob" \
    <"$PROMPT" >"$REPORT" 2>"$OUT/stderr.log"
rc=$?

if [ "$rc" -ne 0 ] || [ ! -s "$REPORT" ]; then
    echo "  the comparison produced nothing (exit $rc) — see $OUT/stderr.log"
    echo "  The collected comments are still in $ARTIFACTS."
    exit 1
fi

echo ""
cat "$REPORT"
echo ""
echo "─────────────────────────────────────────────────────────────"
echo "  learning   $REPORT"
echo "  Apply the amendments yourself after reading them. They edit the prompts"
echo "  the gate runs on, so they are not applied automatically."
echo "─────────────────────────────────────────────────────────────"
