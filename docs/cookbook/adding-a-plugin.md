# Adding a plugin

How to add a new Cordis plugin under `plugins/`. The recipe mirrors
[dsk-poc]'s package conventions. Before starting, decide what the plugin does
(design spec in `docs/specs/`, decision note when non-trivial) — see
[`.agents/notes/README.md`](../../.agents/notes/README.md).

[dsk-poc]: https://github.com/deepseek-ai/dsk-poc

## 1. Scaffold the package

Create `plugins/<name>/` with a `package.json` (bare kebab name, `"type":
"module"`, semver `version`, `main`/`types`/`exports` pointing at `lib/`), a
`tsconfig.json` (extends `../../tsconfig.base.json`, `rootDir: "src"`, `outDir:
"lib"`, `declarationDir: "lib/types"`, `composite: true`), a
`tsconfig.typecheck.json`, and `src/index.ts`. Register the workspace in
`pnpm-workspace.yaml` (`packages: plugins/*` already covers it) and run
`pnpm install`.

## 2. Implement the plugin

`src/index.ts` exports `name`, `inject` (services required), a `Config` schema
(schemastery), the provider/`apply`, and a `Config` interface with JSDoc.
Register providers/services inside `apply(ctx, config)` only. Relative imports
use the `.ts` extension. Give every exported function-like/class member a JSDoc
block with `@param`/`@returns` (`verify-export-jsdoc` gates this).

## 3. Test at the source plane

Add `tests/<name>.test.ts` importing `src/...ts` directly. Mock the seams the
plugin consumes (`fetch`, the credentials service, the launch environment).
Cover every branch so `pnpm run test:coverage` stays at 100% per file.

## 4. Ship it through the profile

The desktop app seeds `plugins/<name>/lib` + `package.json` into the live
profile and the patch layer (`assets/desktop-profile/cordis.patch.yml`) wires
the plugin by its relative name. Update the patch layer, `scripts/build.sh`
(which copies the built plugin into the app bundle), and the plugin README.

## Verify

```sh
pnpm run typecheck && pnpm run lint
pnpm run test && pnpm run test:coverage
pnpm run hygiene && pnpm run duplication && pnpm run doc-sync
./scripts/build.sh   # long — ask first; run as a background job
```

All gates green is the definition of done; open the PR with the spec/Agent
Note in the same change.
