# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

> **Version scheme** — the desktop version is four parts:
> `<dsh major>.<dsh minor>.<dsh patch>.<desktop rev>`. The first three always
> mirror the embedded `@deepseek-ai/dsh` version; the fourth is the desktop
> revision, starting at `0` and resetting on dsh upgrades.

## [Unreleased]

### Fixed

- **更新弹窗文案匹配变体**（spec S-0001 FR-9.14）：`UpdateManager` 的用户可见
  文案（有可用更新 / 已是最新 / 重启并安装 / 下载 / 准备）由硬编码 `dsh-desktop`
  改为 `currentProductName`——light 变体现正确显示 `dsh-desktop-light`，不再两个
  版本都显示 `dsh-desktop`。
- **更新进度 UI 崩溃**（spec S-0001 FR-9.13 / T-6）：`UpdateManager.showProgress`
  对窗口调用 `beginSheet`（模态 sheet）会经
  `_beginWindowBlockingModalSessionForSheet:` 抛 NSException（SIGABRT）——
  对**不可见/最小化/非活动空间**窗口会崩，且对**可见**窗口在真实运行中同样复现
  （已安装的修复版 6754559 仍在更新验证阶段崩溃）；现**彻底移除 sheet**，进度
  一律用 `makeKeyAndOrderFront` 独立窗口呈现，无模态会话、从根上消除崩溃。
- **manifest 生成 JSON 转义**（spec S-0001 §8.3）：`scripts/publish-update.sh`
  与 `scripts/dev-update.sh` 写清单时对字符串字段做 RFC 8259 转义
  （`json_escape()`），修复 `DSH_RELEASE_NOTES` 含换行/引号/反斜杠时产出
  非法 JSON、客户端 `JSONSerialization` 无法解析的问题。
- **同版本不同 build 的更新不再被吞掉**（spec S-0001 §7.2 次级比较此前只在
  `isNewer` 生效，管线其余环节仍按版本串单独判定，导致同版本、rev 不同的新发布
  检测不到）：
  - `restorePendingIfAny` 重启恢复改为 `version`+`build` 判定——版本相同但 build
    不同（桌面修订未递增的新构建）也恢复"重启并安装"提醒，不再被静默丢弃；
  - "跳过此版本"改为以 `version@build` 复合键存储/匹配（兼容旧的纯版本键）——
    跳过某一 build 不再屏蔽同版本串的后续新 build；
  - "已暂存 & 待应用同版本"判定加入 build 比对——同版本不同 build 的新更新照常
    进入下载/暂存流程；
  - 暂存持久化新增 `DSHPendingUpdateBuild`，供重启恢复与"是否已暂存"判断使用。
- **更新相关文案展示 build rev**（spec S-0001 FR-9.10）：手动检查的"有可用更新"
  提示、安装确认框、以及"重启并安装 dsh-desktop …"菜单项均显示
  `v<version> (rev:<git>)`，同版本不同 rev 的新构建在界面上直观可辨；"已是最新"
  同时显示当前版本与 rev。
- **旧版纯版本 skip 值不再吞掉同版本新 build**（spec S-0001 §7.2）：旧版遗留的
  `DSHSkippedUpdateVersion` 裸版本串（如 `0.1.0.0`，不含 `@`）此前被当作整版本
  通配符，会屏蔽同版本串、rev 不同的新发布；现改为遇到**同版本**携带 `build` 的
  清单时丢弃该旧值，仅对不携带 `build` 的旧格式清单按原"跳过此版本"语义生效。
- **dev-update 安装后自动回归默认清单**（spec S-0001 FR-9.11）：当更新来自本地
  `file://` dev 清单（`dev-update.sh`）时，`dsh-updater` 换包成功后自动清除
  `DSHUpdateManifestURL` 覆盖，使应用回归嵌入的默认（GitHub）清单 URL；非
  `file://` 的用户自定义覆盖不受影响。

### Changed

