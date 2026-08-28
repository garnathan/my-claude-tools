---
name: gandolf-local
description: Run the DFL repository's gandolf pull-request review LOCALLY, before pushing, so the automated reviewer has nothing left to comment on. Five parallel reviewers (code, security, memory, concurrency, plus one that predicts the CI reviewer itself), a deterministic rule sweep that greps for the violations gandolf always flags, then apply every finding down to NIT and re-verify. Use when the user says "run gandolf locally", "review before I push", "pre-push review", "preempt gandolf", "what will gandolf say", or asks to get a branch ready for a PR. Also the right skill when a gandolf review has already posted comments and the user wants the next round to come back clean. Backed by a blocking pre-push git hook, so a push refused with "gandolf-local: BLOCKED" is this skill asking to be run.
---

# gandolf-local

The DFL repository reviews every pull request with an automated reviewer called
gandolf. Its entire prompt in
[.github/workflows/claude-code-review.yml](.github/workflows/claude-code-review.yml)
is "run the repo's `/full-review` skill" — so the review is checked into the
repository as `.claude/skills/full-review/SKILL.md`, and roughly three hundred
lines of that workflow are GitHub plumbing rather than review.

This skill runs that review **before the push**, with two additions aimed at one
goal: **gandolf should find nothing.** Every comment it posts costs a review
round and a bot fix commit on the branch.

The two additions are a deterministic rule sweep, and a fifth reviewer whose lens
is gandolf itself.

## The parts

Everything lives beside this file, under `assets/`:

| File | What it does |
|---|---|
| `review.sh` | The orchestrator. Pre-gate, five reviewers in parallel, consolidation, verdict, receipt. |
| `pregate.sh` | The deterministic half: Rule 0, the rule sweep, `compliance.py`, `env_defaults.py`, clippy and `cargo-shear` per touched crate, scoped tests. |
| `gandolf-bait.sh` | Greps the added lines for the rule violations gandolf is certain to flag. Seconds, no build. |
| `lenses/_common.md` | The shared reviewer brief: conventions, severity ladder, required finding shape. |
| `lenses/{code,security,memory,concurrency}.md` | The four specialist lenses gandolf runs. |
| `lenses/gandolf.md` | The fifth lens: predict the comments the CI reviewer will post. |
| `learn-from-pr.sh` | The feedback loop. Pulls what gandolf actually posted on a pull request, scores the local gate against it, and proposes the lens edit for each miss. |
| `install-hook.sh` | Composes the gate into `.git/hooks/pre-push`, preserving the Git LFS hook already there. |

## Running it

The scripts are the fast path, and the pre-push hook calls them on its own. Use
them directly when the user just wants the gate run:

```bash
S=~/.claude/skills/gandolf-local/assets

bash $S/gandolf-bait.sh            # seconds — the certain rule violations
bash $S/pregate.sh --quick         # seconds — build-free checks only
bash $S/pregate.sh                 # minutes — adds clippy, shear, scoped tests
bash $S/review.sh                  # the full gate, five reviewers
bash $S/review.sh --status         # what the last review decided
bash $S/review.sh --check          # exit 0 if this exact tree has a passing review
```

Useful flags: `--base <ref>` (default `origin/main`), `--include-worktree` to
review uncommitted changes too, `--lens <name>` for one lens, `--quick-pregate`
to skip the build, `--skip-pregate` when you have just run it. `pregate.sh` also
takes `--no-test` and `--rule0-only` (the commit-scoped sweep on its own, which
is what `--check` re-runs on every push).

Three things the pre-gate does that are worth knowing, because each one exists to
stop it reporting something untrue:

- **It adopts the repository's own toolchain settings.** `dfl/config.mk` — written
  by `./configure`, machine-local — pins `PYO3_PYTHON` and `DYLD_LIBRARY_PATH`.
  The clippy step inherits them through make; the `cargo test` step invokes cargo
  directly, so the pre-gate reads that file and exports them itself. Without it,
  cargo picks up whatever `python3` is first on `PATH`, and PyO3 0.24 rejects
  anything newer than 3.13 outright — three crates fail to build for a reason
  that has nothing to do with your change.
- **It skips the JDBC bridge jar build when there is no JDK**, using the
  repository's own `DFL_SKIP_JDBC_BRIDGE_JAR_BUILD=1`, and says so. `dfl-core`'s
  build script shells out to `tools/jdbc/build-bridges.sh`, which hard-exits
  without `javac`; that fails `dfl-core`, and anything with it as a
  dev-dependency. Note it tests that `javac` *works*, not that it exists —
  macOS ships stub `java` and `javac` on a machine with no JDK at all.
