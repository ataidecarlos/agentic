Build a Rust CLI tool `clean-read` that extracts the main readable content
from an HTML page and prints clean Markdown, matching the core behavior of
github.com/kepano/defuddle.

Requirements:
- Accept one source argument: a URL, a local HTML file path, or `-`/none for
  HTML on stdin.
- Strip navigation, ads, sidebars, headers/footers, and other non-article
  boilerplate; preserve the article title, headings (h1-h6), paragraphs,
  lists, code blocks, links, and images (image src/alt only).
- Print Markdown to stdout.
- Flags: `--markdown` (default on), `--json` (emit a metadata object with
  `title` and `content`), `--output <file>` (write to file instead of stdout),
  `--user-agent <string>`.
- Handle distinctly: HTTP redirects (follow up to 5), non-200 responses,
  non-HTML Content-Type, network timeouts, and missing local files — each a
  distinct error message with non-zero exit code.
- Choose one content-detection strategy (e.g. article/main/role=main first,
  then a text-density fallback) and document it in the plan.

Deliver an execution plan, not code.
