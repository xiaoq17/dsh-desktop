/**
 * Volcano Ark (火山方舟) web_search provider for the dsh `ctx.web` seam.
 *
 * Implements spec S-0002: a local search provider that calls the Ark
 * OpenAI-compatible Responses API (`POST {baseURL}/responses`) declaring the
 * `web_search` tool, letting the model decide the query and returning an
 * integrated answer plus `url_citation` sources. This replaces the upstream
 * `deepseek-official` provider in the desktop profile (which needs a
 * `DEEPSEEK_API_KEY` the desktop user does not have).
 *
 * Key resolution order (spec S-0002 §3.3.2, extended to reuse the desktop's
 * existing credential store):
 *   1. a literal `apiKey` in the plugin config
 *   2. the `ARK_API_KEY` launch environment
 *   3. the credentials service under `apiKeyEnv` (default `VOLC_2_API_KEY`),
 *      which itself checks the process environment then `~/.dsh/.credentials.yaml`
 *   4. `$DSH_HOME/config/volcano.json` `arkApiKey`
 *   5. otherwise WEB_PROVIDER_CREDENTIAL_MISSING
 *
 * Loaded from the desktop profile's `cordis.patch.yml` via the relative name
 * `./plugins/volcano-search/lib/index.js` (loader baseUrl = profile directory);
 * the compiled `lib/` is shipped into the profile by the desktop app.
 *
 * @module volcano-search
 */
import type { Context } from "@deepseek-ai/cordis";
import z from "@deepseek-ai/schemastery";
import { credentialRef } from "@deepseek-ai/dsh-credentials";
import { launchEnvironmentOf } from "@deepseek-ai/dsh-launch-environment";
import { WebError, type WebSearchProvider, type WebSearchRequest, type WebSearchResult } from "@deepseek-ai/dsh-web";
import { apiErrorFromResponse, mapArkResponse, VolcanoApiError } from "./parser.ts";

/** Cordis plugin name used by loader diagnostics. */
export const name = "web-search-volcano";
/** Services required by this provider. */
export const inject = ["web"];

/** Stable id this provider registers under in the `ctx.web` search registry. */
export const PROVIDER_ID = "volcano-ark";
/** Default Ark Beijing endpoint (the `/responses` path is appended). */
const DEFAULT_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3";
/** Default model: a Doubao tool-calling model confirmed on the user's account. */
const DEFAULT_MODEL = "doubao-seed-2-1-turbo-260628";
/** Default credential reference (matches the desktop's default model provider). */
const DEFAULT_API_KEY_ENV = "VOLC_2_API_KEY";
/** Env names per spec S-0002 §3.3.2. */
const ARK_API_KEY_ENV = "ARK_API_KEY";
const ARK_BASE_URL_ENV = "ARK_BASE_URL";
const ARK_MODEL_ENV = "ARK_MODEL";
/** Attribution header; bump with the package. */
const USER_AGENT = "dsh-desktop/0.0.1 (volcano-search)";
/** Default system prompt (spec S-0002 §3.2.3). */
const DEFAULT_SYSTEM_PROMPT = `你是联网搜索助手。当用户问题涉及时效性信息、知识盲区或事实核验时，必须使用 web_search 工具获取最新信息。回答要求：
1. 优先使用搜索到的资料，不得编造未检索到的事实。
2. 回答结构清晰，使用序号或分段。
3. 结尾列出参考资料（格式：1. [标题](URL)）。`;

/** Plugin config — every field optional, `apply` fills env/constant defaults. */
export interface Config {
  /** Literal Ark API key; prefer {@link apiKeyEnv} so no secret enters config files. */
  apiKey?: string;
  /** Credential reference resolved per search; defaults to `VOLC_2_API_KEY`. */
  apiKeyEnv?: string;
  /** Ark base URL; `/responses` is appended. Defaults to Beijing. */
  baseURL?: string;
  /** Tool-calling model id. Defaults to `doubao-seed-2-1-turbo-260628`. */
  model?: string;
  /** Per-search result limit (1–50). Defaults to 10. */
  limit?: number;
  /** Max keywords the model may search per round (1–50). Defaults to 3. */
  maxKeyword?: number;
  /** Max tool calls per request (1–10). Defaults to 3. */
  maxToolCalls?: number;
  /** System prompt steering search behavior. */
  systemPrompt?: string;
}

export const Config = z.object({
  apiKey: z.string().role("secret"),
  apiKeyEnv: z.string().role("credential-ref").default(DEFAULT_API_KEY_ENV),
  baseURL: z.string(),
  model: z.string(),
  limit: z.number().step(1).min(1).max(50).default(10),
  maxKeyword: z.number().step(1).min(1).max(50).default(3),
  maxToolCalls: z.number().step(1).min(1).max(10).default(3),
  systemPrompt: z.string(),
});

