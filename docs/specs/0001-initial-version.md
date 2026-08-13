# dsh-desktop — 初始版本规格说明

| | |
|---|---|
| **状态（Status）** | 已实现（Implemented） |
| **规格 ID（Spec ID）** | S-0001 |
| **文档版本（Document version）** | 1.20 |
| **日期（Date）** | 2026-08-14 |
| **负责人（Owner）** | Qin Xiao |
| **取代（Supersedes）** | — |
| **被取代（Superseded by）** | — |
| **范围（Scope）** | 桌面客户端的初始版本（当前版本 0.1.0.0） |

> 需求描述中的"必须（MUST）""不得（MUST NOT）""应当（SHOULD）""可以（MAY）"
> 遵循 [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) 语义。

---

## 1. 概述

dsh-desktop 是
[DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh) Web GUI 的原生
macOS 客户端。它在应用包内嵌 Node 运行时和完整的 `@deepseek-ai/dsh` 后端，
启动时自动拉起后端，并用 WKWebView 渲染 GUI —— 无需系统 Node、无需 `dsh` CLI、
无需 npx 缓存、也不依赖固定端口。

本文档规定了初始版本：架构、功能与非功能需求、自动更新管线、构建/打包、数据
处理以及已知限制。它是后续版本演进的基线。

## 2. 目标与非目标

### 2.1 目标

- **G-1** 自包含：应用零外部依赖即可运行。
- **G-2** 原生 macOS 体验：Swift + WKWebView，不使用 Electron。
- **G-3** 无端口冲突：运行时绑定随机空闲端口。
- **G-4** 生命周期健壮：服务器与应用进程同生共死（不留孤儿进程）。
- **G-5** 原地更新：检查、下载、校验、换包、重启 —— 无需手动重新下载。
- **G-6** 复用用户已有的 `~/.dsh` 配置/设置/会话。

### 2.2 非目标（初始版本）

- Windows / Linux 支持。
- CI 中构建 x86_64（Intel）产物。
- 代码签名 / 公证（当前仅 ad-hoc 签名）。
- 多窗口 / 标签页 GUI。
- 离线优先的文档编辑、语音交互或 MCP 集成（列入 §11 未来工作）。

## 3. 术语

| 术语 | 含义 |
|---|---|
| **应用 / 壳（app / shell）** | Swift + WKWebView 构成的 macOS 应用。 |
| **内嵌后端（Embedded backend）** | 运行在随包 Node 下的 `@deepseek-ai/dsh` 服务器。 |
| **DSH_HOME** | 存放 dsh 配置/设置/会话的目录（默认 `~/.dsh`）。 |
| **更新清单（Update manifest）** | 描述最新版本的 JSON，从配置的 URL 获取。 |
| **dsh-updater** | 负责替换应用包并重新启动的独立助手程序。 |
| **Profile（配置文件）** | `$DSH_HOME/profiles/<name>/`：Cordis 插件分层 bundle（`package.json` 声明 bundles + `cordis.patch.yml` 用户补丁层）；`web` 为上游 profile，`desktop` 为桌面自有 profile。 |
| **平台抽象（Platform abstraction）** | `src/Platform.swift`：集中平台标识、路径默认值与清单平台匹配，为未来跨平台壳提供单一扩展点。 |

## 4. 架构

```
┌────────────────────────────────────────────────────────────┐
│                     dsh-desktop.app                        │
│  ┌────────────────────────────────────────────────────┐    │
│  │  AppDelegate  (菜单、生命周期、启动时更新检查)      │    │
│  ├────────────────────────────────────────────────────┤    │
│  │  MainWindowController                              │    │
│  │    ├─ WKWebView (GUI) ──┐                          │    │
│  │    ├─ 恢复视图          │  加载 GUI 于              │    │
│  │    └─ 心跳监控          │  http://127.0.0.1:<port> │    │
│  ├────────────────────────────────────────────────────┤    │
│  │  ServerManager ── 拉起 ──► dsh --profile desktop   │    │
│  │        │                     │  从 stdout 解析端口  │    │
│  │        └── DSH_HOME (~/.dsh) ─┘                    │    │
│  ├────────────────────────────────────────────────────┤    │
│  │  UpdateManager ──► manifest URL ──► 下载 ──► SHA-256      │
│  │        └──► Contents/Helpers/dsh-updater (换包+重启)      │
│  └────────────────────────────────────────────────────┘    │
│  Contents/Resources: runtime/bin/node + dsh/node_modules     │
└────────────────────────────────────────────────────────────┘
```

