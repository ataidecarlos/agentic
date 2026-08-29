# Opencode plan agent output — target 03

## Plan artifact (plans/version-range-plan.md, verbatim)

# version-range crate — execution plan

## Context

Design and implement a std-only Rust library crate `version-range` that parses semantic versions and a node-semver-style subset of range syntax, and answers `Range::satisfied_by(&Version)`. Deliverables required by the ask: module layout, exact public types/signatures, parse grammar and decision points, error variants for each malformed-input case, and a ≥20-row satisfaction test matrix. The workspace (`C:\Users\ataid\projects\planner\scratch\bench\03`) is empty; the crate is created from scratch here. All semantics below were cross-checked against node-semver v7's README grammar and its `test/fixtures/range-include.js` / `range-exclude.js` fixtures (fetched during exploration) for every supported construct; intentional deviations are listed in Assumptions.

## Approach

### 1. Scaffold the crate

- Create `Cargo.toml`: `[package] name = "version-range"`, `version = "0.1.0"`, `edition = "2021"`, empty `[dependencies]` (std only).
- Create `src/lib.rs` with module declarations and the exact re-exports:
  - `mod error; mod version; mod range;`
  - `pub use error::{RangeError, VersionError, VersionPart};`
  - `pub use range::Range;`
  - `pub use version::{PrereleaseIdent, Version};`
- Create empty `src/error.rs`, `src/version.rs`, `src/range.rs`, and `tests/satisfaction.rs`.

### 2. Define the public types and error enums (src/error.rs, src/version.rs)

All new types (no equivalents exist — greenfield). Derive `Debug, Clone, PartialEq, Eq` on every type; `Copy` on `VersionPart`.

- `pub enum VersionPart { Major, Minor, Patch }` — used in error payloads.
- `pub enum VersionError` — the required five malformed cases plus the completion variants needed to give every malformed input a distinct variant (required five are marked `[required]`):
  - `Empty` `[required]` — empty (or whitespace-only) input.
  - `NonNumeric { part: VersionPart, value: String }` `[required]` — a numeric component is not a number, a wildcard appears in a non-suffix position, or the number exceeds `u64::MAX`. `value` = substring from the offending position up to the next `.`, `-`, `+`, or end-of-input (best-effort diagnostic).
  - `MissingPatch` `[required]` — incomplete version (`"1"`, `"1.2"`); doc: "patch (and any component above it) is required".
  - `TooManyParts` — a 4th dot-component (`"1.2.3.4"`, `"1.2.3.x"`).
  - `LeadingZero { part: VersionPart, value: String }` — numeric component with a leading zero (`"01.2.3"`, `"1.2.3-01"` is instead `InvalidPrerelease`).
  - `InvalidPrerelease { ident: String }` — empty prerelease ident (`"1.2.3-"`, `"1.2.3-a..b"`), numeric ident with leading zero (`"1.2.3-01"`), or char outside `[0-9A-Za-z-]`.
  - `InvalidMetadata { ident: String }` — empty build ident (`"1.2.3+"`, `"1.2.3+a..b"`) or bad char. Leading zeros in build idents are allowed (semver spec item 9).
  - `TrailingCharacters { value: String }` — junk after a complete version in `Version::parse` (`"1.2.3abc"`, `"1.2.3-rc.1+xyz q"` → value `"q"`).
- `pub enum RangeError` — required five across the two enums (version-level failures inside a range surface through the wrapper):
  - `Empty` `[required]` — empty/whitespace-only range.
  - `UnknownOperator { operator: String }` `[required]` — token starts with an unrecognized operator (`"!1.2.3"` → `"!"`), an operator immediately followed by another operator char (`"~>1.2.3"` → `"~>"`), or a dangling fragment where a separator was expected (`"1.2.3<2.0.0"` → `"<2.0.0"`, `"1.2.3 - 2.3.4 - 3.4.5"` → `"-"`).
  - `MissingPatch { token: String }` `[required]` — partial version in a position requiring a full X.Y.Z: bare `"1.2"`/`"1"`, after `^`/`~`/comparator (`"~1.2"`), or on either side of a hyphen (`"1.2.3 - 2"`).
  - `UnclosedRange` `[required]` — dangling operator with missing operand: `"1.2.3 -"`, `"1.2.3 ||"`, `"|| 1.2.3"`, `"||"`.
  - `InvalidVersion { token: String, source: VersionError }` — any version-level failure inside a range, preserving the distinct source variant (e.g. `Range::parse(">=1.02.3")` → `InvalidVersion { token: "1.02.3", source: VersionError::LeadingZero { part: Minor, .. } }`).
