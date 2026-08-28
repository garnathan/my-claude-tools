#!/usr/bin/env bash
#
# gandolf-bait.sh — the comments the automated reviewer is certain to make, found
# by grep instead of by a language model.
#
# Every check here corresponds to a numbered rule in CLAUDE.md or dfl/CLAUDE.md,
# so a hit is not a matter of taste: the continuous-integration reviewer will
# comment on it. Deciding these mechanically is both faster and more reliable
# than hoping a reviewer notices, and it leaves the reviewers free to look for
# defects rather than for rule violations.
#
#   gandolf-bait.sh [--base <ref>] [--report <file>]
#
# Exit status: 0 when no certain hit was found, 1 when at least one was. Advisory
# observations never change the exit status; they are printed because the reviewer
# often raises them, not because a rule forbids them.
#
# Written for bash 3.2, which is what macOS ships.

set -uo pipefail

BASE_REF="origin/main"
REPORT=""
INCLUDE_WORKTREE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --base)   BASE_REF="${2:-}"; [ -n "$BASE_REF" ] || { echo "--base needs a ref" >&2; exit 2; }; shift 2 ;;
        --report) REPORT="${2:-}"; [ -n "$REPORT" ] || { echo "--report needs a path" >&2; exit 2; }; shift 2 ;;
        # Include uncommitted work. review.sh forwards this so the mechanical
        # sweep judges the same content the reviewers were given; without it the
        # sweep silently checked only the committed part and reported clean.
        --include-worktree) INCLUDE_WORKTREE=1; shift ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not inside a git work tree" >&2; exit 2; }
cd "$TOP" || exit 2
BASE_SHA="$(git rev-parse --verify --quiet "$BASE_REF^{commit}")" || { echo "cannot resolve $BASE_REF" >&2; exit 2; }
MERGE_BASE="$(git merge-base "$BASE_SHA" HEAD)" || MERGE_BASE="$BASE_SHA"

WORK="$(mktemp -d -t gandolf-bait)"
trap 'rm -rf "$WORK"' EXIT

# Every diff this script parses goes through here, and the flags are not
# decoration. `color.ui = always` or `color.diff = always` in ANY config scope
# forces ANSI escapes even when the output is a pipe, so every added line arrives
# as ESC[32m+ESC[32m... — the awk rules below match nothing, the added-line list
# comes back empty, and all twelve added-line checks report clean. That is this
# gate announcing a pass it did not earn, over exactly the violations it exists to
# find. `diff.external` / GIT_EXTERNAL_DIFF replaces the output wholesale and
# breaks it the same way. Overriding on the command line beats every config scope,
# and --no-ext-diff ignores an external driver. Verified by reproducing the silent
# pass with each setting and confirming this form parses correctly under both.
git_diff() {
    git --no-pager -c color.ui=false -c color.diff=false diff --no-color --no-ext-diff "$@"
}

# The revision range every check below reads. Omitting HEAD makes git compare the
# base against the WORKING TREE, which is what --include-worktree asks for.
if [ "$INCLUDE_WORKTREE" -eq 1 ]; then RANGE="$MERGE_BASE"; else RANGE="$MERGE_BASE HEAD"; fi

CHANGED="$WORK/changed.txt"
# A read failure must not look like "nothing changed" — that is the same false
# clean. `set -e` is deliberately off in this script, so check explicitly.
if ! git_diff --name-only $RANGE >"$CHANGED"; then
    echo "gandolf-bait: cannot read the changed-file list for $MERGE_BASE..HEAD" >&2
    exit 2
fi

# Added lines as file:line:content. -U0 so no context line is mistaken for an
# addition, and the hunk header carries the new-file line number to count from.
ADDED="$WORK/added.txt"
RAW="$WORK/raw.diff"
if ! git_diff -U0 $RANGE >"$RAW"; then
    echo "gandolf-bait: cannot read the diff for $MERGE_BASE..HEAD" >&2
    exit 2
fi
awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^\+\+\+ / { file = "?"; next }
    /^@@/ {
        if (match($0, /\+[0-9]+/)) { ln = substr($0, RSTART + 1, RLENGTH - 1) + 0 }
        next
    }
    /^\+/ { print file ":" ln ":" substr($0, 2); ln++; next }
