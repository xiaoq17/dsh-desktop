# Spec（规格文档）

dsh-desktop 的规格文档。每份 spec 都存放在本目录，按下面的命名
规范编写、统一编号。

> **本仓库的 spec 一律使用中文撰写**（技术标识、路径、命令、需求 ID 等保持
> 英文/代码原样）。

## 规格先行（Spec-First）

**这是本仓库对代码修改的强约定（详见 [`AGENTS.md`](../../AGENTS.md)）：任何
功能/行为性代码修改，必须先更新 spec，再修改代码，且与代码放同一次提交。**

- 顺序：**先**在对应 spec 中新增/修订需求（FR/NFR、章节、流程图）并递增
  **文档版本**、更新 **日期**，**然后**才实现代码。
- 覆盖范围：`src/`、`assets/`、`scripts/`、`.github/`、顶层 `*.sh`、
  `gen-icon.swift` 等——凡影响应用行为/构建/发布的改动都算。
- 没有现成 spec 覆盖时：基于 [`_template.md`](_template.md) 新建
  `NNNN-<slug>.md` 并在下方索引登记。
- 机械校验：pre-commit 钩子（`scripts/hooks/pre-commit`）在「改了代码却没改
  spec」时拦截提交，提示补齐（紧急绕过：`[spec-skip]` / `DSH_SPEC_SKIP=1` /
  `--no-verify`）。

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

- 用 **ID**（`S-0002`）引用 spec；需要精确时写作 `S-0002 §5.3`（章节号）。
  不要在正文里写"见更新文档"这类表述。
- 需求 ID 按 spec 作用域命名：`S-0002-FR-1`（功能）、`S-0002-NFR-1`（非功能），
  从而在整个仓库内保持唯一。

### 索引

维护本文件（`docs/specs/README.md`）中的表格：

| ID | 标题 | 状态 | 日期 | 文件 |
|----|------|------|------|------|
| S-0001 | 初始版本规格说明 | 已实现 | 2026-08-14 | [0001-initial-version.md](0001-initial-version.md) |

## 索引

| ID | 标题 | 状态 | 日期 | 文件 |
|----|------|------|------|------|
| S-0001 | 初始版本规格说明 | 已实现 | 2026-08-14 | [0001-initial-version.md](0001-initial-version.md) |
