# 基于火山引擎 API Key 的 Web Search 实现

| | |
|---|---|
| **状态（Status）** | 已实现（Implemented） |
| **规格 ID（Spec ID）** | S-0002 |
| **文档版本（Document version）** | 1.0 |
| **日期（Date）** | 2026-08-20 |
| **负责人（Owner）** | Qin Xiao |
| **取代（Supersedes）** | — |
| **被取代（Superseded by）** | — |
| **范围（Scope）** | 为 dsh-desktop 内嵌环境中的本地 agent 提供「用火山引擎 API Key 实现 web_search」的规格，涵盖 API 协议、`ctx.web` 搜索 provider 封装、密钥管理与错误处理 |

> 需求描述中的"必须（MUST）""不得（MUST NOT）""应当（SHOULD）""可以（MAY）"
> 遵循 [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) 语义。

---

## 1. 概述

dsh-desktop 内嵌的 `@deepseek-ai/dsh` 后端运行在本地 Node 环境中，模型侧的
`web_search` 工具经 `ctx.web` seam 路由到配置的搜索 provider。上游默认的
`web-search-deepseek` provider 依赖 `DEEPSEEK_API_KEY`，桌面用户普遍没有；本
spec 规定：desktop 通过**火山引擎方舟（Ark）的 Web Search 插件**自研一个
`ctx.web` 搜索 provider（`volcano-ark`），复用用户已有的火山 API Key，使
`web_search` 在桌面版开箱可用。

实现以 TypeScript 插件（`plugins/volcano-search/`，dsk-poc 工程规范）承载：
`VolcanoSearchProvider` 实现 seam 的 `WebSearchProvider` 接口，调用 Ark
Responses API（`POST {base}/responses`）声明 `web_search` 工具，模型自动决定
搜索关键词并返回带 `url_citation` 引用的整合回答；`parser` 纯函数负责响应解析
与错误映射（可单测）。桌面 profile 的 `cordis.patch.yml` 注册该 provider 并
替换 `deepseek-official`。

## 2. 背景与目标

### 2.1 背景：宿主 AI 的 web_search 是怎么做的

作为对比，Doubao（本助手）的 `general_search` 工作机制如下：

1. **触发判断**：当用户问题涉及时效性信息、知识盲区或需要外部事实核验时，
   助手调用平台内置的 `general_search` 工具。
2. **工具调用**：平台侧工具接收查询词，返回结构化结果列表（标题、站点名、
   URL、内容摘要、发布时间）。
3. **结果整合**：助手从摘要中提取事实，在最终回答中以 `["url"]`
   格式标注来源；摘要信息不足时再用 `web.fetch` 精读原文。
4. **密钥透明**：API Key 与搜索后端由平台托管，调用方（助手）不接触密钥。

本地 agent 没有这个平台托管层，因此需要**自行管理 API Key、自行构造请求、
自行解析响应**。火山引擎方舟的 Web Search 插件恰好提供了等价能力——它是
Responses API 中的一个 `tools` 条目，模型会自动判断是否发起搜索、搜索什么
关键词，并返回带引用注释的回答。

### 2.2 目标

- **G-1** 本地 agent 能用一个火山引擎 API Key 完成联网搜索，返回结构化结果
  （整合回答、URL、标题），并接入 dsh 既有的模型侧 `web_search` 工具。
- **G-2** 以 `ctx.web` 搜索 provider 形式实现（`id: volcano-ark`），调用方
  （模型工具 / 上层）无需关心 Responses API 的消息构造与解析。
- **G-3** 密钥安全解析与存储：优先复用 dsh 凭据服务（`~/.dsh/.credentials.yaml`
  或进程环境），也支持 `$DSH_HOME/config/volcano.json` 与 `ARK_API_KEY` 环境
  变量；不得（MUST NOT）硬编码、不得写入日志。
- **G-4** 错误可诊断：网络超时、鉴权失败、配额不足、模型不支持工具、**联网
  插件未开通**等场景有明确错误码与提示。
- **G-5** 纯解析逻辑可单测（vitest），随 workspace 构建/发布。

### 2.3 非目标

- 不实现自己的爬虫/索引；搜索完全委托给火山引擎。
- 不做搜索结果的二次排序或去重（火山引擎侧已处理；provider 仅按 URL 去重）。
- 不绑定特定模型版本；模型名由配置决定，默认值随 spec 版本更新。
- 不实现代理/翻墙；假设运行环境可直接访问 `ark.cn-beijing.volces.com`。
- 不实现流式搜索（`searchStream`）；`ctx.web` seam 与 `web_search` 工具当前
  均为同步语义，流式作为未来工作。

