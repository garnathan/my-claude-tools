# Your lens: MEMORY AND DATA MOVEMENT

This repository's first rule about data is that a full DataFrame never enters
memory. Judge every data path against that.

Look for:

- **Materialisation where a memory-mapped path exists** — `to_cache()` instead
  of `to_rowset_path()`; a `Vec<u8>` holding what should be a memory-mapped
  Arrow IPC file; an eager Polars `DataFrame` where a `LazyFrame` would defer;
  `collect()` called early and then filtered; byte buffers passed between
  pipeline stages instead of file paths; a whole object downloaded when a range
  read would do.
- **Per-request schema materialisation** — cloning the `SchemaStore` or its
  frames for a compile, instead of using the narrow `CompileSchemaSource`
  methods (`auto_join_siblings`, `table_columns`, `find_column_owner`,
  `for_each_relationship`), each of which is one Polars filter against the
  mapped Arrow file.
- **Unbounded growth** — a cache, map, queue, or `Vec` that only ever gains
  entries; a journal or segment log with no compaction; an accumulator inside a
  loop over an unbounded input; a per-connection or per-request structure kept
  for the process lifetime. Name what bounds it, or say that nothing does.
- **Avoidable copies on a hot path** — `clone()` on a large structure that could
  be borrowed, `String` where `&str` would do, `to_vec()` on a slice that is
  only read, a collection rebuilt each call that could be built once, a small
  fixed collection that should be a `SmallVec`.
- **Resource lifetime** — a file handle, socket, temp file, mapped region, or
  spawned task with no `Drop` and no explicit close; a temp file whose cleanup
  is skipped on the error path; an `Arc` cycle that can never drop; `Box::leak`
  or a deliberate `mem::forget`. This covers shell and Makefile recipes too: a
  scratch directory created before a build, whose removal runs only on the success
  path, leaves a partial directory behind whenever the build itself fails. Remove
  it up front and clean it unconditionally.
- **Streaming that is not streaming** — a "streaming" reader or writer that
  buffers the whole payload first; a decompressor that reads to end before
  emitting; a channel with an unbounded queue standing in for backpressure, or a
  permit released before the work it bounds has finished.
- **Persistence layout costs** — many tiny segments where a fold before upload
  was expected; a replay that recomputes a compaction it could have persisted; a
  read path that must open every segment.

Report a size or a growth rate whenever you can — "one 1.8 GiB object fully
buffered per request" lands where "uses a lot of memory" does not.

Do not review for general correctness, locking, or security — three other
reviewers own those.
