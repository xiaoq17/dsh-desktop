# AGENTS.md — The documentation standard

This file defines how dsh-desktop's documentation is structured and written,
and the `verify-doc-budgets` / `verify-md-links` ceilings that gate it. The
tier taxonomy and writing rules mirror [deepseek-harness]'s documentation
standard, scaled to a small repo.

[deepseek-harness]: https://github.com/deepseek-ai/deepseek-harness

## The tier taxonomy: one home per fact

Each fact has one home: the tier whose job it is; elsewhere, link there.

| Tier | Job | Does NOT belong there |
|---|---|---|
| Root [`AGENTS.md`](../AGENTS.md) | Standing orders: rules an agent needs in context in every session, one to three lines each, linking its home | Stories, worked examples, anything restated from a linked home |
| [`docs/specs/`](specs/README.md) | Design and requirement records: `S-NNNN`, Chinese, RFC/ADR style | Decision rationale for *how* a change was made (→ Agent Notes) |
| [Agent Notes](../.agents/notes/README.md) | Active decision records: the why, what was given up, required verification; `implemented/` notes describe shipped reality in present tense | Migration plans, acceptance-task checklists, spec-speak ("should…") |
| [`cookbook/adding-a-plugin.md`](cookbook/adding-a-plugin.md) | Step-by-step how-tos with numbered verify steps | Design rationale (→ the Agent Note each guide links) |
| [`development.md`](development.md) | Contributor setup, daily workflow, toolchain gates | Per-seam semantics (→ specs / plugin README) |
| [`testing.md`](testing.md) | Testing policy: what each layer tests, coverage gate | Test-code narration |
| Plugin README | The per-plugin contract: config, semantics, limitations | JSDoc restatement, other plugins' concerns |

A document's subject and tree position fix its scope: describe its own subject
at appropriate detail, direct children only by purpose and high-level
behavior, and link to the owning descendant for lower-level detail. A
reference may be exhaustive only about its own subject.

## Writing rules

- **Current state, not history.** Write prose as present-tense description of
  what is. Decision rationale, alternatives given up, and required verification
  live in Agent Notes; delete the derivation path, keep the durable contract.
- **One home per fact.** State a fact in its home tier; everywhere else link
  there. If a paragraph would repeat a rule, replace the repetition with a link.
- **One physical line per paragraph.** One paragraph per physical line, so
  diffs stay byte-level and `verify-doc-budgets` counts stable.
- **Cross-reference with machine-checkable relative links, never free prose.**
  Link repository references with relative Markdown paths, never bare
  filenames. `verify-md-links` rejects missing targets and dead `#fragment`
  anchors.
- **One physical line per paragraph**; keep word budgets under the ceilings in
  `scripts/doc-budgets.manifest.json` (`verify-doc-budgets` gates them).
- **Chinese in specs, English in convention docs.** Specs (`docs/specs/`) are
  written in Chinese with technical identifiers/IDs in their original form;
  convention and how-to docs are English. Agent Notes are bilingual (English +
  Chinese, see [.agents/notes/README.md](../.agents/notes/README.md)).

## The slop checklist

These are never acceptable:

- Restating another tier's rule beside a sibling method or section instead of
  once at the owning home.
- Paragraph walls: one paragraph carrying several rules and parenthetical
  asides. Split it or demote the detail to its home.
- Emphasis inflation: bold, CAPS, or "critically" everywhere. Reserve emphasis
  for the clause that changes behavior.
- Spec-speak in `implemented/` Agent Notes: "should", migration plans,
  acceptance checklists. An implemented note describes what is.
- Headings that don't match their slug (GitHub-style slugs are what
  `verify-md-links` checks).

## Editing these instructions

The documentation standard lives here; root `AGENTS.md` links it. Change
rules in the owning tier and update references in the same change, then run
`pnpm run doc-sync` to confirm every gate.
