# Agent Note: 将 web_search 凭据 ref 与模型 key 隔离
Status: implemented

## Problem

web-search-volcano provider 默认从 `VOLC_2_API_KEY` 取 key——与 `volc-2` 模型
provider 共用同一个凭据 ref。共享 ref 使搜索与模型 key 耦合：轮换或删除模型
key 会悄悄让搜索失效，且搜索流量无法独立计费或独立撤销。

## Change

插件默认 `apiKeyEnv` 改为 `WEB_SEARCH_ARK_API_KEY`（搜索专用 ref）。桌面
profile patch 显式设置该值。解析链不变（字面量 `apiKey` → `ARK_API_KEY` →
凭据服务 `apiKeyEnv` → `$DSH_HOME/config/volcano.json`）。

## Alternatives given up

- 继续复用 `VOLC_2_API_KEY`（共享 ref）。拒绝：搜索与模型 key 仍耦合，
  模型 key 轮换会使搜索失效。
- 插件内字面量 `apiKey`。拒绝：把密钥写进 profile 配置，违反 S-0002-NFR-1
  （密钥不进配置/日志）。

## Verification

- `pnpm run test` / `test:coverage`：45 单测全绿，`plugins/volcano-search/src`
  每文件 100%。
- 真实 `~/.dsh` profile + 火山 API 端到端，`WEB_SEARCH_ARK_API_KEY` 已填充时
  返回真实 `WebSearchResult` 与引用来源。
- `~/.dsh/profiles/desktop/cordis.patch.yml` 已更新为新 ref，已安装 App 按
  搜索专用 key 解析。
