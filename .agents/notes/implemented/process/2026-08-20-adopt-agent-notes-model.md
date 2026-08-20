# Agent Note: Adopt the Agent Notes model and dsk-poc toolchain
Status: implemented

## Problem

The repo ran a self-authored "spec-first" gate: every behavioral code change
had to update a Chinese spec first, enforced by a pre-commit hook that blocked
commits touching `app/`, `assets/`, `scripts/`, or `.github/` without a
`docs/specs/` change. The upstream harness family (deepseek-harness and its POC
branch dsk-poc) uses a different model — Agent Notes as decision records plus a
tiered documentation standard and a full toolchain gate stack — and the
repo's own spec-first hook was incompatible with that family workflow and
diverged from it. The conventions were never actually copied into this repo.

## Decision

Adopt the upstream model, per the user's explicit choices: (1) switch the code
gate from spec-first to **Agent Notes** (non-trivial changes ship a note in the
same change); (2) follow dsk-poc's language split — English convention docs,
Chinese specs, bilingual Agent Notes; (3) bring in the **full dsk-poc toolchain
gates** (oxlint, TS7 strict typecheck, vitest 4 source-plane tests with per-file
100% coverage, knip/publint/workspace-constraints/NodeNext-consumer, duplication
detection, and the five doc gates), copied from dsk-poc and adapted to the
`plugins/` layout.

`docs/specs/` stays as Chinese design records (RFC/ADR, `S-NNNN`, single-number
namespace) but is no longer the hard gate; the pre-commit hook becomes a hygiene
gate (LF, trailing newline, `git diff --cached --check`). Spec S-0003 records
the requirements and acceptance; this note records how the change was made.

## Alternatives considered

- **Keep spec-first, add light Agent Notes.** The user explicitly chose the
  upstream Agent Notes model over keeping spec-first as the gate.
- **Full bilingual docs (EN + zh pairs) everywhere.** The user chose dsk-poc's
  split (English convention docs, Chinese specs, bilingual notes) to limit
  maintenance cost.
- **Docs + light gates only.** The user chose the full dsk-poc gate stack,
  including per-file 100% coverage — which requires new provider unit tests.

## Consequences

The repo now matches the harness family conventions and gets machine-checkable
gates for lint, types, coverage, package hygiene, duplication, and docs. Cost:
the toolchain moved to TypeScript 7 (native preview) and vitest 4; the coverage
gate demanded unit tests for the previously integration-only provider
(`index.ts`); the spec-first pre-commit blocker was removed, so the Agent-Note
rule is enforced by review rather than by hook. Specs keep their value as
design records; Agent Notes carry the "why and what was given up" for each
non-trivial change.