### 4.1 组件

| 组件 | 文件 | 职责 |
|---|---|---|
| 应用壳 | `src/AppDelegate.swift` | `@main` 入口、菜单构建、启动时更新检查、退出时停止服务器。 |
| 窗口与 Web 视图 | `src/MainWindowController.swift`、`src/EditingWebView.swift` | 窗口创建、GUI 加载、恢复视图、心跳、编辑命令路由、外部链接处理。 |
| 服务器管理 | `src/ServerManager.swift` | 预置 desktop profile、启动内嵌后端（`--profile desktop`）、从 stdout 解析端口、探测可达性、停止进程树。 |
| 自动更新 | `src/UpdateManager.swift` | 拉取清单、版本比较、下载、校验和校验、安装交接。 |
| 平台抽象 | `src/Platform.swift` | 平台标识（`darwin`/`win32`）、`DSH_HOME` 默认路径、更新清单平台匹配；壳中平台相关逻辑的唯一集中点。 |
| 更新助手 | `src/UpdaterHelper.swift` | 独立可执行程序：等待应用退出 → 挂载 DMG → 替换包 → 重启。 |

### 4.2 平台边界与跨平台策略

- **壳（shell）与核心（core）**：核心 = 内嵌 Node 后端 + Web GUI + 更新协议 +
  版本方案（全部与 OS 无关）；壳 = 原生窗口/WebView、进程管理、换包重启。仅壳是
  平台相关的，且被刻意保持轻薄。
- **平台决策集中**：所有平台相关逻辑集中于 `src/Platform.swift`（平台标识、路径
  默认值、清单平台匹配），壳的其余逻辑保持 OS 无关——未来若迁移到跨平台壳
  （如 Tauri：Rust + 系统 WebView，macOS 用 WKWebView、Windows 用 WebView2），
  这是唯一需要镜像的扩展点。
- **协议先行**：更新清单在协议层即区分 `platform`/`arch`/`minOSVersion`；
  Windows 端可实现同一协议并复用下载/校验/清单概念，仅换包机制不同
  （macOS 为 helper 换包重启；Windows 因运行中的 exe 不可覆盖，需 MSIX 原子更新
  或"暂存 → 下次启动替换"）。
- **路径约定**：`DSH_HOME` 默认值由平台抽象提供（macOS `~/.dsh`；Windows 计划
  `%APPDATA%`）。
- **桌面 profile 扩展点**：应用以 `dsh --profile desktop` 启动，而非 `dsh web`；
  `desktop` profile（`$DSH_HOME/profiles/desktop/`）由应用首启时从 bundle 模板
  预置（FR-1.5），作为桌面侧独立迭代的官方扩展面——增删/配置任何插件、乃至替换
  UI 入口，均不改动上游 `web` profile 与 `dsh-web-app` 插件。

## 5. 功能需求

> **FR-x.y** 格式的标识在初始版本中保持稳定。

### 5.1 后端引导

- **FR-1.1** 应用启动时必须（MUST）以
  `node <bundle>/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js --profile desktop --host 127.0.0.1 --port 0`
  启动内嵌后端（`desktop` profile，见 §4.2）。
- **FR-1.2** 应用必须（MUST）从服务器 stdout（`http://127.0.0.1:<port>`）解析
  实际端口，且不得（MUST NOT）假定固定端口。
- **FR-1.3** 若环境中未设置 `DSH_HOME`，应用必须（MUST）默认使用 `~/.dsh`。
- **FR-1.4** 若运行时或 dsh 包缺失，应用必须（MUST）显示离线/恢复视图，而不是
  空白窗口；离线视图须（MUST）按变体给出针对性提示与动作：完整版提示"内嵌运行时
  缺失，请重新安装。"；light 变体（§8.5）提示"Light 版依赖系统的 dsh 与 node，
  当前未找到。请先安装：`npm install -g @deepseek-ai/dsh`，然后重试。"，并提供
  **复制安装命令**按钮（把 `npm install -g @deepseek-ai/dsh` 写入剪贴板，并在状态
  行提示到终端执行后用菜单重启）。
