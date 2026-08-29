# Opencode plan agent output — target 02

## Plan artifact (plans/print-error-testable-plan.md, verbatim)

# Make `print_error` testable via a caller-supplied sink

## Context

`crate::error::print_error` (src/error.rs:5-8) hardcodes stderr (`eprintln!("[fd error]: {safe}")`) and returns `()`, so error output cannot be captured in unit tests. In-repo verification: the function does not itself terminate — `ExitCode::GeneralError.exit()` lives at the call sites (e.g. main.rs:70) — and the task is the signature refactor, not the termination. The end state: `print_error` takes a caller-supplied `&mut dyn std::io::Write` sink and returns `Result<(), anyhow::Error>`, all 10 call sites pass a sink and handle the Result, the old signature is deleted with no shim, and unit tests prove buffer-write success and write-failure propagation. Byte-identical stderr output must be preserved because integration tests pin the exact `[fd error]: ` text (tests/tests.rs:348, 365-373, 389, 395, 431).

## Approach

### 1. Rewrite the contract in `src/error.rs` (new signature + unit tests)

Replace the whole file body with:

```rust
use crate::sanitize::maybe_sanitize;

pub fn print_error(
    sink: &mut dyn std::io::Write,
    is_terminal: bool,
    msg: impl Into<String>,
) -> anyhow::Result<()> {
    let msg = msg.into();
    let safe = maybe_sanitize(&msg, is_terminal);
    writeln!(sink, "[fd error]: {safe}")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn print_error_writes_message_to_buffer() {
        let mut buffer = Vec::new();
        let result = print_error(&mut buffer, false, "something went wrong");
        assert!(result.is_ok());
        assert_eq!(
            String::from_utf8(buffer).unwrap(),
            "[fd error]: something went wrong\n"
        );
    }

    #[test]
    fn print_error_propagates_sink_write_failure() {
        struct FailingSink;

        impl std::io::Write for FailingSink {
            fn write(&mut self, _buf: &[u8]) -> std::io::Result<usize> {
                Err(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    "sink write failed",
                ))
            }

            fn flush(&mut self) -> std::io::Result<()> {
                Ok(())
            }
        }

        let mut sink = FailingSink;
        let err = print_error(&mut sink, false, "message").unwrap_err();
        assert!(err.to_string().contains("sink write failed"));
    }
}
```

- **Exact new signature:** `pub fn print_error(sink: &mut dyn std::io::Write, is_terminal: bool, msg: impl Into<String>) -> anyhow::Result<()>`. `anyhow::Error` is the crate's error type — no `crate::error::Error` type exists (grep verified: no `struct Error`/`enum Error`/`type Error` in src/; main.rs, walk.rs, exec/mod.rs, cli.rs all use `anyhow::Result`).
- **Delete** `use std::io::IsTerminal;` (was line 1) — the terminal flag is now a parameter. Delete the old `pub fn print_error(msg: impl Into<String>)` (lines 5-8). No compatibility alias or shim; grep confirms only the 10 call sites and the 4 `use crate::error::print_error;` imports reference it.
- The `?` converts `io::Error` → `anyhow::Error` via `From`; no new imports needed in error.rs.
- Error handling of the new path: empty `msg` writes `[fd error]: \n` (unchanged from old behavior); a sink write failure returns `Err` wrapping the `io::Error` (old `eprintln!` panicked — this is the behavior the refactor replaces).
- `is_terminal: bool` is a deliberate addition to the literal "sink + Result" ask: a `&mut dyn Write` cannot be queried with `std::io::IsTerminal`, and computing the flag from the global stderr inside the function would make the buffer test depend on whether the test runner's stderr is a TTY. It mirrors the existing pattern of computing the flag once and threading it (main.rs:277 `std::io::stdout().is_terminal()` → `Config.interactive_terminal`, consumed by `output.rs`).

### 2. Propagate through `anyhow::Result` channels (call sites 2, 5, 6)

These three calls sit in functions returning `anyhow::Result`; use `?`.

