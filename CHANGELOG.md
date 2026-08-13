# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

> **Version scheme** — the desktop version is four parts:
> `<dsh major>.<dsh minor>.<dsh patch>.<desktop rev>`. The first three always
> mirror the embedded `@deepseek-ai/dsh` version; the fourth is the desktop
> revision, starting at `0` and resetting on dsh upgrades.

## [Unreleased]

### Changed

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
