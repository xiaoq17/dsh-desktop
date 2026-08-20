import { describe, expect, it } from "vitest";
import { VolcanoApiError, apiErrorFromResponse, mapArkResponse } from "../src/parser.ts";

/**
 * A realistic Ark Responses API body with a web_search_call + cited answer.
 * Typed `any` on purpose: fixtures model untrusted wire data.
 */
function sampleResponse(): any {
  return {
    id: "resp_abc",
    model: "doubao-seed-2-1-turbo-260628",
    output: [
      { type: "web_search_call", id: "call_1", action: { query: "今天北京天气" } },
      {
        type: "message",
        id: "msg_1",
        role: "assistant",
        content: [
          {
            type: "output_text",
            text: "北京今天晴，气温 12–20℃。",
            annotations: [
              { type: "url_citation", url: "https://weather.example.com/beijing", title: "北京天气" },
              { type: "url_citation", url: "https://example.com/toutiao/beijing", title: "头条北京" },
            ],
          },
        ],
      },
    ],
  };
}

describe("mapArkResponse", () => {
  it("parses answer text and url_citation sources", () => {
    const result = mapArkResponse(sampleResponse());
    expect(result.content).toBe("北京今天晴，气温 12–20℃。");
    expect(result.queries).toEqual(["今天北京天气"]);
    expect(result.sources).toHaveLength(2);
    expect(result.sources[0]).toEqual({
      url: "https://weather.example.com/beijing",
      title: "北京天气",
    });
  });

  it("dedupes sources by url (first occurrence wins)", () => {
    const body = sampleResponse();
    body.output[1].content[0].annotations.push({
      type: "url_citation",
      url: "https://weather.example.com/beijing",
      title: "重复",
    });
    const result = mapArkResponse(body);
    expect(result.sources).toHaveLength(2);
    expect(result.sources[0].title).toBe("北京天气");
  });

  it("keeps snippet and publishedAt when present", () => {
    const body = sampleResponse();
    body.output[1].content[0].annotations[0].snippet = "晴，12-20℃";
    body.output[1].content[0].annotations[0].publishedAt = "2026-08-20T00:00:00Z";
    const result = mapArkResponse(body);
    expect(result.sources[0]).toMatchObject({
      snippet: "晴，12-20℃",
      publishedAt: "2026-08-20T00:00:00Z",
    });
  });

  it("surfaces a body-level API error", () => {
    try {
      mapArkResponse({ error: { code: "ToolNotOpen", message: "not activated" } });
    } catch (error) {
      expect(error).toBeInstanceOf(VolcanoApiError);
      expect((error as VolcanoApiError).code).toBe("WEB_PROVIDER_NOT_OPEN");
    }
  });

  it("throws when there is no answer and no sources", () => {
    expect(() => mapArkResponse({ output: [{ type: "reasoning", summary: [] }] })).toThrowError(/no web_search answer/i);
  });

  it("degrades to a partial result when only citations exist (no answer text)", () => {
    const body = sampleResponse();
    body.output[1].content[0].text = "";
    const result = mapArkResponse(body);
    expect(result.content).toBeUndefined();
    expect(result.sources).toHaveLength(2);
  });

  it("throws on a non-object body", () => {
    expect(() => mapArkResponse(null)).toThrowError(VolcanoApiError);
    expect(() => mapArkResponse("nope")).toThrowError(VolcanoApiError);
  });
});

describe("mapArkResponse malformed-entry degradation", () => {
  it("skips a web_search_call whose query is missing or not a string", () => {
    const body = sampleResponse();
    body.output.unshift({ type: "web_search_call", action: {} });
    body.output.unshift({ type: "web_search_call", action: { query: 42 } });
    body.output.unshift({ type: "web_search_call", action: { query: "" } });
    const result = mapArkResponse(body);
    expect(result.queries).toEqual(["今天北京天气"]);
  });

  it("skips non-object output entries and non-output_text blocks", () => {
    const body = sampleResponse();
    body.output.push(null, "string", { type: "function_call" });
    body.output[1].content.push(null, "blob", { type: "input_text", text: "ignored" });
    const result = mapArkResponse(body);
    expect(result.content).toBe("北京今天晴，气温 12–20℃。");
    expect(result.sources).toHaveLength(2);
  });

  it("skips malformed and empty annotations but keeps valid ones", () => {
    const body = sampleResponse();
    const textBlock = body.output[1].content[0];
    textBlock.annotations.push(null, "str", { type: "other", url: "https://x" });
    textBlock.annotations.push({ type: "url_citation", url: "" });
    textBlock.annotations.push({ type: "url_citation", url: "https://valid.example" });
    const result = mapArkResponse(body);
    expect(result.sources).toHaveLength(3);
    expect(result.sources[2].url).toBe("https://valid.example");
  });

  it("omits absent/empty title, snippet and publishedAt from a source", () => {
    const body = sampleResponse();
    body.output[1].content[0].annotations[0].title = "";
    body.output[1].content[0].annotations[0].snippet = "";
    body.output[1].content[0].annotations[0].publishedAt = "";
    const result = mapArkResponse(body);
    expect(result.sources[0]).toEqual({ url: "https://weather.example.com/beijing" });
  });

  it("treats a missing output array as empty (throws with no answer/sources)", () => {
    const body = sampleResponse();
    delete body.output;
    expect(() => mapArkResponse(body)).toThrowError(/no web_search answer/i);
  });

  it("treats a non-array message content as no content", () => {
    const body = sampleResponse();
    body.output[1].content = "plain string";
    expect(() => mapArkResponse(body)).toThrowError(/no web_search answer/i);
  });

  it("treats non-array annotations as no citations", () => {
    const body = sampleResponse();
    body.output[1].content[0].annotations = "not-an-array";
    const result = mapArkResponse(body);
    expect(result.content).toBe("北京今天晴，气温 12–20℃。");
    expect(result.sources).toHaveLength(0);
  });
});

describe("apiErrorFromResponse", () => {
  it("maps ToolNotOpen (404) to WEB_PROVIDER_NOT_OPEN", () => {
    const error = apiErrorFromResponse(404, { code: "ToolNotOpen", message: "not activated" }, "log-1");
    expect(error.code).toBe("WEB_PROVIDER_NOT_OPEN");
    expect(error.detail.logId).toBe("log-1");
  });

  it("maps 401/403 to WEB_PROVIDER_AUTH", () => {
    expect(apiErrorFromResponse(401, { code: "InvalidAuthenticationCredentials" }, null).code).toBe("WEB_PROVIDER_AUTH");
    expect(apiErrorFromResponse(403, undefined, null).code).toBe("WEB_PROVIDER_AUTH");
  });

  it("maps 429 to WEB_PROVIDER_RATE_LIMIT and 5xx to WEB_PROVIDER_NETWORK", () => {
    expect(apiErrorFromResponse(429, undefined, null).code).toBe("WEB_PROVIDER_RATE_LIMIT");
    expect(apiErrorFromResponse(503, { message: "upstream" }, null).code).toBe("WEB_PROVIDER_NETWORK");
  });

  it("falls back to a generic code and status message", () => {
    const error = apiErrorFromResponse(400, { code: "InvalidParameter" }, null);
    expect(error.code).toBe("WEB_PROVIDER_ERROR");
    expect(error.detail.status).toBe(400);
  });
});
