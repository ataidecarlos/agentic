# Opencode plan agent output — target 01

## Plan artifact (plans/clean-read-plan.md, verbatim)

# clean-read — Rust CLI that extracts main content from HTML as Markdown

## Context

Build a Rust CLI tool `clean-read` in the empty working directory `C:\Users\ataid\projects\planner\scratch\bench\01` (only a stray 0-byte `run.log` exists; leave it). It accepts a URL, a local HTML file path, or `-`/nothing for stdin HTML; detects the article region; strips boilerplate; prints Markdown (or a `{title, content}` JSON object, or a file). It must match the *core behavior* of github.com/kepano/defuddle: semantic entry-point selection, content-start boundary detection, a removal pipeline for nav/ads/sidebars/headers/footers, and clean Markdown output. Five HTTP/file failure classes get distinct messages and exit codes. The content-detection strategy is documented in this plan (step 7) as required by the task.

## Approach

### 1. Scaffold the crate and dependency set

1. Run `cargo init --name clean-read --vcs none .` in the working directory (Rust 1.97.1 is installed; `--vcs none` because the directory is not a git repo).
2. Replace the generated `Cargo.toml` with the exact contents below (dependencies to be fetched from crates.io — network is available):

```toml
[package]
name = "clean-read"
version = "0.1.0"
edition = "2021"

[dependencies]
clap = { version = "4", features = ["derive"] }
reqwest = { version = "0.12", features = ["blocking", "gzip"] }
scraper = "0.23"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
url = "2"
```

3. Create the module layout: `src/main.rs`, `src/error.rs`, `src/fetch.rs`, `src/extract.rs`, `src/markdown.rs`, and `tests/cli.rs` with a `tests/fixtures/` directory. No other files.

### 2. Define the error contract (src/error.rs)

1. Define `#[derive(Debug, thiserror::Error)] enum AppError` with exactly these variants, messages, and exit codes. Every variant's message text is exact and final (printed as `clean-read: error: <msg>` to stderr):

| Variant | Message | Exit code |
|---|---|---|
| `MissingFile { path: String }` | `cannot read "<path>": file not found` | 3 |
| `NotAFile { path: String }` | `cannot read "<path>": not a file` | 3 |
| `RedirectLimit` | `too many redirects (limit 5)` | 4 |
| `HttpStatus { code: String }` | `HTTP <code>` (e.g. `HTTP 404 Not Found`; use `StatusCode::as_u16()` + `StatusCode::canonical_reason().unwrap_or("")`) | 5 |
| `NonHtml { content_type: String }` | `not an HTML page (Content-Type: <ct>)` | 6 |
| `Timeout { secs: u64 }` | `request timed out after <secs>s` | 7 |
| `Network { source: reqwest::Error }` | `network error: <source>` | 8 |
| `Output { path: String, source: std::io::Error }` | `cannot write "<path>": <source>` | 1 |
| `Io { source: std::io::Error }` | `<source>` | 1 |
| `Parse { source: String }` | `failed to parse HTML: <source>` | 1 |

2. Add `impl AppError { pub fn exit_code(&self) -> i32 }` returning the table's code (0 is never returned by an error). Success is exit 0; clap usage errors use clap's default exit 2.
3. `src/main.rs`'s `fn main() -> std::process::ExitCode` calls the real `run()` (which returns `Result<(), AppError>`), prints `clean-read: error: {msg}` to stderr on `Err`, and returns `ExitCode::from(e.exit_code() as u8)`. For `Parse`, also print the message.

### 3. Implement the CLI contract and source resolution (src/main.rs)