' <"$RAW" >"$ADDED"

FINDINGS="$WORK/findings.md"
CERTAIN_FLAG="$WORK/certain"
: >"$FINDINGS"

# hit <severity> <title> <fix>   — reads matching "file:line:content" on stdin
#
# The certain-hit flag is a FILE, not a shell variable. Every call site pipes into
# this function, and a pipeline component runs in a subshell, so an assignment
# here would be discarded the moment it returned — the script would print a
# violation and still exit 0, which is the one failure mode a gate must not have.
hit() {
    local sev="$1" title="$2" fix="$3" body
    body="$(cat)"
    [ -z "$body" ] && return 0
    printf '\n  %s — %s\n' "$sev" "$title"
    printf '%s\n' "$body" | cut -c1-160 | sed 's/^/      /'
    printf '      fix: %s\n' "$fix"
    {
        printf '\n**%s — %s**\n\n' "$sev" "$title"
        printf '```\n%s\n```\n\n' "$(printf '%s\n' "$body" | cut -c1-200)"
        printf 'Fix: %s\n' "$fix"
    } >>"$FINDINGS"
    [ "$sev" = CERTAIN ] && : >"$CERTAIN_FLAG"
    return 0
}

# Added lines in source files only — skip the diff's own documentation, where a
# word like "TODO" is legitimately being written about rather than left behind.
src_added() {
    grep -vE '^[^:]*\.(md|txt|json|lock):' "$ADDED" 2>/dev/null || true
}

# Drop added lines whose content is a comment. Needed for every check that looks
# for a code CONSTRUCT: a doc comment explaining that some value sits behind a
# process-wide OnceLock is documentation, not a new global, and flagging it sends
# the author to a line that is already correct. Checks that deliberately look
# inside comments — the TODO sweep, the AI-attribution sweep — must not use this.
# Also drops a `use` line: importing OnceLock is not declaring one, and importing
# a name is the wrong place to send someone whose problem is the declaration.
code_added() {
    src_added \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|/\*|\*|#[^\[!])' \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(pub )?use '
}

# Added lines that are inside a test module or a test file, printed unchanged.
# Several rules are about library code reachable from an HTTP handler and do not
# bind a unit test: a test that builds its own tokio runtime is normal. Approximate
# "inside a test module" by the first `#[cfg(test)]` in the file, which in this
# codebase is the bottom test module.
is_test_context() {  # is_test_context <file> <line>
    local f="$1" l="$2" ln nxt boundary=""
    case "$f" in */tests/*|*/benches/*|*_test.rs|*/test_*.rs) return 0 ;; esac
    [ -f "$f" ] || return 1
    # The boundary is the LAST `#[cfg(test)]` that introduces a MODULE — the
    # bottom test module. Taking the FIRST marker instead was wrong in the
    # dangerous direction: 245 files in this workspace open with a `#[cfg(test)]`
    # gating a `use`, a helper `fn`, or a `const`, and treating everything after
    # it as test code exempted whole production files from every rule that uses
    # this helper. A marker gating anything other than a module is skipped.
    while IFS=: read -r ln _; do
        [ -n "$ln" ] || continue
        nxt="$(sed -n "$((ln + 1))p" "$f" 2>/dev/null)"
        case "$nxt" in
            *"mod "*) boundary="$ln" ;;
        esac
    done <<EOF
$(grep -n '#\[cfg(test)\]' "$f" 2>/dev/null)
EOF
    [ -n "$boundary" ] || return 1
    [ "$l" -ge "$boundary" ]
}

# Split "file:line:content" input into production hits (stdout) and test-context
# hits (the file named by $1), so a rule can bind the first and merely note the
# second.
split_test_context() {  # split_test_context <test_out_file>
    local out="$1" entry f rest l
    : >"$out"
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        f="${entry%%:*}"; rest="${entry#*:}"; l="${rest%%:*}"
        case "$l" in ''|*[!0-9]*) printf '%s\n' "$entry"; continue ;; esac
        if is_test_context "$f" "$l"; then
            printf '%s\n' "$entry" >>"$out"
        else
            printf '%s\n' "$entry"
        fi
    done
}

