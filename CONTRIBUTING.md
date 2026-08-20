# Contributing to dsh-desktop

Thanks for your interest! This is a small, native macOS desktop client for
DeepSeek Harness (Swift shell + Cordis plugins). Keep contributions focused and
low-friction. The engineering conventions mirror the harness family repos —
read [AGENTS.md](AGENTS.md) and [docs/AGENTS.md](docs/AGENTS.md) first.

## The change gate: Agent Notes

**Any non-trivial change ships with an Agent Note in the same change.** A note
records the decision, the alternatives given up, and the verification required —
see [.agents/notes/README.md](.agents/notes/README.md) for the format and
lifecycle (`proposed/` → `implemented/`/`rejected/`).

- Non-trivial = behavior change, new seam, contract/format/process change, or a
  change a maintainer may revisit. Purely mechanical or local edits are exempt.
- Design and requirement specs live in `docs/specs/` (Chinese, RFC/ADR style,
  `S-NNNN`) — update the owning spec when the change affects a designed area.
- The pre-commit hook enforces byte-level hygiene (LF, trailing newline,
  whitespace), not the note rule — review enforces that.

## Getting started

1. **Fork** the repo and clone your fork.
2. **Check the environment**: macOS 13+ (Apple Silicon), Xcode command line
   tools (`xcode-select --install`), Node `^22.19 || >=24`, pnpm.
3. **Install and verify**:
   ```bash
   pnpm install
   ./scripts/install-hooks.sh     # install the hygiene pre-commit hook
   pnpm run lint && pnpm run typecheck && pnpm run test
   ```

## What to work on

- Clear, scoped bug fixes and small features are always welcome.
- Larger changes (a rewrite of the update pipeline, a new plugin, a new
  provider) should be discussed in an issue first so we agree on direction —
  and start with a `proposed/` Agent Note or spec.

## Before opening a PR

- Keep the diff focused on one concern; split unrelated changes into separate
  PRs.
- Run the full local gate surface — CI runs the same:
  ```bash
  pnpm run lint
  pnpm run typecheck
  pnpm run test
  pnpm run test:coverage        # per-file 100% on plugins/*/src
  pnpm run hygiene
  pnpm run duplication
  pnpm run doc-sync
  bash -n scripts/*.sh          # shell syntax
  ./scripts/run-tests.sh        # Swift UpdatePolicy tests + plugin vitest
  ```
- Update **README.md** and **CHANGELOG.md** if the change affects users.
- Follow the existing style: 4-space indents in Swift, 2-space in shell, LF
  line endings, one trailing newline (see `.editorconfig` / `.gitattributes`).

## Commit messages

Write clear, imperative commit messages:

```
Add X to support Y

Explain why and what, in a few sentences if non-trivial.
```

Reference the spec by `S-NNNN` and the Agent Note by its topic.

## Labels

One `kind/*` label per PR (e.g. `kind/feature`, `kind/bugfix`, `kind/docs`,
`kind/chore`) and an `area/*` label for every material surface (`area/plugins`,
`area/swift`, `area/build`, `area/docs`, `area/ci`, …).

## PR checklist

- [ ] `bash -n` passes on all shell scripts I touched
- [ ] Swift sources compile for `arm64-apple-macos13.0`
- [ ] All pnpm gates green (lint / typecheck / test / coverage / hygiene /
      duplication / doc-sync)
- [ ] **Agent Note added/updated** (same PR) for any non-trivial change
- [ ] Spec (`docs/specs/`, Chinese) updated where a designed area is affected
- [ ] README / CHANGELOG updated where relevant
- [ ] No generated artifacts (`build/`, `dist/`, `lib/`, `*.dmg`) committed

## Releases

Maintainers cut releases with `./scripts/publish-update.sh --release`, which
builds, checksums and uploads the DMG + update manifest to GitHub Releases.
Regular contributors don't need to worry about this.

## Adding or changing a spec

Specs follow the RFC/ADR convention in `docs/specs/` — see
[`docs/specs/README.md`](docs/specs/README.md). **Spec documents are written in
Chinese** (technical identifiers, paths, commands and requirement IDs stay in
their original form):

- New spec: copy `docs/specs/_template.md` → `docs/specs/NNNN-<slug>.md`
  (next free `NNNN`), fill the metadata table, register it in the index.
- Changing an existing spec: keep its `S-NNNN`, bump **Document version**,
  update **Date**. Never rename/delete/renumber a merged spec — supersede it
  instead.
- Reference other specs by ID (`S-XXXX`), never by prose.
