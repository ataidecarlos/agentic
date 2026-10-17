---
description: "Hidden override for OpenCode's built-in Plan agent. The Design pipeline replaces it — see agents/design.md and agents/planner.md. Remove this file to restore the built-in."
hidden: true
---

# Plan (built-in, hidden)

This file exists only to hide OpenCode's built-in `plan` agent from the visible
agent list, because the `design` pipeline supersedes it.

The planning behaviour lives in `agents/planner.md`. This override deliberately
sets no `mode`: the built-in's `primary` mode wins the merge for this colliding
id, and `hidden` is all this file needs to contribute.