## 3. 设计 / 规格

### 3.1 火山引擎 Web Search API 协议

> 本节为 API 参考，与实现一致（实现以 `fetch` 直连，未引入额外 HTTP 客户端）。

#### 3.1.1 Endpoint 与认证

| 项 | 值 |
|---|---|
| 区域 | 北京（默认）/ 上海 |
| Base URL（北京） | `https://ark.cn-beijing.volces.com/api/v3` |
| Base URL（上海） | `https://ark.cn-shanghai.volces.com/api/v3` |
| 路径 | `POST /responses` |
| 认证 Header | `Authorization: Bearer <ARK_API_KEY>` |
| Content-Type | `application/json` |

API Key 在火山引擎控制台「方舟 → API Key 管理」中创建，格式为长字符串。
**一个 API Key 可用于所有方舟模型与工具调用**，无需为搜索单独申请。

#### 3.1.2 请求体

```json
{
  "model": "doubao-seed-2-1-turbo-260628",
  "stream": false,
  "tools": [
    { "type": "web_search", "max_keyword": 3, "limit": 10 }
  ],
  "max_tool_calls": 3,
  "input": [
    { "role": "system", "content": [{"type": "input_text", "text": "<系统提示词>"}] },
    { "role": "user", "content": [{"type": "input_text", "text": "<用户查询>"}] }
  ]
}
```

字段说明：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `model` | string | 是 | 支持工具调用的模型 ID。默认 `doubao-seed-2-1-turbo-260628`（用户账号实测可用），可配置。 |
| `stream` | boolean | 否 | 默认 `false`。 |
| `tools` | array | 是 | 必须包含 `{"type": "web_search"}`。 |
| `tools[].max_keyword` | int | 否 | 单轮最大关键词数，1～50（默认 3）。 |
| `tools[].limit` | int | 否 | 单次搜索返回最大结果数，1～50，默认 10。 |
| `tools[].sources` | string[] | 否 | 附加搜索源（`douyin`/`moji`/`toutiao`）。v1.0 未开放配置，默认仅 `search_engine`（全网）。 |
| `max_tool_calls` | int | 否 | 工具调用最大轮次，1～10，默认 3。 |
| `input` | array | 是 | 消息列表；`content` 为 `input_text` 数组。 |

> **关键认知**：Web Search 不是独立 `/search` 端点，而是 Responses API 的
> 工具声明。**模型自动决定是否搜索、搜什么关键词**，调用方只需把问题放进
> `input` 并声明 `tools: [{"type":"web_search"}]`。

#### 3.1.3 响应体（同步模式）

```json
{
  "id": "resp_xxx",
  "model": "doubao-seed-2-1-turbo-260628",
  "output": [
    { "type": "web_search_call", "id": "ws_xxx", "action": { "query": "搜索关键词" } },
    {
      "type": "message",
      "id": "msg_xxx",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "整合搜索结果后的回答文本…",
          "annotations": [
            { "type": "url_citation", "url": "https://example.com/article", "title": "文章标题" }
          ]
        }
      ]
    }
  ],
  "usage": {
    "input_tokens": 120,
    "output_tokens": 80,
    "tool_usage": { "web_search": 2 },
    "tool_usage_details": { "web_search": { "search_engine": 2, "toutiao": 1 } }
  }
}
```

关键解析点（`parser.mapArkResponse`）：

- `output[]` 中 `type === "web_search_call"` 的条目记录实际发起的搜索
  （`action.query` 为关键词）。
- `output[]` 中 `type === "message"` 的条目是模型最终回答；
  `content[].annotations` 的 `url_citation` 是引用来源（`url` + `title`），
  provider 按 URL 去重。
- 无任何 `output_text` 且无引用来源时视为解析错误（模型可能未触发搜索）。

#### 3.1.4 错误响应

非 2xx 响应体（OpenAI 兼容格式）携带 `error` 对象；`ToolNotOpen` 表示**账号未
开通联网内容插件**（见 §3.4）。请求 ID 位于响应 Header `x-tt-logid`。

### 3.2 实现架构（`ctx.web` provider）

