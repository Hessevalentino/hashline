---
name: code-context
description: Search, read and orient in a codebase efficiently — exact symbol ranges, file API surfaces, structural queries, complete reference lists, repository orientation, and content that plain text search cannot reach (compressed logs, sqlite, archives, PDFs). Use before reading any source file, when orienting in an unfamiliar repository, when listing every use of a symbol, or when the answer may be inside a non-text file.
compatibility: "Best with rg and ctags (Universal Ctags); every tool has a documented fallback. Strongly recommended: ast-grep, fd, rga, tokei, scc."
allowed-tools: Bash(rg:*) Bash(rga:*) Bash(ctags:*) Bash(ast-grep:*) Bash(fd:*) Bash(tokei:*) Bash(scc:*) Read Grep Glob
attribution: >
  Search-strategy guidance (scoping, counting before reading, batching) adapted
  from netresearch/file-search-skill v1.8.0, MIT AND CC-BY-SA-4.0.
---

<!-- agent-code-intel:managed -->

# Code Context

Seven tools, each with something the others cannot do. This skill is about
picking the right one and driving it well.

## The one rule that matters most

**Never guess a line range. Derive it.**

Guessing a window around a match missed the target function in **3 of 5**
measured cases; one miss truncated a 72-line function at line 70, and the
conclusion drawn from it came from a docstring rather than the code.

Deriving the exact range costs **~30 bytes**. There is no reason to guess.

## What each tool uniquely gives you

| Tool | The thing only it does |
|---|---|
| `rg` | Fast exhaustive text search over what is readable as text |
| `ctags` | Exact **start and end** line of a definition, in 164 languages |
| `ast-grep` | Matches **syntax**, so no hits in comments or strings |
| `fd` | Selects files by **time, size, and executability** — not content |
| `rga` | Reads what `rg` cannot open at all: **.gz, .zip, .tar, sqlite, PDF** |
| `tokei` | "What *is* this repository" in one screen |
| `scc` | Per-file **complexity** — where a change will hurt |

If two tools can answer, take the cheaper one. If only one can, that choice
is already made.

## Task → tool

| You need | Use |
|---|---|
| Range of one known symbol | `ctags` targeted (§1) |
| What a file offers | `ctags` skeleton (§2) |
| **Every** use of a symbol | `rg` or `ast-grep` (§3) — **never a graph** |
| Match that regex gets wrong | `ast-grep` (§4) |
| Files by age, size, executability | `fd` (§5) |
| Search inside archives, logs, DBs, docs | `rga` (§6) |
| Orientation in an unknown repo | `tokei` / `scc` / repo map (§7) |
| Meaning, not identifiers ("where is auth?") | GrepAI |
| Architecture, execution flows, rename | GitNexus |

## 1. Read one symbol

**First check how big the file is.** Deriving a range on a small file is pure
overhead — the query costs a round trip to save a few hundred bytes.

```bash
wc -l <file>
```

- **Under ~100 lines** → read it whole. Measured on a Laravel codebase whose
  median PHP file is 38 lines: whole-file reads of 30-, 34- and 68-line files
  were the cheapest correct choice, and a `ctags` step would have added cost
  for nothing.
- **Over ~100 lines** → derive the range. On a 1828-line file the derived
  range cost 4 % of reading the file.

To derive:

```bash
TMPDIR=. ctags -x --_xformat='%N L%n-%{end} %K' -o - <file> | rg '^<symbol> '
# -> parse_args L166-232 function
sed -n '166,232p' <file>
```

**`TMPDIR=.` is not optional under a sandboxed agent.** Verified in Codex:
`ctags` opens a temp file under the system `$TMPDIR`, the sandbox denies it
(`cannot open temporary file: … Operation not permitted`), **and the pipeline
still exits 0** — so the failure is silent and you get an empty result that
looks like "no such symbol". `--sort=no` does not help. If the workspace is
also read-only, skip `ctags` entirely and use `ast-grep` (§1, below).

Exact on 10/10 measured symbols, identical to a real parser — **when the
parser emits ends at all.** Check that first; see below.

### When `%{end}` comes back empty

Not every `ctags` parser emits end lines. Check once per language:

```bash
ctags -x --_xformat='%N|%n|%{end}|%K' -o - <file> | head -3
```

Use `|` as the separator, not `\t`: `ctags` does **not** interpret escape
sequences in `--_xformat` and would emit a literal backslash-t.

**If ends are present** (Python, and others) — use them, they are exact:
measured 10/10 against a real parser.

**If ends are empty, and the language is one `ast-grep` supports — use
`ast-grep`, not a hand-rolled fallback.** Measured on two real projects:

| Language | `ctags` ends | hand-rolled fallback | `ast-grep` kind rule |
|---|---|---|---|
| **Python** | **exact, 10/10** | n/a | not needed |
| TypeScript | 0 of 170 | 80.6 % | **99.4 %** |
| PHP | 0 of 145 | 72.4 % | **99.3 %** |
| JavaScript | 0 of 236 | 76.3 % | **97.4 %** |
| Shell | 2 of 70 | 96.4 % | **100 %** |