- **FR-1.5** 若 `$DSH_HOME/profiles/desktop` 不存在，应用必须（MUST）从随包模板
  `Contents/Resources/desktop-profile/` 预置该 profile（`package.json`、
  `cordis.yml`、`cordis.patch.yml`、`pnpm-workspace.yaml`），且不得（MUST NOT）
  覆盖已存在的用户层。

### 5.2 GUI 加载

- **FR-2.1** WKWebView 只能在服务器报告就绪（HTTP 可达性探测）后加载
  `http://127.0.0.1:<port>`。
- **FR-2.2** 窗口标题栏必须（MUST）显示应用名、版本与 git 提交号
  （完整版 `DeepSeek Harness Desktop v<version> (rev:<git>)`；light 变体
  `DeepSeek Harness Desktop Light v<version> (rev:<git>)`，见 §8.5；版本取
  `CFBundleShortVersionString`，`<git>` 取构建时嵌入 Info.plist 的
  `DSHGitRevision`（即 `git rev-parse --short HEAD`；非 git 环境回退为桌面修订号
  `CFBundleVersion`））；窗口不得（MUST NOT）在标题栏附加页面标题（页面
  `<title>` 与应用名重复，会产生 `- DeepSeek Harness` 冗余后缀）；离线等非加载
  状态可（MAY）在标题栏附加状态（如 `Server Offline`）。
- **FR-2.3** 应用必须（MUST）对 WKWebView 启用 Web Inspector
  （`preferences.developerExtrasEnabled`），以支持右键"检查元素"以及从 Safari
  Develop 菜单附加调试器，便于桌面 profile 与插件迭代。

### 5.3 服务器生命周期

- **FR-3.1** 退出应用必须（MUST）终止服务器进程树。
- **FR-3.2** 用户必须（MUST）能从 **Server** 菜单重启 / 停止服务器，并查看
  **Server Status**。
- **FR-3.3** 重启必须（MUST）拆除并重新拉起后端，重新探测端口。

### 5.4 心跳与恢复

- **FR-4.1** 当 GUI 显示期间，应用必须（MUST）以 2 秒间隔探测服务器可达性。
- **FR-4.2** 若服务器停止响应，应用必须（MUST）切换到带 **Restart Server**
  按钮的恢复视图。
- **FR-4.3** 服务器恢复后，应用必须（MUST）自动重新加载 GUI。

### 5.5 菜单与快捷键

- **FR-5.1** 应用必须（MUST）提供：关于、检查更新…、隐藏、退出；File → 在
  浏览器中打开（⌘B）；完整 Edit 菜单（⌘C/⌘X/⌘V/⌘A/⌘Z…）；View → 重新加载
  （⌘R）、全屏（⌘F）；Server → 重启/停止/状态；Window → 最小化/关闭。
- **FR-5.2** 标准编辑快捷键必须（MUST）路由进 Web 内容（WKWebView 无法可靠
  接收 AppKit 编辑动作；`selectAll` 通过 `document.execCommand` 路由）。

### 5.6 外部链接

- **FR-6.1** 会在新窗口打开的链接必须（MUST）改用用户的默认浏览器打开
  （通过 `NSWorkspace`）。

### 5.7 窗口状态

- **FR-7.1** 窗口大小/位置必须（MUST）在启动间被记住（自动保存键 `MainWindow`）。
- **FR-7.2** 默认尺寸 1280×820，最小 720×480。

### 5.8 日志

- **FR-8.1** 应用生命周期事件必须（MUST）写入
  `~/Library/Logs/dsh-desktop-app.log`。
- **FR-8.2** 内嵌服务器的 stdout/stderr 必须（MUST）写入
  `~/Library/Logs/dsh-desktop-server.log`。
- **FR-8.3** 更新助手必须（MUST）写入
  `~/Library/Logs/dsh-desktop-update.log`。

### 5.9 自动更新

