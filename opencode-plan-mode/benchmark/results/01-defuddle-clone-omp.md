# Plan: `clean-read` — HTML-to-Markdown CLI (defuddle core clone)

## Context

Build a Rust CLI binary `clean-read` that accepts an HTML source (URL, local file, or stdin), extracts the main readable content while stripping navigation/ads/sidebars/headers/footers, and prints clean Markdown — matching the core behavior of github.com/kepano/defuddle (verified against its README: source = file path | URL | stdin, `--markdown`/`--json`/`--output`/`--user-agent` flags, main-content extraction, metadata output). The end state is a working binary whose every required flag, error path, and output mode is implemented and verified; this plan covers the full implementation, not a scaffold.

## Approach

**1. Scaffold the crate and pin dependencies** — `cargo new clean-read --bin`. `Cargo.toml`:
```toml
[dependencies]
clap = { version = "4", features = ["derive"] }
reqwest = { version = "0.12", default-features = false, features = ["blocking", "rustls-tls", "redirect"] }
scraper = "0.20"
serde_json = "1"
```

**2. Define the CLI contract** — `src/main.rs` uses `clap` derive: positional `source: Option<String>` (absent or `-` ⇒ read stdin), `--markdown` (bool, `default_value_t = true` — always on; the target defines no off-switch), `--json` (bool; emits `{"title": ..., "content": ...}` with `content` = the Markdown text), `--output <PathBuf>` (write to file instead of stdout), `--user-agent <String>` (default pinned string `clean-read/0.1 (Rust)`). `--json` and `--markdown` are independent: `--json` wraps the Markdown output in the metadata object. `fn main() -> ExitCode`; clap usage errors exit 2 (clap default); all runtime errors print the distinct message below to stderr and exit 1.

**3. Acquire the source** — `src/acquire.rs`, `fn source_html(source: &Option<String>) -> Result<String, CleanReadError>`:
- `None` or `Some("-")` ⇒ read all of stdin (`Read::read_to_string`); failure ⇒ `ReadFailed { path: "<stdin>", .. }`.
- `Some(s)` starting with `http://` or `https://` (after trim) ⇒ HTTP path; anything else ⇒ local file: `fs::read_to_string`; `NotFound` ⇒ `MissingFile { path }`; other error ⇒ `ReadFailed { path, err }`.

**4. Fetch over HTTP** — `src/fetch.rs`, `fn fetch_html(url: &str, user_agent: &str) -> Result<String, CleanReadError>` using reqwest blocking client built with `redirect::Policy::limited(5)`, `timeout(Duration::from_secs(30))`, `header(USER_AGENT, user_agent)`. Error mapping (each a distinct message, all exit 1):
- Redirect limit exceeded ⇒ `RedirectLimit { url }` → `"error: too many redirects while fetching '{url}' (limit: 5)"`
- Response status not 200-299 ⇒ `HttpStatus { code }` → `"error: HTTP request failed with status {code}"`
- `Content-Type` header neither `text/html*` nor `application/xhtml+xml*` (checked before reading body) ⇒ `NotHtml { ct }` → `"error: response is not HTML (Content-Type: {ct})"`
- Client timeout ⇒ `Timeout { url }` → `"error: request timed out after 30s: {url}"`
- Other transport error ⇒ `FetchFailed { err }` → `"error: request failed: {err}"`
Response body bytes are decoded UTF-8 lossy.