```
┌──────────────────────────────────────────────────────┐
│           模型侧 web_search 工具（dsh-tool-web）       │
│   ctx.web.search({query, maxResults}, signal)         │
└────────────────────────┬─────────────────────────────┘
                         ▼
┌──────────────────────────────────────────────────────┐
│   ctx.web seam（WebRuntime，选择 searchProvider）      │
│   web-search-volcano → VolcanoSearchProvider (volcano-ark) │
│   - 解析 API Key（凭据服务 → ARK_API_KEY → volcano.json）│
│   - 构造 Responses API 请求（tools: web_search）        │
│   - 调用 parser.mapArkResponse 归一化为 WebSearchResult │
│   - 错误映射 → WebError(WEB_PROVIDER_*)                │
└────────────────────────┬─────────────────────────────┘
                         │ HTTPS (Bearer)
                         ▼
┌──────────────────────────────────────────────────────┐
│   火山引擎方舟 Responses API（POST /api/v3/responses） │
│   tools: [{ type: "web_search" }]                     │
└──────────────────────────────────────────────────────┘
```

#### 3.2.1 模块划分（`plugins/volcano-search/`）

| 模块 | 职责 |
|---|---|
| `src/index.ts` | Cordis 插件（`name: web-search-volcano`，`inject: ["web"]`）：注册 `VolcanoSearchProvider`；`Config` 定义配置；`resolveOptions` 汇总端点/模型/密钥解析；错误/重试/中止处理。 |
| `src/parser.ts` | 纯解析（零外部依赖）：`mapArkResponse` 提取回答/关键词/引用；`apiErrorFromResponse` 映射错误码；`VolcanoApiError` 类型。 |
| `tests/parser.test.ts` | vitest 单测（解析、去重、错误映射）。 |

#### 3.2.2 seam 接口映射

provider 实现 `@deepseek-ai/dsh-web` 的 `WebSearchProvider`：

```typescript
interface WebSearchProvider {
  readonly id: string;                       // "volcano-ark"
  available(): boolean;                      // key/endpoint/model 可解析
  search(request: WebSearchRequest, signal?: AbortSignal): Promise<WebSearchResult>;
}
```

`search()` 映射：

- `request.query` → `input[].user` 文本（`Perform a web search for the query: …`）。
- Ark 响应的 `output_text` → `WebSearchResult.content`（整合回答）。
- Ark 响应的 `url_citation` → `WebSearchResult.sources[]`（`url` + `title`）。
- `maxResults` 截断由 seam 负责（`dsh-tool-web` 恒设置）。

配置项（`web-search-volcano` 行的 `config`，均可缺省）：

| 键 | 默认值 | 说明 |
|---|---|---|
| `apiKeyEnv` | `WEB_SEARCH_ARK_API_KEY` | 凭据服务中的凭据引用（搜索专用 ref，与模型 key 隔离；v1.1 起不再复用 `VOLC_2_API_KEY`）。 |
| `apiKey` | — | 字面量 key（不推荐；避免密钥进入配置文件）。 |
| `baseURL` | `https://ark.cn-beijing.volces.com/api/v3` | `/responses` 自动追加；可用 `ARK_BASE_URL` 覆盖。 |
| `model` | `doubao-seed-2-1-turbo-260628` | 支持工具调用的模型；可用 `ARK_MODEL` 覆盖。 |
| `limit` | `10` | 单次搜索结果数（1～50）。 |
| `maxKeyword` | `3` | 单轮最大关键词数（1～50）。 |
| `maxToolCalls` | `3` | 工具调用最大轮次（1～10）。 |
| `systemPrompt` | 见 §3.2.3 | 覆盖默认系统提示词。 |

#### 3.2.3 默认系统提示词

封装层必须（MUST）注入一段默认系统提示词，规范模型的搜索行为与输出格式：

```
你是联网搜索助手。当用户问题涉及时效性信息、知识盲区或事实核验时，
必须使用 web_search 工具获取最新信息。回答要求：
1. 优先使用搜索到的资料，不得编造未检索到的事实。
2. 回答结构清晰，使用序号或分段。
3. 结尾列出参考资料（格式：1. [标题](URL)）。
```

调用方可通过 `config.systemPrompt` 覆盖。

### 3.3 密钥管理

#### 3.3.1 解析优先级（从高到低）

1. `config.apiKey` 字面量（不推荐）。
2. 环境变量 `ARK_API_KEY`（`launchEnvironmentOf` 解析，便于 CI / 临时调试）。
3. 凭据服务 `credentials.resolve(apiKeyEnv)`：先查进程环境（如 `WEB_SEARCH_ARK_API_KEY`），
   再查 `~/.dsh/.credentials.yaml`（dsh 凭据服务，可热更新）。**桌面用户既有的
   火山 key 存在这里，无需重新录入**。
