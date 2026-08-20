# volcano-search

Cordis plugin providing a local `ctx.web` search provider for the desktop
profile. It calls the Volcano Ark (火山方舟) Responses API
(`POST {baseURL}/responses`) declaring the `web_search` tool, letting the model
decide the query, and returns the synthesized answer with cited `url_citation`
sources. Design: [spec S-0002](../../docs/specs/0002-web-search-via-volcano-api.md).

## Registration

The plugin name is `web-search-volcano` and it injects the `web` service. It
registers the provider id **`volcano-ark`** through
`ctx.web.registerSearchProvider`. The desktop profile wires it in
`assets/desktop-profile/cordis.patch.yml` and sets the web seam's
`searchProvider` to `volcano-ark` (see [spec S-0002 §3.2](../../docs/specs/0002-web-search-via-volcano-api.md)).

## Config

| Field | Default | Meaning |
|---|---|---|
| `apiKey` | — | Literal Ark API key (avoid in config files; prefer `apiKeyEnv`). |
| `apiKeyEnv` | `VOLC_2_API_KEY` | Credential reference resolved per search. |
| `baseURL` | `https://ark.cn-beijing.volces.com/api/v3` | Ark endpoint; `/responses` is appended. |
| `model` | `doubao-seed-2-1-turbo-260628` | Tool-calling model id. |
| `limit` | `10` | Per-search result limit (1–50). |
| `maxKeyword` | `3` | Max keywords the model may search per round (1–50). |
| `maxToolCalls` | `3` | Max tool calls per request (1–10). |
| `systemPrompt` | built-in | System prompt steering search behavior. |

Environment fallbacks: `ARK_BASE_URL`, `ARK_MODEL`, and (for the key)
`ARK_API_KEY`.

## Key resolution

First match wins (spec S-0002 §3.3.2): literal `apiKey` → env `ARK_API_KEY` →
credentials service under `apiKeyEnv` (process env then the managed
`.credentials.yaml`) → `$DSH_HOME/config/volcano.json` `arkApiKey` →
`WEB_PROVIDER_CREDENTIAL_MISSING`.

## Errors

Non-2xx responses map to stable `WEB_PROVIDER_*` codes (auth, not-open,
model-unsupported, rate-limit, network); `ToolNotOpen` maps to
`WEB_PROVIDER_NOT_OPEN` regardless of HTTP status. Transient failures (fetch
throw, HTTP 5xx) retry twice with 1s/2s backoff. Aborts surface as
`WEB_ABORTED`. See [spec S-0002 §3.4–3.5](../../docs/specs/0002-web-search-via-volcano-api.md).

## Development

```sh
pnpm -r --filter './plugins/*' build    # tsc → lib/ + lib/types
pnpm -r --filter './plugins/*' test     # vitest (source-plane)
pnpm run test:coverage                  # per-file 100% on src
```

The pure Ark-response parser lives in `src/parser.ts` (no dsh imports, unit
tested in isolation); the provider in `src/index.ts` (tested with a mocked
fetch/credentials/launch environment).
