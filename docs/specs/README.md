# Spec（规格文档）

dsh-desktop 的规格文档。每份 spec 都存放在本目录，按下面的命名规范编写、
统一编号。规格是**设计记录**：描述需求与设计（FR/NFR、接口、流程），
"如何实现这个变更的决策"由 [Agent Note](../../.agents/notes/README.md) 承载。

> **本仓库的 spec 一律使用中文撰写**（技术标识、路径、命令、需求 ID 等保持
> 英文/代码原样）。

## 代码修改门禁：Agent Notes（自 S-0003 起）

**任何功能/行为性代码修改必须先想清楚再动手，并在同一变更中附带 Agent Note**
（记录决策、放弃的备选、所需验证）——详见
[`.agents/notes/README.md`](../../.agents/notes/README.md) 与根
[`AGENTS.md`](../../AGENTS.md)。

- spec 的角色是**设计记录**：没有现成 spec 覆盖的领域，新建
  `NNNN-<slug>.md` 并在下方索引登记；已有 spec 覆盖的，在对应 spec 中修订
  需求与设计。
- pre-commit 钩子（`scripts/hooks/pre-commit`）只做卫生检查（LF / 尾换行 /
  `git diff --cached --check`），不校验 spec 或 Agent Note；后者由 review 把关。

## 命名规范

所有 spec 采用 **RFC/ADR 风格的编号文档**，置于**单一编号命名空间** —— 只需
记一条规则，链接稳定，生命周期清晰。

### 存放位置

`docs/specs/` —— 每份 spec 一个文件。不存放在仓库根目录，也不用按功能分子
目录；扁平目录能让编号和引用保持简单。

### 文件名

```
NNNN-<slug>.md
```

- **`NNNN`** —— 4 位零填充、单调递增的序号。
  - 创建时分配；**永不复用、永不重编号、永不删除**。
  - 序号是 spec 的"身份"（链接/URL 永远稳定）。
  - `0001` 是初始版本总览（伞形 spec + 需求注册表）。子系统深挖从 `0002`、
    `0003`… 开始。
- **`<slug>`** —— 简短 **kebab-case** 中文/英文名词短语（≤5 词），描述
  **关注点**而非版本（如 `update-pipeline`、`mcp-integration`）。
  - **文件名中不写版本标记**（`-v2`、`-final`、`-draft`…）。排序由 `NNNN`
    决定；内容的"版本"用 **状态** 字段表达，而不是文件名。

示例：`0002-update-pipeline.md`、`0003-mcp-integration.md`。

### 表头（front matter）

每份 spec 以 `# 标题` 和如下元数据表开头（复制自
[`_template.md`](_template.md)）：

```markdown
# <标题>

| | |
|---|---|
| **状态（Status）** | 草稿（Draft） | 提议（Proposed） | 已接受（Accepted） | 已实现（Implemented） | 已取代（Superseded） |
| **规格 ID（Spec ID）** | S-<NNNN> |
| **文档版本（Document version）** | <x.y> |
| **日期（Date）** | <YYYY-MM-DD> |
| **负责人（Owner）** | <姓名> |
| **取代（Supersedes）** | <S-XXXX 或 —> |
| **被取代（Superseded by）** | <S-XXXX 或 —> |
| **范围（Scope）** | <一行说明> |
```

### 生命周期

```
草稿（Draft）→ 提议（Proposed）→ 已接受（Accepted）→ 已实现（Implemented）
→ （已废弃（Deprecated）| 已取代（Superseded））
```

- spec 一旦合入，**永不删除、永不重编号**。
- 若某 spec 的决策被替换，它变为**已取代**并指向替代者：
  `被取代（Superseded by）S-XXXX`；替代者在 `取代（Supersedes）` 中记录
  `S-XXXX`。
- 小的内容修正保留原 `S-NNNN`，递增 **文档版本** 并更新 **日期**；结构性变更
  则新建 spec。

### 一 spec 一主题

一份 spec 只覆盖**一个**子系统 / 功能 / 决策领域。不要把 spec 养成大杂烩——
初始版本 spec（S-0001）是指定的伞形文档：目标、架构、NFR 与需求注册表。其余
内容各自成文，按 ID 引用 S-0001（及其它 spec）。

### 引用方式

- 用 **ID**（如 `S-0001`、`S-XXXX`）引用 spec；需要精确时写作
  `S-0001 §5.3`（章节号）。不要在正文里写"见更新文档"这类表述。
- 需求 ID 按 spec 作用域命名：`S-XXXX-FR-1`（功能）、`S-XXXX-NFR-1`（非功能），
  从而在整个仓库内保持唯一。

## 索引

| ID | 标题 | 状态 | 日期 | 文件 |
|----|------|------|------|------|
| S-0001 | 初始版本规格说明 | 已实现 | 2026-08-14 | [0001-initial-version.md](0001-initial-version.md) |
| S-0002 | 基于火山引擎 API Key 的 Web Search 实现 | 已实现 | 2026-08-20 | [0002-web-search-via-volcano-api.md](0002-web-search-via-volcano-api.md) |
| S-0003 | 工程规范对齐（Agent Notes 模型 + dsk-poc 工具链） | 已实现 | 2026-08-20 | [0003-engineering-conventions.md](0003-engineering-conventions.md) |
