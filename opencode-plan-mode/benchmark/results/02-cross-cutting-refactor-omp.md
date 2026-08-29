# Plan: make `fd`'s `print_error` testable via a write sink

## Context

Refactor `crate::error::print_error` so error output can be captured in a buffer and asserted without exiting the process. In-repo verification (this plan is grounded in the cloned `sharkdp/fd` source, commit of the local checkout): the current definition at `src/error.rs:5-8` is `pub fn print_error(msg: impl Into<String>)` — it sanitizes via `maybe_sanitize(&msg, std::io::stderr().is_terminal())` and `eprintln!("[fd error]: {safe}")`, returning `()`. The change: the function takes an `&mut dyn std::io::Write` sink and returns a `Result`, every one of its 10 call sites passes the sink, and the old signature is deleted with no shim. `crate::error` has no `Error` type (verified: `src/error.rs` is 8 lines; the crate uses `anyhow` at the top level), so the Result's error type is `std::io::Error` — the target's `Result<(), Error>` adapts to `std::io::Result<()>` (see Assumptions).

## Approach

**1. Rewrite the definition** — `src/error.rs:5-8` becomes:
```rust
pub fn print_error(sink: &mut dyn std::io::Write, msg: impl Into<String>) -> std::io::Result<()> {
    let msg = msg.into();
    let safe = maybe_sanitize(&msg, std::io::stderr().is_terminal());
    writeln!(sink, "[fd error]: {safe}")
}
```
Terminal detection stays on real stderr (production callers pass `&mut std::io::stderr()`, so detection is unchanged and accurate; test buffers receive the unsanitized text, which is deterministic because test messages contain no ANSI escapes).

**2. Migrate every call site** — complete inventory (grep-verified; 10 sites across 5 files). Every site passes `&mut std::io::stderr()`; the `io::Result` is discarded with `let _ =` because no site's function returns a type that an `io::Error` can convert into (`main` returns `()`, `walk.rs`/`exec/*` return `Result<(), ExitCode>`/`ExitCode`, the `cli.rs` site is inside a `filter_map` closure returning `Option<PathBuf>`); `io::Result` is `#[must_use]`, so bare statement calls would warn. None of the sites change observable behavior:

| Site | Current | New |
|---|---|---|
| `src/main.rs:69` (inside `Err(err)` arm of the `run()` match; then `ExitCode::GeneralError.exit()`) | `crate::error::print_error(format!("{err:#}"));` | `let _ = print_error(&mut std::io::stderr(), format!("{err:#}"));` |
| `src/cli.rs:713` (inside `filter_map` closure in `search_paths`; then `None`) | `print_error(format!("Search path '{}' is not a directory.", path.to_string_lossy()));` | `let _ = print_error(&mut std::io::stderr(), format!("Search path '{}' is not a directory.", path.to_string_lossy()));` |
| `src/walk.rs:229` (in `poll`, `WorkerResult::Error(err)` arm, gated by `show_filesystem_errors`; then continue) | `print_error(err.to_string());` | `let _ = print_error(&mut std::io::stderr(), err.to_string());` |
| `src/walk.rs:256` (in `print`, after a non-BrokenPipe `output::print_entry` error; then `return Err(ExitCode::GeneralError)`) | `print_error(format!("Could not write to output: {e}"));` | `let _ = print_error(&mut std::io::stderr(), format!("Could not write to output: {e}"));` |
| `src/walk.rs:380` (ignore-file match arm `Some(err)`) | `print_error(format!("Malformed pattern in global ignore file. {err}."));` | `let _ = print_error(&mut std::io::stderr(), format!("Malformed pattern in global ignore file. {err}."));` |
| `src/walk.rs:392` (same shape, "custom ignore file") | `print_error(format!("Malformed pattern in custom ignore file. {err}."));` | `let _ = print_error(&mut std::io::stderr(), format!("Malformed pattern in custom ignore file. {err}."));` |
| `src/exec/command.rs:104` (`handle_cmd_error`, `NotFound` arm; then `ExitCode::GeneralError`) | `print_error(format!("Command not found: {}", ...));` | `let _ = print_error(&mut std::io::stderr(), format!("Command not found: {}", ...));` |
| `src/exec/command.rs:111` (`handle_cmd_error`, other-error arm; then `ExitCode::GeneralError`) | `print_error(format!("Problem while executing command: {err}"));` | `let _ = print_error(&mut std::io::stderr(), format!("Problem while executing command: {err}"));` |
| `src/exec/job.rs:27` (in `job`, `WorkerResult::Error` arm, gated by `show_filesystem_errors`; then `continue`) | `print_error(err.to_string());` | `let _ = print_error(&mut std::io::stderr(), err.to_string());` |
| `src/exec/job.rs:57` (in `batch`, `filter_map` closure, same gate; then `None`) | `print_error(err.to_string());` | `let _ = print_error(&mut std::io::stderr(), err.to_string());` |

