---
name: llm-council
description: Ask a council of several different LLMs the same hard question, have them rank each other's answers anonymously, then synthesise a single answer with a chairman model. Use when a question is high-stakes, genuinely open, or too important to trust to one model — architecture and design decisions, trade-off analysis, debugging a subtle bug, reviewing a plan, sanity-checking a conclusion, second opinions. Not for trivial lookups or questions you can answer directly.
---

# LLM Council

Runs the [karpathy/llm-council](https://github.com/karpathy/llm-council) pipeline headlessly. A question goes to several different models (**Stage 1: first opinions**); each model then ranks the others' answers with identities anonymised so it cannot play favourites (**Stage 2: peer review**); a chairman model synthesises everything into one answer (**Stage 3**).

Backed by **OpenCode Go** — four models from four different labs, no separate API key needed.

## When to use it

Reach for the council when the cost of being wrong is high or the question is genuinely contested:

- architecture and design decisions, especially irreversible ones
- trade-off analysis where you want the strongest counter-argument surfaced
- debugging something subtle where one model keeps missing the real cause
- reviewing a plan or a conclusion before acting on it

Skip it for factual lookups, small code edits, or anything you can answer directly — a run takes a minute or two and makes a dozen model calls.

## Usage

```bash
llm-council ask "question"                        # synthesised answer
llm-council ask --json "question"                 # every stage, machine-readable
llm-council ask --stage 1 "question"              # just the first opinions
llm-council ask --stage 2 "question"              # + peer rankings
llm-council ask --models deepseek-v4.1-flash,qwen3.7-plus "question"
llm-council ask --chairman glm-5.3 "question"
```

`llm-council "question"` works too — `ask` is implied.

## Reading the output

- **stdout** is the result only (the answer, or JSON with `--json`); **stderr** carries progress and errors, so it is safe to pipe.
- With `--json`, inspect `metadata.aggregate_rankings` to see which model the council rated highest, and `stage1`/`stage2` to see where models disagreed. Disagreement is often more informative than the synthesis.
- Exit code is non-zero if no model answered or no key is configured.

## Notes

- Default council: `deepseek-v4.1-flash`, `qwen3.7-plus`, `glm-5.3-flash`, `kimi-k2.6`; chairman `deepseek-v4.1-flash`.
- Models must be available on OpenCode Go's `/v1/chat/completions`. Reasoning models are fine, but avoid ones that emit ` thinking` tags into the content (e.g. `minimax-m3`), and `grok-*` / `gpt-*`, which are `/v1/responses` models.
- Run a full council in the background or with a generous timeout — it takes roughly 1–2 minutes.
- Configuration lives in `~/github/llm-council/backend/config.py` and is overridable by env (`LLM_COUNCIL_MODELS`, `LLM_COUNCIL_CHAIRMAN`, `LLM_COUNCIL_API_URL`, `LLM_COUNCIL_PROVIDER=openrouter`).
