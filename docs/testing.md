# testing.md

The testing policy for dsh-desktop. Every behavior ships with tests that run
in CI; the coverage gate is per-file 100% on `plugins/*/src`.

## Layers

- **Plugin unit tests** (vitest, source-plane). Tests import `src/*.ts`
  directly, never the built `lib/` (see [vitest.config.ts](../vitest.config.ts)).
  Pure logic — the Ark response parser (`parser.ts`) — is tested through its
  exports; the provider (`index.ts`) is tested with a mocked `fetch`,
  credentials, and launch environment so every branch is covered.
- **Swift tests** (XCTest-style assertions in `scripts/run-tests.sh` via
  `swiftc -parse-as-library`). The `UpdatePolicy` model is unit-tested; UI and
  network paths are covered by smoke checks.
- **End-to-end verification** is a local, documented procedure (running the
  plugin against the real Ark API from a sandboxed profile), not a CI test —
  it needs a real key. See the spec `S-0002` verification section.

## The coverage gate

`pnpm run test:coverage` enforces 100% lines/functions/statements/branches per
file under `plugins/*/src`. Reaching it is part of "done": a new provider must
mock its seam and exercise every key-resolution path, retry branch, and error
mapping. A branch that is genuinely unreachable in unit tests is documented in
the test with a comment explaining why, and either covered via an injected
fault or excluded through an `/* v8 ignore */` comment with the reason.

## When a test is required

- A behavior change in a plugin: unit tests for the changed surface.
- A new provider/parser branch: tests for the new path and its error mapping.
- A `UpdatePolicy` change: Swift tests for the new policy rule.
- Pure refactors with no behavior change: existing tests must stay green.

## Running

```sh
pnpm run test           # plugin unit tests
pnpm run test:coverage  # plugin coverage gate
./scripts/run-tests.sh  # Swift UpdatePolicy tests + plugin vitest together
```