4. `$DSH_HOME/config/volcano.json` 的 `arkApiKey`（S-0002 v0.1 草案的存储位）。
5. 均未解析到 → `WEB_PROVIDER_CREDENTIAL_MISSING`。

`ARK_BASE_URL`、`ARK_MODEL` 同理可覆盖端点与模型。

#### 3.3.2 安全约束

- **不得（MUST NOT）**将 API Key 写入任何日志文件（包括
  `dsh-desktop-server.log`）。
- **不得（MUST NOT）**将 API Key 作为 URL 参数传递；仅用于 `Authorization`
  Header。
- **不得（MUST NOT）**在错误消息中回显完整 API Key。
- 网络请求必须（MUST）使用 HTTPS。

### 3.4 错误处理

provider 将非 2xx 与解析错误映射为 `WebError`（`HarnessError` 子类，携带稳定
`code`），由 `web_search` 工具向模型呈现 message：

| HTTP 状态 / 情形 | 错误码 | 说明与处理 |
|---|---|---|
| 401 / 403 | `WEB_PROVIDER_AUTH` | Key 无效或无权限，提示检查 Key。 |
| 404 + `ToolNotOpen` | `WEB_PROVIDER_NOT_OPEN` | **账号未开通「联网内容插件」**，提示到 `https://console.volcengine.com/common-buy/CC_content_plugin` 开通。 |
| 404 其它 | `WEB_PROVIDER_MODEL_UNSUPPORTED` | 模型 ID 错误或该模型不支持工具调用。 |
| 429 | `WEB_PROVIDER_RATE_LIMIT` | 配额不足或限流。 |
| 5xx / 网络异常 / 超时 | `WEB_PROVIDER_NETWORK` | 服务端错误或网络异常，自动重试（§3.5）。 |
| 中止 | `WEB_ABORTED` | 调用方取消。 |
| 其它 | `WEB_PROVIDER_ERROR` | 保留原始状态与 `x-tt-logid`（detail 内，便于工单排查）。 |

所有错误必须（MUST）包含：稳定错误码、可读 message、火山引擎返回的
`error.message`（如有）、请求 ID（响应 Header `x-tt-logid`，置于 detail）。

### 3.5 超时与重试

- 超时由调用方 signal 承载（`dsh-tool-web` 的 `searchTimeoutMs`，base bundle
  设为 60 秒），provider 不得（MUST NOT）自行叠加第二个超时。
- 仅对 `WEB_PROVIDER_NETWORK`（fetch 抛错 + 5xx）自动重试，最多 2 次，指数
  退避（1s → 2s）。
- 4xx（鉴权 / 未开通 / 限流 / 模型不支持）**不自动重试**。

### 3.6 与 dsh-desktop 的集成点

- 插件为 `plugins/volcano-search/`（TypeScript workspace 包，dsk-poc 规范）：
  `build.sh` 经 `pnpm -r build` 产出 `lib/`，把 `lib/` + `package.json` 拷入
  `Contents/Resources/desktop-profile/plugins/volcano-search/`。
- 桌面 profile 的 `cordis.patch.yml`（`assets/desktop-profile/`）插入
  `web-search-volcano` 行（相对路径 `./plugins/volcano-search/lib/index.js`，
  相对 profile 目录解析），并把 `web.searchProvider` 覆盖为 `volcano-ark`、
  禁用 `web-search-deepseek`。
- `ServerManager.ensureDesktopProfile()`（S-0001 FR-1.5）在首启/每次启动时把
  模板中的 `plugins/*` 幂等同步进 `$DSH_HOME/profiles/desktop/`，并对仍是空
  默认的 `cordis.patch.yml` 做一次性迁移。
- 搜索产生的网络调用属于用户主动发起的工具调用；必须（MUST）在隐私说明中
  告知用户搜索查询会发送至火山引擎。

## 4. 需求

### 4.1 功能需求

