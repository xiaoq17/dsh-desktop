/**
 * VolcanoSearchProvider unit tests (source-plane, spec S-0002).
 *
 * Covers every branch of `index.ts` — key resolution, retry/backoff, abort,
 * and error mapping — by injecting a ctx stub (launch environment +
 * credentials) and a mocked global `fetch` (docs/testing.md: provider tests
 * mock their seams so the coverage gate stays at 100% per file).
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createLaunchEnvironmentSnapshot } from "@deepseek-ai/dsh-launch-environment";
import { type WebSearchProvider } from "@deepseek-ai/dsh-web";
import { apply, PROVIDER_ID, VolcanoSearchProvider, type Config } from "../src/index.ts";

/** A minimal ctx stub exposing the services `index.ts` consumes. */
function makeCtx(
  env: Record<string, string>,
  credentials?: { resolve: (ref: unknown) => Promise<{ value: string } | undefined> },
): { ctx: { get: (service: string) => unknown }; web: { registerSearchProvider: ReturnType<typeof vi.fn> } } {
  const launchEnvironment = createLaunchEnvironmentSnapshot([{ source: "process", values: env }]);
  const web = { registerSearchProvider: vi.fn() };
  const ctx = {
    get(service: string): unknown {
      if (service === "launchEnvironment") return launchEnvironment;
      if (service === "credentials") return credentials;
      if (service === "web") return web;
      return undefined;
    },
  };
  return { ctx, web };
}

/** Build a provider through `apply` (the real registration path). */
function makeProvider(
  env: Record<string, string>,
  config: Partial<Config> = {},
  credentials?: { resolve: (ref: unknown) => Promise<{ value: string } | undefined> },
): WebSearchProvider {
  const { ctx, web } = makeCtx(env, credentials);
  apply(ctx as never, config as Config);
  return web.registerSearchProvider.mock.calls[0]?.[0] as WebSearchProvider;
}

/** A configurable fetch mock returning a queued sequence of Responses. */
function mockFetch(...responses: Array<{ ok: boolean; status?: number; body: unknown; logId?: string | null; jsonError?: Error } | Error>): ReturnType<typeof vi.fn> {
  const calls: typeof responses = [...responses];
  return vi.fn(async (_url: string, _init: unknown) => {
    const next = calls.shift();
    if (next instanceof Error) throw next;
    if (next === undefined) throw new Error("fetch called more times than mocked");
    const body = next.body as string;
    return {
      ok: next.ok,
      status: next.status ?? (next.ok ? 200 : 400),
      headers: { get: (name: string) => (name === "x-tt-logid" ? next.logId ?? null : null) },
      json: async () => {
        if (next.jsonError !== undefined) throw next.jsonError;
        return body;
      },
    } as Response;
  });
}

/** Standard success body mirroring a real Ark `/responses` response. */
const successBody = {
  output: [
    { type: "web_search_call", action: { query: "北京天气" } },
    {
      type: "message",
      role: "assistant",
      content: [
        {
          type: "output_text",
          text: "北京今天晴，5°C。",
          annotations: [
            { type: "url_citation", url: "https://weather.com.cn/beijing", title: "中国天气网" },
            { type: "url_citation", url: "https://weather.com.cn/beijing", title: "中国天气网" },
          ],
        },
      ],
    },
  ],
};

