# Your lens: CONCURRENCY, LOCKING AND DURABILITY

Look for:

- **A lock held across an `.await`.** This is the single most common defect in
  this repository. Trace the guard's scope, not just the line it is created on:
  a guard bound to a variable lives to the end of its block, so any `.await`
  after it — including inside a called function, a `?` that awaits, or a loop
  body — holds the lock. Name the exact `.await`.
- **An embedded tokio runtime in library code** — `reqwest::blocking::Client`,
  `tokio::runtime::Runtime::new()`, `Builder::new_current_thread().build()`, or
  `block_on` on a runtime this code created, anywhere reachable from a
  `dfl-http` async handler. Dropping it on a tokio worker panics, the panic is
  swallowed, and the write is skipped — a silent false success. The correct
  bridges are `spawn_blocking`, `block_on_async`, and
  `block_on_async_or_thread`.
- **Lock ordering and scope** — two locks acquired in different orders on two
  paths; a lock held while doing I/O, a large allocation, or CPU-bound work that
  could be done after cloning the data out; a write lock taken for a read-only
  operation; `Arc<Mutex<T>>` on a read-dominated structure that wants `RwLock`;
  `std::sync` where the codebase uses `parking_lot`.
- **Read starvation and fairness** — a writer that can be starved, or a reader
  path that takes the write lock; a long-held read lock blocking a needed write.
- **Time-of-check to time-of-use races** — an existence or capacity check
  followed by an act on the result, with the state readable or writable by
  another task in between. Includes "read the manifest, then write" and "check
  the version, then commit" without a compare-and-set.
- **CPU-bound work inside an async handler** with no `spawn_blocking` — parsing,
  compression, hashing, embedding, or index building on a tokio worker thread.
- **Durability and commit ordering** — a write not flushed or fsynced before the
  pointer that names it is published; a local snapshot bumped before the backend
  commit rather than after; an atomic-pointer write with no ETag compare-and-set
  and no typed retry on a 412; a destroy before its replacing commit; a
  concurrent read-modify-write across replicas with no lease making it
  single-flight.
- **At-least-once delivery treated as exactly-once** — a retry that is not
  idempotent; an unknown send outcome that releases its slot; a fold that
  accepts a result from a superseded attempt with no fencing.
- **Cancellation and shutdown** — a task that leaks on cancel; a `select!` arm
  that drops work in flight; a spawned task holding a guard past the request; a
  shutdown path that does not drain.
- **Test-level races** — a new test sharing a fixed path, port, temp directory,
  or process-wide environment variable with another test; an assertion on
  `HashMap` iteration order, wall-clock timing, or completion order. In this
  repository a flaky test is a live defect to fix, not something to re-run.

Do not review for general correctness, memory, or security — three other
reviewers own those.