1. `#[derive(clap::Parser)] #[command(name = "clean-read", version, about = "Extract the main readable content from an HTML page as Markdown")] struct Cli` with exactly:
   - `source: Option<String>` — positional; help `"URL, local HTML file path, or - for stdin (default: stdin)"`.
   - `#[arg(long)] json: bool` — help `"Emit a JSON object {\"title\":...,\"content\":...} instead of raw Markdown"`.
   - `#[arg(long)] markdown: bool` — accepted for compatibility; **no-op** (Markdown is always the output format). Suppress the unused-field warning with `let _ = cli.markdown;` after parse.
   - `#[arg(long, short = 'o')] output: Option<PathBuf>` — help `"Write output to <file> instead of stdout"`.
   - `#[arg(long)] user_agent: Option<String>` — help `"Custom User-Agent header for HTTP requests"`.
2. `enum Source { Stdin, Url(String), File(String) }`; `fn resolve_source(cli: &Cli) -> Source`:
   - `None` or `Some("-")` → `Stdin`.
   - Else try `url::Url::parse(s)`; if it parses **and** the scheme is `http` or `https` (case-insensitive) → `Url`.
   - Else → `File(s.to_string())`. This correctly treats `C:\foo.html` (scheme `c`) and `page.html` (parse failure) as file paths.
3. Timeout knob (test-only, not a CLI flag): `fn timeout_secs() -> u64` reads env var `CLEAN_READ_TIMEOUT_SECS`; valid `u64` → that value, else default `30`.

### 4. Implement the fetch layer (src/fetch.rs)

1. `pub fn fetch_html(url: &str, user_agent: &str) -> Result<String, AppError>`:
   - Build `reqwest::blocking::Client` via `Client::builder().redirect(reqwest::redirect::Policy::limited(5)).timeout(std::time::Duration::from_secs(timeout_secs())).user_agent(user_agent).build().map_err(AppError::Network)?`.
   - `client.get(url).send()`; on `Err(e)`: `e.is_timeout()` → `Timeout { secs }`; `e.is_redirect()` → `RedirectLimit`; anything else → `Network { source: e }`.
   - If `!resp.status().is_success()` → `HttpStatus { code }` (see table).
   - Content-Type check: read header `content-type`; if present and its value (case-insensitive, whitespace-trimmed) does **not** start with `text/html` or `application/xhtml+xml` → `NonHtml { content_type }`. A missing header is accepted (lenient, curl-like).
   - `resp.bytes()` → `String::from_utf8_lossy(&bytes).into_owned()` (no charset detection — documented limitation).
2. Default user-agent constant in `src/main.rs`: `const DEFAULT_UA: &str = "clean-read/0.1.0";` used when `--user-agent` is absent.

### 5. Implement file/stdin input (src/main.rs)

1. `fn read_local(path: &str) -> Result<String, AppError>`: if `!std::path::Path::new(path).exists()` → `MissingFile`; if it exists but `is_dir()` → `NotAFile`; else `std::fs::read_to_string(path).map_err(AppError::Io)`.
2. `fn read_stdin() -> Result<String, AppError>`: `std::io::read_to_string(std::io::stdin())`, mapping errors to `AppError::Io`.

### 6. Implement title extraction (src/extract.rs)

1. `pub fn extract_title(doc: &scraper::Html) -> String`:
   - Prefer `<meta property="og:title" content="...">` (first match), else `<title>` text.
   - Trim, whitespace-collapse (`fn normalize_ws(&str) -> String` collapses all runs of whitespace to single spaces and trims).
   - Return `""` if neither exists.

### 7. Implement content detection — THE strategy (src/extract.rs)

Write this as a module doc comment so the strategy is documented in code, then implement it exactly as specified. The strategy mirrors defuddle's pipeline (entry points → content-start boundary → removals) with a text-density fallback:

**Stage 1 — semantic entry point.** Iterate this ordered selector list; for each, take the **first** element match in document order; if its *effective text* (see below) is ≥ 140 chars, that element is the content root and stop:
`article`, `[role="article"]`, `main`, `[role="main"]`, `.post-content`, `.entry-content`, `.article-content`, `#content`.
*Effective text* of an element = length of whitespace-collapsed `el.text()` minus length of whitespace-collapsed text of all descendant `a` elements.