Existing imports (`src/cli.rs:14`, `src/walk.rs:20`, `src/exec/command.rs:6`, `src/exec/job.rs:2`, and `main.rs`'s full path `crate::error::print_error`) stay unchanged. All other error output flows through these sites (verified: `main.rs:86` `bail!("No valid search paths given.")` surfaces via the `main.rs:69` site).

**3. Delete the old signature** — no compatibility shim, no alias, no deprecated path. Step 1's rewrite is the only definition in `src/error.rs`.

**4. Add unit tests** — `src/error.rs`, `#[cfg(test)] mod tests` (fd convention: inline `#[cfg(test)]` tests, cf. `src/sanitize.rs:158`):
```rust
#[test]
fn writes_message_to_buffer_and_returns_ok() {
    let mut buf = Vec::new();
    let result = print_error(&mut buf, "boom");
    assert!(result.is_ok());
    assert_eq!(String::from_utf8(buf).unwrap(), "[fd error]: boom\n");
}

struct FailingWriter;
impl std::io::Write for FailingWriter {
    fn write(&mut self, _buf: &[u8]) -> std::io::Result<usize> {
        Err(std::io::Error::new(std::io::ErrorKind::Other, "sink down"))
    }
    fn flush(&mut self) -> std::io::Result<()> { Ok(()) }
}

#[test]
fn failing_sink_yields_the_error() {
    let result = print_error(&mut FailingWriter, "x");
    assert!(result.is_err());
    assert_eq!(result.unwrap_err().to_string(), "sink down");
}
```
The first asserts the expected text lands in the buffer and the call returns Ok; the second asserts a failing sink path yields the expected error (the "failing path yields the expected text" requirement, expressed as the propagated `io::Error`).

## Critical files & anchors

- `src/error.rs:5-8` — the definition being rewritten; the new tests attach here.
- `src/main.rs:66-72` — `main`'s `Err` arm; the only process-terminating call site.
- `src/cli.rs:710-718` — `search_paths` filter_map closure; the only `Option`-closure site.
- `src/walk.rs:219-262` — `poll` and `print`; two of the four walk.rs sites, both inside `Result<(), ExitCode>` functions.
- `src/exec/command.rs:100-114` — `handle_cmd_error`; both arms print then return `ExitCode::GeneralError`.

## Verification

- `cargo test` in the fd repo root must pass, including `tests/tests.rs:347-397` (`assert_output`/`assert_failure_with_error` asserting exact stderr strings `[fd error]: Search path 'fake' is not a directory.` etc.) — this is the byte-level proof that the sink migration did not change production output — plus the two new `error.rs` unit tests.
- `cargo build --release` must compile with no warnings (the `let _ =` at every site proves `#[must_use]` handling; `cargo clippy` clean on the touched files).
- Behavior smoke: `target/release/fd --exec totally-not-a-cmd .` prints `[fd error]: Command not found: totally-not-a-cmd` on stderr and exits 1; `target/release/fd foo /definitely/missing` prints `[fd error]: Search path '/definitely/missing' is not a directory.` — both identical to pre-change output.

## Assumptions & contingencies

- **`Result<(), Error>` ⇒ `std::io::Result<()>`**: `crate::error` has no `Error` type (verified: 8-line module), so the sink write's natural error is `std::io::Error`. If an fd-specific `Error` type is wanted instead, define it in `src/error.rs` and `.map_err()` the `writeln!` — the callsite table above is unaffected.
- **`let _ =` policy**: no site propagates the `io::Result` via `?` because no site's return type accepts `io::Error` without a signature change rippling beyond this refactor (the target's decisive test — every callsite migrated, no shim — is met). If a future function returns `io::Result`, it can `?` directly.
- **Sanitize terminal detection** stays `std::io::stderr().is_terminal()`: production callers pass stderr so detection is exact; buffer tests are deterministic because `maybe_sanitize` only rewrites ANSI sequences, which test messages do not contain.
- **No docs/changelog updates needed**: grep found no documentation referencing `print_error` or the `[fd error]:` prefix outside `src/` and `tests/`; the integration tests pin the format.
