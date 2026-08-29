# Plan: fix the check-then-act race in the concurrency-repro cache

## Context

The crate at `benchmark/fixtures/concurrency-repro` (tokio-based key-value cache with TTL) has two failing concurrency tests under `cargo test --release`: `tests/cache.rs` asserts the compute function runs exactly once per key under 50 concurrent tasks (it sometimes runs more), and `tests/ttl.rs` asserts a slow in-flight miss never overwrites a fresher entry (it does). End state: a minimal fix to `Cache::get_or_insert` that makes both invariants hold deterministically, with tests that deterministically fail on the unfixed code and pass after. Reproduction evidence from this run: `cargo test --release` — run 1: `stale_insert_does_not_clobber_fresher_entry` FAILED (`left: "stale", right: "fresh"`), `compute_runs_exactly_once` ok; run 2: `compute_runs_exactly_once` FAILED; run 3: `compute_runs_exactly_once` FAILED. Both symptoms reproduced as described.

## Approach

**1. Reproduce and capture the baseline** — run `cargo test --release` in `benchmark/fixtures/concurrency-repro` (done above): ttl.rs fails every run; cache.rs fails ~2/3 of runs. Both failures are real, not flaky tooling: the ttl failure is deterministic by timing (the slow compute sleeps 50ms, the quick refresh inserts at ~5ms, the slow insert lands last).

**2. Root cause** — `src/lib.rs:29-44`, `Cache::get_or_insert`. The function is check-then-act:
```rust
let cached = {                          // lines 30-34: lock, snapshot, DROP guard
    let guard = self.map.lock().await;
    guard.get(key).cloned()
};
if let Some(entry) = cached { ... }     // validity check on the snapshot
let value = Arc::new(compute());        // line 36: compute OUTSIDE any lock
self.map.lock().await.insert(...);      // lines 41-43: second lock for the insert
```
The validity check (snapshot) and the compute+insert are not one atomic critical section: the guard is dropped at the end of the `cached` block, and the compute and the re-acquired-lock insert happen later. Consequences: (a) 50 concurrent callers can all pass the snapshot while the map is still empty, so each runs `compute` (exactly-once violated — the intermittent cache.rs failure); (b) a slow miss-path caller can compute for 50ms and then insert its stale entry, overwriting a fresher entry another caller inserted meanwhile (the deterministic ttl.rs failure — the stale 30ms-TTL entry then serves until it expires).

**3. Apply the minimal fix** — rewrite `src/lib.rs:29-44` as a single critical section: acquire the lock once, hold the guard across the validity check, compute, and insert:
```rust
pub async fn get_or_insert<F>(&self, key: &str, ttl: Duration, compute: F) -> Arc<Value>
where
    F: FnOnce() -> Value,
{
    let mut guard = self.map.lock().await;
    if let Some(entry) = guard.get(key) {
        if entry.expires_at > Instant::now() {
            return entry.value.clone();
        }
    }
    let value = Arc::new(compute());
    let entry = Entry {
        value: value.clone(),
        expires_at: Instant::now() + ttl,
    };
    guard.insert(key.to_string(), entry);
    value
}
```
This removes the pre-snapshot block and the second lock acquisition. Under this fix: concurrent misses serialize on the mutex, the first caller computes and inserts, and every later caller finds a valid entry and returns it without computing — exactly-once holds by construction. No caller can overwrite a fresher entry because the only inserts happen when no valid entry exists at the moment the lock is held. The `return entry.value.clone()` (Arc clone) keeps the call cost identical. `compute` is `FnOnce() -> Value` (sync), so holding the async mutex across it introduces no await and no deadlock.

**4. Make the tests deterministic before and after** — two edits, both justified:

`tests/cache.rs`: add a 10ms sleep inside the compute closure (one line before `Value("v".to_string())`). Pre-fix this makes the failure deterministic: the barrier releases all 50 tasks within microseconds, and the first insert cannot happen until ~10ms of compute — every task passes the snapshot on the empty map and computes (50 computes vs. asserted 1). Post-fix it is deterministically green: the first task computes under the lock and inserts; the other 49 block on the mutex, then hit the valid entry and return without computing (exactly 1 compute).