- **FR-9.1** 应用启动时可以（MAY）静默检查更新，但最多每 24 小时一次，且必须
  （MUST）尊重用户的"跳过此版本"选择。
- **FR-9.2** 用户必须（MUST）能通过 **检查更新…** 手动检查。
- **FR-9.3** 存在新版本时，应用必须（MUST）先在**后台下载并校验**（不打断使用）；
  就绪后以**非阻塞**方式提醒（Dock 图标跳动一次 + 菜单项"重启并安装
  dsh-desktop …"亮起），仅当用户明确点按后才进入安装。手动检查时的**跳过此版本**
  选项保留。
- **FR-9.4** 提供安装选项前，下载必须（MUST）对照清单中的 `dmgSha256` 校验。
- **FR-9.5** 安装时，应用必须（MUST）拉起内嵌的 `dsh-updater` 助手后退出；助手
  必须（MUST）等待应用退出、挂载 DMG、替换应用包并重启新版本。
- **FR-9.6** 若未配置清单 URL，手动检查必须（MUST）提示未配置更新，静默检查
  必须（MUST）不执行任何操作。
- **FR-9.7** 若清单中 `platform` 存在且与当前平台不符，应用必须（MUST）将该更新
  视为不可安装（静默不动作；手动提示"当前平台无更新"）。
- **FR-9.8** 下载与安装必须（MUST）解耦：在用户点按"重启并安装…"之前，应用
  不得（MUST NOT）自行终止或重启；应用退出后再启动必须（MUST）恢复尚未应用的
  已暂存更新（持久化于 UserDefaults，见 §9）。
- **FR-9.9** 清单 URL 与 `dmgUrl` 必须（MUST）支持 `file://`（本地开发）：本地
  构建经 `dev-update.sh` 生成清单与 DMG 后，走与 GitHub 发布完全相同的"后台暂存
  → 提醒 → 点按更新"流程。

## 6. 非功能需求

- **NFR-1** *自包含*：应用包必须（MUST）包含 Node 及全部 dsh 生产依赖；启动
  无需网络访问。
- **NFR-2** *端口隔离*：应用不得（MUST NOT）依赖端口 3080 或任何固定端口。
- **NFR-3** *启动*：首次启动可能因后端引导需数秒；后续冷启动应当（SHOULD）
  与本地 Web 服务器相当。
- **NFR-4** *更新完整性*：更新必须（MUST）经校验和验证（CryptoKit 的
  SHA-256）；不得（MUST NOT）信任未认证的更新源。
- **NFR-5** *兼容性*：macOS 13.0+，Apple Silicon（arm64）。
- **NFR-6** *体积*：应用包约 460 MB（内嵌运行时 + dsh 依赖）；DMG 约 194 MB。
- **NFR-7** *隐私*：无分析、无遥测；除用户发起的更新检查和本地后端外，无其他
  网络调用。
- **NFR-8** *资源生命周期*：退出后不得（MUST NOT）残留孤儿服务器进程。
- **NFR-9** *品牌图标*：应用图标是**静态资产** `assets/AppIcon.icns`（深色
  圆角 tile 内嵌青色鲸鱼 logo，一次性制作后固化），构建时直接复制、**不再生成**
  （MUST NOT）；后续更换图标直接替换该静态资产即可。

## 7. 更新管线

### 7.1 清单结构

应用轮询 `DSHUpdateManifestURL`（解析顺序：UserDefaults 覆盖 → Info.plist 值 →
未配置）。清单格式：

```json
{
  "version": "0.1.0.0",
  "build": "458b452",
  "app": "dsh-desktop-light",
  "minOSVersion": "13.0",
  "arch": "arm64",
  "platform": "darwin",
  "dmgUrl": "https://github.com/xiaoq17/dsh-desktop/releases/download/v0.1.0.0/dsh-desktop-light-0.1.0.0-arm64.dmg",
  "dmgSha256": "<sha256>",
  "releaseNotes": "• 支持自动更新。"
}
```

`build` 为**构建来源的 git 短 revision**（`git rev-parse --short HEAD` 的短 SHA，
如 `458b452`），用于同版本串时的"是否新 build"判断（见 §7.2）；非 git 环境回退为
桌面修订号。