echo "gandolf-bait — rule violations the CI reviewer will certainly comment on"
echo "  base $BASE_REF ($(git rev-parse --short "$MERGE_BASE"))  head $(git rev-parse --short HEAD)"
echo "  $(grep -c . <"$CHANGED" || true) changed files, $(grep -c . <"$ADDED" || true) added lines"

# ── Rule 1: no TODOs, stubs, mocks, or unimplemented paths ───────────────────
src_added | grep -iE ':.*(\bTODO\b|\bFIXME\b|\bXXX\b|\bHACK\b|todo!\(|unimplemented!\(|panic!\("not implemented)' \
    | hit CERTAIN "Rule 1 — a TODO, FIXME, or unimplemented path was added" \
      "remove it and complete the path, or get explicit permission recorded in the change"

# ── Rule 7: no process-wide state that could hold per-tenant data ────────────
# `static X: OnceLock<...>` declares one; a doc comment mentioning OnceLock does
# not, so read code lines only. A declaration inside a test module is reported
# separately, because tenant isolation is about the serving process.
# CERTAIN is reserved for a MODULE-LEVEL declaration whose payload could plausibly
# hold per-tenant data, because that is the shape of the isolation defect Rule 7
# exists for. Two narrowings, both measured against this workspace:
#
#   - Require the `static` at content column zero. 159 declarations here are
#     function-local memoisation caches (`static PATH: OnceLock<String>` inside a
#     helper); calling all of them certain rule violations would bury the 132
#     module-level ones that actually matter.
#   - Require a payload that can hold data — a map, a collection, or a type named
#     for a store, cache, registry, overlay, schema, token or credential. A
#     `OnceLock<String>` holding a path is not the tenant-isolation defect.
#
# Anything process-wide that misses those tests is still reported, as ADVISORY.
T7="$WORK/t7-test.txt"
T7_WIDE="$WORK/t7-wide.txt"
code_added \
    | grep -E ':.*(OnceLock|OnceCell|lazy_static!|thread_local!|static +[A-Z_]+ *: *(Mutex|RwLock|HashMap))' \
    | split_test_context "$T7" >"$T7_WIDE"
grep -E ':(pub(\([a-z]+\))? )?(static|lazy_static!|thread_local!)' "$T7_WIDE" 2>/dev/null \
    | grep -iE '(HashMap|BTreeMap|HashSet|Vec<|Store|Cache|Registry|Overlay|Schema|Token|Credential|Wallet|Session|Tenant|Agent)' \
    | hit CERTAIN "Rule 7 — new module-level process-wide state that could hold per-tenant data" \
      "key it per agent_id and pass it explicitly, or say in a comment why it holds no per-tenant data"
grep -vE ':(pub(\([a-z]+\))? )?(static|lazy_static!|thread_local!)' "$T7_WIDE" 2>/dev/null \
    | hit ADVISORY "Rule 7 — process-wide state added inside a function" \
      "usually a memoisation cache and fine; confirm it holds nothing scoped to one tenant"
cat "$T7" | hit ADVISORY "Rule 7 — process-wide state added inside a test module" \
    "usually fine, but a bundled test binary cannot re-set a OnceLock between cases — check the test does not depend on ordering"

# ── Rule 9: no embedded tokio runtime in library code ───────────────────────
# The rule is about code reachable from a dfl-http async handler. A test that
# builds its own runtime is normal and is separated out rather than flagged.
T9="$WORK/t9-test.txt"
code_added | grep -E ':.*(reqwest::blocking|Runtime::new\(\)|new_current_thread\(\)|Builder::new_multi_thread\(\))' \
    | split_test_context "$T9" \
    | hit CERTAIN "Rule 9 — an embedded tokio runtime or blocking HTTP client in library code" \
      "bridge with spawn_blocking, block_on_async, or block_on_async_or_thread instead"
cat "$T9" | hit ADVISORY "Rule 9 — a tokio runtime built inside a test" \
    "expected in a test; confirm the same code path does not run under dfl-http"