- **cli.rs `Opts::search_paths` (line 713)** — the `filter_map` closure cannot return a Result, so restructure to a loop with `?` (only site needing control-flow change; ordering and output unchanged):

```rust
    pub fn search_paths(&self) -> anyhow::Result<Vec<PathBuf>> {
        // would it make sense to concatenate these?
        let paths = if !self.path.is_empty() {
            &self.path
        } else if !self.search_path.is_empty() {
            &self.search_path
        } else {
            let current_directory = Path::new("./");
            ensure_current_directory_exists(current_directory)?;
            return Ok(vec![self.normalize_path(current_directory)]);
        };

        let mut valid_paths = Vec::new();
        for path in paths {
            if filesystem::is_existing_directory(path) {
                valid_paths.push(self.normalize_path(path));
            } else {
                print_error(
                    &mut std::io::stderr(),
                    std::io::stderr().is_terminal(),
                    format!(
                        "Search path '{}' is not a directory.",
                        path.to_string_lossy()
                    ),
                )?;
            }
        }
        Ok(valid_paths)
    }
```

- **walk.rs `WorkerState::build_walker` (lines 380, 392)** — inside each `Some(err)` match arm of the `builder.add_ignore(...)` results (global and custom ignore files):

```rust
                    Some(err) => {
                        print_error(
                            &mut std::io::stderr(),
                            std::io::stderr().is_terminal(),
                            format!("Malformed pattern in global ignore file. {err}."),
                        )?;
                    }
```
```rust
                    Some(err) => {
                        print_error(
                            &mut std::io::stderr(),
                            std::io::stderr().is_terminal(),
                            format!("Malformed pattern in custom ignore file. {err}."),
                        )?;
                    }
```

### 3. Propagate through the `ExitCode` error channel (call site 3)

- **walk.rs `ReceiverBuffer::poll` (line 229)** — the enclosing function returns `Result<(), ExitCode>`, so map the write failure into that channel (`ExitCode` is already imported in walk.rs):

```rust
                        WorkerResult::Error(err) => {
                            if self.config.show_filesystem_errors {
                                print_error(
                                    &mut std::io::stderr(),
                                    std::io::stderr().is_terminal(),
                                    err.to_string(),
                                )
                                .map_err(|_| ExitCode::GeneralError)?;
                            }
                        }
```

### 4. Discard at `()`/`ExitCode`/`Option` call sites (call sites 1, 4, 7, 8, 9, 10)

These sites cannot propagate (no `anyhow::Result` in scope) and either exit with `ExitCode::GeneralError` immediately after the call or are non-fatal diagnostics. Use `let _ =` with a one-line comment; `let _` trips no default warnings and CI clippy runs `-Dwarnings` without pedantic lints.

- **main.rs `main()` Err arm (line 69)** — `IsTerminal` already imported (main.rs:18):

```rust
        Err(err) => {
            // The process exits with an error code immediately below; if the
            // error message itself cannot be written, there is nothing left
            // to report or act on.
            let _ = crate::error::print_error(
                &mut std::io::stderr(),
                std::io::stderr().is_terminal(),
                format!("{err:#}"),
            );
            ExitCode::GeneralError.exit();
        }
```

- **walk.rs `ReceiverBuffer::print` (line 256)** — the following line already returns `Err(ExitCode::GeneralError)`:

```rust
            let _ = print_error(
                &mut std::io::stderr(),
                std::io::stderr().is_terminal(),
                format!("Could not write to output: {e}"),
            );
            return Err(ExitCode::GeneralError);
```

- **exec/command.rs `handle_cmd_error` (lines 104, 111)** — both match arms:

```rust
        (Some(cmd), err) if err.kind() == io::ErrorKind::NotFound => {
            // The function returns `ExitCode::GeneralError` right below, so a
            // failure to write the message itself is unactionable.
            let _ = print_error(
                &mut std::io::stderr(),
                std::io::stderr().is_terminal(),
                format!("Command not found: {}", cmd.get_program().to_string_lossy()),
            );
            ExitCode::GeneralError
        }
        (_, err) => {
            let _ = print_error(
                &mut std::io::stderr(),
                std::io::stderr().is_terminal(),
                format!("Problem while executing command: {err}"),
            );
            ExitCode::GeneralError
        }
```

- **exec/job.rs `job` (line 27)** and **`batch` (line 57)** — non-fatal filesystem-error diagnostics; both loops must continue:

```rust
                if config.show_filesystem_errors {
                    // Non-fatal diagnostics: the loop must continue either
                    // way, so a failed write is discarded.
                    let _ = print_error(
                        &mut std::io::stderr(),
                        std::io::stderr().is_terminal(),
                        err.to_string(),
                    );
                }
```

### 5. Import updates required by the above

- `src/error.rs`: remove `use std::io::IsTerminal;` (Step 1 already covers this).
- `src/cli.rs`: add `use std::io::IsTerminal;` before `use std::num::NonZeroUsize;` (line 1).
- `src/walk.rs`: change line 3 `use std::io::{self, Write};` → `use std::io::{self, IsTerminal, Write};`.
- `src/exec/command.rs`: change lines 1-2 `use std::io; use std::io::Write;` → `use std::io::{self, IsTerminal, Write};`.
- `src/exec/job.rs`: add `use std::io::IsTerminal;` as the first line of the file.
- `src/main.rs`: no change (`IsTerminal` already imported).

No changes to Cargo.toml, exit_codes.rs, sanitize.rs, output.rs, or tests/tests.rs.

## Critical files & anchors

- `src/error.rs` — `print_error` (lines 5-8): the re-signed function; append `#[cfg(test)] mod tests` at end of file.
- `src/main.rs` — `main()` Err arm (lines 62-73): top-level error path; `use std::io::IsTerminal` already present (line 18).
- `src/cli.rs` — `Opts::search_paths` (lines 696-721): the only site needing a control-flow restructure (`filter_map` → loop); imports at lines 1-3.
- `src/walk.rs` — `ReceiverBuffer::poll` (line 229), `ReceiverBuffer::print` (line 256), `WorkerState::build_walker` (lines 380, 392); import at line 3.
- `src/exec/` — `command.rs::handle_cmd_error` (lines 101-115) and `job.rs::job`/`job.rs::batch` (lines 19-64): all four calls in the exec module; imports at command.rs:1-2 and job.rs:1.

## Verification

1. New unit tests: `cargo test --lib error::tests` — both pass:
   - `print_error_writes_message_to_buffer`: buffer content is exactly `[fd error]: something went wrong\n`, result is `Ok`.
   - `print_error_propagates_sink_write_failure`: returned error's `to_string()` contains `sink write failed`.
2. Full suite: `cargo test` — green, in particular `tests/tests.rs` `test_multi_file_with_missing`, `test_pattern_with_forward_slash_is_rejected`, `test_and_pattern_with_forward_slash_is_rejected`, which assert the exact `[fd error]: ` stderr text (lines 348, 365-373, 389, 395, 431). Passing unchanged proves byte-identical output on a pipe (the test harness captures stderr as a pipe → `is_terminal() == false` → no sanitize → same bytes as old `eprintln!`).
3. CI gates: `cargo fmt -- --check` and `cargo clippy --all-targets --all-features -- -Dwarnings` (both enforced by .github/workflows/CICD.yml lines 52 and 64). Run `cargo fmt` before the check.
4. Manual smoke (pwsh): `cargo build` then `.\target\debug\fd.exe 'nonexistent/path' 2>&1 | Out-String; "exit=$LASTEXITCODE"` — stderr contains exactly `[fd error]: The search pattern 'nonexistent/path' contains a path-separation character and will not lead to any search results.` and `exit=1`.

## Assumptions & contingencies

