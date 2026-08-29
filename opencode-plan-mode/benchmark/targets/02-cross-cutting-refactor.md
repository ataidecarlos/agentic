In the `fd` repository (github.com/sharkdp/fd), refactor error output to be
testable without exiting the process.

Current state (verify in-repo): `crate::error::print_error` prints an error
and terminates. Change it to take an `&mut dyn std::io::Write` sink and return
`Result<(), Error>`, letting callers write errors to a buffer.

- Update EVERY call site (main.rs, walk.rs, exec/, cli.rs, and any other
  module) to pass the sink and propagate the Result.
- Clean cutover: delete the old signature; no compatibility shim or alias.
- Add a unit test asserting print_error writes the expected message to a
  buffer and returns Ok, and that a failing path yields the expected text.

Deliver an execution plan that names every call site and the exact new
signature.