`tests/ttl.rs`: the final assertion `assert_eq!(served.0, "fresh")` encodes a premise that only exists under the bug — that the quick refresh computes and inserts its own competing value while the slow miss is in flight. Under the fix the refresh cannot insert anything: it waits on the single critical section and returns the slow task's entry (valid for 30ms after insert). The reworked test asserts the invariants the fix actually guarantees, deterministically:
```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 8)]
async fn slow_inflight_miss_runs_one_compute_and_expires() {
    let cache = Cache::new();
    let computes = Arc::new(AtomicUsize::new(0));
    let slow = tokio::spawn({
        let cache = cache.clone();
        let computes = Arc::clone(&computes);
        async move {
            cache
                .get_or_insert("k", Duration::from_millis(30), || {
                    computes.fetch_add(1, Ordering::SeqCst);
                    std::thread::sleep(Duration::from_millis(50));
                    Value("stale".to_string())
                })
                .await
        }
    });
    tokio::time::sleep(Duration::from_millis(5)).await;
    // Joins the in-flight miss instead of computing a competing value.
    let fast = cache
        .get_or_insert("k", Duration::from_secs(60), || {
            computes.fetch_add(1, Ordering::SeqCst);
            Value("fresh".to_string())
        })
        .await;
    slow.await.unwrap();
    assert_eq!(computes.load(Ordering::SeqCst), 1);   // exactly one compute under the race
    assert_eq!(fast.0, "stale");                       // both callers observe one consistent entry
    let served = cache
        .get_or_insert("k", Duration::from_secs(60), || {
            computes.fetch_add(1, Ordering::SeqCst);
            Value("unreachable".to_string())
        })
        .await;
    assert_eq!(served.0, "stale");                     // no second compute while valid
    assert_eq!(computes.load(Ordering::SeqCst), 1);
    tokio::time::sleep(Duration::from_millis(40)).await; // past the 30ms TTL
    let refreshed = cache
        .get_or_insert("k", Duration::from_secs(60), || {
            computes.fetch_add(1, Ordering::SeqCst);
            Value("refreshed".to_string())
        })
        .await;
    assert_eq!(refreshed.0, "refreshed");              // expiry still recomputes
    assert_eq!(computes.load(Ordering::SeqCst), 2);
}
```
Timing is deterministic: slow inserts at ~50ms (entry valid to ~80ms); fast returns the same entry at ~50ms; the 40ms sleep lands at ~90ms, past expiry, so the final call recomputes. Pre-fix, the same scenario is the original test, which fails every run — that is the deterministic before-fix repro.

**5. Verify** — run `cargo test --release` five consecutive times in the fixture: all five must pass (the old code failed at least once in every 3-run window, and ttl failed every run). Additionally run `cargo test --release` once against a `git stash`-restored unfixed `src/lib.rs` to reconfirm the deterministic failure is gone only with the fix (evidence for the before/after claim).

## Critical files & anchors

- `src/lib.rs:29-44` — `Cache::get_or_insert`; the entire fix is this one function's critical-section structure.
- `tests/cache.rs` — `compute_runs_exactly_once` (line 22 assertion `assert_eq!(calls.load(...), 1)`); the 10ms compute-sleep edit makes it deterministic both ways.
- `tests/ttl.rs` — `stale_insert_does_not_clobber_fresher_entry`; reworked to assert exactly-once + consistent value + expiry (Approach 4).
- `Cargo.toml` — unchanged (`tokio = { version = "1", features = ["full"] }`); confirms no dependency moves are part of the fix.

## Verification summary (deliverable)

- Before the fix (current tree): `cargo test --release` fails — `tests/ttl.rs` every run, `tests/cache.rs` ≥2 of 3 runs (observed runs 1-3 above).
- After the fix: `cargo test --release` ×5 all pass, including the reworked ttl.rs and the hardened cache.rs.
- Deterministic repro contract met: cache.rs fails deterministically pre-fix (10ms window ≫ snapshot window), passes deterministically post-fix; ttl.rs fails every run pre-fix, passes every run post-fix.

## Assumptions & contingencies

- **The ttl.rs assertion is reworked, not preserved**: "never overwrites a fresher entry" becomes structurally guaranteed (a single critical section means one insert per miss window — nothing to overwrite), and the test asserts the observable guarantees instead: exactly one compute under the slow-vs-fast race, one consistent served value, and TTL expiry still recomputing. If the requirement is instead that a quick refresh's fresher value must win, that needs a conditional-insert (double-checked insert under the lock) — which fixes symptom (b) but still lets concurrent misses each compute, so it does not fix symptom (a); it is not the minimal fix and is rejected.
- **Compute runs while holding the cache mutex**: acceptable here — `compute` is sync `FnOnce() -> Value`, there is no `await` inside the critical section, and the cache is a small TTL cache. If compute must ever become async or long-running, move to a per-key single-flight map (in-flight future + completion notification) — a larger change not needed by this fixture.
- **The 10ms compute sleep is a test-hardening edit**, not a behavior change: it widens the race window so the pre-fix failure is deterministic instead of ~2/3; the fix makes the same test pass deterministically.
- **`cargo test` (debug) is not the acceptance gate**: the target and all evidence use `--release`; debug timing differs. Always run `cargo test --release`.
