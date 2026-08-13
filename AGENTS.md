# AGENTS.md — 编码代理工作约定

> **本文件是 dsh-desktop 仓库对「编码代理 / AI 助手」的强约束。**
> 任何代理在本仓库修改代码前，**必须**先读本文件，并遵守「规格先行」约定。

## 铁律：规格先行（Spec-First）

**所有功能/行为性代码修改，必须先更新规格（spec），再修改代码。**

- 规格文档：`docs/specs/NNNN-<slug>.md`（见 `docs/specs/README.md` 的命名与
  生命周期规范；**一律中文撰写**，技术标识/路径/命令/需求 ID 保持英文）。
- 正确顺序：**先**在对应 spec 中新增/修订需求（FR/NFR、章节、流程图），递增
  **文档版本（Document version）** 并更新 **日期**，**然后**才实现代码，**同一
  次提交**里同时包含 spec 与代码。
- 没有现成 spec 覆盖该功能时：基于 `docs/specs/_template.md` 新建
  `NNNN-<slug>.md`，并在 `docs/specs/README.md` 索引登记。
- 引用方式：提交信息与代码注释中用 `S-NNNN`（精确时 `S-NNNN §x.y`）引用。

### 什么算"代码修改"（必须带 spec）

- `src/**`（Swift 应用逻辑）、`assets/**`（随 App 分发的模板/资源）、
- `scripts/**`（含 build.sh / make-dmg.sh / install.sh / publish-update.sh /
  dev-update.sh 等构建/发布脚本）、`.github/**`（CI）。

### 什么不算（无需 spec，但若影响行为请同样说明）

- 纯注释、拼写/排版、变量改名等**不影响行为**的改动——提交信息里注明即可。

### 其余配套

- 用户可见的改动同步更新 `README.md` 与 `CHANGELOG.md`。
- 与用户交流使用中文；技术标识/路径/命令保持原样。

## 提交前自查（必做）

1. 本次改动是否改了代码？→ 是，则确认同一次提交里**已有** `docs/specs/` 的
   对应修改（内容匹配，不是凑数）。
2. 文档版本是否已递增、日期是否已更新？
3. README / CHANGELOG 是否需同步？
4. 工作区里有没有本该一起提交却漏掉的文件？

## 钩子强制校验

仓库配有 pre-commit 钩子（`scripts/hooks/pre-commit`，经
`./scripts/install-hooks.sh` 安装到 `.git/hooks/`）：**改了代码却没改 spec 时，
`git commit` 会被拦截**，并提示补齐 spec。**遵守它，不要绕过。** 紧急情况才允许
`DSH_SPEC_SKIP=1` 或 `git commit --no-verify`，且事后必须补 spec。

## 本仓库其他硬约束

- 不自动 `git push` / 不自动发布 release / 不重装正在使用的 App——除非用户
  明确要求。
- 启动服务器/打包等长任务用后台任务管理；`dist/`、`build/` 为构建产物，不提交。
- **临时脚本规则**：临时/一次性脚本（图标迭代、一次性分析等）一律放 `build/`
  （gitignore，不提交），避免污染 git；只有需要随仓库版本化的基础设施脚本
  （钩子、CI、发布管线）才放 `scripts/`。
- **构建前置询问**：`scripts/build.sh` / `scripts/make-dmg.sh` /
  `scripts/dev-update.sh` / `scripts/publish-update.sh` 等构建/打包耗时长
  （通常 1–2 分钟以上），**动手前必须先询问用户**，得到确认后再用后台任务
  运行；不要擅自触发构建。
