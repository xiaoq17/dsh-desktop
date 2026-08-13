# Contributing to dsh-desktop

Thanks for your interest! This project is small, native and fully self-contained,
so please keep contributions focused and low-friction.

## Spec-first（规格先行）—— 强约定

**任何代码修改都必须先更新 spec，再修改代码**（见 [`AGENTS.md`](AGENTS.md) 与
[`docs/specs/README.md`](docs/specs/README.md)）：

- 先改 `docs/specs/NNNN-*.md`：新增/修订需求（FR/NFR、章节、流程图），递增
  **文档版本**、更新日期；然后实现代码，**同一提交**里带上 spec。
- 改动 `src/`、`assets/`、`scripts/`（含 build / make-dmg / install /
  publish-update / dev-update 等脚本）、`.github/` 等（影响行为/
  构建/发布）而未改 spec 时，pre-commit 钩子会**拦截提交**并提示补齐。
- 安装钩子：`./scripts/install-hooks.sh`（一次即可，克隆后重装）。

## Getting started

1. **Fork** the repo and clone your fork.
2. **Check the environment**: macOS 13+ (Apple Silicon), with the Xcode command
   line tools installed (`xcode-select --install`).
3. **Build**:
   ```bash
   ./scripts/build.sh      # compiles Swift, assembles dist/dsh-desktop.app
   ./scripts/make-dmg.sh   # packages dist/dsh-desktop-<version>-arm64.dmg
   ```
   `scripts/build.sh` downloads the official Node runtime and installs
   `@deepseek-ai/dsh` on first run — subsequent builds reuse the cache under
   `build/`.

## What to work on

- Clear, scoped bug fixes and small features are always welcome.
- Larger changes (e.g. a rewrite of the update pipeline) should be discussed in
  an issue first so we agree on the direction before you invest the time.

## Before opening a PR

- Keep the diff focused on one concern; split unrelated changes into separate PRs.
- Run the checks that CI runs locally:
  ```bash
  bash -n scripts/build.sh scripts/make-dmg.sh scripts/install.sh scripts/publish-update.sh   # shell syntax
  ```
  and make sure the Swift sources compile (CI type-checks them).
- Update the **README** and **CHANGELOG.md** if the change affects users.
- Follow the existing style: 4-space indents in Swift, 2-space in shell
  scripts, LF line endings (see `.editorconfig`).

## Commit messages

Write clear, imperative commit messages:

```
Add X to support Y

Explain why and what, in a few sentences if non-trivial.
```

## PR checklist

- [ ] `bash -n` passes on all shell scripts I touched
- [ ] Swift sources compile for `arm64-apple-macos13.0`
- [ ] **Spec updated FIRST** (same commit) for any code change; Document version bumped
- [ ] README / CHANGELOG updated where relevant
- [ ] No generated artifacts (`build/`, `dist/`, `*.dmg`) committed

## Releases

Maintainers cut releases with:

```bash
./scripts/publish-update.sh --release
```

which builds, checksums and uploads the DMG + update manifest to GitHub
Releases. Regular contributors don't need to worry about this.

## Adding or changing a spec

Specs follow the RFC/ADR-style convention in `docs/specs/` — see
[`docs/specs/README.md`](docs/specs/README.md). **Spec documents are written in
Chinese** (technical identifiers, paths, commands and requirement IDs stay in
their original form):

- New spec: copy `docs/specs/_template.md` → `docs/specs/NNNN-<slug>.md`
  (next free `NNNN`), fill the metadata table, register it in the index.
- Changing an existing spec: keep its `S-NNNN`, bump **Document version**,
  update **Date**. Never rename/delete/renumber a merged spec — supersede it
  instead.
- Reference other specs by ID (`S-XXXX`), never by prose.
- **Every code change ships with its spec change in the same commit** — spec
  first, then code (see the Spec-first section above).
