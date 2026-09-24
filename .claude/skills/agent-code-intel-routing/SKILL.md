---
name: agent-code-intel-routing
description: Automatically choose between GrepAI, GitNexus, and ripgrep for codebase discovery, architecture exploration, debugging, reviews, refactoring, and implementation tasks.
---

<!-- agent-code-intel:managed -->

# Code Intelligence Routing

Use this skill as the source of truth for choosing a code-intelligence tool.
Choose the smallest tool that answers the current question; combine tools only
when the task crosses their boundaries. Preserve repository safety rules such
as required GitNexus impact analysis, graph-aware renames, and change detection.

## Code-context rules

Before reading a source file, use the repo-scoped `code-context` skill.

These rules apply regardless of the rest of this routing:

- Exhaustive reference lists for cross-module calls belong to `rg`/`ast-grep`,
  not the knowledge graphs.
- Derive the exact definition range; never guess it or truncate it.

## Tool roles

### GrepAI

Use semantic search for intent and behavior:

- locating business logic without knowing its identifiers;
- discovering where a feature or responsibility lives;
- exploring domain concepts and likely change locations.

### GitNexus

Use the repository graph for structure and relationships:

- dependency and module relationships;
- architecture and execution flows;
- callers, callees, impact analysis, and refactor blast radius;
- graph-aware symbol renames and affected-flow verification.

Run impact analysis before changing shared or unfamiliar symbols and before
large refactors.

### ripgrep

Use `rg` for exact text and final verification:

- identifiers, config keys, environment variables, migrations, and logs;
- scripts and documentation;
- confirming that references or stale text remain after a change.

Start with ripgrep when the target string or file is already known.

## Workflows

### Architecture and behavior

1. Use GrepAI to discover the relevant domain when its location is unknown.
2. Use GitNexus to inspect relationships, dependencies, and execution flows.
3. Read the relevant implementation before drawing conclusions.

### Debugging

1. Use GrepAI to locate the behavior behind the symptom.
2. Use GitNexus to trace the dependency or call chain.
3. Read the relevant code, identify the root cause, and verify it with exact
   searches or tests.

### Feature implementation

1. Use GrepAI to locate the implementation area when it is not already known.
2. Use GitNexus to understand surrounding architecture and impact.
3. Read affected files, implement the smallest change, then verify with tests
   and ripgrep.

### Refactoring

1. Use GitNexus to determine blast radius and inspect references.
2. Read every affected implementation; use graph-aware rename support for
   symbol renames.
3. Verify remaining references with ripgrep and run relevant tests.

## Evidence gate

Search and graph results identify where to read; they are not implementation
evidence by themselves. Read the relevant source before editing or concluding.

## Fallbacks

- Without GrepAI, use GitNexus for discovery and ripgrep for exact search.
- Without GitNexus, use GrepAI for discovery, direct source reads for
  relationships, and ripgrep for verification.
- When both indexes are unavailable, use ripgrep and direct file reads.

Treat an unavailable tool as a fallback condition. Retry it only when the task
is to repair that tool.
