/**
 * Volcano Ark (火山方舟) web_search response parser — pure functions with no
 * external imports, so they are unit-testable in isolation with plain vitest
 * (spec S-0002 §3.1.3).
 *
 * Parses the OpenAI-compatible Responses API response produced by the
 * `web_search` tool declaration into the normalized shape the `ctx.web`
 * search seam consumes:
 *
 *   { content?: string, sources: Array<{url, title?, snippet?, publishedAt?}> }
 *
 * Errors are thrown as {@link VolcanoApiError} (a plain Error carrying a
 * stable `code` and `detail`) so the provider can wrap them into the seam's
 * `WebError` without importing anything from the dsh runtime here.
 *
 * @module volcano-search/parser
 */

/** One normalized source entry (the seam's WebSource shape). */
export interface WebSource {
  url: string;
  title?: string;
  snippet?: string;
  publishedAt?: string;
}

/** The parsed search outcome: an integrated answer plus citation sources. */
export interface ParsedSearch {
  /** The model's integrated answer text, when present. */
  content?: string;
  /** Every `web_search_call` query the model actually issued. */
  queries: string[];
  /** Deduped citation sources. */
  sources: WebSource[];
}

/** A parsed Ark API error: stable `code` plus human message and detail. */
export class VolcanoApiError extends Error {
  code: string;
  detail: Record<string, unknown>;
  constructor(code: string, message: string, detail: Record<string, unknown> = {}) {
    super(message);
    this.name = "VolcanoApiError";
    this.code = code;
    this.detail = detail;
  }
}

/**
 * Build a normalized API error for a non-2xx HTTP response, mapping to a
 * stable, seam-friendly code per spec S-0002 §3.4.
 * @param status - HTTP status code (0 when only a body error is available).
 * @param error - the parsed `error` body (may be absent).
 * @param logId - the `x-tt-logid` header, for support tickets.
 * @returns the typed error.
 */
export function apiErrorFromResponse(
  status: number,
  error: { code?: string; message?: string } | undefined,
  logId: string | null,
): VolcanoApiError {
  const message = typeof error?.message === "string" && error.message.length > 0
    ? error.message
    : `Volcano Ark API error (HTTP ${status})`;
  const detail: Record<string, unknown> = {
    status,
    ...(typeof error?.code === "string" ? { arkCode: error.code } : {}),
    ...(logId ? { logId } : {}),
  };
  let code = "WEB_PROVIDER_ERROR";
  // ToolNotOpen is identifiable by code regardless of transport status (a body
  // error may arrive without an HTTP status context); treat it distinctly so
  // the user always sees the "activate the web-search plugin" hint.
  if (error?.code === "ToolNotOpen") code = "WEB_PROVIDER_NOT_OPEN";
  else if (status === 401 || status === 403) code = "WEB_PROVIDER_AUTH";
  else if (status === 404) code = "WEB_PROVIDER_MODEL_UNSUPPORTED";
  else if (status === 429) code = "WEB_PROVIDER_RATE_LIMIT";
  else if (status >= 500) code = "WEB_PROVIDER_NETWORK";
  return new VolcanoApiError(code, message, detail);
}

/**
 * Parse a successful Ark Responses API body into the seam's search result.
 * Walks `output[]` for `web_search_call` queries and the assistant
 * `message`'s `output_text` answer plus `url_citation` annotations.
 * Malformed-but-usable bodies degrade to partial results rather than throwing;
 * a body with no output at all throws a parse error.
 * @param data - the parsed JSON response body.
 * @returns the normalized search result.
 */
export function mapArkResponse(data: unknown): ParsedSearch {
  if (data == null || typeof data !== "object") {
    throw new VolcanoApiError("WEB_PROVIDER_ERROR", "Volcano Ark returned an unparseable response body");
  }
  const record = data as Record<string, unknown>;
  if (record.error != null) {
    throw apiErrorFromResponse(0, record.error as { code?: string; message?: string }, null);
  }
  const output = Array.isArray(record.output) ? record.output : [];
  const queries: string[] = [];
  const sources: WebSource[] = [];
  const texts: string[] = [];
  const seen = new Set<string>();
  for (const item of output) {
    if (item == null || typeof item !== "object") continue;
    const entry = item as Record<string, unknown>;
    if (entry.type === "web_search_call") {
      const action = entry.action as { query?: unknown } | undefined;
      if (typeof action?.query === "string" && action.query.length > 0) queries.push(action.query);
      continue;
    }
    if (entry.type !== "message") continue;
    const content = Array.isArray(entry.content) ? entry.content : [];
    for (const block of content) {
      if (block == null || typeof block !== "object") continue;
      const part = block as Record<string, unknown>;
      if (part.type !== "output_text") continue;
      if (typeof part.text === "string" && part.text.length > 0) texts.push(part.text);
      const annotations = Array.isArray(part.annotations) ? part.annotations : [];
      for (const ann of annotations) {
        if (ann == null || typeof ann !== "object") continue;
        const citation = ann as Record<string, unknown>;
        if (citation.type !== "url_citation" || typeof citation.url !== "string" || citation.url.length === 0) continue;
        if (seen.has(citation.url)) continue;
        seen.add(citation.url);
        const source: WebSource = { url: citation.url };
        if (typeof citation.title === "string" && citation.title.length > 0) source.title = citation.title;
        if (typeof citation.snippet === "string" && citation.snippet.length > 0) source.snippet = citation.snippet;
        if (typeof citation.publishedAt === "string" && citation.publishedAt.length > 0) source.publishedAt = citation.publishedAt;
        sources.push(source);
      }
    }
  }
  const content = texts.join("\n\n");
  if (texts.length === 0 && sources.length === 0) {
    throw new VolcanoApiError(
      "WEB_PROVIDER_ERROR",
      "Volcano Ark returned no web_search answer or citations; the model may not have triggered the web_search tool",
    );
  }
  return {
    ...(content.length > 0 ? { content } : {}),
    queries,
    sources,
  };
}
