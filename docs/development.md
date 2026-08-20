# development.md

Contributor setup, the daily workflow, and the toolchain gates. Read
[`AGENTS.md`](../AGENTS.md) for standing orders and
[`docs/AGENTS.md`](AGENTS.md) for documentation rules first.

## Environment

- macOS 13+ on Apple Silicon with the Xcode command line tools
  (`xcode-select --install`); Swift is compiled with `swiftc`, no Xcode project.
- Node `^22.19 || >=24` and pnpm (`^9 || ^11`; the repo pins the workspace via
  `pnpm-workspace.yaml`). The plugins use pnpm workspaces with a hoisted
  `nodeLinker`, mirroring the shipped profile layout.

## Daily workflow

```sh
pnpm install            # first clone; resolves the full toolchain
pnpm run build          # tsc -b per plugin → lib/
pnpm run typecheck      # strict NodeNext typecheck of plugins + scripts
pnpm run lint           # oxlint
pnpm run test           # vitest (source-plane)
pnpm run test:coverage  # per-file 100% coverage gate on plugins/*/src
pnpm run hygiene        # knip + publint + constraints + NodeNext consumer
pnpm run doc-sync       # md-links / budgets / jsdoc / doc-typecheck / agent-notes
./scripts/run-tests.sh  # Swift UpdatePolicy tests + plugin vitest
./scripts/build.sh      # assemble the .app (long; ask first, run as background job)
```

Run the full local check before opening a PR: `lint`, `typecheck`, `test`,
`test:coverage`, `hygiene`, `duplication`, `doc-sync`, and `bash -n scripts/*.sh`.
CI runs the same surface.

## Toolchain gates

| Command | Gate | Fail condition |
|---|---|---|
| `pnpm run lint` | oxlint | correctness/suspicious rule violations |
| `pnpm run typecheck` | `tsc -p tsconfig.typecheck.json` | any strict diagnostic in plugins + scripts |
| `pnpm run test` | vitest | any failing unit test |
| `pnpm run test:coverage` | vitest coverage | < 100% per file on `plugins/*/src` |
| `pnpm run hygiene:knip` | knip | unused files/dependencies/exports |
| `pnpm run hygiene:publint` | publint | package `exports`/`types` misdeclared |
| `pnpm run hygiene:constraints` | `check-workspace-constraints.ts` | package name/type/version/dependency violations |
| `pnpm run hygiene:node-next` | `verify-node-next-types.ts` | built declarations don't compile as a NodeNext consumer |
| `pnpm run duplication` | `check-duplication.ts` | 6+ normalized lines cloned across files |
| `pnpm run doc-sync` | five doc gates | dead links, over-budget docs, missing JSDoc, uncompilable `ts` fences, malformed Agent Notes |

## TODO markers

`FIXME` (must fix before merge), `TODO` (next change), `XXX` (known weak spot,
works for now). Markers carry the owning note when the reason is non-obvious.

## Adding a dependency

Add runtime deps to the plugin's `dependencies` and the toolchain to the root
`devDependencies`. The workspace constraint gate verifies every declared
dependency resolves from `node_modules` or the workspace. New `@deepseek-ai/*`
`rc.*` packages may need an entry in `pnpm-workspace.yaml` `minimumReleaseAgeExclude`.