describe("VolcanoSearchProvider key resolution", () => {
  it("uses the literal apiKey from config when present", async () => {
    vi.stubGlobal("fetch", mockFetch({ ok: true, body: successBody }));
    const provider = makeProvider({}, { apiKey: "lit-key", baseURL: "https://ark.example/v3", model: "m1" });
    expect(provider.available()).toBe(true);
    const result = await provider.search({ query: "q" });
    expect(result.content).toContain("北京今天晴");
    expect(result.sources).toHaveLength(1);
    vi.unstubAllGlobals();
  });

  it("resolves the key from the ARK_API_KEY launch environment", async () => {
    vi.stubGlobal("fetch", mockFetch({ ok: true, body: successBody }));
    const provider = makeProvider({ ARK_API_KEY: "env-key" }, {});
    const result = await provider.search({ query: "q" });
    expect(result.sources).toHaveLength(1);
    vi.unstubAllGlobals();
  });

  it("falls back to the credentials service under apiKeyEnv", async () => {
    vi.stubGlobal("fetch", mockFetch({ ok: true, body: successBody }));
    const credentials = { resolve: vi.fn(async () => ({ value: "cred-key" })) };
    const provider = makeProvider({}, { apiKeyEnv: "MY_KEY" }, credentials);
    const result = await provider.search({ query: "q" });
    expect(credentials.resolve).toHaveBeenCalled();
    expect(result.sources).toHaveLength(1);
    vi.unstubAllGlobals();
  });

  it("reads arkApiKey from $DSH_HOME/config/volcano.json as the last file source", async () => {
    const home = mkdtempSync(join(tmpdir(), "volcano-home-"));
    mkdirSync(join(home, "config"), { recursive: true });
    writeFileSync(join(home, "config", "volcano.json"), JSON.stringify({ arkApiKey: "file-key" }), "utf8");
    process.env.DSH_HOME = home;
    vi.stubGlobal("fetch", mockFetch({ ok: true, body: successBody }));
    const provider = makeProvider({});
    const result = await provider.search({ query: "q" });
    expect(result.sources).toHaveLength(1);
    delete process.env.DSH_HOME;
    rmSync(home, { recursive: true, force: true });
    vi.unstubAllGlobals();
  });

  it("treats a non-string arkApiKey in volcano.json as unset", async () => {
    const home = mkdtempSync(join(tmpdir(), "volcano-home-"));
    mkdirSync(join(home, "config"), { recursive: true });
    writeFileSync(join(home, "config", "volcano.json"), JSON.stringify({ arkApiKey: 12345 }), "utf8");
    process.env.DSH_HOME = home;
    const provider = makeProvider({});
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_CREDENTIAL_MISSING" });
    delete process.env.DSH_HOME;
    rmSync(home, { recursive: true, force: true });
  });

  it("treats an empty credentials value as unresolved (falls through to missing)", async () => {
    const credentials = { resolve: vi.fn(async () => ({ value: "" })) };
    const provider = makeProvider({}, {}, credentials);
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_CREDENTIAL_MISSING" });
  });

  it("resolves no key when the options carry no resolver at all", async () => {
    const provider = new VolcanoSearchProvider(() => ({
      apiKeyEnv: "WEB_SEARCH_ARK_API_KEY",
      baseURL: "https://ark.example/v3",
      model: "m",
      limit: 10,
      maxKeyword: 3,
      maxToolCalls: 3,
      systemPrompt: "",
    }));
    expect(provider.available()).toBe(false);
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_CREDENTIAL_MISSING" });
  });

  it("aborts when the credential resolver fails after the signal aborts", async () => {
    const controller = new AbortController();
    const provider = new VolcanoSearchProvider(() => ({
      apiKeyEnv: "WEB_SEARCH_ARK_API_KEY",
      baseURL: "https://ark.example/v3",
      model: "m",
      limit: 10,
      maxKeyword: 3,
      maxToolCalls: 3,
      systemPrompt: "",
      resolveApiKey: async () => {
        controller.abort();
        throw new Error("late failure");
      },
    }));
    await expect(provider.search({ query: "q" }, controller.signal)).rejects.toMatchObject({ code: "WEB_ABORTED" });
  });

  it("throws WEB_PROVIDER_CREDENTIAL_MISSING when no key source exists", async () => {
    const provider = makeProvider({});
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_CREDENTIAL_MISSING" });
  });

  it("surfaces a credentials-service failure as WEB_PROVIDER_ERROR", async () => {
    const credentials = { resolve: vi.fn(async () => { throw new Error("boom"); }) };
    const provider = makeProvider({}, {}, credentials);
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_ERROR" });
  });

  it("aborts before key resolution with WEB_ABORTED", async () => {
    const controller = new AbortController();
    controller.abort();
    const provider = makeProvider({}, { apiKey: "lit-key" });
    await expect(provider.search({ query: "q" }, controller.signal)).rejects.toMatchObject({ code: "WEB_ABORTED" });
  });

  it("reports availability by key-source presence and non-empty endpoint/model", () => {
    // A resolver is always present (resolveApiKey), so availability turns on
    // with defaults; it is false only when the model/endpoint are empty.
    expect(makeProvider({}).available()).toBe(true);
    expect(makeProvider({}, { apiKey: "k", model: "" }).available()).toBe(false);
    expect(makeProvider({}, { apiKey: "k", baseURL: "" }).available()).toBe(false);
  });
});