- `pub enum PrereleaseIdent { Numeric(u64), Alpha(String) }` — semantic-ordered prerelease identifier.
- `pub struct Version { pub major: u64, pub minor: u64, pub patch: u64, pub prerelease: Vec<PrereleaseIdent>, pub build: Vec<String> }`.
- Exact public API (nothing else is re-exported):
  - `impl Version { pub fn parse(s: &str) -> Result<Version, VersionError> }`
  - `impl Range { pub fn parse(s: &str) -> Result<Range, RangeError> }`
  - `impl Range { pub fn satisfied_by(&self, version: &Version) -> bool }`

### 3. Version scanning and `Version::parse` (src/version.rs)

- Implement `pub(crate) enum ScannedVersion { Full(Version), Wildcard { leading: u8 }, Partial { parts: u8 } }` (parts 1 or 2) and `pub(crate) fn scan_version(input: &str) -> Result<ScannedVersion, VersionError>` — the single shared scanner used by both `Version::parse` and `Range::parse`.
- Scanner rules (decision points):
  1. Trim whitespace first; empty remainder → `Empty`.
  2. Strip one leading `v` or `V` prefix (node-semver-compatible).
  3. Read up to 3 dot-separated components. A component is `[0-9]+` (no leading zeros → `LeadingZero`), or a wildcard `x`/`X`/`*`.
  4. Wildcard suffix rule: every component after the first wildcard must also be a wildcard; `leading` = count of numeric components before the first wildcard. `"1.x.3"`, `"x.2"`, `"1.x-rc.1"` → `NonNumeric { part: <first wildcard part>, value: "x" }`. `"1.2.3.x"` (4 components) → `TooManyParts`.
  5. After the last component: `-pre` (idents split on `.`, each `[0-9A-Za-z-]+`, non-empty, numeric idents without leading zeros → else `InvalidPrerelease`) and/or `+build` (idents split on `.`, each `[0-9A-Za-z-]+`, non-empty, leading zeros allowed → else `InvalidMetadata`).
  6. Classification: 3 numeric components → `Full`; numeric-only with 1–2 components → `Partial`; a wildcard suffix with 0–2 leading numerics → `Wildcard`.
  7. `Version::parse` additionally requires the whole input was consumed by the version grammar; leftover characters (`"1.2.3abc"`, characters after `+`/`-` sections) → `TrailingCharacters { value: <leftover> }`.
- Note: `Version::parse` never returns `Wildcard`/`Partial` — those are for the range parser; `parse` maps them to `MissingPatch` (via the classification in step 6, `Partial`) or `NonNumeric` (wildcard shapes are rejected in step 4/7 context only when they are not a valid suffix form; a bare `"1.2.x"` string passed to `Version::parse` yields `NonNumeric { part: Patch, value: "x" }` because a wildcard is not a numeric version component).

### 4. Version ordering (src/version.rs)

- Implement `PartialEq`, `Eq`, `PartialOrd`, `Ord` **by hand** for `Version`, comparing only `major`, `minor`, `patch`, then `prerelease` — build metadata is ignored (semver precedence; matches node-semver `eq`).
- Prerelease comparison (semver spec items 11/12): identical if both empty. One empty → the release (empty) is greater. Both non-empty: compare ident-by-ident; numeric idents numerically, alphanumeric lexically (ASCII), numeric < alphanumeric; if all compared idents equal, the shorter list is smaller. `PreIdent` ordering uses the same rules.
- These `Ord` impls are the only comparison path used by comparator tests in step 7.

### 5. Range grammar, tokenizer, and atom parser (src/range.rs)

- Grammar (EBNF) — note the user-specified union semantics where both `||` and whitespace separate OR-ed atoms:

```
range      := or_atom ( sep or_atom )*
sep        := '||' | ws+                    // user spec: whitespace is OR (node-semver: AND)
or_atom    := hyphen | tilde | caret | comparator | wildcard | version
hyphen     := version ws+ '-' ws+ version   // both sides full X.Y.Z only
tilde      := '~' ws? version
caret      := '^' ws? version
comparator := ( '>=' | '>' | '<=' | '<' | '=' ) ws? version
wildcard   := w1 | num '.' w1 | num '.' num '.' w1
w1         := 'x' | 'X' | '*' | num         // plus the suffix rule from step 3.4
version    := [vV]? num '.' num '.' num ('-' pre)? ('+' build)?
```

- Parse pipeline (`Range::parse`): trim → empty ⇒ `Empty`. Loop scanning tokens left to right:
  1. Skip whitespace.
  2. `||` → union separator; if it is the first token, follows another `||`, or is followed by EOF, → `UnclosedRange`; otherwise start a new atom slot.
  3. Operator: match longest prefix from `>=`, `>`, `<=`, `<`, `=`, `^`, `~`. If the char after the operator is another operator-start char → `UnknownOperator` (handles `~>`). If no operator matches and the char is not a version start (`[0-9vVxX*]`) → `UnknownOperator { operator: <the atom's remaining text up to whitespace/||> }`; otherwise scan a version token via `scan_version`.
  4. Version token classification:
     - `Full(v)` bare → atom `[Eq v]`; after `^` → caret; after `~` → tilde; after a comparison operator → primitive `[Op]`.
     - `Wildcard` bare → x-range atom; after any operator → `InvalidVersion` (operator requires a full version). `=0.7.x`-style and `>=*` are rejected (node-semver accepts them — documented deviation).
     - `Partial` in any position (bare, after operator, or in a hyphen side) → `RangeError::MissingPatch { token }`.
  5. Hyphen detection: a bare `-` token (whitespace-delimited, per `hyphen` grammar) only continues a hyphen range when the previous atom was a bare `Full` version and a `Full` version follows. Right side missing → `UnclosedRange`; left side was not a bare full version (operator form, wildcard, another hyphen) → `UnknownOperator { operator: "-" }`.
  6. After a complete atom, the next char must be whitespace, `||`, or EOF; otherwise the remaining fragment → `UnknownOperator { operator: <fragment> }` (covers `"1.2.3<2.0.0"`).
  7. Whitespace between operator and version is allowed (`>= 1.0.0`); build metadata inside a comparator version is parsed and then discarded from the stored comparator version (node-semver behavior).
