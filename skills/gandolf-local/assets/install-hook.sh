#!/usr/bin/env bash
#
# install-hook.sh — make the local gandolf review a blocking pre-push gate.
#
#   bash install-hook.sh              install, idempotent
#   bash install-hook.sh --status     report, change nothing
#   bash install-hook.sh --uninstall  remove cleanly
#
# WHY IT EXTENDS THE EXISTING HOOK RATHER THAN REPLACING IT
#
# Git LFS owns `pre-push` in the DFL clone — the hook is three lines and the last
# one is `git lfs pre-push "$@"`. This repository keeps real build inputs in LFS:
# the MiniLM ONNX model, the JDBC jars, the DuckPGQ extension. Overwriting the
# hook, or pointing `core.hooksPath` somewhere else, stops LFS uploading objects
# on push, and the failures that follow point nowhere near the cause. So the gate
# is composed into whatever hook is already there, delimited by the markers
# below, exactly as dfl/scripts/install-git-hooks.sh does for post-checkout and
# post-merge.
#
# WHY THE BLOCK MUST NOT READ STDIN CARELESSLY
#
# Git feeds the pre-push hook one line per ref on standard input. `git lfs
# pre-push` reads those lines to decide which objects to upload. A block that
# consumed standard input and did not put it back would leave LFS with nothing to
# read, and LFS would upload nothing — silently, with a successful push. So the
# block captures standard input to a temporary file, uses it, and restores it with
# `exec` before falling through. Unlinking a file whose descriptor is still open
# keeps the data, so the temporary file is removed immediately after.
#
# WHY IT PREPENDS
#
# A hook body that ends in an explicit `exit` never reaches anything appended
# after it, so an appended block can be installed and never run, with nothing to
# show for it. Prepending always runs. The block exits non-zero only to block a
# push; otherwise it falls through and the original hook decides the status.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REVIEW="$HERE/review.sh"

BEGIN='# >>> gandolf-local pre-push review gate (managed by install-hook.sh) >>>'
END='# <<< gandolf-local pre-push review gate <<<'

ACTION="install"
case "${1:-}" in
    --status)    ACTION="status" ;;
    --uninstall) ACTION="uninstall" ;;
    "")          ACTION="install" ;;
    -h|--help)   sed -n '2,40p' "$0"; exit 0 ;;
    *)           echo "unknown argument: $1" >&2; exit 2 ;;
esac

