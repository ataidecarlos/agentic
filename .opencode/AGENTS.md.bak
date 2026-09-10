# Project Instructions for AI Agents

This file provides context and instructions for all AI agents working on this project.

## Persistent Memory

This project maintains persistent lessons learned from previous sessions. **At the start of each session, read the memory index and relevant memory files to benefit from past experience.**

### Memory Index

Read `~/.opencode/projects/agentic/memory/MEMORY.md` to see all available lessons.

### Memory Location

Individual memory files are stored at:
```
~/.opencode/projects/agentic/memory/
```

### How to Use Memory

1. **At session start**: Read `MEMORY.md` to understand what lessons have been learned
2. **When relevant**: Read specific memory files that relate to your current task
3. **Before making decisions**: Check if a lesson applies to avoid repeating past mistakes
4. **When updating memory**: If you learn something new that relates to an existing lesson, update that file rather than creating a duplicate

### Memory Format

Each memory file has this structure:

```yaml
---
name: lesson-name
description: Brief description of the lesson
metadata:
  type: feedback
---

# Lesson Title

## Content
```

### Current Lessons

As of this session, the following lessons have been learned:

1. **Deployment Infrastructure** — Always update deployment scripts when adding new agents or skills
2. **Avoid Hardcoding** — Don't hardcode provider-specific values in portable agents
3. **Clarify Requirements** — Ask clarifying questions before implementing complex features
4. **Test Integration** — Test agent orchestration integration points early and iterate
5. **Document Memory** — Document memory system conventions for skills clearly

## Project Structure

```
agentic/
├── prompts/          # Canonical portable prompts
├── agents/           # Opencode agents (frontmatter + prompt body)
├── skills/           # Opencode skills
├── deploy.ps1        # PowerShell deployment script
├── deploy.sh         # Bash deployment script
└── AGENTS.md         # This file
```

## Agent Orchestration

The Plan agent automatically invokes the Reviewer agent after completing a plan. This ensures every plan is reviewed for flaws before implementation.

## Key Principles

1. **Single Responsibility** — Each step in a plan should perform a single, clearly defined task
2. **Grounded Discovery** — Use reads, globs, and greps to discover facts, never guess
3. **Concrete Edits** — Every step must specify exact targets and behaviors
4. **No Assumptions** — Mark unverified facts as `unverified — confirm first`

## When in Doubt

If you're unsure about something:
1. Check the memory files for relevant lessons
2. Read the README.md for project documentation
3. Ask the user for clarification rather than guessing