`app` 标识**目标变体**：`dsh-desktop`（完整版，缺省值，向后兼容）或
`dsh-desktop-light`（light 变体）。客户端以自身 `CFBundleIdentifier` 对应
`dsh-desktop` / `dsh-desktop-light` 与之比对，不匹配则不视为可安装（§7.3）——
使两个变体**独立升级**、互不误装（§8.5）。

`platform` 取值沿用 Node 的 `process.platform` 约定（`darwin`/`win32`/`linux`），
由发布脚本写入，可用 `DSH_PLATFORM` 覆盖。缺失或空值表示"任意平台"，向后兼容旧
清单；客户端在目标平台不匹配时，不将本次更新视为可安装（见 §7.3）。

`dmgUrl` 及清单 URL 本身均可为 `file://`（本地开发流程，见 §8.3 `dev-update.sh`）；
客户端对 `file://` 以文件复制代替网络下载，其余流程一致。

### 7.2 版本比较

- 以**版本串优先**：将 `version` 按点号分隔为数值段逐段比较；段数不同时缺失段
  按 0 处理，天然支持四位桌面版本。
- 版本串相同（`DSH_DESKTOP_REV` 相同）时，以 `build`（git 短 revision，如
  `458b452`）作次级比较：**只要与当前 build 不同即视为新 build**；`build` 缺失
  视为与当前相同（非更新）。
- 由此，dsh 升级（前三位变化）即使桌面修订归零，也必然判定为"有新版本"；
  桌面独占修复（第四位递增）在同一 dsh 版本下也能正确判定。

### 7.3 流程

```
检查 → 拉取清单（15s 超时；`file://` 直接读本地文件）
     → 平台不匹配？→（静默：不动作；手动："当前平台无更新"）
     → app 不匹配（清单 `app` ≠ 本变体）？→（静默：不动作；手动："该更新不适用于本应用"）
     → 无新版？否 →（静默：不动作；手动："已是最新"）
     → 是 → 已跳过此版本？→ 不动作
下载   → caches/com.deepseek.dsh.desktop/dsh-desktop-<v>.dmg（后台；`file://` 为复制）
校验   → SHA-256（CryptoKit）对照清单
就绪   → 设置 pendingUpdate 并持久化（UserDefaults）
       → 菜单"重启并安装 dsh-desktop v…"亮起 + Dock 图标跳动一次（不重启）
应用   → 用户点按"重启并安装…"→ 确认框
安装   → 拉起 Contents/Helpers/dsh-updater --app <bundle> --dmg <dmg> --pid <pid> --log <log>
      → NSApp.terminate
助手   → 等待 pid 退出（≤120s）→ hdiutil attach → 复制 .app → detach
       → 清除隔离属性 → open <bundle>
重启后 → restorePendingIfAny()：若上次已暂存但未应用，恢复提醒
```

### 7.4 默认清单 URL

- 完整版：
  `https://github.com/xiaoq17/dsh-desktop/releases/latest/download/update-manifest.json`
  —— 每次发布必须（MUST）附带一个恰好名为 `update-manifest.json` 的文件，以及带
  版本的 `.dmg`。
- Light 变体：同上但文件名（及 URL）为 `update-manifest-light.json`，构建时
  `DSH_LIGHT=1` 自动使用；同一 release 可同时附带两份清单与两个 DMG（§8.3）。

## 8. 构建、打包与发布

### 8.1 构建管线（`build.sh`）

> 默认构建**完整版** `dsh-desktop.app`（自包含）。`DSH_LIGHT=1` 构建轻量变体
> `dsh-desktop-light.app`（不打包 Node/dsh，复用本机完整版运行时，见 §8.5）；
> 其余步骤一致。

1. 复制静态图标 `assets/AppIcon.icns` 到 `Contents/Resources/`（NFR-9；
   构建不生成图标）。
2. 打包官方 Node 运行时（`v22.16.0`，darwin-arm64）——仅完整版。
3. 仅安装 `@deepseek-ai/dsh@0.1.0-rc.6` 的生产依赖——仅完整版。
4. 编译 Swift（`swiftc -O -target arm64-apple-macos13.0`）。
5. 编译独立的 `dsh-updater` 助手。
6. 组装应用包、设置版本（四位：dsh 三位 + 桌面修订，当前 0.1.0.0）、写入清单
   URL、ad-hoc 签名。