/** Options one search consumes, snapshotted at the operation's entry. */
interface SearchOptions {
  apiKey?: string;
  resolveApiKey?: () => Promise<string | undefined>;
  apiKeyEnv: string;
  baseURL: string;
  model: string;
  limit: number;
  maxKeyword: number;
  maxToolCalls: number;
  systemPrompt: string;
}

/**
 * Project the resolved configuration into the options one search consumes.
 * Environment fallbacks live here, matching the seam's conventions.
 * @param ctx - plugin context (credential and environment planes).
 * @param config - the validated plugin config.
 * @returns options for one search.
 */
function resolveOptions(ctx: Context, config: Config): SearchOptions {
  const apiKeyEnv = config.apiKeyEnv ?? DEFAULT_API_KEY_ENV;
  const literalApiKey = typeof config.apiKey === "string" && config.apiKey.length > 0 ? config.apiKey : undefined;
  return {
    ...(literalApiKey !== undefined ? { apiKey: literalApiKey } : {}),
    resolveApiKey: async () => {
      // 2. ARK_API_KEY launch environment.
      const ambient = launchEnvironmentOf(ctx).get(ARK_API_KEY_ENV);
      if (ambient !== undefined && ambient.value.length > 0) return ambient.value;
      // 3. Credentials service (process env first, then the managed document).
      const credentials = ctx.get("credentials") as { resolve(ref: ReturnType<typeof credentialRef>): Promise<{ value: string } | undefined> } | undefined;
      if (credentials !== undefined) {
        const resolved = await credentials.resolve(credentialRef(apiKeyEnv));
        if (resolved !== undefined && resolved.value.length > 0) return resolved.value;
      }
      // 4. $DSH_HOME/config/volcano.json (spec S-0002 §3.3.1).
      const fileKey = await volcanoConfigApiKey();
      if (fileKey !== undefined) return fileKey;
      return undefined;
    },
    apiKeyEnv,
    baseURL: config.baseURL ?? launchEnvironmentOf(ctx).get(ARK_BASE_URL_ENV)?.value ?? DEFAULT_BASE_URL,
    model: config.model ?? launchEnvironmentOf(ctx).get(ARK_MODEL_ENV)?.value ?? DEFAULT_MODEL,
    limit: config.limit ?? 10,
    maxKeyword: config.maxKeyword ?? 3,
    maxToolCalls: config.maxToolCalls ?? 3,
    systemPrompt: config.systemPrompt ?? DEFAULT_SYSTEM_PROMPT,
  };
}

/**
 * Read `arkApiKey` from `$DSH_HOME/config/volcano.json` (spec S-0002 §3.3.1).
 * Absent/invalid files are treated as unset so a broken sidecar never fails
 * search harder than the missing-credential error.
 * @returns the stored key, or undefined.
 */
async function volcanoConfigApiKey(): Promise<string | undefined> {
  try {
    const home = process.env.DSH_HOME ?? "";
    const { readFile } = await import("node:fs/promises");
    const text = await readFile(`${home.replace(/\/+$/, "")}/config/volcano.json`, "utf8");
    const doc = JSON.parse(text) as { arkApiKey?: unknown };
    return typeof doc.arkApiKey === "string" && doc.arkApiKey.length > 0 ? doc.arkApiKey : undefined;
  } catch {
    return undefined;
  }
}

/** Resolve one operation's credential without retaining it on the provider. */
async function providerApiKey(options: SearchOptions, signal?: AbortSignal): Promise<string> {
  throwIfAborted(signal);
  if (options.apiKey !== undefined && options.apiKey.length > 0) return options.apiKey;
  let resolved: string | undefined;
  try {
    resolved = await (options.resolveApiKey?.() ?? Promise.resolve(undefined));
  } catch (error) {
    if (signal?.aborted === true || isAbortError(error)) throw abortError(signal, error);
    throw new WebError(`Volcano search credential resolution failed: ${String(error)}`, "WEB_PROVIDER_ERROR", { cause: error as Error });
  }
  if (resolved !== undefined && resolved.length > 0) return resolved;
  throw new WebError(
    `Volcano search has no API key for "${options.apiKeyEnv}"; store it through the credentials service (the web Models page writes it), export ${ARK_API_KEY_ENV} or ${options.apiKeyEnv} in the launching environment, or set a literal "apiKey" in the web-search-volcano config`,
    "WEB_PROVIDER_CREDENTIAL_MISSING",
  );
}

/**
 * The Ark-backed search provider. Calls the Responses API with the
 * `web_search` tool; native fetch, no `ctx.llm` involvement.
 */