# ── Rule 3: never materialise a whole DataFrame ─────────────────────────────
T3="$WORK/t3-test.txt"
code_added | grep -E ':.*to_cache\(' \
    | split_test_context "$T3" \
    | hit CERTAIN "Rule 3 — to_cache() copies a whole frame into memory" \
      "use to_rowset_path() and pass the file path to the next stage"
# The test-context hits were being collected into a file nothing ever read, so
# they silently vanished. Report them, like every other split does.
cat "$T3" | hit ADVISORY "Rule 3 — to_cache() inside a test module" \
    "fine for a small fixture; confirm the frame is bounded and that no production path shares the helper"

# ── Rule 5: error-ids.md is nightly-owned ───────────────────────────────────
grep -E 'docs/reference/error-ids\.md' "$CHANGED" \
    | hit CERTAIN "Rule 5 — error-ids.md was edited, and it is owned by the nightly pipeline" \
      "revert the file; the macro plus a unique checked-in literal is all a change needs"
src_added | grep -E ':.*make docs-errors' \
    | hit CERTAIN "Rule 5 — a script invokes make docs-errors" \
      "remove it; only the nightly pipeline regenerates that catalogue"

# ── Suppression discipline: every allow needs a reason on the line above ─────
# Read each hit back from the working tree so the preceding line can be inspected.
sup="$WORK/sup.txt"; : >"$sup"
src_added | grep -E ':.*(#\[allow\(|# noqa|// eslint-disable|# type: ignore|@ts-ignore|# pylint: disable)' >"$sup" || true
if [ -s "$sup" ]; then
    bare="$WORK/bare.txt"; : >"$bare"
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        f="${entry%%:*}"; rest="${entry#*:}"; l="${rest%%:*}"
        [ -f "$f" ] || continue
        case "$l" in ''|*[!0-9]*) continue ;; esac
        prev=""
        [ "$l" -gt 1 ] && prev="$(sed -n "$((l - 1))p" "$f" 2>/dev/null)"
        same="$(sed -n "${l}p" "$f" 2>/dev/null)"
        # A justification is any comment on the line above, or a trailing comment
        # on the same line after the suppression.
        if printf '%s' "$prev" | grep -qE '^\s*(//|#)' ; then continue; fi
        if printf '%s' "$same" | grep -qE '(\)\]|ignore|disable).*(//|#).+[A-Za-z]{4}'; then continue; fi
        printf '%s\n' "$entry" >>"$bare"
    done <"$sup"
    cat "$bare" | hit CERTAIN "a static-analysis suppression was added with no written reason" \
        "put a one-line comment directly above it saying why the finding is a false positive, or why a refactor would be worse"
    n_sup="$(grep -c . <"$sup" || true)"
    if [ "$n_sup" -gt 2 ]; then
        printf '%s\n' "$n_sup new suppressions in one change" \
            | hit ADVISORY "more than two new suppressions — the reviewer reads this as a skipped refactor pass" \
              "reduce them, or explain in the change description why each is unavoidable"
    fi
fi

# ── Rule 20 / credential hygiene: force push and shell tracing ──────────────
src_added | grep -E ':.*git +push.*--force([^-]|$)' \
    | hit CERTAIN "a plain --force push was added" \
      "use --force-with-lease, and never force-push a shared branch"
src_added | grep -E ':.*(set +-x|set +-o +xtrace|bash +-x)' \
    | hit ADVISORY "shell tracing was enabled — it echoes the value of every secret it traces" \
      "turn tracing off across every credential load and use, and back on after"

# ── Rule 5 / ENVIRONMENT.md: a new environment variable must be documented ──
# Read from CODE lines only: a doc comment quoting `env::var("FOO")` as an example
# is documentation, and minting a variable name from it sends the author to
# document something that does not exist.
#
# Severity is split by what actually blocks a merge. The white page and the
# DFL_ENV_VARS registry list are enforced by a test, so a name missing from either
# is CERTAIN. ENVIRONMENT.md is prose organised into tables and value-convention
# sections, and a plain substring search over it produces a large number of false
# misses on names that ARE documented — so that arm is ADVISORY. Getting this
# backwards would have the gate demand documentation for names already shipped.
env_new="$WORK/env.txt"; : >"$env_new"
code_added | grep -oE 'env::var(_os)? *\( *"[A-Z][A-Z0-9_]+"' \
    | grep -oE '"[A-Z][A-Z0-9_]+"' | tr -d '"' | sort -u >"$env_new" || true