7. 复制 `assets/desktop-profile/` 模板到 `Contents/Resources/desktop-profile/`
   （首启时预置 `$DSH_HOME/profiles/desktop`，见 FR-1.5）。
8. 将 `git rev-parse --short HEAD` 写入 `Contents/Info.plist` 的
   `DSHGitRevision`（非 git 环境回退桌面修订号），供标题栏 `(rev:…)`
   使用（FR-2.2）。

### 8.2 打包（`make-dmg.sh`）

- 产出 `dist/dsh-desktop-<VERSION>-arm64.dmg`（UDZO，zlib level 9），文件名
  取自构建产物的 `CFBundleShortVersionString`。
- 自动识别 `dist/` 中**最新构建**的 `.app`（完整版或 light），也可用
  `APP_NAME=dsh-desktop-light` 显式指定；light 变体产出
  `dsh-desktop-light-<VERSION>-arm64.dmg`。

### 8.3 发布（`publish-update.sh` / `dev-update.sh`）

- `./publish-update.sh` —— 构建 + 打包 + 生成 `dist/update-manifest.json`。
  `DSH_LIGHT=1` 时构建 light 变体并生成 `update-manifest-light.json`
  （`app: dsh-desktop-light`）；`--both` 一次构建**两个变体**，同一 release
  附带两个 DMG 与两份清单（§7.4）。清单均含 `app` 字段标识目标变体。
- `./publish-update.sh --release` —— 额外创建 GitHub release（tag
  `v<VERSION>`）并通过 `gh` 或 `GITHUB_TOKEN` 上传 DMG 与清单。
- `./dev-update.sh` —— 本地开发：构建 + 打包 + 生成 `dist/dev-update.json`
  （`file://` 清单），配合
  `defaults write com.deepseek.dsh.desktop DSHUpdateManifestURL "file://…/dist/dev-update.json"`
  让运行中的应用走与 GitHub 发布完全相同的更新流程（FR-9.9）。
  `DSH_LIGHT=1` 时构建 light 变体、生成 `dist/dev-update-light.json`
  （`app: dsh-desktop-light`），并提示
  `defaults write com.deepseek.dsh.desktop.light DSHUpdateManifestURL "file://…/dist/dev-update-light.json"`
  实现 light 的**独立本地升级**。桌面修订由 build.sh 从 git 历史**最近
  release-tag** 回溯（无 tag 为 0，见 §8.4），清单 `build` 取
  `git rev-parse --short HEAD`（git 短 revision），使每次本地构建（即便 squash
  后 revision 变化）都能被检测为更新而无需改动可见版本。

### 8.4 版本管理

- 桌面版本为**四位**：`<dsh主>.<dsh次>.<dsh补丁>.<桌面修订>`。
  - 前三位**始终跟随**内嵌 `@deepseek-ai/dsh` 版本：构建时从该包 package.json
    派生并去除预发布后缀（如 `0.1.0-rc.6` → `0.1.0`）。
  - 第四位为**桌面修订号，从 0 开始**：桌面独占修复时递增；dsh 升级时归零。
  - `CFBundleShortVersionString` ↔ 完整四位版本；`CFBundleVersion`（build）↔
    构建来源的 git 短 revision（`git rev-parse --short HEAD`，非 git 环境回退
    桌面修订号）。
- 修订号在构建时以 `DSH_DESKTOP_REV` 覆盖；未覆盖时**回溯 git 历史中最近一个
  release-tag**（`v<dsh>.<dsh>.<dsh>.<rev>` 的第四位），使发布后的构建沿用该
  发布的桌面修订，直到切新发布；没有任何 release-tag 才为 0。前三位由构建
  自动派生，无需手动同步。
- 更新比较**以完整四位版本串优先**（`build` 号仅作同版本时的次级比较），从而在
  dsh 升级、桌面修订归零时仍能正确判定"有新版本"。