describe("VolcanoSearchProvider request handling", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("retries a transient fetch failure twice with backoff, then succeeds", async () => {
    const fetchMock = mockFetch(new Error("network down"), new Error("network down"), { ok: true, body: successBody });
    vi.stubGlobal("fetch", fetchMock);
    const provider = makeProvider({}, { apiKey: "k" });
    const expectation = provider.search({ query: "q" }).then((result) => {
      expect(result.sources).toHaveLength(1);
    });
    await vi.advanceTimersByTimeAsync(1000);
    await vi.advanceTimersByTimeAsync(2000);
    await expectation;
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it("throws WEB_PROVIDER_NETWORK after retries are exhausted", async () => {
    vi.stubGlobal("fetch", mockFetch(new Error("down"), new Error("down"), new Error("down")));
    const provider = makeProvider({}, { apiKey: "k" });
    const expectation = expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_NETWORK" });
    await vi.advanceTimersByTimeAsync(1000);
    await vi.advanceTimersByTimeAsync(2000);
    await expectation;
  });

  it("maps non-2xx statuses to stable codes via apiErrorFromResponse", async () => {
    const cases: Array<[number, string]> = [
      [401, "WEB_PROVIDER_AUTH"],
      [403, "WEB_PROVIDER_AUTH"],
      [404, "WEB_PROVIDER_MODEL_UNSUPPORTED"],
      [429, "WEB_PROVIDER_RATE_LIMIT"],
    ];
    for (const [status, code] of cases) {
      vi.stubGlobal("fetch", mockFetch({ ok: false, status, body: { error: { message: `http ${status}` } }, logId: "log-1" }));
      const provider = makeProvider({}, { apiKey: "k" });
      await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code });
      vi.unstubAllGlobals();
    }
  });

  it("retries an HTTP 500 (WEB_PROVIDER_NETWORK) and throws after backoff is exhausted", async () => {
    vi.stubGlobal("fetch", mockFetch(
      { ok: false, status: 500, body: { error: { message: "boom" } } },
      { ok: false, status: 500, body: { error: { message: "boom" } } },
      { ok: false, status: 500, body: { error: { message: "boom" } } },
    ));
    const provider = makeProvider({}, { apiKey: "k" });
    const expectation = expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_NETWORK" });
    await vi.advanceTimersByTimeAsync(1000);
    await vi.advanceTimersByTimeAsync(2000);
    await expectation;
    vi.unstubAllGlobals();
  });

  it("maps a body-level ToolNotOpen to WEB_PROVIDER_NOT_OPEN regardless of status", async () => {
    vi.stubGlobal("fetch", mockFetch({ ok: false, status: 0, body: { error: { code: "ToolNotOpen", message: "not open" } } }));
    const provider = makeProvider({}, { apiKey: "k" });
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_NOT_OPEN" });
    vi.unstubAllGlobals();
  });

  it("keeps the status-based message when the error body is not JSON", async () => {
    vi.stubGlobal("fetch", mockFetch({ ok: false, status: 429, body: "not json" }));
    const provider = makeProvider({}, { apiKey: "k" });
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_RATE_LIMIT" });
    vi.unstubAllGlobals();
  });

  it("throws WEB_PROVIDER_ERROR when the success body is unparseable JSON", async () => {
    const fetchMock = mockFetch({ ok: true, body: "{broken" });
    vi.stubGlobal("fetch", fetchMock);
    const provider = makeProvider({}, { apiKey: "k" });
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_ERROR" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("wraps a json() failure on an ok response as WEB_PROVIDER_ERROR", async () => {
    vi.stubGlobal("fetch", mockFetch({ ok: true, body: successBody, jsonError: new Error("bad json") }));
    const provider = makeProvider({}, { apiKey: "k" });
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_ERROR" });
    vi.unstubAllGlobals();
  });

  it("surfaces an aborted json() read as WEB_ABORTED", async () => {
    const abortError = new Error("The operation was aborted.");
    abortError.name = "AbortError";
    vi.stubGlobal("fetch", mockFetch({ ok: true, body: successBody, jsonError: abortError }));
    const provider = makeProvider({}, { apiKey: "k" });
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_ABORTED" });
    vi.unstubAllGlobals();
  });

  it("passes through a WebError from the response parser", async () => {
    vi.stubGlobal("fetch", mockFetch({ ok: true, body: { output: [] } }));
    const provider = makeProvider({}, { apiKey: "k" });
    await expect(provider.search({ query: "q" })).rejects.toMatchObject({ code: "WEB_PROVIDER_ERROR" });
  });

  it("surfaces fetch aborts as WEB_ABORTED", async () => {
    const abortError = new Error("The operation was aborted.");
    abortError.name = "AbortError";
    vi.stubGlobal("fetch", mockFetch(abortError));
    const controller = new AbortController();
    const provider = makeProvider({}, { apiKey: "k" });
    await expect(provider.search({ query: "q" }, controller.signal)).rejects.toMatchObject({ code: "WEB_ABORTED" });
  });

  it("aborts mid-retry when the fetch fails after the signal aborts", async () => {
    const controller = new AbortController();
    const plainError = new Error("boom");
    const fetchMock = vi.fn(async () => {
      controller.abort();
      throw plainError;
    });
    vi.stubGlobal("fetch", fetchMock);
    const provider = makeProvider({}, { apiKey: "k" });
    await expect(provider.search({ query: "q" }, controller.signal)).rejects.toMatchObject({ code: "WEB_ABORTED" });
  });

  it("aborts when the response parse fails after the signal aborts", async () => {
    const controller = new AbortController();
    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      headers: { get: () => null },
      json: async () => {
        controller.abort();
        return { output: [] };
      },
    }));
    vi.stubGlobal("fetch", fetchMock);
    const provider = makeProvider({}, { apiKey: "k" });
    await expect(provider.search({ query: "q" }, controller.signal)).rejects.toMatchObject({ code: "WEB_ABORTED" });
  });
});

