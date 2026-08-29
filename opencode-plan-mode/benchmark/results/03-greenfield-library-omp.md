# Plan: `version-range` — std-only node-semver subset library

## Context

Design and implement a Rust library crate `version-range` that parses semantic-version ranges (a node-semver subset) and answers `satisfied_by`, with no dependencies beyond the standard library. The exact public API, operator coverage (caret, tilde, wildcard, hyphen, comparators, unions), semver.org prerelease semantics, and distinct error variants are fixed by the request; the end state is a crate whose public surface is exactly `Version::parse`, `Range::parse`, `Range::satisfied_by` plus the two error enums, with a passing test matrix. Grammar and expansion rules below are grounded in the node-semver README (Advanced Range Syntax + Range Grammar BNF), which this crate is a subset of.

## Approach

**1. Scaffold** — `cargo new version-range --lib`; `Cargo.toml` has no `[dependencies]` (std only). `src/lib.rs` re-exports: `pub use version::Version; pub use range::Range; pub use error::{VersionError, RangeError};` with doc comments; module files `src/version.rs`, `src/range.rs`, `src/error.rs`.

**2. Version model + parse** — `src/version.rs`:
```rust
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Version {
    pub(crate) major: u32, pub(crate) minor: u32, pub(crate) patch: u32,
    pub(crate) prerelease: Option<Vec<PrereleaseId>>,   // None = release
}
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum PrereleaseId { Numeric(u64), Alpha(String) }   // Numeric < Alpha
pub fn parse(input: &str) -> Result<Version, VersionError>
```
Parse steps (decision points): trim; reject empty ⇒ `Empty`; strip one optional leading `v` (node-semver compat); split on `.`; reject more than 3 numeric parts ⇒ `TooManyComponents`; each part must parse as `u32` (also catches `-1`, overflow) ⇒ `NonNumeric { component: "major"|"minor"|"patch", found }`; fewer than 3 parts ⇒ `MissingPatch`; if a `-` follows the tuple, split prerelease on `.`, each identifier numeric-or-alpha (numeric must have no leading zeros ⇒ `InvalidPrerelease(String)`); a trailing `+` build-metadata segment is stripped and ignored. Ordering derives `(major, minor, patch, prerelease)` with `None` prerelease greatest (semver precedence). A `Version` used inside a comparator always carries the full triplet.

**3. Comparator model** — `src/range.rs`:
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Op { Lt, Le, Gt, Ge, Eq }
#[derive(Debug, Clone, PartialEq, Eq)]
struct Comparator { op: Op, version: Version }
```
Match semantics (semver comparison): `Lt` `v < c`, `Le` `v <= c`, `Gt` `v > c`, `Ge` `v >= c`, `Eq` `v == c`.

**4. Range grammar** — `src/range.rs`:
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Range { pub(crate) sets: Vec<Vec<Comparator>> }
pub fn parse(input: &str) -> Result<Range, RangeError>
```
`Range::parse` tokenizes per the node-semver BNF (`range-set ::= range ( logical-or range ) *`, `logical-or ::= ( ' ' ) * '||' ( ' ' ) *`, `hyphen ::= partial ' - ' partial`, `simple ::= primitive | partial | tilde | caret`):
- Trim; empty ⇒ `Ok(Range { sets: vec![vec![Comparator { op: Ge, version: 0.0.0 }]] })` (node-semver: `""` := `*`).
- Split on `||` (whitespace-tolerant); a trailing `||` or an empty set between `||`s ⇒ `Unclosed` (pinned; see Assumptions). A set with no tokens after split (e.g. `"||"`) ⇒ `Unclosed`.
- Per set, split on whitespace; a token that is exactly `-` is the hyphen operator: its left neighbor (previous token, must exist and be a partial) and right neighbor (next token, must exist and be a partial) form a hyphen range; missing either side ⇒ `MissingHyphenRhs` for a leading/`1.2.3 -` case, `Unclosed` for `- 2.3.4` leading case (pinned naming).
- Each remaining simple token expands to comparators:
  - Leading operator (`<`, `>`, `<=`, `>=`, `=`) ⇒ primitive on the following partial. Unknown leading char (`!`, `==`, `~>`) ⇒ `UnknownOperator(String)`. Full-triplet version ⇒ that comparator; partial version ⇒ zero-fill, except `Gt` which increments the last specified component (`>1.2` ⇒ `>=1.3.0`, `>1` ⇒ `>=2.0.0`, `>1.2.3` ⇒ `>=1.2.4`); `Lt`/`Le`/`Ge`/`Eq` zero-fill (`<1.2` ⇒ `<1.2.0`).
  - `~` tilde: `~1.2.3` ⇒ `>=1.2.3 <1.3.0`; `~1.2` ⇒ `>=1.2.0 <1.3.0`; `~1` ⇒ `>=1.0.0 <2.0.0`; `~0.2.3` ⇒ `>=0.2.3 <0.3.0`; `~0` ⇒ `>=0.0.0 <1.0.0` (upper bound bumps the last specified component; nothing after `~` ⇒ `InvalidVersion`).
  - `^` caret: `^1.2.3` ⇒ `>=1.2.3 <2.0.0`; `^0.2.3` ⇒ `>=0.2.3 <0.3.0`; `^0.0.3` ⇒ `>=0.0.3 <0.0.4`; `^0.0` ⇒ `>=0.0.0 <0.1.0`; `^0` ⇒ `>=0.0.0 <1.0.0`; `^1.2.x` ⇒ `>=1.2.0 <2.0.0`; `^1.x` ⇒ `>=1.0.0 <2.0.0` (upper bound increments the left-most non-zero element of the tuple as specified by the input).
  - Bare partial (no operator): `1.2.3` ⇒ `Eq(1.2.3)`; `1.2` ⇒ `>=1.2.0 <1.3.0`; `1` ⇒ `>=1.0.0 <2.0.0`; `1.2.x`/`1.2.*`/`1.X`/`1.x`/`*` wildcards: `1.2.x` ⇒ `>=1.2.0 <1.3.0`, `1.x` ⇒ `>=1.0.0 <2.0.0`, `*` ⇒ `Ge(0.0.0)` (no upper bound). `x`/`X`/`*` as a component means wildcard; a trailing `x` on a full triplet ⇒ `InvalidVersion` (pinned; `1.2.3.x` is not a partial). Prerelease qualifiers on partials are rejected ⇒ `InvalidVersion`.