- **It tells a test-isolation race apart from a real failure.** A crate's unit
  tests share one process, so a test that writes a process-wide environment
  variable leaks into the others. When a crate's tests fail, the pre-gate re-runs
  each failing test on its own; passing alone while failing in the group is the
  signature of an ordering race, so it reports the race by name instead of
  blocking the push. Nothing is hidden and this is not "retry until green" — if a
  test fails alone as well, the failure stands. Two such races exist in the
  workspace today, each around a process-wide variable a test sets;
  `dfl/CLAUDE.md` Rule 21 asks for them to be fixed rather than re-run.

Knobs, all environment variables: `GANDOLF_LOCAL=0` skips the hook for one push,
`GANDOLF_LOCAL_STRICT=1` makes the hook require the low tiers cleared as well,
`GANDOLF_LOCAL_MODEL` (default `opus`), `GANDOLF_LOCAL_TIMEOUT` (default 1800
seconds per reviewer), `GANDOLF_LOCAL_BASE`.

## Running it as this session's own work

When the user wants you to *do* the review rather than shell out — because they
want the findings fixed in the same pass — run these phases yourself.

### Phase 1 — pre-flight

```bash
git fetch origin main --quiet
git status --porcelain
git log --oneline origin/main..HEAD
```

Confirm the base is current, and decide whether uncommitted work is in scope. A
push carries commits, so the hook judges commits; if the user is mid-change,
either commit first or pass `--include-worktree` and say which you did.

Then run the deterministic half and **fix what it reports before spending a
reviewer on it**:

```bash
bash ~/.claude/skills/gandolf-local/assets/pregate.sh --report /tmp/pregate.md
```

A clippy finding, a missing environment-variable entry, or a stray TODO is
cheaper to fix here than to have five reviewers describe.

### Phase 2 — five reviewers, in parallel, in one message

Fire all five with the Agent tool in a **single message**, `subagent_type:
"general-purpose"`, and give each one:

- the shared brief `assets/lenses/_common.md`, verbatim;
- its own lens file, verbatim;
- the diff path, the changed-files path, the base and head, and an instruction to
  read `.claude/skills/full-review/SKILL.md` for the lens paragraph gandolf uses.

**Never end your turn while a reviewer is still running.** The CI skill carries
this warning because it happened in CI: the orchestrator ended
after 24 turns with all four reviewers pending, the session died, and the run
posted nothing while reporting success. If the harness returns reviewers by
notification, keep working — corroborate findings against the code yourself —
and consolidate only once every report is in hand.

### Phase 3 — consolidate, and cut only what is false

Merge duplicates across lenses. Then check each finding against the code and drop
it **only** when the line does not say what the finding claims, the failure is
unreachable, it requests no change, or it duplicates a kept finding.

Do not drop a finding for being small. Tier it — `CRITICAL`, `HIGH`, `MEDIUM`,
`LOW`, `NIT` — and keep it. The low tiers are the point of this skill: they are
what comes back as pull-request comments.

Write the consolidated report to a file and show the user the tier counts.

### Phase 4 — fix everything, including the nits

Every tier gets a real code change in this branch. The repository forbids a
follow-up TODO, and its own review skill says a LOW finding still earns a commit
rather than a ticket.

Commit discipline: one commit per logical group, not one per finding and not one
giant commit. Name the lens that raised it, for example `address concurrency
review — lock-order fix and spawn_blocking on open_or_create`. Run the nearest
test target for each group.

Two things to watch, both from experience with the CI reviewer:

- **Do not write a claim you have not made true.** Gandolf once added a comment
  saying a gap "is tracked as a separate change" when nothing tracked it. If a fix
  needs to reference an issue, open the issue.
- **Do not silence a finding you disagree with.** Answer it in the report with the
  reason, and say so to the user. A finding dismissed silently comes back as a
  pull-request comment.

### Phase 5 — re-verify, then hand back

Fixing changes the diff, so the receipt no longer applies — that is deliberate.
Re-run the gate:

```bash
bash ~/.claude/skills/gandolf-local/assets/review.sh
```

Target `PASS` with zero findings at every tier. `CONDITIONAL PASS` with nits
outstanding means gandolf still has something to say; tell the user exactly what
is left and why you left it, rather than reporting the branch as clean.

Then the push is the user's call. Never push or open a pull request unless they
asked for it. When they do, remember that a new pull request opens as a **draft**
(Rule 14), and that the CI review still runs — this gate reduces what it finds,
it does not replace it.

## The pre-push hook

