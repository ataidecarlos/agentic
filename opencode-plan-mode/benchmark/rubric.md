# Rubric

Score each plan 1–5 per dimension. 5 = fully satisfies the dimension; 1 = absent or materially wrong. A dimension with no observable evidence gets 1, not a middle score.

| # | Dimension | 5 means |
|---|---|---|
| 1 | Decision-completeness | An engineer with no knowledge of the planning conversation executes top-to-bottom with zero design decisions; no open questions, no hand-waved choices. |
| 2 | Concrete edits | Every step names a verb + exact target (file/symbol/function) + new behavior. Zero "area to update/handle/consider" phrasing. |
| 3 | Callsite/symbol enumeration | Renames/signature changes enumerate every affected callsite and deletion; clean cutover with no shims/aliases. Decisive on target 02. |
| 4 | Verification specificity | At least one check with a concrete input and its expected observable output, exercising the real surface — not "run the tests". |
| 5 | Grounding | Real files/symbols read and cited; unconfirmed claims marked `unverified — confirm first`; no guesses stated as settled. |
| 6 | No padding | No Non-Goals/Out of Scope/Alternatives/Risks/Future Work sections; no mechanical cleanup tail; high signal-to-length. |
| 7 | Error/edge handling | Every new path states empty/missing/conflict/error handling, or explicitly "none, and why". |
| 8 | Structure | All five sections present, in order, populated: Context / Approach / Critical files & anchors / Verification / Assumptions & contingencies. |

## Scoring notes

- Target 02: dimension 3 is weighted by completeness of the callsite list against the real `fd` source (every `print_error` call site named; old signature deleted, no alias).
- Target 04: dimension 5 includes whether the plan reproduces the failure itself (runs `cargo test --release` and observes the intermittent failure) rather than asserting it.
- Structure violations (missing section, extra Non-Goals section) cap dimension 8 at 2 and should be called out in the per-target delta note.