- **spec 合并：S-0002 并入 S-0001**（docs）：脚本目录整理（scripts/ 归置与
  `gen-icon.swift` 移除）决策并入 S-0001 §8.7，删除 `0002-scripts-reorg.md` 并从
  spec 索引移除；需求引用统一改指 S-0001 §8.7。

- **dev-update 自动指向本地清单**（spec S-0001 FR-9.12）：`scripts/dev-update.sh`
  生成 `file://` 清单后自动写入目标 bundle 的 `DSHUpdateManifestURL`（full/light
  按变体），不再需要手动 `defaults write`；本地更新安装后仍由 `dsh-updater`
  自动清除覆盖、回归默认 GitHub 清单（FR-9.11）。
- **脚本整理进 `scripts/`**（spec S-0001 §8.7，原 S-0002）：顶层 `build.sh`、
  `make-dmg.sh`、`install.sh`、`publish-update.sh`、`dev-update.sh` 统一移入
  `scripts/`（调用方式改为 `./scripts/build.sh` 等）；删除停用的 `gen-icon.swift`。
  CI、pre-commit 钩子、README / CONTRIBUTING / SECURITY / AGENTS.md 与 spec 文档
  中的命令引用同步更新，构建/发布行为不变。
- **内嵌后端子进程继承用户登录 shell 的 PATH**（spec S-0001 FR-1.6 / NFR-10）：
  macOS GUI app 经 launchd 启动时 PATH 只有系统目录，导致 bash 工具无法直接调用
  brew / 用户级命令（如 `gh`）。现由 `ServerManager` 启动后端前用登录 shell
  （`zsh -l` / `bash -l`，每 shell 3s 超时）探测真实 PATH 并注入守护进程环境；
  仅取唯一标记行的内容，登录脚本 stdout 杂讯不污染结果；不硬编码机器路径，失败
  时回退继承值。
- **Independent upgrades for full & light**: the manifest now carries an `app`
  field (`dsh-desktop` / `dsh-desktop-light`) that the client validates against
  its own bundle id, and `dsh-updater` picks the DMG's `.app` by **bundle-id
  match** before swapping — the two variants upgrade independently and can never
  install each other's bundle even with the same version/build. Light gets its
  own manifest asset (`update-manifest-light.json`) and default URL; `dev-update.sh`
  (`DSH_LIGHT=1`) and `publish-update.sh` (`--both`) produce light manifests too
  (spec S-0001 §7.1 / §7.3 / §7.4 / §8.3 / §8.5).