if [ -s "$env_new" ]; then
    undoc="$WORK/undoc.txt"; : >"$undoc"
    softdoc="$WORK/softdoc.txt"; : >"$softdoc"
    while IFS= read -r v; do
        [ -z "$v" ] && continue
        # Obvious placeholders from examples and doctests, not real names.
        case "$v" in FOO|BAR|BAZ|EXAMPLE|TEST|VAR|NAME|KEY|VALUE|X|Y|Z) continue ;; esac
        hard=""
        [ -f dfl/docs/reference/env-vars-whitepage.md ] \
            && ! grep -qF "$v" dfl/docs/reference/env-vars-whitepage.md \
            && hard="$hard env-vars-whitepage.md"
        case "$v" in
            DFL_*)
                [ -f dfl/crates/dfl-common/src/env_registry.rs ] \
                    && ! grep -qF "$v" dfl/crates/dfl-common/src/env_registry.rs \
                    && hard="$hard env_registry.rs(DFL_ENV_VARS)"
                ;;
        esac
        [ -n "$hard" ] && printf '%s — missing from:%s\n' "$v" "$hard" >>"$undoc"
        if [ -f dfl/docs/ENVIRONMENT.md ] && ! grep -qF "$v" dfl/docs/ENVIRONMENT.md; then
            printf '%s — not found in ENVIRONMENT.md\n' "$v" >>"$softdoc"
        fi
    done <"$env_new"
    cat "$undoc" | hit CERTAIN "Rule 5 — an environment variable is read but not registered" \
        "add it to each file listed; the DFL_ENV_VARS entry is a merge-blocking test, not a doc"
    cat "$softdoc" | hit ADVISORY "Rule 5 — an environment variable may be missing from ENVIRONMENT.md" \
        "document its accepted values and default there; check by hand, since that page is organised into tables and sections"
fi

# ── Rule 4: a new test that nothing actually runs ────────────────────────────
# Most new `tests/*.rs` files need no wiring at all: scripts/test_infra/
# collapse_tests.py folds every one of them into the generated `tests/all.rs`
# bundle, which is exactly why adding a test touches no tracked file. So a
# missing Makefile line is NOT a violation, and flagging it would cry wolf on
# every change that adds a test.
#
# The real orphan is narrower and worth catching: a test given its OWN `[[test]]`
# entry in the crate manifest — the escape hatch for a test that mutates
# process-wide state — is thereby taken OUT of the bundle, so if no make target
# names it, nothing runs it at all.
newtests="$WORK/newtests.txt"; : >"$newtests"
git_diff --name-only --diff-filter=A $RANGE \
    | grep -E '^dfl/crates/[^/]+/tests/.*\.rs$' >"$newtests" || true
if [ -s "$newtests" ] && [ -f dfl/Makefile ]; then
    orphan="$WORK/orphan.txt"; : >"$orphan"
    live="$WORK/live.txt"; : >"$live"
    while IFS= read -r t; do
        [ -z "$t" ] && continue
        stem="$(basename "$t" .rs)"
        crate_dir="$(printf '%s' "$t" | cut -d/ -f1-3)"
        mani="$crate_dir/Cargo.toml"
        named_by_make=0
        grep -qF "$stem" dfl/Makefile && named_by_make=1
        has_own_target=0
        [ -f "$mani" ] && grep -qF "\"$stem\"" "$mani" && has_own_target=1
        if [ "$has_own_target" -eq 1 ] && [ "$named_by_make" -eq 0 ]; then
            printf '%s — has its own [[test]] entry (so it is out of the bundle) and no make target names it\n' \
                "$t" >>"$orphan"
        fi
        # Rule 4 does ask for a live-dependency test to reach make test-live.
        case "$stem" in
            *_live|*live_*|*_oracle_e2e|*_oci_e2e)
                [ "$named_by_make" -eq 0 ] && printf '%s — a live-dependency test no make target names\n' "$t" >>"$live" ;;
        esac
    done <"$newtests"
    cat "$orphan" | hit CERTAIN "Rule 4 — a new test has its own [[test]] entry but no make target runs it" \
        "add it to the right make test-* target; the tests/all.rs bundle does not cover a test with its own entry"
    cat "$live" | hit ADVISORY "Rule 4 — a live-dependency test may need a make test-live entry" \
        "add it to make test-live so the external-dependency suite runs it"
