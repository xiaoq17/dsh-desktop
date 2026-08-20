# S-0003：工程规范对齐（Agent Notes 模型 + dsk-poc 工具链）

| | |
|---|---|
| **状态（Status）** | 已实现（Implemented） |
| **规格 ID（Spec ID）** | S-0003 |
| **文档版本（Document version）** | 1.0 |
| **日期（Date）** | 2026-08-20 |
| **负责人（Owner）** | — |
| **取代（Supersedes）** | — |
| **被取代（Superseded by）** | — |
| **范围（Scope）** | 把本仓库的工程规范对齐到 harness 家族仓库（deepseek-harness / dsk-poc）：代码门禁由 spec-first 切换为 Agent Notes 模型；工具链/门禁、文档分层、GitHub 协作约定按 dsk-poc 落地。 |

---

## 1. 背景与目标

本仓库此前采用自建的「规格先行（spec-first）」约定：任何行为性代码修改必须先
更新 spec 再改代码，由 pre-commit 钩子强制。两个上游仓库（deepseek-harness 与
其 POC 分支 dsk-poc）采用另一套家族约定：**Agent Notes 决策记录** + 文档分层
（one home per fact）+ 完整工具链门禁（lint / typecheck / build / test:
coverage / hygiene / duplication / doc-sync）。

用户要求：阅读两个上游仓库的工程规范，评估取舍（优先采用对应仓库的约定），
复制要用的规范文档到本地，重建本仓库的工作规范。本项目是 GitHub 项目，因此
同时落地 GitHub 协作约定。

目标（S-0003-FR-1）：代码门禁切换为 Agent Notes 模型；spec 保留为中文设计记录。
目标（S-0003-FR-2）：工具链与门禁对齐 dsk-poc（oxlint、TS7 typecheck、
vitest 4 源码层测试 + 每文件 100% 覆盖率、knip/publint/workspace 约束/
NodeNext consumer、跨文件查重、五个文档门）。
目标（S-0003-FR-3）：文档分层对齐上游（根 AGENTS.md = standing orders；
docs/AGENTS.md = 文档标准；docs/development.md / testing.md / cookbook/；
.agents/notes/ = 决策记录，双语）。
目标（S-0003-NFR-1）：规范文档语言策略参考 dsk-poc——规范/指南类用英文，
spec 用中文，Agent Notes 双语（EN + zh）。
目标（S-0003-NFR-2）：所有门禁可本地运行且 CI 覆盖，全绿视为「完成」。

## 2. 设计

### 2.1 代码门禁模型（S-0003-FR-1）

- 非平凡变更必须在同一变更中附带 Agent Note（决策/放弃的备选/所需验证），
  生命周期 `proposed/ → implemented/ / rejected/`，分类 `feature / bug-fix /
  simplification / architecture / process / testing`，格式由
  `scripts/verify-agent-note-format.ts` 强制。
- `docs/specs/` 保留为中文设计记录（RFC/ADR、`S-NNNN`、单一编号命名空间），
  但不再是硬门禁；pre-commit 钩子降级为卫生检查（LF / 尾换行 /
  `git diff --cached --check`）。
- 迁移说明：历史 spec（S-0001、S-0002）保留、状态不变；本提交即迁移提交，
  同时新增本 spec（S-0003）与对应 process 类 Agent Note。

### 2.2 工具链与门禁（S-0003-FR-2）

- 根 `package.json` 脚本对齐 dsk-poc：`clean / typecheck / lint / test /
  test:coverage / hygiene（knip+publint+constraints+node-next）/ duplication /
  doc-sync（links+budgets+jsdoc+typecheck+agent-notes）`。
- devDeps 对齐 dsk-poc：typescript ^7（原生预览，`typescript/unstable` API 供
  门禁脚本使用）、oxlint、knip、publint、tsx、vitest ^4、
  @vitest/coverage-v8、vite-tsconfig-paths、@types/node ^26。
