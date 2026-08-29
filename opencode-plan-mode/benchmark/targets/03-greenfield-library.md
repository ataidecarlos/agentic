Design a Rust library crate `version-range` that parses and matches semantic
version ranges (a subset of node-semver), with no external dependencies beyond
the standard library.

Public API (exact):
- `Version::parse(&str) -> Result<Version, VersionError>`
- `Range::parse(&str) -> Result<Range, RangeError>`
- `Range::satisfied_by(&Version) -> bool`

Must support: caret (`^1.2.3`), tilde (`~1.2.3`), wildcard (`1.2.x`, `1.*`,
`*`), hyphen ranges (`1.2.3 - 2.3.4`), comparators (`>=`, `>`, `<=`, `<`, `=`),
and unions (`||` and space-separated OR).

Prerelease semantics per semver.org: a version with a prerelease satisfies a
comparator only when the comparator names the same [major,minor,patch] and the
version is not less than a prerelease on that triplet.

Define `VersionError` and `RangeError` enums with distinct variants for each
malformed-input case (empty string, non-numeric component, missing patch when
required, unknown operator, unclosed range).

Deliver an execution plan: module layout, the exact public types and
signatures, the parse grammar/decision points, error variants, and a test
matrix (range string + version + expected bool) covering at least 20 cases.
