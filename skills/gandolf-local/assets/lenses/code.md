# Your lens: CODE

Correctness first. Then API design, error handling, and test shape.

Look for:

- **Logic bugs a real input triggers** — off-by-one, inverted condition, wrong
  operator precedence, an early `return` that skips cleanup, a `match` arm that
  swallows a case, integer overflow or truncation, a wrong default.
- **Boundary and empty cases** — empty collection, single element, zero rows, a
  `None` where the code assumes `Some`, a slice index that can exceed length, an
  unwrap on a value the caller can make `None`.
- **Error handling** — `unwrap()` / `expect()` / `panic!` on a path that user
  input or a network reply can reach; an error swallowed with `let _ =` or
  `.ok()` where the caller needed to know; an error mapped to a type that loses
  the cause; a missing stable error ID on a compile or execute path.
- **Test shape, not test count** — a risky new path with no test; an assertion
  weakened or deleted by this change; a test that asserts the code's own output
  back at itself rather than the intended behaviour; a test that would pass if
  the feature were removed. In this repo a compilation-only test is a unit test,
  never an end-to-end test: flag a change that claims end-to-end coverage but
  only compiles DFL without executing it against a real backend.
- **Rule violations from the shared brief** — a TODO, a stub, a mock, a silent
  fallback; a reimplementation of something already in the workspace; a missing
  error ID; an undocumented new environment variable.
- **Dead code and drift** — a branch that can never be taken, a parameter never
  read, a function no caller reaches, a doc comment that contradicts the body,
  a constant duplicated instead of imported.
- **False claims** — a code comment, commit message, doc line, README, or CI
  workflow comment in this diff that asserts something untrue: an issue number
  that does not exist or does not track the thing, "covered by X" where X does
  not cover it, "already tested" where no test exists. When a doc, a workflow
  name, or a step comment describes what a suite runs — which browsers, which
  projects, "the same four checks", "desktop plus two phone viewports" — open the
  config it refers to and count what really runs. A count word that disagrees
  with the list beside it is a finding, and so is a comparison check whose comment
  omits an assumption it depends on. Check each one.

Do not review for memory, locking, or security posture — three other reviewers
own those. If you notice something there, mention it in one line under Residual
risks rather than writing it up as a finding.
