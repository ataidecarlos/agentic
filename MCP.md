# High-Value MCP Servers for AI Coding Agents

This document presents MCP servers that provide significant benefits for AI coding workflows. These are recommendations based on community adoption, GitHub stars, and real-world impact. Evaluate each against your needs before installing.

## Tier 1: Universal Value

### Context7
**What it does:** Fetches up-to-date, version-specific library documentation directly from source. Eliminates hallucinated APIs.

**Why it matters:** Every coding agent hallucinates library APIs without current docs. Context7 solves this with zero API keys, free tier, and instant integration.

**Stats:** 62k GitHub stars, 3.9M+ npm downloads

**Install:**
```bash
npx -y @upstash/context7-mcp
```

**Verdict:** Install first. Highest impact for any coding agent.

---

### GitHub MCP (Official)
**What it does:** Full GitHub API access — repositories, issues, pull requests, code search, workflows, CI automation.

**Why it matters:** Agents can triage issues, draft PRs, search code across repos, and monitor CI without leaving the conversation.

**Stats:** 33k GitHub stars, official GitHub server

**Install:**
```bash
npx -y @modelcontextprotocol/server-github
```

**Verdict:** Essential for any repo-based workflow.

---

### Playwright MCP (Microsoft)
**What it does:** Browser automation, screenshots, page inspection, web interaction using Playwright.

**Why it matters:** Most-used MCP server in the community (mid-2026). Lets agents test UIs, scrape dynamic pages, verify deployments, and automate browser flows.

**Stats:** 38k GitHub stars, official Microsoft server

**Install:**
```bash
npx -y @playwright/mcp
```

**Verdict:** Default install for browser automation and testing.

---

## Tier 2: High Value for Specific Workflows

### Firecrawl MCP
**What it does:** Web scraping, search, crawling, and browser interaction. Converts pages to clean markdown or structured JSON.

**Why it matters:** Cleanest web-to-markdown for agents. Handles JS-heavy SPAs, geo-sensitive sites, and pages other scrapers can't parse.

**Stats:** Vendor server, free tier available (keyless)

**Install:**
```bash
npx -y firecrawl-mcp
```

**Verdict:** Install if you need live web access beyond basic search.

---

### Chrome DevTools MCP (Official)
**What it does:** Programmatic access to Chrome DevTools for debugging, performance profiling, network inspection, and page analysis.

**Why it matters:** Lets agents debug running applications instead of declaring success when code merely compiles. Deeper than Playwright for live debugging.

**Stats:** 53k GitHub stars, official Chrome DevTools server

**Install:**
```bash
npx -y @anthropic/chrome-devtools-mcp
```

**Verdict:** Install for web development and debugging workflows.

---

### Filesystem MCP (Reference)
**What it does:** Secure file operations with configurable access controls.

**Why it matters:** Reference implementation for local file access. Useful when you want scoped, permission-controlled file operations.

**Stats:** Official MCP reference server

**Install:**
```bash
npx -y @modelcontextprotocol/server-filesystem
```

**Verdict:** Install if you need explicit filesystem permissions.

---

### Exa MCP
**What it does:** Semantic search engine tuned for AI agents. Returns structured results optimized for LLM consumption.

**Why it matters:** Better than traditional search for agent workflows. Returns clean, structured data instead of raw HTML.

**Stats:** Vendor server, API key required

**Install:**
```bash
npx -y @exa-labs/exa-mcp-server
```

**Verdict:** Install if you need semantic web search.

---

## Code Graph MCP Servers

Code graph servers index your codebase into a knowledge graph, enabling structural queries, call-path tracing, and semantic code understanding. They solve the problem of agents grepping through entire repos.

### Graphify (Recommended Alternative)
**What it does:** Deterministic tree-sitter AST → knowledge graph. Parses 13+ languages plus docs, SQL schemas, configs, PDFs, and images. No vector store required.

**Why it's the best alternative:**
- **112.4k GitHub stars** — highest in this category
- **Deterministic** — no embeddings, no hallucination risk
- **Multi-format** — code, docs, schemas, configs, PDFs, images
- **Export options** — Neo4j Cypher, crawlable markdown wiki
- **3-tier edge provenance** — `EXTRACTED`/`INFERRED`/`AMBIGUOUS` for transparency

