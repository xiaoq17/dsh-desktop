# Agent Note: 采用 Agent Notes 模型与 dsk-poc 工具链
Status: implemented

## Problem

本仓库此前运行自建的「规格先行」门禁：每次行为性代码修改都须先改中文 spec，
由 pre-commit 钩子强制（改动 `app/`、`assets/`、`scripts/`、`.github/` 而未改
`docs/specs/` 即拦截）。上游 harness 家族（deepseek-harness 及其 POC 分支
dsk-poc）采用另一套模型——以 Agent Note 作为决策记录 + 分层文档标准 + 全套
工具链门禁；本仓库自建的 spec-first 钩子与该家族工作流不兼容且偏离它，规范
文档也从未真正复制进来。

## Decision

按用户的明确选择采用上游模型：(1) 代码门禁由 spec-first 切换为 **Agent Notes**
（非平凡变更在同一变更中附带记录）；(2) 采用 dsk-poc 的语言切分——规范文档
英文、spec 中文、Agent Notes 双语；(3) 引入**全套 dsk-poc 工具链门禁**
（oxlint、TS7 严格 typecheck、vitest 4 源码层测试 + 每文件 100% 覆盖率、
knip/publint/workspace 约束/NodeNext consumer、跨文件查重、五个文档门），
从 dsk-poc 复制并适配到 `plugins/` 布局。

`docs/specs/` 保留为中文设计记录（RFC/ADR、`S-NNNN`、单一编号命名空间），但
不再是硬门禁；pre-commit 钩子降级为卫生检查（LF、尾换行、`git diff
--cached --check`）。spec S-0003 记录需求与验收；本记录说明变更如何落地。

## Alternatives considered

- **保留 spec-first，仅新增轻量 Agent Notes。** 用户明确选择上游 Agent Notes
  模型，而非保留 spec-first 作为门禁。
- **全量双语文档（处处 EN + zh 对照）。** 用户选择 dsk-poc 的切分（规范文档
  英文、spec 中文、记录双语）以控制维护成本。
- **仅文档 + 轻量门禁。** 用户选择全套 dsk-poc 门禁，包括每文件 100% 覆盖率
  ——这要求为原先仅集成测试的 provider 补齐单元测试。

## Consequences

仓库现已与 harness 家族约定一致，lint、类型、覆盖率、包卫生、查重与文档均有
机器可查的门禁。代价：工具链升级到 TypeScript 7（原生预览）与 vitest 4；覆盖
率门迫使 `index.ts`（原先只做集成测试的 provider）补齐单元测试；spec-first
的 pre-commit 拦截被移除，Agent-Note 规则改由 review 把关而非钩子强制。spec
继续作为设计记录承载价值；Agent Notes 承载每次非平凡变更的"为什么与放弃了
什么"。