- 版本串相同（`DSH_DESKTOP_REV` 相同）时，`build`（git 短 revision）只要与当前
  不同即视为**新 build**——因此本地开发（`dev-update.sh`）每次构建的 revision
  变化即可被检测为更新，无需改动可见版本（§8.3、FR-9.9）。

### 8.5 Light 变体（`dsh-desktop-light`）

`DSH_LIGHT=1 ./build.sh` 构建一个**代码完全一致**的轻量变体
`dsh-desktop-light.app`：

- **不打包** Node 运行时与 `@deepseek-ai/dsh`（包更小、构建更快）；其余
  代码、图标、桌面 profile 模板、自动更新机制与完整版完全相同。
- 运行时**只依赖本机系统的 `dsh` CLI 与 `node`**（无完整版兜底）：
  `node` 按序解析 `$DSH_NODE`（环境变量）→ `UserDefaults DSHNodePath` →
  PATH 上的 `node` → 常见路径（`/opt/homebrew/bin`、`/usr/local/bin`、
  `/usr/bin`）；`dsh` 按序解析 `$DSH_DSH` → `UserDefaults DSHDSHPath` →
  PATH 上的 `dsh` → 常见路径（`/opt/homebrew/bin`、`/usr/local/bin`）。
  任一缺失则运行时不可用，进入离线态并提示安装系统 dsh
  （`npm install -g @deepseek-ai/dsh`）与 node（§8.1 守卫同理，完整版优先用
  bundle 内资源）。
- 版本号：前三位从**本机系统 dsh** 的 `package.json` 派生（经 `$DSH_DSH` 或
  `command -v dsh` 解析，再回退仓库 `build/dsh`）；第四位与 `build`（git rev）
  规则同完整版（§8.4）。
- Bundle ID 为 `com.deepseek.dsh.desktop.light`（独立 defaults/日志），
  `CFBundleDisplayName`/`CFBundleName`/`CFBundleExecutable` 相应为
  `dsh-desktop-light` / `DSHDesktopLight`，与完整版互不干扰。
- 打包：`DSH_LIGHT=1 ./make-dmg.sh`（或 `APP_NAME=dsh-desktop-light`）产出
  `dsh-desktop-light-<VERSION>-arm64.dmg`（§8.2）。
- **可独立升级**：清单含 `app: dsh-desktop-light`，默认清单 URL 为
  `update-manifest-light.json`（§7.4）；本地开发用 `DSH_LIGHT=1 ./dev-update.sh`
  生成 `dev-update-light.json`（§8.3）。`UpdateManager` 以 `app` 字段做变体校验
  （§7.3），`dsh-updater` 按 **bundle id 匹配** DMG 内 `.app` 再换包，杜绝跨
  变体误装；两个变体各自的 defaults（清单 URL / skip / pending）完全独立，
  `build` 相同互不影响。

## 9. 数据与状态

| 数据 | 位置 | 说明 |
|---|---|---|
| 窗口位置 | UserDefaults 自动保存 `MainWindow` | `setFrameAutosaveName` |
| 更新检查时间戳 | `UserDefaults` `DSHLastAutoCheckDate` | 限制静默检查（24h） |
| 跳过的版本 | `UserDefaults` `DSHSkippedUpdateVersion` | 在新版本出现前一直生效 |
| 待应用的更新 | `UserDefaults` `DSHPendingUpdateVersion` / `DSHPendingUpdatePath` | 暂存成功后写入；重启后 `restorePendingIfAny()` 恢复提醒 |
| 清单 URL 覆盖 | `UserDefaults` `DSHUpdateManifestURL` | 覆盖 Info.plist 值 |
| 已下载的 DMG | `~/Library/Caches/com.deepseek.dsh.desktop/dsh-desktop-<v>.dmg` | 校验后保留至用户点按应用 |
| 日志 | `~/Library/Logs/dsh-desktop-*.log` | 应用 / 服务器 / 更新 |
| 配置/会话 | `~/.dsh`（`DSH_HOME`） | 由内嵌后端持有 |
| Desktop profile | `$DSH_HOME/profiles/desktop/` | 桌面自有 Cordis 配置层（首启从 bundle 模板预置，用户层不被覆盖） |

## 10. 安全考量