**Stage 2 — text-density fallback.** If Stage 1 yields no qualifying root: for every `div` and `section` element in the document (document order), compute effective text; pick the element with the **maximum** effective text. If the maximum is ≥ 140 chars → that is the content root; otherwise use `body`. This handles pages with no semantic markers (the "text-density fallback" required by the task).

**Stage 3 — content-start boundary** (adapted from defuddle `content-boundary.ts`): find where prose begins inside the root:
- Anchor: the first `h1` or `h2` whose normalized text equals `extract_title(doc)` (normalized). If found, start the walk there; if nothing qualifies after the anchor, retry the whole walk from the root top with no anchor (defuddle's retry).
- Walk descendants in document order (skipping the anchor itself). The first element that `is_prose_block(el)` becomes the content start:
  - tag ∈ {`p`, `div`, `section`, `blockquote`, `font`};
  - not inside (any ancestor of tag) `aside, nav, header, footer, form, [role="dialog"], [role="alertdialog"]`;
  - class does not match `\b(?:isHidden(?:-[A-Za-z0-9_]+)?|is-hidden)\b`;
  - no `script`/`style`/dialog descendant;
  - trimmed text ≥ 7 words (`fn count_words(&str) -> usize` splits on whitespace);
  - contains at least one of `. ! ?`;
  - not a byline: starts with `by ` (case-insensitive) and < 15 words; not a date line: matches `\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+\d{1,2}\b|\b\d{1,2}(?:st|nd|rd|th)?\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\b|\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b` and < 20 words;
  - descendant `a` text ≤ 70% of total text.
- Everything strictly before the content start (non-ancestor subtrees) is dropped; ancestors of the start are transparent containers. If no prose block is found, keep the whole root (no signal → don't trim).

**Stage 4 — cleanup predicates.** Two predicate functions consulted during serialization (the scraper tree is immutable; no DOM mutation):
- `fn is_removed(el: &scraper::ElementRef) -> bool` — true if the element matches any of:
  - Exact CSS list (one precompiled `scraper::Selector`, comma-joined): `script, style, noscript, template, iframe, object, embed, form, button, input, select, textarea, canvas, dialog, header, footer, nav, [role="dialog"], [role="alertdialog"], [role="navigation"], [role="banner"], [role="complementary"], [hidden], [aria-hidden="true"], .ad, .ads, .adsbygoogle, .sidebar, #sidebar, #comments, #comment, .comments, .toc, #toc, .copyright, #banner, .sr-only, .visually-hidden, .hidden, .invisible, .noprint`.
  - Partial substring matcher: lowercased `class` and `id` attribute values are tested (case-insensitive substring) against this bounded list: `advert, adsbygoogle, sidebar, breadcrumb, pagination, comment, share, social, newsletter, subscribe, signup, cookie, consent, popup, modal, related, recommended, toc, byline, timestamp, published, author-bio, skip-link, back-to-top, copyright, sponsored, promo, widget, navbar, navigation`. Any hit → removed.
  - Inline-hidden: the `style` attribute matches `(?i)(?:display|visibility)\s*:\s*(?:none|hidden)\b`.
- `fn is_low_score(el: &scraper::ElementRef) -> bool` — for block containers (`div, section, ul, ol, nav, aside`): true if effective text < 25 chars **and** descendant-`a` text > 60% of total text (link-list blocks, e.g. "most read" widgets). Also true for empty containers: no text and no descendant of `img, iframe, pre, table, ul, ol, li, blockquote, figure` (with `img/br/hr` counted non-empty).
- `fn is_small_image(el: &scraper::ElementRef) -> bool` — for `img`: true if a `width` or `height` attribute parses to an integer < 40 (tracking pixels; defuddle's `removeSmallImages`).

Selectors are static and known-valid: `Selector::parse` errors are `expect("static selector")`.

`pub struct Extracted<'a> { pub title: String, pub root: scraper::ElementRef<'a>, pub start_id: Option<usize>, pub removed_ids: std::collections::HashSet<usize> }`; `pub fn detect(doc: &scraper::Html) -> Extracted<'_>` runs Stages 1–4:
- `removed_ids` = ids of all elements matching `is_removed` **inside root** (`root.select(&removal_selector)` + per-element class/id/style checks). `scraper::NodeRef::id()` gives the tree-unique id; ancestor-of-removed subtrees are naturally skipped by the walker.
- If `root` itself matches a removal selector, the root is replaced by its first child that does not match (recursively).
- `start_id` = `Option<NodeRef::id>` of the content start; `None` when Stage 3 finds no block.

### 8. Implement the Markdown serializer (src/markdown.rs)

`pub fn to_markdown(extracted: &Extracted<'_>, doc: &scraper::Html) -> String`. Traverse descendants of `root` pre-order; build output with `fn push_block(out: &mut String, block: &str)` that trims each block and joins blocks with exactly one blank line (`\n\n`); final output is trimmed with a single trailing `\n`.

Per-node rules (children of each block serialized by `fn inline(el) -> String`; inline output gets whitespace-collapsed text; leading/trailing spaces trimmed at block boundaries):

- **Removal**: if node id ∈ `removed_ids`, or element and `is_low_score`, or `img` and `is_small_image` → skip node and entire subtree.
- **Boundary**: if `start_id` is `Some`, precompute `ancestor_ids` = ids of the start node's ancestors (via `NodeRef::ancestors()`); before reaching the start node, descend only into nodes whose id ∈ `ancestor_ids`, emitting nothing; at the start node, begin emitting (it and everything after).
- **Text** (`Node::Text`): whitespace-collapse; emit raw (no escaping — documented limitation).
- **`h1`–`h6`**: `#`×level + ` ` + inline children + blank line. **Title dedupe**: after serialization, if `title` is non-empty and the *first* block of output is an `h1` whose normalized text equals the normalized title, drop that first h1 block (the title is emitted separately, below); otherwise keep it.
- **`p`**: inline children + blank line. Skip if inline output is empty.
- **`br`**: emit `\n` (soft break) inside inline text.
- **`strong`/`b`**: `**` + inline + `**`. **`em`/`i`**: `*` + inline + `*`. **`code`** (inline): `` ` `` + text + `` ` `` (if text contains a backtick, emit as-is without fences).
- **`a`**: `[<inline children>](<href>)`; if `href` attr is absent/empty → emit inline children only; if inline children are empty → emit nothing.
- **`img`**: `![<alt>](<src>)` using `alt` (or `""`) and `src` attributes; if `src` is absent/empty → emit nothing.
- **`ul`/`ol`**: each `li` on its own line; `ul` prefix `- `, `ol` prefix `<n>. ` where `n` counts sequentially from 1; nested lists indent 2 spaces per level; blank line after the list.
- **`pre`**: take first descendant `code` element (else the `pre` itself); text is emitted **verbatim** (no whitespace collapse); language = first `class` token starting with `language-` (strip prefix), or the `data-lang` attr; fence is ```` ```lang ```` (or plain ```` ``` ```` when no language) + `\n` + text + `\n` + ```` ``` ```` + blank line.
- **`blockquote`**: prefix every line of the inner serialization with `> `.
- **`hr`**: `---` + blank line.
- **`table`** (out of required scope, documented limitation): emit each cell's inline text as plain paragraphs (cells joined by a space).
- **Other elements** (`div`, `section`, `span`, `small`, `sub`, `sup`, `mark`, `del`, `ins`, `u`, `figure`, `figcaption`, `time`, etc.): transparent — serialize children inline/block per child type.

Title emission: after dedupe, if `title` is non-empty, prepend `# <title>\n\n` to the output.

### 9. Implement output dispatch (src/main.rs)

1. `fn run() -> Result<(), AppError>`:
   - `cli = Cli::parse()`; `let _ = cli.markdown;`
   - `html = match resolve_source(&cli) { Stdin => read_stdin()?, Url(u) => fetch_html(&u, cli.user_agent.as_deref().unwrap_or(DEFAULT_UA))?, File(p) => read_local(&p)? };`
   - `doc = scraper::Html::parse_document(&html)`; on panic-free parse (`Html::parse_document` never fails) — no `Parse` path is reachable; keep the variant for future use. `extracted = extract::detect(&doc)`; `md = markdown::to_markdown(&extracted, &doc)`.
   - `payload = if cli.json { serde_json::to_string(&serde_json::json!({"title": extracted.title, "content": md})).map_err(...)? + "\n" } else { md }`.
   - Output: if `cli.output` is `Some(path)` → `std::fs::write(&path, &payload).map_err(|e| AppError::Output { path: path.display().to_string(), source: e })?`; else print `payload` to stdout (using `print!` with `{}`, which honors the trailing `\n`; no extra newline beyond `payload`'s).
   - JSON field names are exactly `title` and `content`; `content` is the same Markdown string as the non-JSON path (matches defuddle's `--markdown --json` combination).

### 10. Write tests and fixtures

1. `tests/fixtures/article.html` — exact content:
```html
<!doctype html><html><head><title>Rust CLI Tools</title><meta property="og:title" content="Rust CLI Tools"></head>
<body>
<nav>Navigation: Home About Contact</nav>
<header><h1>Rust CLI Tools</h1><p>by Jane Smith</p></header>
<div id="ad-zone">Advertisement: Buy now</div>
<main>
  <p>Rust CLI tools are compiled, fast, and easy to distribute as single binaries.</p>
  <h2>Why Rust</h2>
  <ul><li>Memory safety</li><li>Zero-cost abstractions</li></ul>
  <p>See <a href="https://rust-lang.org">rust-lang.org</a> for details.</p>
  <pre><code class="language-rust">fn main() { println!("hi"); }</code></pre>
  <img src="https://example.com/diagram.png" alt="Architecture diagram">
</main>
<footer>© 2026 Rust CLI Tools. All rights reserved.</footer>
</body></html>
```
2. `tests/fixtures/density.html` — a page with **no** semantic markers (`article`/`main`/`role=main` absent): two sibling `div`s, one a link-dense sidebar, one prose (≥ 140 effective chars) — exercises Stage 2 and the low-score/link-ratio removal.
3. `tests/fixtures/tiny.html` — a minimal page: `<html><body><p>Hello world.</p></body></html>` — exercises the empty-title and boundary-fallback paths.
4. `tests/http_server.rs` — a `std::net::TcpListener`-based HTTP/1.1 server (zero extra dev-dependencies), started in a spawned thread on `127.0.0.1:0`; the bound port is sent back over an `std::sync::mpsc` channel. Handlers (each returns `200` unless noted; all `text/html` unless noted):
   - `/ok` — the `article.html` fixture body.
   - `/ua` — body is `<html><body><p>UA: <USER-AGENT></p></body></html>` echoing the request's `User-Agent` header.
   - `/redir` — `302` + `Location: /ok`.
   - `/loop` — `302` + `Location: /loop` (never terminates).
   - `/missing` — `404` + `text/html` body `<html><body><p>Not found</p></body></html>`.
   - `/not-html` — `200` with `Content-Type: text/plain`, body `hello`.
   - `/slow` — sleeps 5 s, then `200` `text/html`.
   (The server reads the request line, responds, and closes; sequential handling is fine for tests.)
5. `tests/cli.rs` — spawn the built binary via `env!("CARGO_BIN_EXE_clean-read")` with `std::process::Command` and assert, for each case, `status.code()` and the stderr/stdout:
   - File input (`article.html`) → exit 0; stdout **exactly** equals the expected block in the Verification section.
   - Stdin: pipe `article.html` content to `clean-read -` and to `clean-read` (no arg) → same output.
   - `--json article.html` → stdout parses as JSON with keys `title` and `content` (assert values).
   - `--output out.md article.html` → file `out.md` exists with the same content as the stdout run.
   - Density fixture → stdout contains `Density prose paragraph.` text and **not** `Sidebar link` text.
   - HTTP: `/ok` exit 0 and content matches fixture output; `/ua` with no `--user-agent` contains `clean-read/0.1.0`, with `--user-agent TestUA` contains `TestUA`; `/redir` exit 0; `/loop` exit 4 with stderr containing `too many redirects`; `/missing` exit 5 with `HTTP 404`; `/not-html` exit 6 with `not an HTML page`; `/slow` exit 7 with `timed out` (set env `CLEAN_READ_TIMEOUT_SECS=1` for this test only).
   - Missing file `tests/fixtures/does-not-exist.html` → exit 3, stderr contains `file not found`; directory passed as source → exit 3, stderr contains `not a file`.
   - Assert every success exit is 0 and every failure exit is non-zero.

## Critical files & anchors

- `Cargo.toml` — the exact dependency block from step 1; anchors the crate name `clean-read` (must match the binary name used by `env!("CARGO_BIN_EXE_clean-read")`).
- `src/main.rs` — `Cli` struct, `resolve_source`, `read_local`/`read_stdin`, `DEFAULT_UA`, `run()`, `main()` exit-code mapping; consumes `AppError` from `src/error.rs`.
- `src/fetch.rs` — `fetch_html` with the reqwest builder (`Policy::limited(5)`, 30 s timeout, UA), the five-way error mapping, and the Content-Type gate.
- `src/extract.rs` — `extract_title`, `detect` (Stages 1–4), `is_prose_block`, `is_removed`, `is_low_score`, `is_small_image`, all threshold constants, the strategy doc comment.
- `src/markdown.rs` — `to_markdown`, `inline`, `push_block`, title dedupe, per-tag block rules from step 8.

## Verification

1. `cargo build` succeeds with no warnings (except the silenced `markdown` field); `cargo test` passes all cases in step 10.
2. Concrete end-to-end check (the primary smoke): run
   `cargo run -- tests/fixtures/article.html`
   and expect **exactly** this stdout (the nav/header-byline/ad/footer are stripped; the `h1` matching the title is deduped against the emitted `# Rust CLI Tools`):
```
# Rust CLI Tools

Rust CLI tools are compiled, fast, and easy to distribute as single binaries.

## Why Rust

- Memory safety
- Zero-cost abstractions

See [rust-lang.org](https://rust-lang.org) for details.

```rust
fn main() { println!("hi"); }
```

![Architecture diagram](https://example.com/diagram.png)
```
3. Stdin parity: `Get-Content -Raw tests/fixtures/article.html | cargo run -- -` produces identical output (PowerShell 7 pipes UTF-8; `-Raw` avoids line-splitting).
4. `cargo run -- --json tests/fixtures/article.html` prints one line: `{"title":"Rust CLI Tools","content":"# Rust CLI Tools\n\nRust CLI tools are compiled, fast, and easy to distribute as single binaries.\n\n## Why Rust\n\n- Memory safety\n- Zero-cost abstractions\n\nSee [rust-lang.org](https://rust-lang.org) for details.\n\n```rust\nfn main() { println!(\"hi\"); }\n```\n\n![Architecture diagram](https://example.com/diagram.png)\n"}`
5. `cargo run -- --output out.md tests/fixtures/article.html` creates `out.md` whose bytes equal the step-2 stdout; then delete `out.md`.
6. HTTP failure modes are proven by `cargo test` (hermetic local server): `/loop` → exit 4, `/missing` → exit 5, `/not-html` → exit 6, `/slow` → exit 7, missing file → exit 3, plus the `/ua` user-agent assertions.

## Assumptions & contingencies

- **Crates.io is reachable** during build. Contingency: if the network is blocked, vendor the four crates (`cargo vendor`) and note it — no design change.
- **Version pins are minimums**: use the latest semver-compatible release of each crate at implementation time (clap 4.x, reqwest 0.12.x, scraper 0.23.x, serde/serde_json 1.x, thiserror 2.x, url 2.x). If scraper's API differs at that version (e.g. `NodeRef::id()`/`ancestors()` moved), adapt calls to the documented equivalents — the detection strategy itself is unchanged.
- **No charset detection**: response/file bytes are decoded via `from_utf8_lossy`. Fallback if real pages show mojibake: add `encoding_rs` and sniff `Content-Type` charset / `<meta charset>`, wiring a `decode(html, bytes)` step between fetch and parse.
- **No JS execution and no stylesheet parsing** (a CLI cannot run a page's JS): hidden detection covers inline `style` and `hidden`/`aria-hidden`/hidden-classes only; sites whose boilerplate is JS-inserted will yield whatever the raw HTML contains. This matches defuddle's `removeHiddenElements` within a non-browser DOM.
- **`header`/`footer`/`nav` are removed wholesale** per the task's "strip headers/footers" requirement, even though defuddle keeps a `header` that contains multiple paragraphs. Sites wrapping the entire article in `<header>` may lose content — accepted tradeoff, documented in the strategy comment.
- **`--markdown` is a no-op** (Markdown is always the output; `--json` only changes the envelope). This matches "`--markdown` (default on)" in the task; if the user wants `--markdown` to toggle a non-default format later, that is a separate change.
- **Distinct exit codes are a superset of the requirement** (task only demands non-zero); they are documented in the `AppError` table and may be simplified to a single non-zero code without affecting behavior tests (which assert the specific codes — keep them).
- **No markdown escaping pass** (headings/lists with literal `#`/`*` at line start may render ambiguously); inline emphasis is preserved for `strong`/`em`/`code` only. Escaping is out of scope unless a test fixture exposes breakage.
- **Tables are out of required scope**: rendered as plain paragraph text. If the user needs GFM tables, that is a follow-up.
- The 0-byte `run.log` in the working directory is left untouched.

## Chat summary (verbatim from run output)

## Summary

**Goal:** A Rust CLI `clean-read` that extracts the main content of an HTML page (URL / file / stdin) and prints Markdown, matching defuddle's core behavior — plus `--json`, `--output`, `--user-agent`, and five distinct error classes.

**Key decisions (all grounded in research):**
- **Stack:** `clap` 4 (derive), `reqwest` 0.12 blocking (`redirect(Policy::limited(5))`, 30s timeout, gzip), `scraper` 0.23 (html5ever DOM + CSS selectors — same parsing family as defuddle's DOM), `serde_json`, `thiserror`, `url`. Hand-rolled Markdown serializer (~no external HTML→MD dep) for exact control over the required output (title, h1–h6, paragraphs, lists, code fences with language, links, `![alt](src)` images).
- **Detection strategy (documented in the plan, as required):** Stage 1 ordered semantic selectors (`article` → `[role=article]` → `main` → `[role=main]` → `.post-content`/`.entry-content`/`.article-content` → `#content`) with an effective-text threshold; Stage 2 text-density fallback (max effective text among `div`/`section`, else `body`); Stage 3 defuddle's content-start boundary (title-anchored prose-block walk with byline/date/link-density guards); Stage 4 cleanup (exact+partial removal selectors, inline-hidden, low-score link-lists, small-image removal).
- **Error contract:** distinct messages + exit codes — 3 missing/not-a-file, 4 redirect limit, 5 non-200, 6 non-HTML Content-Type, 7 timeout, 8 network.
- **Verification:** hermetic — a tiny `std::net` HTTP test server exercises redirects/404/non-HTML/timeout/UA paths against the built binary, plus a concrete fixture with the exact expected stdout listed in the plan.

**Assumptions worth your review:** `--markdown` is a no-op (Markdown is always the format); `header`/`footer`/`nav` removed wholesale; no charset detection (lossy UTF-8); no markdown escaping; tables rendered as plain text.