export class VolcanoSearchProvider implements WebSearchProvider {
  readonly id = PROVIDER_ID;
  readonly #resolveOptions: () => SearchOptions;
  constructor(resolveOptionsProvider: () => SearchOptions) {
    this.#resolveOptions = resolveOptionsProvider;
  }
  /**
   * Whether the provider can serve searches: a key source and non-empty endpoint/model.
   * @returns true when a search may proceed.
   */
  available(): boolean {
    const options = this.#resolveOptions();
    return ((options.apiKey?.length ?? 0) > 0 || options.resolveApiKey !== undefined)
      && options.baseURL.length > 0
      && options.model.length > 0;
  }
  /**
   * Run one web search: resolve the key, call the Ark Responses API with the
   * `web_search` tool, and map the integrated answer + cited sources.
   * @param request - the search request (query, optional result cap).
   * @param signal - caller-provided cancellation (carries the tool timeout budget).
   * @returns the synthesized answer with its cited sources.
   */
  async search(request: WebSearchRequest, signal?: AbortSignal): Promise<WebSearchResult> {
    const options = this.#resolveOptions();
    const apiKey = await providerApiKey(options, signal);
    throwIfAborted(signal);
    const endpoint = `${options.baseURL.replace(/\/+$/, "")}/responses`;
    const body = {
      model: options.model,
      stream: false,
      tools: [{ type: "web_search", limit: options.limit, max_keyword: options.maxKeyword }],
      max_tool_calls: options.maxToolCalls,
      input: [
        { role: "system", content: [{ type: "input_text", text: options.systemPrompt }] },
        { role: "user", content: [{ type: "input_text", text: `Perform a web search for the query: ${request.query}` }] },
      ],
    };
    const headers = {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Accept": "application/json",
      "User-Agent": USER_AGENT,
    };
    // Retry only transient failures (fetch throw + 5xx), max 2 retries with
    // 1s/2s exponential backoff (spec S-0002 §3.5). 4xx never retried.
    for (let attempt = 0; ; attempt += 1) {
      try {
        return await this.#requestOnce(endpoint, headers, body, signal);
      } catch (error) {
        if (signal?.aborted === true || isAbortError(error)) throw abortError(signal, error);
        if (error instanceof WebError && error.code === "WEB_PROVIDER_NETWORK" && attempt < 2) {
          await sleep(attempt === 0 ? 1000 : 2000);
          continue;
        }
        throw error;
      }
    }
  }
  async #requestOnce(endpoint: string, headers: Record<string, string>, body: unknown, signal?: AbortSignal): Promise<WebSearchResult> {
    let response: Response;
    try {
      // The caller's signal already carries the tool-call timeout budget
      // (enforced by the timeout-policy plugin); never layer a second one.
      response = await fetch(endpoint, {
        method: "POST",
        headers,
        body: JSON.stringify(body),
        ...(signal !== undefined ? { signal } : {}),
      });
    } catch (error) {
      if (signal?.aborted === true || isAbortError(error)) throw abortError(signal, error);
      throw new WebError(`Volcano Ark search request failed: ${String(error)}`, "WEB_PROVIDER_NETWORK", { cause: error as Error });
    }
    if (!response.ok) {
      let errorBody: { error?: { code?: string; message?: string } } | undefined;
      try {
        errorBody = (await response.json()) as { error?: { code?: string; message?: string } };
      } catch {
        // Non-JSON error body: apiErrorFromResponse falls back to the status message.
      }
      const mapped = apiErrorFromResponse(response.status, errorBody?.error, response.headers.get("x-tt-logid"));
      throw new WebError(mapped.message, mapped.code, { cause: mapped });
    }
    let data: unknown;
    try {
      data = await response.json();
    } catch (error) {
      if (signal?.aborted === true || isAbortError(error)) throw abortError(signal, error);
      throw new WebError(`Volcano Ark returned an unprocessable response body: ${String(error)}`, "WEB_PROVIDER_ERROR", { cause: error as Error });
    }
    try {
      const parsed = mapArkResponse(data);
      return { content: parsed.content, sources: parsed.sources, truncated: false };
    } catch (error) {
      if (signal?.aborted === true || isAbortError(error)) throw abortError(signal, error);
      // The parser throws only VolcanoApiError with a stable code + message
      // (never WebError); wrap it directly rather than guessing at a shape.
      const apiError = error as VolcanoApiError;
      throw new WebError(apiError.message, apiError.code, { cause: error as Error });
    }
  }
}

/** Throw the provider's stable cancellation error when the caller aborted. */
function throwIfAborted(signal?: AbortSignal): void {
  if (signal?.aborted === true) throw abortError(signal);
}

/** Build the provider's stable cancellation error while retaining the reason. */
function abortError(signal?: AbortSignal, fallback?: unknown): WebError {
  return new WebError("Volcano search aborted", "WEB_ABORTED", { cause: signal?.aborted === true ? signal.reason : fallback });
}

/** True for a fetch/`AbortSignal` abort, surfaced as `WEB_ABORTED`. */
function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === "AbortError";
}

/** Promise-based sleep for backoff. */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Register the Volcano search provider with `ctx.web`.
 * @param ctx - Cordis context (with the `web` seam injected).
 * @param config - validated plugin config.
 */
export function apply(ctx: Context, config: Config): void {
  const web = ctx.get("web") as { registerSearchProvider(provider: WebSearchProvider): unknown };
  web.registerSearchProvider(new VolcanoSearchProvider(() => resolveOptions(ctx, config)));
}