1. `Result<(), Error>` in the ask maps to `anyhow::Result<()>` — no `crate::error::Error` type exists in-repo and every module uses `anyhow::Result`. If the user intended `std::io::Result<()>` instead, swap only the return type; all `?` propagations and `let _` discards work unchanged and the tests differ only in the `unwrap_err()` type.
2. `is_terminal: bool` is added beyond the literal "sink + Result" wording (see Step 1 rationale). If the user rejects the extra parameter, fallback: keep the two-arg `print_error(sink, msg)` and compute `std::io::stderr().is_terminal()` inside — the two specified tests still pass deterministically (plain message, failing sink), but any sanitize-behavior test would become environment-dependent.
3. Propagation policy is per-site as specified in Steps 2-4 (3 sites `?`, 1 site `map_err` → `ExitCode::GeneralError`, 6 sites `let _`). The `let _` sites return `()`/`ExitCode`/`Option` and either exit with `GeneralError` immediately after or are non-fatal diagnostics; converting them to error exits would change runtime policy beyond the ask (a broken stderr would turn a successful search into a failed one).
4. Format parity holds: `writeln!(sink, "[fd error]: {safe}")` with `sink = std::io::stderr()` and `is_terminal = std::io::stderr().is_terminal()` produces the same bytes as the removed `eprintln!("[fd error]: {safe}")` — same prefix, same newline, same sanitize decision. Pinned by the integration tests in Verification step 2.
5. Upstream master has the identical old implementation (fetched raw from github.com/sharkdp/fd), so there is no upstream refactor to mirror; the design here is new to this checkout.

## Chat summary (verbatim from run output)

## Summary

**Verification in-repo:** `crate::error::print_error` (src/error.rs:5-8) currently does `eprintln!("[fd error]: {safe}")` and returns `()`. It does **not** terminate — `ExitCode::GeneralError.exit()` lives at the call sites (e.g., main.rs:70). Upstream master is identical, so there's no precedent to mirror. There is **no `crate::error::Error` type** — the crate's error type everywhere is `anyhow::Error`. Grep found exactly **10 call sites**: cli.rs:713, walk.rs:229/256/380/392, exec/command.rs:104/111, exec/job.rs:27/57, main.rs:69.

**Exact new signature:**
```rust
pub fn print_error(
    sink: &mut dyn std::io::Write,
    is_terminal: bool,
    msg: impl Into<String>,
) -> anyhow::Result<()>
```
One deliberate extension beyond the literal "sink + Result" ask: an `is_terminal: bool` param — a `&mut dyn Write` can't be probed with `IsTerminal`, and computing it from global stderr would make unit tests TTY-dependent. It mirrors the existing `Config.interactive_terminal` pattern (main.rs:277).

**Call-site handling (all 10 named in the plan):**
- `?` propagation — cli.rs `search_paths` (restructured `filter_map` → loop, the only control-flow change), walk.rs `build_walker` ×2
- `map_err(|_| ExitCode::GeneralError)?` — walk.rs `poll` (returns `Result<(), ExitCode>`)
- `let _` + comment — main.rs Err arm, walk.rs `print`, exec/command.rs `handle_cmd_error` ×2, exec/job.rs `job`/`batch` (these return `()`/`ExitCode`/`Option` and either exit GeneralError right after or are non-fatal diagnostics)

**Clean cutover:** old signature and `use std::io::IsTerminal;` deleted from error.rs, no shim. Format `[fd error]: ` + `\n` is byte-preserved via `writeln!` — required because integration tests pin the exact stderr text (tests/tests.rs:348, 365-373, 389, 395, 431).

**Tests added (src/error.rs):** buffer-write test asserting `[fd error]: something went wrong\n` + `Ok`, and a `FailingSink` test asserting the returned error contains `sink write failed`.

**Verification:** `cargo test --lib error::tests`, full `cargo test`, `cargo fmt -- --check` + `cargo clippy --all-targets --all-features -- -Dwarnings` (both CI-enforced), plus a concrete `fd.exe 'nonexistent/path'` smoke with expected stderr and exit code 1.