**Python is the exception, not the rule.** Measured on five languages across
four real projects, `ctags` emits end lines for Python and essentially nothing
else. Assume `ast-grep` unless you are in Python — but still check once, as
above, because `ctags` is cheaper when it works.

Every `ast-grep` miss in that table was an artefact of the verification
script, confirmed by hand — its ranges were right. The hand-rolled fallback
fails systematically: the last member of a class swallows the class's
closing brace.

**JavaScript needs a wider rule.** The kinds above find 152 definitions where
`ctags` finds 236, because JS assigns functions to variables. Add
`function_expression` and `arrow_function` when you need completeness — that
found 511 at 93.2 % correct, but it also matches every inline callback, so
keep it for targeted lookups rather than for listing a file.

```yaml
# /tmp/defs.yml
id: defs
language: typescript          # or the language you need
rule:
  any:
    - kind: method_definition
    - kind: function_declaration
    - kind: class_declaration
```

```bash
ast-grep scan -r /tmp/defs.yml --json=compact <file>
# ranges are 0-based: add 1 to start.line and end.line
```

**Only if neither works** — a language `ctags` truncates and `ast-grep` does
not parse — derive the end from the next definition's start, and expect
roughly one line of overshoot at the end of each container:

```bash
ctags -x --_xformat='%N|%n|%{end}|%K' -o - <file> | sort -t'|' -k2 -n
```

Measured on a 33 kB shell script: `ctags` gave ends for 2 of 70
definitions; the fallback produced usable ranges for all 68 functions.

## 2. See what a file offers

```bash
ctags -x --_xformat='%N L%n-%{end} %K' -o - <file>
```

Every definition with its range: 1.6 kB instead of a 70 kB file, and it
hands you the ranges §1 needs, so the follow-up read costs no extra query.

Add `%S` for signatures when names alone are ambiguous — it roughly triples
the output, so not by default.

## 3. List every use of a symbol

**Knowledge graphs are incomplete for this.** Measured here:
`agent_skills.install_targets` has 18 call sites; `gitnexus_impact` and
`graft callers` both reported **zero**, because neither resolves
cross-module `module.function()` calls. There are 83 such sites in
production code.

```bash
rg -n '\bmodule\.function\(' -tpy .                # fast; also hits comments/strings
ast-grep run -p 'module.function($$$A)' -l py .    # syntax-aware; no false hits
```

Start with `rg`. Switch to `ast-grep` when comments or strings pollute the
result. Graphs remain authoritative for **architecture, execution flows and
renames** — not for completeness of a reference list.

## 4. Structural search

`ast-grep` matches syntax, not text — use it where a regex is simply wrong:

```bash
ast-grep run -p 'open($$$A)' -l py .            # verified: 32 hits here
ast-grep run -p 'subprocess.run($$$A)' -l py .  # verified: 30 hits
ast-grep run -p '<pattern>' -l py --json=compact .   # ranges, for scripting
```

`$X` captures one node, `$$$X` captures a list. The binary is `ast-grep`;
`sg` still works but warns it is deprecated.

**A pattern must be a complete syntactic unit.** `except $E: pass` matches
nothing, because in Python an `except` clause cannot stand alone — write the
whole statement:

```bash
ast-grep run -p 'try: $$$B
except $E:
    pass' -l py .          # swallowed exceptions
```

If a pattern returns zero, suspect the pattern before concluding the code is
clean: check it against a file you know contains the construct.

**Do not use `ast-grep` to look up a range in a language where `ctags`
emits `%{end}`** — its output carries the full matched text and measured
**113 %** of the cost of `ctags` on Python. Where `ctags` gives no end
(TypeScript and friends), `ast-grep` is the correct tool for ranges — see §1.

## 5. Select files by properties, not content

`fd` and `rg --files` return the same list for a plain "all .py files"
query. Reach for `fd` when the *property* is the point:

```bash
fd -e py --changed-within 2d .        # what moved recently
fd -t f -S +100k .                    # large files
fd -t x .                             # executables — rg cannot express this
fd -e py --changed-within 2d . -X rg -c 'def '   # filtered set, ONE rg walk
```

`-X` passes the whole result set to one command; `-x` runs it per file.
Prefer `-X`.

## 6. Search what `rg` cannot open

`rg` skips binary files. `rga` transparently extracts first, so the search
reaches inside. This matters more in other repositories than in a
pure-source one — logs, fixtures and vendor docs live in these formats.

**Works with no extra install:**

```bash
rga 'disk full' logs/       # inside .gz .tgz .bz2 .xz .zst — rotated logs
rga 'endpoint' .            # inside .db/.sqlite — verified: reads table rows
rga 'ClassName' libs/       # inside .zip .jar .tar
```

Measured: a match inside `app.log.gz` was found by `rga` and missed by `rg`.
A value stored in a `sqlite` table was returned as `cfg: k='endpoint',
v='...'` — content `rg` cannot reach at all.