- **S-1** 内嵌服务器仅绑定 `127.0.0.1`。
- **S-2** 更新下载对照 `dmgSha256` 校验；不一致必须（MUST）中止并丢弃下载。
- **S-3** 发布产物为 ad-hoc 签名 DMG；更新助手会清除隔离属性。**这对公开分发
  不够** —— 面向大众分发必须以 Developer ID 签名 + 公证为前提
  （见 SECURITY.md）。
- **S-4** 壳层不存储任何凭据或令牌；后端的认证状态存放于 `~/.dsh`。
- **S-5** 更新流程在校验和通过前不执行任何代码，且唯一"可信"来源是配置的清单
  URL。

## 11. 已知限制

- 仅 arm64，未构建 x86_64。
- ad-hoc 签名 —— 下载版可能触发 Gatekeeper 提示；暂不适合大规模公开分发。
- 全量 DMG 更新（每次约 194 MB）；无增量/差分更新。
- 更新检查需要网络；离线用户会看到"无法连接"。
- 内嵌后端版本固定在 `@deepseek-ai/dsh@0.1.0-rc.6`，直至更新 `build.sh`。

## 12. 未来工作（候选）

- MCP 客户端支持（让 agent 挂接外部工具/服务器）。
- Developer ID 签名 + 公证 + hardened runtime。
- CI 驱动的发布（tag → 构建 → 发布）。
- x86_64（通用二进制）构建。
- 增量更新 / 更小的更新载荷。
- 更深的 macOS 集成（全局快捷键、Dock 菜单、拖拽、菜单栏常驻、通知）。
- 本地/离线能力（文档处理、知识库）。
- 跨平台壳迁移（候选 Tauri：Rust + 系统 WebView 双平台；扩展点见 §4.2）。

## 13. 附录

### A. 仓库布局（受版本控制）

```
src/                    Swift 源码
  AppDelegate.swift       应用生命周期、主菜单、@main 入口
  MainWindowController.swift  WKWebView 窗口、恢复视图、心跳监控
  EditingWebView.swift     编辑命令路由进 Web 内容
  ServerManager.swift      内嵌服务器启动/停止/端口探测
  UpdateManager.swift      自动更新编排
  Platform.swift            平台抽象（标识/路径/清单平台匹配）
  UpdaterHelper.swift      独立换包助手
  Info.plist               bundle 元数据
build.sh / make-dmg.sh / install.sh / publish-update.sh
gen-icon.swift            程序化图标生成器（不再由 build.sh 调用，保留历史）
scripts/                  辅助脚本（install-hooks.sh / hooks/pre-commit）
assets/
  AppIcon.icns            应用图标（静态资产，取自参考图内圈鲸鱼图形，NFR-9）
  desktop-profile/        桌面 profile 模板（package.json / cordis.yml / cordis.patch.yml / pnpm-workspace.yaml）
docs/specs/               spec 文档（本文件为 S-0001）
docs/app.png              截图
```

### B. 菜单映射

```
dsh-desktop
  关于 dsh-desktop
  检查更新…
  隐藏（⌘H）/ 退出（⌘Q）
File          在浏览器中打开（⌘B）
Edit          撤销（⌘Z）重做（⇧⌘Z）剪切 拷贝 粘贴 粘贴并匹配样式 删除 全选
View          重新加载（⌘R）进入全屏（⌘F）
Server        重启服务器 / 停止服务器 / 服务器状态…
Window        最小化（⌘M）关闭（⌘W）
```

### C. 需求可追溯性

| 需求 | 实现位置 |
|---|---|
| FR-1.x | `ServerManager.swift` |
| FR-2.x | `MainWindowController.swift` |
| FR-3.x、FR-4.x | `MainWindowController.swift`、`ServerManager.swift` |
| FR-5.x | `AppDelegate.swift`、`EditingWebView.swift` |
| FR-6.x、FR-7.x | `MainWindowController.swift` |
| FR-8.x | `ServerManager.swift`、`AppDelegate.swift`、`UpdaterHelper.swift` |
| FR-9.x | `UpdateManager.swift`、`UpdaterHelper.swift`、`AppDelegate.swift` |
| 构建/发布 | `build.sh`、`make-dmg.sh`、`publish-update.sh` |
