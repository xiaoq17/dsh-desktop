# Agent Note: Isolate the web_search credential ref from the model key
Status: implemented

## Problem

The web-search-volcano provider resolved its key from `VOLC_2_API_KEY` by
default — the same credential ref as the `volc-2` model provider. Sharing the
ref couples search to the model's key: rotating or removing the model key
silently breaks search, and search traffic cannot be billed or revoked
independently.

## Change

The plugin's default `apiKeyEnv` is now `WEB_SEARCH_ARK_API_KEY`, a search-only
credential ref. The desktop profile patch sets it explicitly. The resolution
chain is unchanged (literal `apiKey` → `ARK_API_KEY` → credentials service
under `apiKeyEnv` → `$DSH_HOME/config/volcano.json`).

## Alternatives given up

- Keep reusing `VOLC_2_API_KEY` (shared ref). Rejected: search and model keys
  stay coupled; a model-key rotation disables search.
- A plugin-local literal `apiKey`. Rejected: puts the secret in the profile
  config, violating S-0002-NFR-1 (no secrets in config/logs).

## Verification

- `pnpm run test` / `test:coverage`: 45 unit tests green, per-file 100% on
  `plugins/volcano-search/src`.
- E2E against the real `~/.dsh` profile + Ark API with `WEB_SEARCH_ARK_API_KEY`
  populated returns a real `WebSearchResult` with cited sources.
- `~/.dsh/profiles/desktop/cordis.patch.yml` updated to the new ref so the
  installed app resolves the search-dedicated key.