**Needs an external binary** (check before promising a result):

| Formats | Requires |
|---|---|
| `.pdf` | `pdftotext` (poppler) |
| `.docx .odt .epub .ipynb .html` | `pandoc` |
| `.mkv .mp4 .mp3 …` metadata, subtitles | `ffmpeg` |

Without them `rga` fails loudly on that file rather than silently skipping.
Note `.ipynb` is JSON, so plain `rg` already searches it — use `rga` there
only when you want prose instead of escaped JSON.

`rga` is slower than `rg` and caches extractions. Use `rg` for source,
`rga` when the answer may be inside something `rg` reports as binary.

## 7. Orient in an unfamiliar repository

Three different questions. Ask the one you have; all three cost 4.4 kB and
that is usually waste.

| Question | Command | Cost |
|---|---|---|
| What is this repo? | `tokei` | 2.0 kB |
| Which file will hurt? | `scc --by-file --sort complexity -i <ext> \| head -10` | 1.3 kB |
| What is central? | repo map below | 1.1 kB |

```bash
# definitions: use ctags, NOT a regex — it is language-neutral
ctags -x --_xformat='%N|%K' -o - $(fd -e <ext> -E vendor .) \
  | awk -F'|' '$2=="function"||$2=="method"||$2=="class"{print $1}' | sort -u

# call sites: names followed by '(' , counted
rg -o --no-filename -r '$1' '\b([A-Za-z_]\w*)\s*\(' -t<lang> . \
  | sort | uniq -c | sort -rn | head -400
# keep the names that appear in both lists, take the top ~12
```

**Do not hand-write the definition regex per language.** A `^\s*(?:def|class)`
pattern found 87 of 388 definitions on a PHP project — 22 % — because PHP
uses `function`, not `def`. `ctags` gets all 388 and works the same way in
164 languages.

Restrict the call-site pattern to names followed by `(`. Counting bare
identifiers ranked `path` first at 638 hits — a variable name, not a hub.

`scc` also prints COCOMO cost and schedule estimates. Ignore them; they say
nothing about the code you are about to change. Use `scc` for the
Complexity column and `--by-file`, and `tokei` when you only want the
language breakdown.

## Driving `rg` well

1. **Scope it.** Types (`-t py`), directories, and `-g '!vendor/'`. An
   unscoped search over a monorepo is the most common waste there is.
2. **Count before reading.** `rg -c 'pat' -tpy .` tells you whether the
   result is worth looking at.
3. **One walk, not N.** Union patterns with `-e`:
   `rg -e P1 -e P2 -e P3` is one traversal instead of three. Multiple types
   and paths also take one call: `rg -t py -t md 'pat' src/ docs/`.
   Independent queries belong in **parallel tool calls**, never an `&&`
   chain — that is still sequential.
4. **Extract, don't eyeball.** `-o -r '$1'` returns just the capture group;
   `--json` when a script consumes it.
5. **Cross lines with `-U`.** Multi-line patterns need it:
   `rg -U 'except.*:\s*\n\s*pass'`.
6. **Context flags** `-A`/`-B`/`-C` are for *reading a match*, never for
   establishing a definition's extent. That is §1's job.

## Hard rules

1. **`rg` needs an explicit path when called from a script or hook.**
   With no path and a non-tty stdin, `rg` searches **stdin** and hangs.
   Write `rg 'pat' -tpy .` — the trailing `.` is not optional.
   Conversely, when you pipe *into* `rg`, pass **no** path.
2. **Evidence gate.** A range tells you where to read, not what the code
   does. Read the range before concluding — never quote a docstring as
   behaviour.
3. **Do not truncate a range you derived.** Piping a correct range through
   `head` reintroduces exactly the problem deriving it solved. Measured in a
   behavioural run: 5 of 5 ranges were derived correctly, then 2 of them were
   truncated with `head`, and one answer then rested on a docstring whose
   implementation lay in the unread part.
   If a range is genuinely too large to read whole, **filter inside it**
   rather than cutting it short:

   ```bash
   sed -n '1613,1722p' <file> | rg -n 'qdrant|raise|return'
   ```

   Filtering keeps the whole range in scope and tells you what you skipped;
   `head` silently hides the end.
4. **Check the tool exists** before relying on it; none of them is a hard
   requirement, every one has a fallback:

   | Missing | Do this instead |
   |---|---|
   | `ctags`, Python | stdlib `ast` (§1) — equally exact |
   | `ctags`, other languages | `ast-grep` kind rule (§1) — equally exact |
   | `ctags` **and** `ast-grep`, non-Python | `rg` for starts, derive ends — expect 72–81 % correct, say so when you rely on it |
   | `rg` | `grep -rn`; you lose `-t` types, `.gitignore` awareness and speed |
   | `rga`, `fd`, `tokei`, `scc` | the capability is simply unavailable — say so rather than guessing |

   Install the whole set with `agent-code-intel --install-deps`.