- 门禁脚本从 dsk-poc 复制并适配本地布局（`plugins/` 代替 `packages|apps`）：
  `scripts/clean.ts`、`check-workspace-constraints.ts`、`verify-node-next-types.ts`、
  `check-duplication.ts`、`verify-md-links.ts`、`verify-doc-budgets.ts`、
  `verify-export-jsdoc.ts`、`doc-typecheck.ts`、`verify-agent-note-format.ts`。
- 根 `tsconfig.json`（项目引用）、`tsconfig.typecheck.json`（全仓 strict）、
  `vitest.config.ts`（源码层测试 + 每文件 100% 覆盖率门）。
- `assets/`、`app/`（Swift）、构建/发布 shell 脚本保持本地约定（无上游对应），
  见 S-0001 附录 A 与根 AGENTS.md。

### 2.3 文档分层（S-0003-FR-3）

| 层级 | 职责 |
|---|---|
| 根 `AGENTS.md` | standing orders（每条 1–3 行，链接其归属） |
| `docs/AGENTS.md` | 文档标准：one home per fact、current-state 写作、slop checklist |
| `docs/development.md` | 环境、日常流程、门禁表、TODO 语义 |
| `docs/testing.md` | 测试策略与覆盖率门 |
| `docs/cookbook/adding-a-plugin.md` | 新增插件的分步指南 |
| `docs/specs/` | 设计记录（中文） |
| `.agents/notes/` | 决策记录（双语） |

### 2.4 GitHub 协作（S-0003-FR-4）

- CONTRIBUTING.md 重写：Agent Notes 门禁、PR 规范（单一关注点、一个 `kind/*`
  + 相关 `area/*` 标签）、不得提交构建产物、Spec/Agent Note 同变更。
- CI（.github/workflows/build.yml）扩展为运行插件 lint/typecheck/test/
  test:coverage/hygiene/doc-sync + Swift 编译 + shell 语法检查。

## 3. 决策记录

- **放弃 spec-first 硬门禁，改用 Agent Notes 模型**：上游家族（deepseek-harness
  / dsk-poc）一致采用 Agent Notes；spec-first 的强制钩子与上游工作流冲突，
  且 spec 更适合承载设计而非"每次改动的门禁"。保留 spec 作为设计记录以保留
  既有价值。备选：继续 spec-first（与上游不一致，拒绝）。
- **文档语言参考 dsk-poc**：规范/指南英文、spec 中文、Agent Notes 双语。
  备选：全量双语对照（维护成本高，拒绝）；spec 英文（与既有中文 spec 冲突，
  拒绝）。
- **工具链采用全套 dsk-poc 门禁**（用户指定）：含每文件 100% 覆盖率，要求
  为 provider 补齐单元测试。备选：仅文档 + 轻量门禁（用户否决）。

## 4. 验收（S-0003 完成定义）

- 验收 1：根 AGENTS.md 已切换为 Agent Notes 门禁，pre-commit 钩子不再拦截
  无 spec 的提交。
- 验收 2：`pnpm run lint / typecheck / test / test:coverage / hygiene /
  duplication / doc-sync` 全部通过；`bash -n scripts/*.sh` 通过。
- 验收 3：`plugins/volcano-search` 新增 provider 单元测试，`test:coverage`
  每文件 100%。
- 验收 4：docs/specs/README.md 索引含 S-0003；.agents/notes/ 有对应 process
  类 Agent Note（implemented）。
- 验收 5：CI workflow 覆盖上述门禁且通过。

## 5. 参考

- [S-0001 初始版本规格说明](0001-initial-version.md)（仓库布局、构建管线）
- [S-0002 基于火山引擎 API Key 的 Web Search 实现](0002-web-search-via-volcano-api.md)
- [docs/AGENTS.md](../AGENTS.md)（文档标准）
- [.agents/notes/README.md](../../.agents/notes/README.md)（Agent Notes 约定）
