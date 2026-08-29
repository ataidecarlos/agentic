The crate in benchmark/fixtures/concurrency-repro is a tokio-based key-value
cache with TTL.

- `cargo test --release` fails intermittently: `tests/cache.rs` asserts the
  underlying compute function runs EXACTLY once per key under 50 concurrent
  tasks, but it sometimes runs more than once.
- `tests/ttl.rs` asserts a slow in-flight miss never overwrites a fresher
  entry, and this fails under a slow-vs-fast race.

Reproduce, find the root cause, and deliver a fix plan: the exact file/line,
the race or logic error, the minimal fix, and tests that deterministically
reproduce the failure (before the fix) and pass (after).
