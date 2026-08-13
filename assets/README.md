# assets

Static assets for the project — reserved for future use (e.g. app icon source
files, marketing images, extra screenshots).

The in-repo screenshot lives in [`docs/app.png`](../docs/app.png).

- `desktop-profile/` — the desktop Cordis profile template (`package.json`,
  `cordis.yml`, `cordis.patch.yml`, `pnpm-workspace.yaml`), bundled into
  `Contents/Resources/desktop-profile/` by `scripts/build.sh` and seeded into
  `$DSH_HOME/profiles/desktop/` on first launch (spec S-0001 FR-1.5).
