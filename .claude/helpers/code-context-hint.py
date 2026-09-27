#!/usr/bin/env python3
"""SessionStart hint for the code-context toolchain.

Carries the single highest-value rule inline, so it works even when the
skill is never invoked, and points at the skill for everything else.
"""
import json

MSG = (
    "Code context tooling here: rg, ctags, ast-grep, fd, rga, tokei, scc.\n"
    "Reading a symbol: check `wc -l` first. Under ~100 lines read the file whole. "
    "Over that, DERIVE the exact range - never guess a line window:\n"
    "  TMPDIR=. ctags -x --_xformat='%N L%n-%{end} %K' -o - <file> | rg '^<symbol> '\n"
    "(TMPDIR=. matters: under a sandboxed agent ctags fails on its temp file and "
    "the pipeline STILL exits 0, so the failure is silent.)\n"
    "If the end column is empty (TypeScript, PHP and others - verified), ctags "
    "cannot give ranges in that language: use `ast-grep scan -r <rule.yml> "
    "--json=compact` with a `kind:` rule instead. Do not hand-roll a fallback.\n"
    "Read exactly that range; do not truncate it with head.\n"
    "Exhaustive reference lists: rg or ast-grep, never the knowledge graphs - "
    "neither GitNexus nor Graft resolves cross-module module.function() calls.\n"
    "Everything else, incl. rga for compressed logs/sqlite: Skill code-context."
)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": MSG,
    }
}))