| ID | 需求 | 状态 |
|----|------|------|
| S-0002-FR-1 | 提供 `ctx.web` 搜索 provider（`id: volcano-ark`），实现 `WebSearchProvider.search()`，把 Ark 响应归一化为 seam 的 `WebSearchResult`（`content` + `sources[]`）。 | 已实现 |
| S-0002-FR-2 | 桌面 profile 必须（MUST）注册该 provider 并把 `web.searchProvider` 设为 `volcano-ark`，禁用 `web-search-deepseek`，使模型侧 `web_search` 工具可用。 | 已实现 |
| S-0002-FR-3 | 通过 `Authorization: Bearer <KEY>` 调用 `POST {baseURL}/responses`，并在 `tools` 声明 `{"type":"web_search"}`。 | 已实现 |
| S-0002-FR-4 | 支持 `limit`、`maxKeyword`、`model`、`systemPrompt` 配置；`sources`/`userLocation`/`timeoutMs` 未开放（后续）。 | 部分实现 |
| S-0002-FR-5 | 从响应 `output[]` 提取 `web_search_call.action.query` 与 `message.content[].annotations`（`url_citation`），按 URL 去重。 | 已实现 |
| S-0002-FR-6 | 密钥解析优先级：字面量 `apiKey` > 环境 `ARK_API_KEY` > 凭据服务 `apiKeyEnv` > `$DSH_HOME/config/volcano.json` > 报错。 | 已实现 |
| S-0002-FR-7 | 注入默认系统提示词，要求模型在时效性/知识盲区/事实核验场景使用搜索并列出参考资料。 | 已实现 |
| S-0002-FR-8 | 将 HTTP 错误映射为稳定 `WebError` 码（AUTH / NOT_OPEN / MODEL_UNSUPPORTED / RATE_LIMIT / NETWORK / ABORTED / ERROR），并携带请求 ID。 | 已实现 |
| S-0002-FR-9 | 对 5xx 与网络异常执行最多 2 次指数退避重试（1s → 2s）；4xx 不重试。 | 已实现 |
| S-0002-FR-10 | 桌面应用启动时把编译后插件同步进 `$DSH_HOME/profiles/desktop/plugins/`（幂等，不覆盖已有内容）。 | 已实现 |
| S-0002-FR-11 | 流式搜索 `searchStream()`。 | 不做（后续） |

### 4.2 非功能需求

| ID | 需求 | 状态 |
|----|------|------|
| S-0002-NFR-1 | API Key 不得（MUST NOT）硬编码、不得（MUST NOT）写入日志；优先复用凭据服务，也支持 `volcano.json`（0600）与 `ARK_API_KEY`。 | 已实现 |
| S-0002-NFR-2 | 所有网络请求必须（MUST）使用 HTTPS；API Key 仅出现在 `Authorization` Header。 | 已实现 |
| S-0002-NFR-3 | 错误消息中不得（MUST NOT）回显完整 API Key。 | 已实现 |
| S-0002-NFR-4 | 超时由 seam 的 tool-call 超时预算承载（默认 60s），provider 不叠加超时。 | 已实现 |
| S-0002-NFR-5 | 使用 Node 原生 `fetch`，不引入额外 HTTP 客户端依赖。 | 已实现 |
| S-0002-NFR-6 | 搜索查询内容会发送至火山引擎，必须（MUST）在用户可见的隐私说明中告知。 | 已实现（见 README） |
| S-0002-NFR-7 | 提供 TypeScript 类型定义（`lib/types/*.d.ts`），纯解析逻辑可单测（vitest）。 | 已实现 |
| S-0002-NFR-8 | 插件随 pnpm workspace 构建（`src/` → `lib/`），未开通联网插件时返回明确的 `WEB_PROVIDER_NOT_OPEN` 提示。 | 已实现 |

## 5. 待决问题

- **Q1（已决）**：默认模型。实测用户账号 `doubao-seed-2-1-turbo-260628` 可用，
  定为默认；模型迭代后由配置更新，文档记录当前默认值。
- **Q2（未做）**：缓存。搜索场景时效性要求高，暂不缓存，作为未来优化。
- **Q3（未做）**：纯搜索模式（不经模型整合）。当前 Web Search 插件绑定模型
  调用；若需纯搜索 API，评估火山引擎「豆包搜索」独立产品（Custom/Global 版）。
- **Q4（未做）**：多区域。当前仅北京区，`baseURL` 可配置以切换上海区。

## 6. 参考资料

- S-0001（初始版本规格说明）— 桌面 profile、DSH_HOME、FR-1.5、NFR-7 隐私约束。
- 火山引擎方舟 Web Search（联网内容插件）官方文档：
  `https://www.volcengine.com/docs/82379/1756990`
- 火山引擎方舟快速入门：
  `https://www.volcengine.com/docs/82379/1399008`
- 火山引擎豆包搜索（独立产品）：
  `https://www.volcengine.com/docs/87772/2272953`（Custom 版）、
  `https://www.volcengine.com/docs/87772/2548026`（Global 版）
