# dsh-desktop — 内嵌后端 PATH 探测（shell-path）

| | |
|---|---|
| **状态（Status）** | 已实现（Implemented） |
| **规格 ID（Spec ID）** | S-0002 |
| **文档版本（Document version）** | 0.1 |
| **日期（Date）** | 2026-08-14 |
| **负责人（Owner）** | Qin Xiao |
| **取代（Supersedes）** | — |
| **被取代（Superseded by）** | — |
| **范围（Scope）** | 内嵌 dsh 后端及其 bash 工具子进程的 `PATH` 环境：让代理的 shell 工具能直接调用 brew / 用户级命令（如 `gh`），不硬编码路径 |

> 需求描述中的"必须（MUST）""不得（MUST NOT）""应当（SHOULD）""可以（MAY）"
> 遵循 [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) 语义。

---

## 1. 概述

dsh-desktop 是 macOS GUI 应用，经 launchd / LaunchServices 启动时继承的
`PATH` 是精简的系统目录（`/usr/bin:/bin:/usr/sbin:/sbin`）。内嵌 dsh 守护进程
（`dsh --profile desktop`，见 S-0001 §4.2 / §8.5）由 `ServerManager.startServer`
启动，其环境继承自应用进程；由守护进程派生的 bash 工具子进程同样继承这一精简
`PATH`，导致会话内**无法直接**调用 `/opt/homebrew/bin`（brew，如 `gh`）或
`~/.local/bin` 等用户级命令，每次都要写绝对路径或手动拼 PATH。

## 2. 背景与目标

### 2.1 背景

- 应用进程本身的 `PATH` 无法通过 `launchctl setenv` 修复（macOS 15.x 实测：
  从 Dock / LaunchServices 启动的 GUI app 不再自动继承用户域环境变量）。
- 守护进程启动参数（node / dsh 路径）均为绝对路径，与 `PATH` 无关——问题
  仅影响**代理的 shell 工具**体验。

### 2.2 目标

- 内嵌 dsh 守护进程及其 bash 工具子进程的 `PATH` 必须（MUST）包含用户登录
  shell 的真实 `PATH`（含 brew 前缀、`~/.local/bin` 等用户级目录）。
- 不得（MUST NOT）硬编码任何机器相关的路径（如固定 `/opt/homebrew/bin`）。

### 2.3 非目标

- 不修改应用进程自身的 `PATH`（`LSEnvironment` 构建期注入**不采用**：它固化
  的是构建机的路径，无法覆盖用户机的 brew 前缀 / `~/.local/bin`）。
- 不解决与 node / dsh 无关的启动问题。

## 3. 设计 / 规格

### 3.1 运行时探测

`ServerManager.startServer` 在组装守护进程环境（S-0001 §4.2）时，先探测用户
**登录 shell** 的 `PATH`：

1. 依次尝试 `/bin/zsh -l -c 'echo $PATH'`、`/bin/bash -l -c 'echo $PATH'`；
2. 取第一个成功（退出码 0 且输出非空）的结果；
3. 若全部失败，回退为当前进程环境已有的 `PATH`（继承行为，不额外兜底）。

探测在 `startServer` 内**同步**完成一次（超时约 5s，避免用户 shell 启动配置
（如 `.zprofile`）卡住时阻塞启动流程；超时视为探测失败并回退）。

### 3.2 注入

将探测得到的 `PATH` 写入传给守护进程的 `environment["PATH"]`；`DSH_HOME` 等
其余环境处理保持不变（S-0001 §4.2）。

### 3.3 流程

```
startServer → 探测登录 shell PATH（zsh→bash，5s 超时）
    → 成功？ → 是 → environment["PATH"] = 探测结果
    → 成功？ → 否 → 保留继承的 PATH（回退）
    → 启动 dsh --profile desktop（其余逻辑不变）
```

## 4. 需求

### 4.1 功能需求

| ID | 需求 | 状态 |
|----|------|------|
| S-0002-FR-1 | 守护进程环境中的 `PATH` 必须（MUST）优先使用用户登录 shell 的 `PATH` | 已实现 |
| S-0002-FR-2 | 探测必须（MUST）不硬编码机器路径，通过登录 shell 获得 | 已实现 |
| S-0002-FR-3 | 探测失败时，必须（MUST）回退为继承的 `PATH`，不得阻止服务器启动 | 已实现 |

### 4.2 非功能需求

| ID | 需求 | 状态 |
|----|------|------|
| S-0002-NFR-1 | 探测超时应当（SHOULD）≤ 5s，避免阻塞启动 | 已实现 |
| S-0002-NFR-2 | 探测不应（SHOULD NOT）对应用自身环境产生副作用（只影响守护进程子进程） | 已实现 |

## 5. 待决问题

- 无。

## 6. 参考资料

- [Issue #2](https://github.com/xiaoq17/dsh-desktop/issues/2)（本功能的来源）
- S-0001 §4.2（内嵌后端启动）、S-0001 §8.5（light 变体）
