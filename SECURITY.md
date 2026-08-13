# Security Policy

## Supported Versions

The latest release is the only supported version. We do not backport fixes to
older releases.

| Version | Supported          |
|---------|--------------------|
| latest  | ✅                 |
| older   | ❌ (update instead) |

## Reporting a Vulnerability

Please **do not** open a public issue for security problems. Instead report
privately:

- Use GitHub's **private vulnerability reporting**:
  repo → **Security** → **Report a vulnerability**, or
- Email `xiaoqin.7@bytedance.com` with the subject prefix `[dsh-desktop]`.

Please include:

- The affected version(s)
- A description of the issue and how to reproduce it
- (If known) a suggested fix

We aim to acknowledge reports within **3 business days** and to ship a fix in
the next release once a severity is agreed.

## Scope

- The Swift app shell and its build/install scripts (`src/`, `scripts/`).
- The auto-update pipeline (`UpdateManager.swift`, `UpdaterHelper.swift`,
  `scripts/publish-update.sh`) — checksum-verified downloads, no unauthenticated
  update sources.

The embedded `@deepseek-ai/dsh` backend is a separate, MIT-licensed upstream
package; report issues against it upstream.

## Note

The release builds are **ad-hoc signed** (for local use). The update mechanism
verifies the DMG against the SHA-256 published in the signed update manifest,
but it does **not** cryptographically sign the binaries themselves — do not
distribute ad-hoc builds publicly without Developer ID signing + notarization.