**5. Parse HTML and detect the article root** — `src/extract.rs`. Parse with `scraper::Html::parse_document`. Title: text of the first `title` element; if empty, text of the first `h1` inside the chosen root; if still empty, `""`. Content-detection strategy (documented decision, per the target's "choose one strategy"): candidate chain `article` → `main` → `[role="main"]` (first match in document order); if none exists, text-density fallback: walk the top-level children of `body`, score each by `text_len − 2 × link_text_len` (Readability-inspired; text_len counts non-whitespace chars of descendant text nodes, link_text_len the text inside descendant `a` elements), pick the child with the highest strictly positive score; if no child scores > 0, use the `body` element itself.

**6. Strip boilerplate inside the root** — `fn strip_boilerplate(root: ElementRef) -> ElementRef` (operates on the same document): remove descendants matching `nav, header, footer, aside, form, noscript, script, style, iframe, svg`; remove any element with a `hidden` attribute or an inline `style` attribute containing `display:none`; remove elements whose trimmed text content is empty (after the other removals). `article`/`main`/`[role=main]` wrapper elements themselves are kept but render as transparent containers (see step 7).

**7. Render Markdown** — `src/render.rs`, `fn to_markdown(root: ElementRef) -> String`, document-order walk emitting:
- `h1`–`h6` ⇒ `#`×level + space + inline content + blank line
- `p` ⇒ inline content + blank line
- `ul` ⇒ `- ` items, nested lists indented 2 spaces; `ol` ⇒ `1. `, `2. `, … (continue numbering)
- `pre` ⇒ fenced block: ```` ```lang ```` (lang = value of first `class` token on `pre` or `code` child, else empty) + raw inner text + closing fence + blank line
- inline `code` ⇒ backtick-wrapped
- `a` ⇒ `[text](href)` (href from `href` attribute; if text empty, use href as text)
- `img` ⇒ `![alt](src)` using `alt` and `src` attributes only; no other image attributes
- `div`/`span`/`article`/`main`/`section` ⇒ transparent: emit their inline content in place
- everything else ⇒ skip (no output)
Block-level children get blank-line separation; inline content is flattened.

**8. Emit output** — `--output <file>` ⇒ `fs::write`; failure ⇒ `WriteFailed { path, err }` → `"error: cannot write '{path}': {err}"`. Else stdout. `--json` ⇒ `serde_json::to_string(&json!({"title": title, "content": content}))` + newline.

**9. Error type** — `src/error.rs`: `enum CleanReadError` with the variants named in steps 3–4 and 8 (`MissingFile`, `ReadFailed`, `RedirectLimit`, `HttpStatus`, `NotHtml`, `Timeout`, `FetchFailed`, `WriteFailed`), hand-written `Display` (the exact message strings above) + `std::error::Error`. `main` matches and prints `{e}` to stderr, exit 1.

## Critical files & anchors

- `clean-read/Cargo.toml` — dependency set (clap/reqwest/scraper/serde_json); everything else follows from it.
- `clean-read/src/main.rs` — `fn main() -> ExitCode`; arg parse + error dispatch; the only place all five error classes converge.
- `clean-read/src/fetch.rs` — `fn fetch_html`; redirect/status/content-type/timeout distinctions live here.
- `clean-read/src/extract.rs` — `fn detect_root` + `fn strip_boilerplate`; the documented content-detection strategy.
- `clean-read/src/render.rs` — `fn to_markdown`; element-to-Markdown mapping the target's preserve-list pins.

## Verification

Concrete checks (all against the built binary, `cargo build --release` first):

1. **Stdin → Markdown**: `printf '<html><head><title>My Post</title></head><body><nav>Nav</nav><article><h1>Hello</h1><p>World <a href="/x">link</a></p><img src="/img.png" alt="pic"></article><footer>Foot</footer></body></html>' | ./target/release/clean-read -` must print exactly:
```
# Hello

World [link](/x)

![pic](/img.png)
```
(stderr silent; exit 0; `nav`/`footer` text absent — proves boilerplate stripping and the preserve list.)

2. **Local file + JSON**: write the same HTML to `tests/fixtures/blog.html`; `./target/release/clean-read --json tests/fixtures/blog.html` must print a JSON object with `"title":"My Post"` and `"content"` equal to the Markdown from check 1.

3. **Missing file**: `./target/release/clean-read /definitely/missing.html` must print `error: cannot read '/definitely/missing.html': no such file` to stderr and exit 1.

4. **HTTP error classes**: integration test `tests/http.rs` spins a `std::net::TcpListener`-based mini server in a thread serving four routes: `/ok` (HTML 200), `/missing` (404), `/loop` (301 → `/loop`), `/json` (`Content-Type: application/json`). Assert per route: `/ok` extracts content; `/missing` → stderr `error: HTTP request failed with status 404`, exit 1; `/loop` → `error: too many redirects while fetching '<url>' (limit: 5)`, exit 1; `/json` → `error: response is not HTML (Content-Type: application/json)`, exit 1. Timeout path asserted with a `127.0.0.1:9` (discard port) connection attempt and a 30s→2s timeout override constant in tests only (pinned: the 30s constant lives in `src/fetch.rs` as `const REQUEST_TIMEOUT: Duration`; tests set a cfg(test) override of 2s).

## Assumptions & contingencies

- **Detection strategy** is the decision the target requires documenting: selector chain then density fallback (step 5). If a real-world page defeats it (density picks a sidebar), the fallback is documented and testable — no silent change.
- **Default user-agent** pinned to `clean-read/0.1 (Rust)`; override with `--user-agent`. If a site 403s the default, the flag exists per the target.
- **Timeout 30s** pinned; if network conditions need more, change the single `REQUEST_TIMEOUT` constant.
- **`--markdown` has no off-switch** — the target defines only `--markdown` (default on); `content` in JSON is therefore always Markdown. If the user later wants raw-HTML JSON output, add `--format html` behind a new flag; not in this plan.
- **All runtime errors exit 1** (distinct messages satisfy the target's "distinct error message with non-zero exit code"); clap usage errors exit 2. If distinct exit codes per class are desired, map each `CleanReadError` variant to a code in `main` — one match arm.
- **Charset**: response/file bytes decoded UTF-8 lossy; no charset negotiation (target does not require it). If non-UTF-8 pages must round-trip, add encoding detection — out of this plan's scope by the target's silence.
- **reqwest 0.12 redirect API**: `Policy::limited(5)` is current; if the pinned version's API differs (`unverified — confirm first` at build time), fall back to `Policy::none()` plus a manual ≤5-follow loop in `fetch_html` — same observable errors.