- Embedded version parse failures surface as `RangeError::InvalidVersion(String)` wrapping the `VersionError` Display text (e.g. `~1.a`, `^1.2`).

**5. `satisfied_by`** — `Range::satisfied_by(&self, v: &Version) -> bool`: true iff at least one set has every comparator satisfied. Comparator satisfaction: normal semver comparison, with the pinned prerelease rule:
> A version with a prerelease satisfies a comparator only when the comparator's version has the same `[major, minor, patch]` triplet AND the comparator's version carries a prerelease AND `v >=` that version (semver order). Otherwise (different triplet, or comparator without a prerelease) a prerelease version does not satisfy the comparator.
This implements the request's "same [major,minor,patch] and not less than a prerelease on that triplet" exactly as node-semver does: `>1.2.3-alpha.3` satisfies `1.2.3-alpha.7` but not `3.4.5-alpha.9`; `>=1.2.3` does not satisfy `1.2.3-alpha.1`; `3.4.5` (release) satisfies `>1.2.3-alpha.3`.

**6. Errors** — `src/error.rs`:
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VersionError { Empty, NonNumeric { component: &'static str, found: String }, MissingPatch, TooManyComponents, InvalidPrerelease(String) }
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RangeError { UnknownOperator(String), Unclosed, MissingHyphenRhs, InvalidVersion(String) }
```
(Empty-string maps to `VersionError::Empty`; the empty range is legal per node-semver, see Assumptions.) Hand-written `Display` with one-line messages naming the offending input; `impl std::error::Error`. The five required malformed cases get distinct variants: empty string ⇒ `VersionError::Empty`; non-numeric component ⇒ `NonNumeric { component, found }`; missing patch when required ⇒ `MissingPatch`; unknown operator ⇒ `RangeError::UnknownOperator`; unclosed range ⇒ `RangeError::Unclosed`. `TooManyComponents`/`InvalidPrerelease`/`MissingHyphenRhs`/`InvalidVersion` cover the remaining malformed inputs the request's list implies.

**7. Tests** — `tests/satisfies.rs` (table-driven: parse each range once via `Range::parse`, iterate `(version, expected)` rows) and `tests/errors.rs` (variant-equality assertions). Matrix below (28 satisfy cases + 6 error cases ≥ the required 20).

## Critical files & anchors

- `src/range.rs` — `Range::parse` + `satisfied_by` + `Op`/`Comparator`; the grammar's decision points all live here.
- `src/version.rs` — `Version::parse` + `PrereleaseId` ordering; every other module depends on its ordering semantics.
- `src/error.rs` — `VersionError`/`RangeError` variant sets; the distinct-message contract.
- `src/lib.rs` — the exact public re-export surface the request pins.
- `tests/satisfies.rs` — the ≥20-case matrix proving the semantics.

## Verification

`cargo test` in the crate root. Concrete cases (a subset of the matrix; each asserts `Range::parse(r)?.satisfied_by(&Version::parse(v)?) == expected`):
- `("*", "1.2.3", true)`, `("1.x", "2.0.0", false)`, `("1.2.x", "1.3.0", false)`
- `("~1.2.3", "1.3.0", false)`, `("^0.2.3", "0.3.0", false)`, `("^0.0.3", "0.0.4", false)`
- `("1.2.3 - 2.3.4", "2.3.5", false)`, `("1.2 - 2.3.4", "1.2.0", true)`, `("1.2.3 - 2.3", "2.4.0", false)`
- `(">=1.2.7 <1.3.0", "1.3.0", false)`, `(">1", "1.9.9", false)`, `("1.2.7 || >=1.2.9 <2.0.0", "1.2.8", false)`
- `(">1.2.3-alpha.3", "1.2.3-alpha.7", true)`, `(">1.2.3-alpha.3", "3.4.5-alpha.9", false)`, `(">=1.2.3", "1.2.3-alpha.1", false)`, `("*", "1.2.3-alpha.1", false)`
- Errors: `Version::parse("") == Err(VersionError::Empty)`; `Version::parse("a.b.c")` ⇒ `NonNumeric { component: "major", found: "a" }`; `Version::parse("1.2") == Err(MissingPatch)`; `Version::parse("1.2.3.4") == Err(TooManyComponents)`; `Range::parse("!1.2.3")` ⇒ `UnknownOperator("!")`; `Range::parse("1.2.3 -")` ⇒ `MissingHyphenRhs`; `Range::parse("1.2.3 - 2.3.4 ||")` ⇒ `Unclosed`.

Full matrix (28 satisfy rows): `*`→`0.0.1` T / `1.x`→`1.5.0` T / `1.x`→`2.0.0` F / `1.2.x`→`1.2.9` T / `1.2.x`→`1.3.0` F / `1`→`1.9.9` T / `1.2`→`1.2.0` T / `1.2`→`1.3.0` F / `~1.2.3`→`1.2.9` T / `~1.2.3`→`1.3.0` F / `~1.2`→`1.2.5` T / `~1`→`1.9.0` T / `~1`→`2.0.0` F / `^1.2.3`→`1.9.9` T / `^1.2.3`→`2.0.0` F / `^0.2.3`→`0.2.9` T / `^0.2.3`→`0.3.0` F / `^0.0.3`→`0.0.3` T / `^0.0.3`→`0.0.4` F / `1.2.3 - 2.3.4`→`2.3.4` T / `1.2.3 - 2.3.4`→`2.3.5` F / `1.2 - 2.3.4`→`1.2.0` T / `1.2.3 - 2.3`→`2.3.9` T / `1.2.3 - 2.3`→`2.4.0` F / `>=1.2.7 <1.3.0`→`1.2.9` T / `>=1.2.7 <1.3.0`→`1.3.0` F / `>1.2.3`→`1.2.4` T / `>1.2.3`→`1.2.3` F / `>1`→`2.0.0` T / `>1`→`1.9.9` F / `<=2.0.0`→`2.0.0` T / `<=2.0.0`→`2.0.1` F / `=1.2.3`→`1.2.3` T / `1.2.3`→`1.2.4` F / `1.2.7 || >=1.2.9 <2.0.0`→`1.2.7` T / `1.2.7 || >=1.2.9 <2.0.0`→`1.4.6` T / `1.2.7 || >=1.2.9 <2.0.0`→`1.2.8` F / `>1.2.3-alpha.3`→`1.2.3-alpha.7` T / `>1.2.3-alpha.3`→`3.4.5-alpha.9` F / `>1.2.3-alpha.3`→`3.4.5` T / `>=1.2.3`→`1.2.3-alpha.1` F / `^1.2.3`→`1.2.3-beta.1` F / `*`→`1.2.3-alpha.1` F / `>=1.2.3-alpha.3`→`1.2.3-beta.1` T — 44 rows total.

## Assumptions & contingencies

- **"Space-separated OR"**: node-semver's grammar (verified in its README BNF) defines whitespace as AND within a comparator set and `||` (with optional surrounding spaces) as OR; the request's "unions (`||` and space-separated OR)" is implemented as `||` OR-unions with whitespace-tolerant parsing, matching the cited reference — `>=1.2.7 <1.3.0` is an intersection. If the user genuinely wants whitespace-separated terms to union, the set-splitting step (Approach 4) flips from "split set on whitespace" to "each whitespace token is its own set" — one branch; the hyphen-range tokenization is unaffected.
- **`""` range**: per node-semver, `""` is a valid range matching everything (`*`); the "empty string" malformed case in the request is `VersionError::Empty` on `Version::parse("")`. If `Range::parse("")` must error instead, replace the empty-trim early return with `Err(RangeError::Empty)` and add the variant.
- **`1.2.3.x` and prerelease-qualified partials** are rejected (`InvalidVersion`); node-semver's loose parsing is out of the subset.
- **Build metadata** (`+build`) is stripped and ignored; the request's API has no place for it.
- **Trailing `||` / empty set** ⇒ `Unclosed` (stricter than node-semver, which treats empty sets as `*`); chosen so the "unclosed range" error case is reachable.
- **Upper bounds use the plain tuple** (`<1.3.0`, not node-semver's `<1.3.0-0`): the prerelease rule (Approach 5) independently governs prerelease inclusion, so the `-0` marker is unnecessary in this subset.
- **`Gt` on a partial increments the last specified component** (`>1.2` ⇒ `>=1.3.0`), matching node-semver; pinned here because it is easy to get wrong.