fi

# ── Rule 5: documentation duty for grammar, functions and examples ──────────
touched_grammar=0
grep -qE 'dfl-core/src/parser/(grammar\.pest|ast\.rs)' "$CHANGED" && touched_grammar=1
if [ "$touched_grammar" -eq 1 ] && ! grep -qE 'docs/reference/grammar\.md' "$CHANGED"; then
    printf '%s\n' "the parser grammar or AST changed, and grammar.md did not" \
        | hit CERTAIN "Rule 5 — grammar.md was not updated alongside a syntax change" \
          "document the new or changed syntax in dfl/docs/reference/grammar.md, and add an examples.md entry"
fi
if grep -qE 'dfl-core/src/(compiler|ir)/.*function' "$CHANGED" && ! grep -qE 'docs/reference/functions\.md' "$CHANGED"; then
    printf '%s\n' "a function surface changed, and functions.md did not" \
        | hit ADVISORY "Rule 5 — functions.md may need the new or changed built-in" \
          "add or update the entry in dfl/docs/reference/functions.md"
fi

# ── Rule 0: no AI attribution in anything being added ───────────────────────
src_added | grep -iE ':.*(co-authored-by:.*(claude|anthropic)|generated with .*claude|claude\.com/claude-code)' \
    | hit CERTAIN "Rule 0 — AI attribution was added" \
      "remove it; Claude must not appear as an author, co-author, or generator anywhere"

# ── Advisory: debug output and unwraps left in library code ─────────────────
TDBG="$WORK/tdbg.txt"
code_added | grep -E ':.*(dbg!\(|println!\(|eprintln!\()' \
    | grep -vE '(examples?/|bin/|main\.rs|/dfl-cli/|/dfl-log/|/dfl-gui/)' \
    | split_test_context "$TDBG" \
    | hit ADVISORY "debug printing in library code" \
      "use the tracing macros the surrounding module already uses, or delete the line"

n_unwrap="$(src_added | grep -cE ':.*\.(unwrap|expect)\(' || true)"
if [ "${n_unwrap:-0}" -gt 5 ]; then
    printf '%s\n' "$n_unwrap added .unwrap() or .expect() calls" \
        | hit ADVISORY "many added unwraps — the reviewer asks about each one on a reachable path" \
          "return a typed error with a stable error ID on any path a caller or the network can reach"
fi

# ── Advisory: an Err on a compile or execute path with no stable error ID ───
err_no_id="$(src_added \
    | grep -E '^(dfl/crates/dfl-(core|planner|http))/' \
    | grep -E ':.*Err\(' \
    | grep -vE 'dfl_(compile|execute)_err!' || true)"
if [ -n "$err_no_id" ]; then
    printf '%s\n' "$err_no_id" | head -12 \
        | hit ADVISORY "an Err was added in dfl-core, dfl-planner, or dfl-http without a stable error ID" \
          "if the path is reachable from compile or execute, wrap it with dfl_compile_err! or dfl_execute_err! and a unique checked-in literal"
fi

# ── summary ────────────────────────────────────────────────────────────────
echo ""
if [ -f "$CERTAIN_FLAG" ]; then
    echo "gandolf-bait: at least one certain rule violation — the CI reviewer will comment on it."
else
    echo "gandolf-bait: no certain rule violations found."
fi

if [ -n "$REPORT" ]; then
    {
        echo "## Rule violations found mechanically"
        echo
        if [ -s "$FINDINGS" ]; then
            echo "Each of these maps to a numbered rule, so the CI reviewer will raise it."
            cat "$FINDINGS"
        else
            echo "None. Every mechanical rule check passed."
        fi
        echo
    } >>"$REPORT"
fi

[ ! -f "$CERTAIN_FLAG" ]