- Representation (private, mirrors node-semver's `set`): `pub struct Range { sets: Vec<Vec<Comparator>> }` where `pub(crate) enum Comparator { Any, Op { op: ComparatorOp, version: Version } }` and `pub(crate) enum ComparatorOp { Gt, Ge, Lt, Le, Eq }`.

### 6. Comparator expansion (desugaring) (src/range.rs)

Each `or_atom` becomes one set (AND-group); `Range.sets` is the OR of sets. Bumps use `saturating_add` (a saturated bump makes the set unsatisfiable — accepted, pathological input only).

| Syntax | Expansion |
|---|---|
| `*`, `x`, `X`, `x.x`-suffix with `leading == 0` | `[Any]` |
| `1.*` / `1.x` (`leading == 1`, major M) | `[Ge M.0.0, Lt (M+1).0.0]` |
| `1.2.x` / `1.2.*` (`leading == 2`) | `[Ge M.m.0, Lt M.(m+1).0]` |
| `~X.Y.Z` | `[Ge X.Y.Z, Lt X.(Y+1).0]` |
| `^X.Y.Z`, X > 0 | `[Ge X.Y.Z, Lt (X+1).0.0]` |
| `^0.Y.Z`, Y > 0 | `[Ge 0.Y.Z, Lt 0.(Y+1).0]` |
| `^0.0.Z` | `[Ge 0.0.Z, Lt 0.0.(Z+1)]` |
| `>=v` / `>v` / `<=v` / `<v` / `=v` | `[Ge/... v]` / `[Eq v]` |
| bare `X.Y.Z` | `[Eq X.Y.Z]` |
| `A - B` | `[Ge A, Le B]` (inclusive both ends) |

Upper bounds are plain releases (`<2.0.0`), not node-semver's `<2.0.0-0`; proven equivalent for all supported inputs (the `-0` comparator never changes an observable result: any version on the upper tuple fails numerically either way, and its gate-unlocking effect cannot rescue a version because such versions always fail the numeric upper test).

### 7. `Range::satisfied_by` with the prerelease gate (src/range.rs)

- `pub fn satisfied_by(&self, version: &Version) -> bool { self.sets.iter().any(|set| set_satisfies(set, version)) }`
- `Comparator::test(v)`: `Any` → always true; `Op` → compare via `Version`'s `Ord` (build ignored).
- `set_satisfies(set, v)` — node-semver `testSet` port; per set (each atom is one set, so this equals the user's per-comparator rule applied to the atom's own comparators):
  1. Every comparator must test true numerically (full semantic comparison including prerelease ordering).
  2. Prerelease gate: if `v.prerelease` is empty → true. Otherwise the set passes only if at least one comparator is `Op { version: cv, .. }` with `!cv.prerelease.is_empty()` and `cv.major == v.major && cv.minor == v.minor && cv.patch == v.patch`. `Any` never qualifies.
  - This implements the stated rule exactly: a prerelease version satisfies only when a comparator names the same `[major,minor,patch]` (with a prerelease on that triplet) and the version is not less than it (enforced by step 1).
  - Pinned by node-semver fixtures: `^1.2.3` × `1.2.3-rc.1` → false; `^1.2.3-rc.1` × `1.2.3-rc.2` → true; `^1.2.3-rc.1` × `1.2.4-rc.1` → false; `*` × `1.0.0-rc.1` → false; `1.2.3-pre - 2.4.3-pre` × `1.2.3-pre.2` → true.

### 8. Tests (tests/satisfaction.rs plus unit tests)

- `tests/satisfaction.rs` (integration, public API only): the full bool matrix from Verification below (38 rows) implemented as `(range, version, expected)` tuples; the error-variant table (17 rows) as `(parser, input, expected variant)` asserts; plus equality/ordering spot checks (`1.2.3+a == 1.2.3+b`, `1.2.3 > 1.2.3-rc.1`).
- Unit tests in `src/version.rs` (scanner edges: `v`-prefix, leading zeros, overflow, prerelease idents, `TrailingCharacters`) and `src/range.rs` (tokenizer edges: `~>`, `||` misuse, hyphen misuse, whitespace variants).

## Critical files & anchors

- `Cargo.toml` — package metadata (`version-range`, edition 2021) and the empty `[dependencies]`; the std-only constraint lives here.
- `src/lib.rs` — module declarations and the exact `pub use` re-exports; defines the crate's public surface.
- `src/error.rs` — `VersionError` (8 variants), `RangeError` (5 variants), `VersionPart`; every required malformed-input variant is named here.
- `src/version.rs` — `scan_version` (shared scanner), `Version::parse`, `PrereleaseIdent`, and the hand-written `Ord`/`PartialEq` ignoring build.
- `src/range.rs` — `Range`, `Comparator`/`ComparatorOp` (private), the expansion table in step 6, and `satisfied_by`/`set_satisfies` with the prerelease gate.

## Verification

Run `cargo test` in the crate root; expect `test result: ok` with all integration and unit tests passing, and `cargo build` with no warnings.

Exact behavioral checks (all encoded as tests in `tests/satisfaction.rs`):

1. Satisfaction matrix — 38 rows `(range, version, expected)`, covering every required feature and the prerelease semantics:

| # | range | version | expected |
|---|---|---|---|
| 1 | `>=1.2.3` | 1.2.3 | true |
| 2 | `>=1.2.3` | 1.2.2 | false |
| 3 | `>1.2.3` | 1.2.4 | true |
| 4 | `>1.2.3` | 1.2.3 | false |
| 5 | `<=2.0.0` | 2.0.0 | true |
| 6 | `<=2.0.0` | 2.0.1 | false |
| 7 | `<2.0.0` | 1.9.9 | true |
| 8 | `<2.0.0` | 2.0.0 | false |
| 9 | `=1.2.3` | 1.2.3 | true |
| 10 | `=1.2.3` | 1.2.4 | false |
| 11 | `^1.2.3` | 1.9.9 | true |
| 12 | `^1.2.3` | 2.0.0 | false |
| 13 | `^0.2.3` | 0.2.9 | true |
| 14 | `^0.2.3` | 0.3.0 | false |
| 15 | `^0.0.3` | 0.0.4 | false |
| 16 | `~1.2.3` | 1.2.9 | true |
| 17 | `~1.2.3` | 1.3.0 | false |
| 18 | `~0.0.3` | 0.0.4 | false |
| 19 | `1.2.x` | 1.2.99 | true |
| 20 | `1.2.x` | 1.3.0 | false |
| 21 | `1.*` | 1.9.9 | true |
| 22 | `1.*` | 2.0.0 | false |
| 23 | `*` | 0.0.1 | true |
| 24 | `1.2.3 - 2.3.4` | 1.2.3 | true |
| 25 | `1.2.3 - 2.3.4` | 2.3.4 | true |
| 26 | `1.2.3 - 2.3.4` | 2.3.5 | false |
| 27 | `1.2.3 || 2.3.4` | 1.2.3 | true |
| 28 | `1.2.3 || 2.3.4` | 2.0.0 | false |
| 29 | `>=1.2.3 <2.0.0` | 1.0.0 | true (space=OR: satisfied via `<2.0.0`) |
| 30 | `>=1.2.3 <2.0.0` | 2.5.0 | true (space=OR: satisfied via `>=1.2.3`) |
| 31 | `^1.2.3` | 1.2.3-rc.1 | false |
| 32 | `^1.2.3-rc.1` | 1.2.3-rc.2 | true |
| 33 | `^1.2.3-rc.1` | 1.2.4-rc.1 | false |
| 34 | `>=1.2.3-rc.1` | 1.2.3 | true |
| 35 | `>=1.2.3-rc.1` | 1.2.3-rc.0 | false |
| 36 | `>=1.2.3` | 1.2.3-rc.1 | false |
| 37 | `1.2.3-pre - 2.4.3-pre` | 1.2.3-pre.2 | true |
| 38 | `*` | 1.0.0-rc.1 | false |

2. Error-variant table — 17 rows asserted with `matches!` on the exact variant (and payload where material): `Version::parse`: `""`→`Empty`, `"1.2"`→`MissingPatch`, `"1.2.3.4"`→`TooManyParts`, `"1.a.3"`→`NonNumeric{Minor}`, `"01.2.3"`→`LeadingZero{Major}`, `"1.2.3-01"`→`InvalidPrerelease{"01"}`, `"1.2.3+"`→`InvalidMetadata{""}`, `"1.2.3abc"`→`TrailingCharacters{"abc"}`. `Range::parse`: `""`→`Empty`, `"!1.2.3"`→`UnknownOperator{"!"}`, `"~>1.2.3"`→`UnknownOperator{"~>"}`, `"1.2.3 -"`→`UnclosedRange`, `"1.2.3 ||"`→`UnclosedRange`, `"~1.2"`→`MissingPatch{"1.2"}`, `"1.2"`→`MissingPatch{"1.2"}`, `"1.2.3 - 2"`→`MissingPatch{"2"}`, `">=1.02.3"`→`InvalidVersion{token:"1.02.3", source: LeadingZero{Minor}}`.

3. Public API smoke check (doc example in `src/lib.rs`, compiled by `cargo test`): `Version::parse("1.9.9").unwrap()`; `Range::parse("^1.2.3").unwrap().satisfied_by(&v)` → `true`.

## Assumptions & contingencies

1. **Whitespace-separated atoms are OR** (the ask states "unions (`||` and space-separated OR)"). This deviates from node-semver, where whitespace is AND. Implemented as specified; matrix rows 29–30 pin it. Fallback: if the user intended node-semver's AND semantics, change only the tokenizer's separator rule (whitespace starts a new AND set inside one OR branch) and flip rows 29–30.
2. **Partial versions are rejected where a full version is required** (bare `"1.2"`, after `^`/`~`/operators, in hyphen sides), which is what makes the required `MissingPatch` error reachable. node-semver fills zeros instead. Fallback: switch `Partial` classification to node-semver's zero-fill expansion (`"1"` → `>=1.0.0 <2.0.0-0`, `"1.2"` → `>=1.2.0 <1.3.0-0`, `~1.2`/`>=1.2` → zero-filled lower bound, `>1.2` → `>=1.3.0`, `<1.2` → `<1.2.0`), and remove the `MissingPatch` range rows from the error table.
3. **Empty strings error** (`Empty`) rather than node-semver's `"" == "*"`. Fallback: treat `""` as `*` (ANY).
4. **Operator + wildcard forms are rejected** (`>=*`, `=0.7.x`, `^1.2.x` — node-semver accepts `>=*` as `*` and `=0.7.x` as `>=0.7.0 <0.8.0`). Fallback: allow them with node-semver's desugarings.
5. **`~>` is rejected** as `UnknownOperator` (node-semver treats it as `~`; the ask's operator list excludes it). Fallback: alias `~>` to `~`.
6. **Bare `||` and leading/trailing `||` error** with `UnclosedRange` (node-semver parses `"||"` as `*`). Fallback: treat `||` with no operand as `*`.
7. **Hyphen sides must be full versions** (node-semver permits partials/wildcards: `1.2 - 2.3.4` → `>=1.2.0 <=2.3.4`, `x - 1.0.0` → `<=1.0.0`). Fallback: implement node-semver's partial-hyphen expansion (left zero-fill, right: `<bumped` with `-0`).
8. **Leading `v`/`V` prefix is supported** in versions and range tokens (node-semver-compatible; not listed in the ask). Fallback: reject the prefix and map it to `NonNumeric`/`UnknownOperator`.
9. **No `includePrerelease` option** — the prerelease gate is always applied (the ask defines only the default behavior).
10. **Upper bounds expand to plain releases** (`<2.0.0`), not node-semver's `<2.0.0-0`; behaviorally equivalent for every input the crate accepts (argument in Approach step 6; confirmed against node-semver fixtures). Fallback: emit `-0` bounds verbatim; the gate/numeric logic is unchanged.
11. **`u64` limits**: components above `u64::MAX` → `NonNumeric`; range-bump arithmetic uses `saturating_add` (a saturated bump yields an unsatisfiable set — pathological input only).
12. **Build metadata** is parsed and stored on `Version` but ignored by `PartialEq`/`Ord` (semver precedence) and stripped from comparator versions in ranges.
13. **Reference drift**: semantics were verified against node-semver `main` (v7). Prerelease gate and expansion rules are stable since v5.3; if the evaluation reference differs on `*`×prerelease behavior, the gate in Approach step 7 is the single place to adjust (flip the `Any`-qualification rule).

## Chat summary (verbatim from run output)

**Deliverable** — a complete execution plan for a std-only Rust crate `version-range` with the exact public API (`Version::parse`, `Range::parse`, `Range::satisfied_by`) plus module layout, grammar/decision points, error variants, and a 38-row satisfaction matrix (≥20 required) with a 17-row error-variant table.

**Key design decisions (all grounded in exploration):**
- **Layout**: `src/lib.rs` (re-exports) + `error.rs` + `version.rs` + `range.rs`, integration tests in `tests/satisfaction.rs`. Cargo 1.97 available; workspace is empty greenfield.
- **Errors**: `VersionError` (8 variants) and `RangeError` (5 variants) covering the five required malformed cases (empty, non-numeric, missing patch, unknown operator, unclosed range) with distinct variants, plus the few completion variants needed to give every malformed input a home.
- **Semantics verified against node-semver's actual test fixtures** (fetched during exploration): the prerelease gate (same `[major,minor,patch]` tuple + not less than the comparator's prerelease), `*` never matching prereleases, hyphen inclusive bounds, `v`-prefix, build-metadata stripping. Node's v24 is available for any runtime cross-check the implementer wants.
- **Documented deviations from node-semver**, per the ask: whitespace = OR (node-semver uses AND) — pinned by matrix rows 29–30; partial versions rejected (`MissingPatch` stays reachable); empty string errors; `~>`/op+wildcard rejected.
- Every deviation carries a pre-decided fallback in Assumptions, so the implementer never stalls.

The one design fork I did not need to ask about: your sentence "unions (`||` and space-separated OR)" is unambiguous, so whitespace-as-OR is implemented as specified, with a contingency noted in case node-semver AND semantics were intended.

Ready for review — approve to hand off to the Build agent.