- Update detection: the manifest `build` now carries the build source's **git
  short revision**; when the four-part version is equal, any *different* build
  counts as a new build. The desktop revision is derived from the **most recent
  release tag** (`v<version>`'s 4th part, `0` when none exists) instead of being
  hardcoded, so every fresh build is picked up as an update without bumping the
  visible version (spec S-0001 §7.2 / §8.3 / §8.4).
- App icon is now a **static asset** `assets/AppIcon.icns` — a dark rounded
  tile with the cyan whale — and the build simply copies it into the bundle
  (it no longer generates an icon) (spec S-0001 NFR-9).
- Window title shows the git revision too:
  `DeepSeek Harness Desktop v0.1.0.0 (rev:<short-sha>)` — the embedded
  `git rev-parse --short HEAD` (falls back to the desktop rev outside a git
  checkout); the **light variant** titles itself `DeepSeek Harness Desktop
  Light v…` (spec S-0001 FR-2.2).
- Offline view for a missing runtime is now variant-specific (spec S-0001
  FR-1.4): the full build says "内嵌运行时缺失，请重新安装。"; the light build
  explains it needs a system dsh + node and offers a **复制安装命令** button that
  copies `npm install -g @deepseek-ai/dsh` to the pasteboard.

### Added

- **Light variant** `dsh-desktop-light` (`DSH_LIGHT=1 ./build.sh`): identical
  code but no bundled Node / `@deepseek-ai/dsh` — at runtime it depends **only
  on the system `dsh` CLI + `node`** (smaller package, faster build; no
  dependency on the full app). `node`/`dsh` resolve via `$DSH_NODE`/`$DSH_DSH`
  env → UserDefaults `DSHNodePath`/`DSHDSHPath` → PATH → common locations.
  `make-dmg.sh` auto-detects the newest built app (spec S-0001 §8.5).
- Desktop boots its own **`desktop` Cordis profile** (`dsh --profile desktop`)
  instead of `dsh web`, seeded into `$DSH_HOME/profiles/desktop/` from a bundled
  template on first launch — the desktop iterates its plugins/config
  independently of the upstream `web` profile and `@deepseek-ai/dsh-web-app`
  (spec S-0001 FR-1.5).
- **Non-interrupting update flow**: checking/downloading/verifying now run fully
  in the background and never restart the app on their own. A verified update is
  *staged* and surfaced as a non-blocking reminder — the **Restart to Install
  dsh-desktop …** menu item lights up and the Dock icon bounces once — and is
  applied only when the user clicks it. Staged updates persist across restarts.
- **Local-development updates**: `DSHUpdateManifestURL` / `dmgUrl` accept
  `file://`, and `dev-update.sh` produces a local manifest + DMG so a freshly
  built version flows through the same stage → remind → apply pipeline as a
  GitHub release.
- **Update 纯逻辑提取与单元测试**（spec S-0001 §8.6 T-1/T-2/T-5）：更新策略的
  纯逻辑（四段版本比较、skip/pending 键、manifest 平台/变体适配、newer 判定、
  pending 恢复判定、`rev:` 文案）从 `UpdateManager` 提取到 Foundation-only 的
  `src/UpdatePolicy.swift`，并以 `tests/UpdatePolicyTests.swift`（42 个断言）
  覆盖；`scripts/run-tests.sh` 本地运行，CI 新增 `test` job 执行。
  附带修正一处真实缺陷：版本比较现先剥离 `-rc` 预发布后缀再按点分比较，
  `1.0.0.0-rc.6` 与 `1.0.0.0` 视为同版本。
- **CI 产物级 smoke validation**（spec S-0001 §8.6 T-4）：`scripts/smoke-check.sh`
  在 CI 构建后校验 `Info.plist` 关键字段（版本/build/git rev/标识/可执行名）、
  helper 可执行文件、release manifest 字段完整性、DMG 存在；full / light 双变体
  各跑一次。
- **CI 构建矩阵改用 `publish-update.sh`**：full 与 light 各构建一次并生成
  release manifest，替代原先仅 full 的手工 build+DMG，使产物校验覆盖双变体。
- **仓库 hygiene**：`.gitignore` 补充 `.AppleDouble` / `Icon?` / `._*` /
  `Desktop.ini` 等 Finder/系统垃圾文件规则（`scripts/.DS_Store` 早已不在仓库）。

## [0.1.0.0] - 2026-08-14

### Added

- Native macOS desktop client for the DeepSeek Harness Web GUI (Swift + WKWebView, no Electron).
- Fully self-contained: bundles its own Node runtime and the `@deepseek-ai/dsh` backend — nothing to install or configure.
- Embedded server on a random free port (`--port 0`), heartbeat monitor with recovery view and one-click restart.
- Menus (Reload / Open in Browser / Server controls), external links open in the default browser, window size & position memory.
- **Auto-update** — checks on launch (≤ 1/day, honours "Skip This Version") and on demand via **dsh-desktop ▸ Check for Updates…**; downloads + SHA-256 verifies the update DMG, then swaps the app bundle in place via the embedded `dsh-updater` helper and relaunches.
- `publish-update.sh` — one command to build, package, checksum and publish a release (GitHub Releases via `gh` or `GITHUB_TOKEN`).
- One-click installers: DMG, `install.sh`, `make-dmg.sh`.
- Four-part desktop versioning derived from the embedded dsh version (see note above).