describe("provider identity", () => {
  it("registers under the stable PROVIDER_ID", () => {
    expect(PROVIDER_ID).toBe("volcano-ark");
  });
  it("honors config for limit/maxKeyword/maxToolCalls/systemPrompt and env for baseURL/model", async () => {
    const fetchMock = mockFetch({ ok: true, body: successBody });
    vi.stubGlobal("fetch", fetchMock);
    const provider = makeProvider(
      { ARK_BASE_URL: "https://env-base/v3", ARK_MODEL: "env-model" },
      { apiKey: "k", limit: 5, maxKeyword: 2, maxToolCalls: 4, systemPrompt: "custom" },
    );
    await provider.search({ query: "q" });
    const init = JSON.parse(((fetchMock.mock.calls[0] as unknown[])[1] as { body: string }).body) as {
      model: string;
      tools: Array<{ limit: number; max_keyword: number }>;
      max_tool_calls: number;
      input: Array<{ role: string }>;
    };
    expect(init.model).toBe("env-model");
    expect(init.tools[0]?.limit).toBe(5);
    expect(init.tools[0]?.max_keyword).toBe(2);
    expect(init.max_tool_calls).toBe(4);
    expect(init.input[0]?.role).toBe("system");
    vi.unstubAllGlobals();
  });
});
