# Agent Notes

English | [中文](README.zh.md)

An **Agent Note** records a decision or proposal that affects this codebase —
the *why* and *what we gave up*, the parts code and docs can't carry. This
file defines where notes live, when to write one, and the in-file format. The
convention mirrors [dsk-poc], scaled to this repo.

[dsk-poc]: https://github.com/deepseek-ai/dsk-poc

## Layout and naming

Every Agent Note's **path** encodes its two axes:
`{lifecycle}/{class}/yyyy-mm-dd-topic-title.md`.

- **Lifecycle** (top-level folder) is the status, and a note moves between
  folders as the status changes:
  - **`proposed/`** — reviewed before implementation; not yet built.
  - **`implemented/`** — the decision shipped. Keep the file current with what
    actually shipped: when code later moves, renames, or changes a key/default,
    update the note in the same change (facts only, not the decision).
  - **`rejected/`** — considered and declined. Keep it only while its rationale
    prevents a tempting, meaningful mistake; otherwise delete it (and its
    Chinese counterpart) together.
- **Class** (nested folder) is the *kind* of decision:
  `feature`, `bug-fix`, `simplification`, `architecture` (shipped source
  structure), `process` (tooling/policy/workflow around the code), `testing`.

The filename date is when the topic was **first proposed**. Cross-references
between notes use relative markdown links, never numbers or prose.

## When to write one

**Every non-trivial change adds or updates at least one Agent Note in the same
change.** Non-trivial means the change alters behavior, architecture, a
contract, process or tooling, testing strategy, an on-disk/wire/config format,
or another decision a maintainer may revisit. Substantial future work starts in
`proposed/`; a decision already made starts in `implemented/`.

Updating the note that already owns the decision satisfies the rule — never
duplicate. Purely mechanical or local edits with no behavior change are exempt.
Never edit a note into a *different decision*: supersede it with a new note and
cross-link both.

## The file format

Enforced by `pnpm run doc:agent-notes` (`scripts/verify-agent-note-format.ts`,
part of `doc-sync`). The first three lines are exactly:

```markdown
# Agent Note: <title>

Status: <status>
```

followed by a blank line. `Status:` is one of `proposed` / `implemented` /
`rejected — <why, one line>`, and must agree with the lifecycle folder. No
dates or parentheticals on the status line — the filename holds the date.

The body opens with `## Problem` (the motivation, written to stand without the
solution). What follows depends on the lifecycle:

- **`proposed/`**: `## Proposal` (may speak in the future tense — plans and
  open questions belong here), `## Alternatives considered`, `## Acceptance
  criteria`, `## Risks`.
- **`implemented/`**: `## Decision` (shipped reality, present tense, kept
  current), `## Alternatives considered`, `## Consequences` (what the trade-off
  cost **and** bought). Proposal-era headings are rejected here: `## Proposal`,
  `## Plan`, `## Migration plan`, `## Acceptance criteria` may not appear.
- **`rejected/`**: the proposal frozen; the verdict lives on the `Status:` line.

**`## Alternatives considered` is mandatory** — each genuine alternative and
why it lost, one bold-led paragraph per alternative. A decision recorded
without what it beat invites re-litigation.

## Chinese counterparts

Each note has a `.zh.md` mirror with the same section structure; the
machine-checked header tokens (`# Agent Note: ` and the `Status:` line) stay in
English verbatim. Update both language files together.

## Editing these instructions

The Agent Notes convention lives here; root `AGENTS.md` links it as the
code-change gate. Change rules here and update references in the same change.
