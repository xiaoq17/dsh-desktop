# Agent Notes（Agent 决策记录）

[English](README.md) | 中文

**Agent Note** 记录影响本仓库的决策或提案——即"为什么"与"我们放弃了什么"，
这些是代码和文档承载不了的部分。本文件定义记录的存放位置、何时撰写，以及
[文件格式](#文件格式)。约定镜像 [dsk-poc]，按本仓库规模缩水。

[dsk-poc]: https://github.com/deepseek-ai/dsk-poc

## 存放与命名

每条记录的**路径**编码了它的两个维度：`{lifecycle}/{class}/yyyy-mm-dd-topic-title.md`。

- **Lifecycle（生命周期，顶层目录）** 即状态，记录随状态变更在目录间移动：
  - **`proposed/`** —— 实现前待评审；尚未构建。
  - **`implemented/`** —— 决策已落地。保持文件与真实落地方案一致：后续代码
    移动、改名、改默认值时，在同一个变更里同步更新记录（只改事实，不改决策）。
  - **`rejected/`** —— 已考虑并否决。只有当其理由能阻止某个诱人且有意义的
    错误时才保留，否则连同中文版一起删除。
- **Class（分类，嵌套目录）** 是决策的种类：`feature`（功能）、`bug-fix`
  （缺陷修复）、`simplification`（简化）、`architecture`（交付源码的结构）、
  `process`（代码周边的工具/策略/流程）、`testing`（测试）。

文件名中的日期是主题**首次提出**的日期。记录间交叉引用使用相对 Markdown
链接，绝不用数字或纯文本。

## 何时撰写

**任何非平凡变更都必须在同一变更中新增或更新至少一条 Agent Note。** 非平凡
指变更触及行为、架构、契约、流程或工具、测试策略、磁盘/网络/配置格式，或
其他维护者可能重新审视的决策。大块未来工作在 `proposed/` 起步；已作出的决策
直接从 `implemented/` 起步。

更新已拥有该决策的记录即可满足规则——绝不重复。纯机械或局部、无行为变化的
改动可豁免。绝不把一条记录改写成另一个不同的决策：用新记录取代，并互相链接。

## 文件格式

由 `pnpm run doc:agent-notes`（`scripts/verify-agent-note-format.ts`，属
`doc-sync`）强制。前三行必须为：

```markdown
# Agent Note: <标题>

Status: <status>
```

后跟一个空行。`Status:` 取值 `proposed` / `implemented` /
`rejected — <一句话理由>`，且必须与生命周期目录一致。状态行不带日期和括号
——日期由文件名承载。

正文以 `## Problem` 开头（动机，脱离解决方案也站得住）。其后按生命周期：

- **`proposed/`**：`## Proposal`（可用将来时——计划与未决问题放这里）、
  `## Alternatives considered`、`## Acceptance criteria`、`## Risks`。
- **`implemented/`**：`## Decision`（已落地的事实，现在时，保持最新）、
  `## Alternatives considered`、`## Consequences`（权衡付出的代价**和**换来的
  收益）。提案期标题在此被拒绝：不得出现 `## Proposal`、`## Plan`、
  `## Migration plan`、`## Acceptance criteria`。
- **`rejected/`**：提案被冻结；裁决写在 `Status:` 行上。

**`## Alternatives considered`（备选方案）是强制项**——每个真实备选及其落败
原因，每项一段、以加粗开头。不记录被击败方案就记录的决策，会招致反复争议。

## 中文对照

每条记录都有结构一致的 `.zh.md` 镜像；机器校验的头部标记（`# Agent Note: `
与 `Status:` 行）保持英文原文。两份语言文件必须一起更新。

## 编辑本说明

Agent Notes 约定以本文件为家；根 `AGENTS.md` 把它作为代码变更门禁引用。
在此修改规则，并在同一变更中更新所有引用。
