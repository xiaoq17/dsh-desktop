# AGENTS.md

dsh-desktop is the **native macOS desktop client** for DeepSeek Harness: a
Swift + WKWebView shell (`app/`) that boots a Cordis profile, plus the TypeScript
plugins it ships through the desktop profile (`plugins/*`). Engineering
conventions mirror the harness family repos — [deepseek-harness] and [dsk-poc] —
scaled to a small, self-contained client. Read [docs/AGENTS.md](docs/AGENTS.md)
before writing documentation and [docs/development.md](docs/development.md)
before touching the toolchain.

[deepseek-harness]: https://github.com/deepseek-ai/deepseek-harness
[dsk-poc]: https://github.com/deepseek-ai/dsk-poc

## Repository layout

```
app/            Swift sources (AppDelegate, ServerManager, UpdateManager, …) —
                built with swiftc, no Xcode project (see scripts/build.sh)
assets/         Non-code app assets: Info.plist, the desktop-profile templates
assets/desktop-profile/   Pure configuration shipped into the profile
                (package.json, cordis.yml, cordis.patch.yml, pnpm-workspace.yaml)
plugins/        Cordis plugin workspaces (pnpm). src/*.ts → lib/*.js +
                lib/types/*.d.ts; main/exports point at lib/ (gitignored)
docs/           Specs (docs/specs/, Chinese, RFC/ADR style) + documentation
                standards (docs/AGENTS.md, development.md, testing.md, cookbook/)
scripts/        Repo gates (TS, run via tsx) + infra shell scripts (build,
                hooks, CI-invoked)
.agents/        Agent workflows and Agent Notes (notes/)
.github/        GitHub workflows + PR/issue templates
```

Package-level rules live in [plugins/volcano-search/README.md](plugins/volcano-search/README.md).

## Commands

```sh
pnpm install            # pnpm workspaces; node ^22.19 || >=24
pnpm run build          # tsc -b per plugin → lib/*.js + lib/types/*.d.ts
pnpm run typecheck      # tsc -p tsconfig.typecheck.json (whole repo, strict)
pnpm run lint           # oxlint
pnpm run test           # vitest unit tests (source-plane)
pnpm run test:coverage  # CI coverage gate: per-file 100% on plugins/*/src
pnpm run hygiene        # knip + publint + workspace constraints + NodeNext consumer
pnpm run duplication    # cross-file TypeScript clone detection
pnpm run doc-sync       # all documentation gates (md-links/budgets/jsdoc/typecheck/agent-notes)

./scripts/run-tests.sh  # Swift UpdatePolicy tests + plugin vitest together
./scripts/build.sh      # assemble dist/dsh-desktop.app (long; ask first)
bash -n scripts/*.sh    # shell syntax gate (CI)
```

## Code-change gate: Agent Notes

**Any non-trivial change ships with an Agent Note in the same change** (upstream
model). A note records the decision, the alternatives given up, and the
verification required — see [.agents/notes/README.md](.agents/notes/README.md)
for the format and lifecycle (`proposed/` → `implemented/`/`rejected/`).

- **What counts as non-trivial**: a behavior change, a new seam, a non-obvious
  fix, a change to the shipped profile wiring, or a process/toolchain change.
- **What is exempt**: typo/whitespace/comment-only edits, pure refactors with
  no behavior change, and fixes fully explained by the linked spec/issue.
- **Specs stay**: design and requirement specs remain in `docs/specs/`
  (Chinese, RFC/ADR style, `S-NNNN`) — they are the *design records*; the
  Agent Note is the *decision record* for how a change was made. Reference
  specs by `S-NNNN`; Agent Notes are not numbered, they are dated + filed.
- The `scripts/hooks/pre-commit` hook enforces hygiene (LF, trailing newline,
  `git diff --cached --check`), not the Agent-Note rule — review enforces that.

## Conventions

- **Everything is a plugin.** Plugin behavior ships through the `ctx.web`/
  `ctx.credentials`/… seams; new capabilities are new plugins under `plugins/`,
  registered via the profile patch layer. Read [docs/cookbook/adding-a-plugin.md](docs/cookbook/adding-a-plugin.md) before adding one.
- **ESM everywhere.** Every TS package is `"type": "module"`; relative imports
  use the `.ts` extension and tsc rewrites them (mirrors dsk-poc).
- **Registrations are effects.** Providers/services are registered inside
  `apply(ctx, config)`; constructors do not touch the world.
- **Empty catches name their catch value** (`catch (error) { … }`); never
  `catch {}`. Empty `catch (error)` bodies are allowed only with a comment
  saying why the error is deliberately swallowed.
- **TODO markers by urgency**: `FIXME` (must fix before merge), `TODO` (next
  change), `XXX` (known weak spot, works for now) — semantics in
  [docs/development.md](docs/development.md).
- **Files end with exactly one trailing newline; LF canonical.** Pinned by
  `.gitattributes` (`* text=auto eol=lf`) and `.editorconfig`; the pre-commit
  hook and `git diff --cached --check` gate it.
- **Docs are current state, not history; one home per fact.** Write prose as
  present-tense description of what is; move decision rationale to Agent
  Notes; cross-link with relative paths. See [docs/AGENTS.md](docs/AGENTS.md).
- **Swift, shell, and app infra are local rules.** The harness family has no
  Swift conventions; follow the existing style (4-space Swift indents,
  LF; see `.editorconfig`) and [CONTRIBUTING.md](CONTRIBUTING.md).

## GitHub / collaboration

This is a GitHub project. Follow [CONTRIBUTING.md](CONTRIBUTING.md): scoped
PRs, one `kind/*` + all-material `area/*` labels, spec or Agent Note alongside
code, no generated artifacts committed. Do **not** auto-push or auto-publish
releases; do not rebuild/reinstall the running app without asking — `scripts/build.sh`
and the packaging scripts are long, ask first and run them as a background job.

## Editing these instructions

Root `AGENTS.md` holds only standing orders (one to three lines each, linking
their home). Subtree details live in `docs/` and `.agents/`. When you change a
rule, update the home and the reference together in the same change.