**Stats:** 112.4k GitHub stars, Python-based

**Install:**
```bash
pip install "graphifyy[mcp]"
# The PyPI package is `graphifyy` (double y). The CLI command is `graphify`,
# and the MCP stdio server is `python -m graphify.serve` (or `graphify-mcp`).
```

**Opencode entry:**
```jsonc
{ "type": "local", "command": ["python", "-m", "graphify.serve"] }
```

The server serves a prebuilt `graphify-out/graph.json` from the working
directory, so it only connects in a project where `graphify .` has already been
run. It is therefore registered `disabled: true` by default.

**Verdict:** Most comprehensive code graph solution. Install if you need multi-language, multi-format code intelligence.

---

### codegraph
**What it does:** Function-level dependency graph using tree-sitter → SQLite. Auto-syncs with file changes.

**Why it's notable:**
- **70.5k GitHub stars** — went viral in 2026
- **Claims significant savings** — 62% fewer tokens, 88% fewer tool calls, 44% lower cost
- **TypeScript over Rust** — native extraction kernel with vendored C grammars
- **Self-benchmarked** — most transparent self-benchmark in the field

**Stats:** 70.5k GitHub stars, TypeScript/Rust

**Install:**
```bash
npm install -g @colbymchenry/codegraph
codegraph serve --mcp
```

A bare `npx -y @colbymchenry/codegraph` invocation does **not** start an MCP
server; it prints CLI help and hangs, which Opencode reports as a 30s startup
timeout. The `serve --mcp` subcommand is required.

**Verdict:** Strong alternative if you want function-level graph with proven token savings.

---

### codebase-memory-mcp (Already Installed)
**What it does:** Tree-sitter parses 162 languages into SQLite-backed knowledge graph. Structural analysis backend for functions, classes, call chains, HTTP routes, cross-service links.

**Why it's solid:**
- **45k GitHub stars**
- **162 languages** — widest language support
- **No embedded LLM** — pure structural analysis
- **Native executable** — no API keys, no dependencies

**Stats:** 45k GitHub stars, native binary

**Verdict:** You already have this. Excellent for broad language support and structural queries.

---

### Claude Context (Different Approach)
**What it does:** Semantic code search using hybrid BM25 + dense vector search over Milvus/Zilliz Cloud. AST-aware chunking with Merkle-tree incremental indexing.

**Why it's different:**
- **Vector DB approach** — not a graph, but semantic retrieval
- **14 languages** — AST-aware chunking
- **~40% token savings** — targeted retrieval vs. loading whole folders
- **Managed cloud option** — Zilliz Cloud for teams

**Stats:** 13k GitHub stars, by Zilliz

**Install:**
```bash
npx -y @zilliz/claude-context-mcp
```

Requires a Zilliz Cloud account for the embedding backend, so it is registered
`disabled: true` until credentials exist.

**Verdict:** Install if you prefer semantic search over graph queries.

---

## Comparison: Code Graph Servers

| Server | Stars | Approach | Languages | Key Differentiator |
|--------|-------|----------|-----------|-------------------|
| **Graphify** | 112.4k | AST → Knowledge Graph | 13+ | Multi-format (code, docs, PDFs, images), deterministic |
| **codegraph** | 70.5k | Function-level Graph | Tree-sitter | Proven token savings, auto-sync |
| **codebase-memory-mcp** | 45k | Structural Graph | 162 | Widest language support, native binary |
| **Claude Context** | 13k | Semantic Search | 14 | Vector DB, hybrid BM25 + dense |

## Decision Framework

**Install these first:**
1. Context7 (docs)
2. GitHub MCP (repos)
3. Playwright MCP (browser)

**Add based on workflow:**
- Web scraping/search → Firecrawl or Exa
- Web development/debugging → Chrome DevTools MCP
- Code intelligence → Graphify (if you want the best) or stick with codebase-memory-mcp

**Skip if not needed:**
- Filesystem MCP (only if you need explicit permissions)
- Chrome DevTools (only for web dev)
- Exa (only if you need semantic search)

## Notes

- All servers listed are actively maintained as of September 2026
- Star counts and features may change; verify before installing
- Most servers support both stdio and HTTP transports
- Check each server's documentation for authentication requirements