```bash
bash ~/.claude/skills/gandolf-local/assets/install-hook.sh            # install
bash ~/.claude/skills/gandolf-local/assets/install-hook.sh --status   # report
bash ~/.claude/skills/gandolf-local/assets/install-hook.sh --uninstall
```

Three details matter:

- **Git LFS owns `pre-push` in this repository.** The gate is composed in above
  the LFS line, never replacing it, because this repository keeps real build
  inputs in LFS — the ONNX model, the JDBC jars, the DuckPGQ extension — and a
  replaced hook stops them uploading silently. The block also captures standard
  input, uses it, and restores it with `exec`, because LFS reads the ref list
  from there.
- **A receipt is keyed by the content of the diff**, not by the branch. This is
  the local counterpart of CI's `gandolf-full-reviewed` label with its flaw
  removed: that label sticks to a pull request across later commits, so a green
  review can sit over a diff nobody read. Change one line and the receipt stops
  applying. Because a diff carries no commit author or message, `--check` also
  re-runs the commit-scoped Rule 0 sweep every time — otherwise amending a
  message to add a `Co-authored-by:` trailer would keep a passing receipt while
  changing the one thing that check exists to catch.
- **A cancelled push cancels the review.** The hook runs the review in the
  background and traps the interrupt signals, so Ctrl-C kills the whole process
  group. Without that, an interrupted push left the review and five model
  processes running detached with nobody to read the result — observed for real,
  with the launcher reparented to init.
- **Inside an agent session the hook refuses rather than reviewing.** A nested
  review would outlive the tool call that triggered it and hit that call's
  timeout. So it blocks with the command to run, which is the enforcement the
  gate exists for. If you are an agent and a push is refused this way, run the
  review — do not set `GANDOLF_LOCAL=0` unless the user tells you to.
- **A narrowed run cannot unlock a push.** The receipt records which lenses ran
  and whether the deterministic half ran, and `--check` requires both to be
  complete. This matters because the script's own advice when a reviewer fails is
  to re-run one lens, so without the scope check the documented way to debug the
  tool was also a way to unlock a push having reviewed a fifth of the change. A
  receipt written before that field existed counts as incomplete.
- **It fails closed.** If the review script is missing — the skill moved, renamed,
  or absent on another machine — the hook blocks and says so. Skipping would let
  every push through a gate that looks installed and enforces nothing.
- **Uninstall refuses rather than guessing.** Removing the block is a destructive
  edit to a file whose remaining line is `git lfs pre-push`, so it checks there is
  exactly one begin and one end marker in the right order first, and keeps a
  `.gandolf-local.bak` copy. A partially-marked block used to delete everything to
  the end of the file, taking the Git LFS invocation with it.

## Closing the loop after a real review

A local review that is merely good does not drive the comment count down on its
own. What drives it down is knowing which comments the local gate failed to
predict. So whenever gandolf does post a review, feed it back:

```bash
bash ~/.claude/skills/gandolf-local/assets/learn-from-pr.sh <pr-number>
```

It collects every marker-free comment gandolf posted — across the conversation,
its formal reviews, and its inline diff comments — finds the local report for the
same commit through the receipts, and reports three things: what was predicted,
what was missed, and the exact lens edit for each miss. A miss a grep could catch
belongs in `gandolf-bait.sh` rather than in a lens, and it says which is which.

Read the amendments before applying them; they edit the prompts the gate runs on,
so nothing is applied automatically. Then commit the lens change in
`my-claude-tools`, so the next branch starts from the improved version.

One thing already learned this way: gandolf's review format on a real pull
request has a `### Nits (optional)` section. Nits genuinely come back as
comments, which is why the shared brief tells reviewers to report them rather
than filter them — the opposite of the calibration in
[.github/review-prompt-impl.md](.github/review-prompt-impl.md), which belongs to
a different workflow and is not what the pull-request reviewer runs.

## What this gate does not cover

Say so rather than implying full parity:

- **No live backend.** The CI reviewer runs with an OCI api-key profile, an ADB
  wallet, and OCI GenAI wired up, so it can reproduce a live gate. Locally
  `~/.oci/config` holds session tokens under tenancy-named profiles, so a
  live-path finding comes back as "pending verification" unless you run
  `ociauth status` and point the check at a real profile.
- **No `make test-ci`.** The pre-gate runs clippy, `cargo-shear`, and library
  tests for the touched crates. The full suite takes hours and belongs in CI.
- **The CI review still runs.** A pull request that opens non-draft still fires
  the four-reviewer gate, and this skill's job is to make that pass first time.