command -v git >/dev/null 2>&1 || { echo "git not found" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not inside a git work tree" >&2; exit 2; }

# The directory git will actually read. `--git-path hooks` already resolves to the
# common directory inside a linked worktree, so one install covers a clone and
# every worktree attached to it. A core.hooksPath set by someone else wins,
# because that is the directory git reads.
hooks_dir="$(git config --get core.hooksPath 2>/dev/null || true)"
if [ -n "$hooks_dir" ]; then
    case "$hooks_dir" in
        /*) : ;;
        *)  hooks_dir="$(git rev-parse --show-toplevel)/$hooks_dir" ;;
    esac
else
    hooks_dir="$(git rev-parse --git-path hooks)"
fi
HOOK="$hooks_dir/pre-push"

emit_block() {
    cat <<EOF
$BEGIN
# Blocks a push whose commits have not been through the local gandolf review.
# The review itself is $REVIEW; only this call site lives in .git/.
# Turn it off for one push with GANDOLF_LOCAL=0; remove it with
#     bash $HERE/install-hook.sh --uninstall
#
# Standard input carries one line per ref and Git LFS needs it, so capture it,
# use it, and restore it before falling through to the rest of this hook.
__gl_review='$REVIEW'
__gl_refs="\$(mktemp -t gandolf-local-refs)"
cat >"\$__gl_refs"

__gl_skip=''
if [ -n "\${CI:-}" ] || [ -n "\${GITHUB_ACTIONS:-}" ]; then
    __gl_skip='running in CI'
elif [ "\${GANDOLF_LOCAL:-1}" = "0" ]; then
    __gl_skip='GANDOLF_LOCAL=0'
elif [ ! -f "\$__gl_review" ]; then
    __gl_skip="the review script is missing (\$__gl_review)"
fi

if [ -z "\$__gl_skip" ]; then
    # Every non-deleting local sha on this push. A deletion sends all zeros.
    __gl_shas="\$(awk '\$2 !~ /^0+\$/ { print \$2 }' "\$__gl_refs" | sort -u)"
    __gl_head="\$(git rev-parse HEAD 2>/dev/null)"
    if [ -z "\$__gl_shas" ]; then
        __gl_skip='nothing to review (a deletion, or an empty push)'
    else
        for __gl_s in \$__gl_shas; do
            if [ "\$__gl_s" != "\$__gl_head" ]; then
                echo "gandolf-local: this push carries \$__gl_s, which is not the checked-out HEAD." >&2
                echo "  The gate reviews the checked-out tree, so it cannot judge that ref here." >&2
                echo "  Check the branch out and push it, or set GANDOLF_LOCAL=0 for this push." >&2
                exec <"\$__gl_refs"; rm -f "\$__gl_refs"
                exit 1
            fi
        done
    fi
fi

if [ -n "\$__gl_skip" ]; then
    echo "gandolf-local: gate skipped (\$__gl_skip)."
elif bash "\$__gl_review" --check </dev/null; then
    echo "gandolf-local: this tree already has a passing review — allowing the push."
elif [ -n "\${CLAUDECODE:-}" ]; then
    # An agent is pushing. Do NOT start a nested review here: it would stall
    # inside the agent's own tool call for as long as the review takes, and hit
    # that call's timeout rather than finishing. Refuse with the command to run,
    # which is the enforcement the gate exists for.
    echo "gandolf-local: BLOCKED — no passing review for this tree." >&2
    echo "" >&2
    echo "  Run the review first, address what it finds, then push:" >&2
    echo "      bash \$__gl_review" >&2
    echo "" >&2
    echo "  (Refusing to start a review inside an agent session, because it would" >&2
    echo "   outlive the tool call that triggered it. Set GANDOLF_LOCAL=0 to bypass.)" >&2
    exec <"\$__gl_refs"; rm -f "\$__gl_refs"
    exit 1
else
    echo "gandolf-local: no review on record for this tree — running it now."
    echo "  Five reviewers plus the deterministic checks. This takes a while."
    echo "  Set GANDOLF_LOCAL=0 to skip the gate for one push."
    echo "  Interrupting the push (Ctrl-C) also stops the review."
    echo ""
    # Do NOT let the review outlive the push that asked for it. Observed for real:
    # a push was interrupted, the hook and git went away, and review.sh kept
    # running with parent process 1 and five model processes still going, with
    # nothing left to read the result. So run it in the background, record its
    # process id, and trap the signals a cancelled push delivers so the whole
    # process group dies with the push. \`wait\` still yields its exit status, and
    # killing the negated pid targets the group, which is what actually stops the
    # reviewers rather than just their launcher.
    set -m 2>/dev/null || true
    bash "\$__gl_review" </dev/null &
    __gl_pid=\$!
    trap 'kill -TERM -\$__gl_pid 2>/dev/null; kill -TERM \$__gl_pid 2>/dev/null' INT TERM HUP
    wait "\$__gl_pid"
    __gl_rc=\$?
    trap - INT TERM HUP

    # Decide on the RECEIPT, not on that exit status. Interrupting the push kills
    # the review's process group, and a shell whose child was killed can still run
    # on to its last line and exit zero — measured: after an interrupt the review
    # died, yet the launcher returned zero and this hook allowed the push. An
    # interrupted or crashed review must never read as a pass, so ask the same
    # question the hook opened with: is there a passing review for this exact tree?
    # That depends on a receipt the review only writes once it has actually reached
    # a verdict, which no signal can fake.
    if bash "\$__gl_review" --check </dev/null; then
        echo "gandolf-local: review passed — allowing the push."
    else
        echo "" >&2
        if [ "\$__gl_rc" -ne 0 ]; then
            echo "gandolf-local: BLOCKED — the review did not pass (exit \$__gl_rc)." >&2
        else
            echo "gandolf-local: BLOCKED — the review ended without recording a passing" >&2
            echo "  verdict for this tree. It was most likely interrupted." >&2
        fi
        echo "  Report: bash \$__gl_review --status" >&2
        exec <"\$__gl_refs"; rm -f "\$__gl_refs"
        exit 1
    fi
fi

exec <"\$__gl_refs"
rm -f "\$__gl_refs"
$END
EOF
}

case "$ACTION" in
status)
    echo "gandolf-local pre-push gate"
    echo "  hook file   $HOOK"
    if [ ! -f "$HOOK" ]; then
        echo "  state       no pre-push hook exists"
    elif grep -qF "$BEGIN" "$HOOK"; then
        echo "  state       INSTALLED"
        grep -qF 'git lfs pre-push' "$HOOK" && echo "  alongside   git-lfs pre-push (preserved)"
    else
        echo "  state       not installed"
        grep -qF 'git lfs pre-push' "$HOOK" && echo "  existing    git-lfs pre-push (will be preserved)"
    fi
    echo "  review      $REVIEW"
    [ -f "$REVIEW" ] || echo "  WARNING     review script not found at that path"
    exit 0
    ;;

uninstall)
    if [ ! -f "$HOOK" ] || ! grep -qF "$BEGIN" "$HOOK"; then
        echo "gandolf-local: not installed in $HOOK — nothing to remove."
        exit 0
    fi
    tmp="$(mktemp)"
    # Delete exactly the marked range, so nothing is left behind and the file is
    # byte-for-byte what it was before the install.
    awk -v b="$BEGIN" -v e="$END" '
        index($0, b) == 1 { skip = 1; next }
        index($0, e) == 1 { skip = 0; next }
        !skip { print }
    ' "$HOOK" >"$tmp"
    cat "$tmp" >"$HOOK"
    rm -f "$tmp"
    echo "gandolf-local: removed the gate from $HOOK."
    exit 0
    ;;
esac

# ── install ──────────────────────────────────────────────────────────────────
[ -f "$REVIEW" ] || { echo "gandolf-local: review.sh not found at $REVIEW" >&2; exit 2; }
mkdir -p "$hooks_dir"

if [ -f "$HOOK" ] && grep -qF "$BEGIN" "$HOOK"; then
    # Already installed. Replace the block in place so an updated call site lands
    # without a manual uninstall first.
    tmp="$(mktemp)"
    awk -v b="$BEGIN" -v e="$END" '
        index($0, b) == 1 { skip = 1; next }
        index($0, e) == 1 { skip = 0; next }
        !skip { print }
    ' "$HOOK" >"$tmp"
    cat "$tmp" >"$HOOK"
    rm -f "$tmp"
    echo "gandolf-local: refreshing the existing block."
fi

if [ ! -f "$HOOK" ]; then
    # No hook yet. If LFS is in use it must install its own hooks first: `git lfs
    # install` refuses to touch a hook file it did not write, so creating one here
    # would leave LFS without its pre-push and stop object upload.
    if git config --get filter.lfs.clean >/dev/null 2>&1 && command -v git-lfs >/dev/null 2>&1; then
        git lfs install --local >/dev/null 2>&1 || true
    fi
fi

if [ ! -f "$HOOK" ]; then
    printf '%s\n' '#!/bin/sh' >"$HOOK"
    chmod +x "$HOOK"
    echo "gandolf-local: created $HOOK."
fi

# Prepend immediately after the shebang.
tmp="$(mktemp)"
{
    head -1 "$HOOK"
    emit_block
    tail -n +2 "$HOOK"
} >"$tmp"
cat "$tmp" >"$HOOK"
rm -f "$tmp"
chmod +x "$HOOK"

echo "gandolf-local: installed the pre-push gate in $HOOK."
grep -qF 'git lfs pre-push' "$HOOK" && echo "  git-lfs pre-push preserved below the block."
echo "  status:     bash $HERE/install-hook.sh --status"
echo "  bypass one: GANDOLF_LOCAL=0 git push ..."
echo "  remove:     bash $HERE/install-hook.sh --uninstall"
