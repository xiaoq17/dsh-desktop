import Cocoa
import CryptoKit

/// Update manifest served from the configured URL.
///
/// Minimal shape:
/// ```json
/// {
///   "version": "0.1.0.0",
///   "build": "458b452",
///   "app": "dsh-desktop-light",
///   "minOSVersion": "13.0",
///   "arch": "arm64",
///   "platform": "darwin",
///   "dmgUrl": "https://example.com/dsh-desktop-light-0.1.0.0-arm64.dmg",
///   "dmgSha256": "…",
///   "releaseNotes": "• What's new"
/// }
/// ```
///
/// `dmgUrl` (and the manifest URL itself) may be a `file://` URL for local
/// development: the "download" then copies the local DMG instead of hitting the
/// network, and the rest of the flow is identical.
struct UpdateManifest: Decodable {
    let version: String
    /// Build source's git short revision (e.g. "458b452"); used as the
    /// same-version tiebreaker — a different rev means a new build.
    let build: String?
    /// Target variant ("dsh-desktop" / "dsh-desktop-light"). `nil` = the full
    /// build (backwards compatible with manifests that predate this field).
    let app: String?
    let minOSVersion: String?
    let arch: String?
    /// Target platform ("darwin" / "win32", Node-style). `nil` = any platform
    /// (backwards compatible with manifests that predate this field).
    let platform: String?
    let dmgUrl: String
    let dmgSha256: String?
    let releaseNotes: String?
}

/// A fully downloaded and checksum-verified update, waiting for the user to
/// choose to restart and apply it. Staging and applying are decoupled: nothing
/// is installed or terminated until the user clicks "Restart to Install…".
struct PendingUpdate {
    let version: String
    /// Build (git short rev) of the staged update. Kept so a same-version
    /// different-build update is not mistaken for the already-applied build
    /// (spec S-0001 §7.2).
    let build: String?
    let dmgPath: URL
}

/// Fetch → compare → download & verify (stage) → remind → apply only when the
/// user clicks "Restart to Install…".
///
/// The pipeline never interrupts the current session on its own:
/// - checking and downloading happen in the background;
/// - once verified, the update is only *staged* — a `pendingUpdate` is set and
///   a non-blocking reminder is shown (menu item + Dock bounce);
/// - applying hands off to the embedded `dsh-updater` helper (the
///   `relaunch_helper` pattern: wait for the app to quit → swap the bundle →
///   relaunch) and only happens on an explicit user action.
final class UpdateManager: NSObject, URLSessionDownloadDelegate {

    static let shared = UpdateManager()

    // MARK: - Configuration

    /// Remote manifest URL. Resolution order:
    ///   1. UserDefaults override (`defaults write com.deepseek.dsh.desktop DSHUpdateManifestURL …`)
    ///   2. `DSHUpdateManifestURL` embedded in Info.plist at build time
    ///   3. nil → updates disabled (silent check does nothing, manual check reports it)
    ///
    /// A `file://` URL is allowed and drives the local-development flow.
    var manifestURL: URL? {
        if let s = UserDefaults.standard.string(forKey: "DSHUpdateManifestURL"),
           !s.isEmpty, let u = URL(string: s) {
            return u
        }
        if let s = Bundle.main.object(forInfoDictionaryKey: "DSHUpdateManifestURL") as? String,
           !s.isEmpty, let u = URL(string: s) {
            return u
        }
        return nil
    }

    private let autoCheckInterval: TimeInterval = 24 * 60 * 60
    private let lastAutoCheckKey = "DSHLastAutoCheckDate"
    private let skipVersionKey = "DSHSkippedUpdateVersion"
    private let pendingVersionKey = "DSHPendingUpdateVersion"
    private let pendingBuildKey = "DSHPendingUpdateBuild"
    private let pendingPathKey = "DSHPendingUpdatePath"

    // MARK: - Current version

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Identity of THIS build variant: "dsh-desktop" (full) or "dsh-desktop-light".
    private static var currentProductName: String {
        switch Bundle.main.bundleIdentifier {
        case "com.deepseek.dsh.desktop.light": return "dsh-desktop-light"
        default: return "dsh-desktop"
        }
    }

    // MARK: - State

    private var isChecking = false
    private var isDownloading = false
    private var pendingManifest: UpdateManifest?

    /// The verified update that is ready to apply, or nil. Staging never
    /// terminates the app — applying is always user-triggered.
    private(set) var pendingUpdate: PendingUpdate?

    /// Called on the main thread whenever `pendingUpdate` changes, so the UI
    /// (e.g. the "Restart to Install…" menu item) can reflect it.
    var onPendingUpdateChanged: ((PendingUpdate?) -> Void)?

    private var progressWindow: NSWindow?
    private var progressIndicator: NSProgressIndicator?
    private var progressLabel: NSTextField?
    private var progressDetail: NSTextField?

    private override init() { super.init() }

    // MARK: - Public API

    /// Menu action: "Check for Updates…"
    @objc func checkForUpdates(_ sender: Any?) {
        checkForUpdates(interactive: true)
    }

    /// Menu action: "Restart to Install dsh-desktop …".
    /// Applies the staged update (if any): confirm, then hand off to the
    /// updater helper and quit. This is the ONLY path that terminates the app.
    @objc func restartToInstall(_ sender: Any?) {
        guard let pending = pendingUpdate else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Restart to Install dsh-desktop \(revLabel(version: pending.version, build: pending.build))"
        alert.informativeText = "The app will quit and reopen with the new version."
        alert.addButton(withTitle: "Restart & Install")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            installAndRelaunch(dmgPath: pending.dmgPath)
        }
    }

    /// Silent launch-time check. Runs at most once per `autoCheckInterval`
    /// and honours "Skip This Version".
    func autoCheck() {
        let now = Date()
        let last = UserDefaults.standard.object(forKey: lastAutoCheckKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= autoCheckInterval else { return }
        UserDefaults.standard.set(now, forKey: lastAutoCheckKey)
        checkForUpdates(interactive: false)
    }

    /// On launch: re-surface an update that a previous session staged but the
    /// user has not applied yet (the staged DMG persists in caches).
    func restorePendingIfAny() {
        guard pendingUpdate == nil else { return }
        guard let version = UserDefaults.standard.string(forKey: pendingVersionKey),
              let path = UserDefaults.standard.string(forKey: pendingPathKey) else { return }
        let build = UserDefaults.standard.string(forKey: pendingBuildKey)
        // Newer = strictly greater version, OR same version with a different
        // build (spec S-0001 §7.2 build tiebreaker). A missing persisted build
        // is treated as "same build" to stay backwards compatible.
        let cmp = compareVersion(version, currentVersion)
        let isNewer: Bool
        switch cmp {
        case .orderedDescending: isNewer = true
        case .orderedSame: isNewer = build.map { $0 != currentBuild } ?? false
        case .orderedAscending: isNewer = false
        }
        guard isNewer else { return }
        let dmg = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: dmg.path) else {
            UserDefaults.standard.removeObject(forKey: pendingVersionKey)
            UserDefaults.standard.removeObject(forKey: pendingBuildKey)
            UserDefaults.standard.removeObject(forKey: pendingPathKey)
            return
        }
        let pending = PendingUpdate(version: version, build: build, dmgPath: dmg)
        pendingUpdate = pending
        onPendingUpdateChanged?(pending)
        Self.log("Restored staged update \(version) from a previous session.")
    }

    func checkForUpdates(interactive: Bool) {
        guard !isChecking, !isDownloading else { return }
        guard let url = manifestURL else {
            if interactive {
                presentOK(title: "Check for Updates",
                          message: "Updates are not configured for this build.\n\nSet DSHUpdateManifestURL (UserDefaults or Info.plist) to the manifest URL.")
            }
            return
        }
        isChecking = true
        if url.isFileURL {
            // Local development manifest (file://) — read off the main thread.
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let data = try? Data(contentsOf: url)
                DispatchQueue.main.async {
                    self?.isChecking = false
                    self?.handleManifest(data: data, error: nil, interactive: interactive)
                }
            }
        } else {
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            req.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
                DispatchQueue.main.async {
                    self?.isChecking = false
                    self?.handleManifest(data: data, error: error, interactive: interactive)
                }
            }.resume()
        }
    }

    // MARK: - Manifest handling

    private func handleManifest(data: Data?, error: Error?, interactive: Bool) {
        guard let data else {
            if interactive {
                presentOK(title: "Check for Updates",
                          message: "Could not read the update manifest: \(error?.localizedDescription ?? "no data")")
            }
            return
        }
        guard let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data) else {
            if interactive {
                presentOK(title: "Check for Updates", message: "The update manifest is invalid.")
            }
            return
        }
        // Update targets another platform → not applicable on this build.
        if !Platform.acceptsManifestPlatform(manifest.platform) {
            if interactive {
                presentOK(title: "Check for Updates",
                          message: "No update available for this platform.")
            }
            return
        }
        // Update targets another variant (full vs light) → not for this app.
        // Missing `app` means the full build (backwards compatible).
        if (manifest.app ?? "dsh-desktop") != Self.currentProductName {
            if interactive {
                presentOK(title: "Check for Updates",
                          message: "This update is for \(manifest.app ?? "dsh-desktop"), "
                            + "not \(Self.currentProductName).")
            }
            return
        }
        guard isNewer(manifest) else {
            if interactive {
                presentOK(title: "Check for Updates",
                          message: "You're up to date — dsh-desktop \(revLabel(version: currentVersion, build: currentBuild)).")
            }
            return
        }
        // Honour "Skip This Version" (interactive and silent alike), keyed by
        // version+build so a skipped build never blocks a newer build of the
        // same version (spec S-0001 §7.2).
        // A legacy plain-version skip (stored before the build key existed)
        // must not act as a whole-version wildcard — it cannot express which
        // build was skipped, so it would swallow a same-version new build.
        // It is migrated away the first time it meets a manifest that carries
        // a build, and only still applies to manifests that themselves carry
        // no build (old-format manifests), preserving the legacy behaviour.
        let storedSkip = UserDefaults.standard.string(forKey: skipVersionKey)
        if let storedSkip {
            if storedSkip.contains("@") {
                // New-style composite key (version@build): exact match only.
                if storedSkip == skipKey(for: manifest) { return }
            } else if manifest.build == nil {
                // Old-format manifest (no build) + legacy plain-version skip:
                // keep the legacy "skip this version" behaviour.
                if storedSkip == manifest.version { return }
            } else {
                // Legacy plain-version skip meets a build-carrying manifest:
                // migrate the stale value away so the same-version new build
                // is offered (spec S-0001 §7.2).
                UserDefaults.standard.removeObject(forKey: skipVersionKey)
            }
        }
        // Already staged & waiting to apply this exact version+build? Nothing
        // to do. A different build of the same version is still a new update.
        if let p = pendingUpdate,
           p.version == manifest.version,
           p.build == manifest.build { return }

        if interactive {
            offerDownload(manifest)
        } else {
            // Silent check: pre-stage the update so it is ready to apply the
            // moment the user decides to — the reminder appears when done.
            startDownload(manifest)
        }
    }

    /// Manual check found a newer version: ask what to do. Downloading only
    /// stages + verifies; applying is a separate, later, user-triggered step.
    private func offerDownload(_ manifest: UpdateManifest) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "dsh-desktop \(revLabel(version: manifest.version, build: manifest.build)) is available"
        let notes = manifest.releaseNotes ?? ""
        alert.informativeText = notes.isEmpty
            ? "You're running \(revLabel(version: currentVersion, build: currentBuild)). Download it now and restart whenever you're ready."
            : notes
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            startDownload(manifest)
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(skipKey(for: manifest), forKey: skipVersionKey)
        default:
            break
        }
    }

    /// Newer when the manifest's four-part version string is greater, or — as
    /// a tiebreaker for equal versions — when its `build` (the build source's
    /// git short revision) differs from the current build.
    /// Version-string comparison takes precedence: the desktop version is
    /// `dshMajor.dshMinor.dshPatch.desktopRev`, and the desktopRev resets to 0
    /// on a dsh upgrade, so the `build` alone would wrongly report a downgrade
    /// in that case.
    private func isNewer(_ m: UpdateManifest) -> Bool {
        let c = compareVersion(m.version, currentVersion)
        if c != .orderedSame { return c == .orderedDescending }
        // Same version (DSH_DESKTOP_REV equal): any different build = new build
        // (spec S-0001 §7.2). A missing build means "same as current" (no update).
        if let build = m.build { return build != currentBuild }
        return false
    }

    /// Composite identity of an update for skip/pending bookkeeping:
    /// `version@build` when the manifest carries a build, plain `version`
    /// otherwise (backwards compatible with manifests that predate `build`).
    /// A same-version different-build release is therefore a DIFFERENT update
    /// and is never shadowed by a skip or a staged update of another build
    /// (spec S-0001 §7.2).
    private func skipKey(for manifest: UpdateManifest) -> String {
        if let build = manifest.build { return "\(manifest.version)@\(build)" }
        return manifest.version
    }

    /// User-facing "v<version> (rev:<build>)" label (spec S-0001 FR-9.10).
    /// The build (git short rev) is shown so a same-version different-build
    /// update is visually distinguishable. Falls back to version-only when the
    /// build is missing.
    private func revLabel(version: String, build: String?) -> String {
        if let build, !build.isEmpty { return "v\(version) (rev:\(build))" }
        return "v\(version)"
    }

    private func compareVersion(_ a: String, _ b: String) -> ComparisonResult {
        let ac = a.split(separator: ".").compactMap { Int($0) }
        let bc = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(ac.count, bc.count) {
            let av = i < ac.count ? ac[i] : 0
            let bv = i < bc.count ? bc[i] : 0
            if av != bv { return av > bv ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }

    // MARK: - Download & verify (stage only — never restarts)

    private func startDownload(_ manifest: UpdateManifest) {
        guard !isDownloading, let url = URL(string: manifest.dmgUrl) else { return }
        isDownloading = true
        pendingManifest = manifest

        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.deepseek.dsh.desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("dsh-desktop-\(manifest.version).dmg")
        try? FileManager.default.removeItem(at: dest)   // drop stale partial

        if url.isFileURL {
            // Local development build: copy instead of network download.
            showProgress(title: "Preparing dsh-desktop \(manifest.version)…", indeterminate: true)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var copyError: String?
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                } catch {
                    copyError = error.localizedDescription
                }
                DispatchQueue.main.async {
                    self?.hideProgress()
                    guard copyError == nil else {
                        self?.failDownload("Could not copy the local update: \(copyError ?? "unknown error")")
                        return
                    }
                    self?.verifyAndPrepare(manifest: manifest, dmgPath: dest)
                }
            }
        } else {
            showProgress(title: "Downloading dsh-desktop \(manifest.version)…")
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
            session.downloadTask(with: url).resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        updateProgress(received: totalBytesWritten, expected: max(totalBytesExpectedToWrite, 0))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let dest = cachesDestination(for: pendingManifest?.version ?? "") else { return }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            failDownload("Could not save the downloaded file: \(error.localizedDescription)")
            return
        }
        verifyAndPrepare(manifest: pendingManifest, dmgPath: dest)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            failDownload("Download failed: \(error.localizedDescription)")
        }
    }

    private func cachesDestination(for version: String) -> URL? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.deepseek.dsh.desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dsh-desktop-\(version).dmg")
    }

    // MARK: - Verification & staging

    private func verifyAndPrepare(manifest: UpdateManifest?, dmgPath: URL) {
        guard let manifest else {
            failDownload("Update aborted: no manifest.")
            return
        }
        guard let sha = manifest.dmgSha256, !sha.isEmpty else {
            stageUpdate(manifest: manifest, dmgPath: dmgPath)
            return
        }
        showProgress(title: "Verifying download…", indeterminate: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let actual = self?.sha256OfFile(dmgPath)
            DispatchQueue.main.async {
                self?.hideProgress()
                if actual?.lowercased() == sha.lowercased() {
                    self?.stageUpdate(manifest: manifest, dmgPath: dmgPath)
                } else {
                    try? FileManager.default.removeItem(at: dmgPath)
                    self?.failDownload("The downloaded file failed its checksum check and was discarded.")
                }
            }
        }
    }

    /// Store the verified update and surface a non-blocking reminder. Does NOT
    /// terminate or restart the app — applying is a separate user action.
    private func stageUpdate(manifest: UpdateManifest, dmgPath: URL) {
        isDownloading = false
        pendingManifest = nil
        hideProgress()
        let pending = PendingUpdate(version: manifest.version,
                                    build: manifest.build,
                                    dmgPath: dmgPath)
        pendingUpdate = pending
        UserDefaults.standard.set(manifest.version, forKey: pendingVersionKey)
        if let build = manifest.build {
            UserDefaults.standard.set(build, forKey: pendingBuildKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingBuildKey)
        }
        UserDefaults.standard.set(dmgPath.path, forKey: pendingPathKey)
        onPendingUpdateChanged?(pending)
        // Non-intrusive reminder: bounce the Dock icon once.
        NSApp.requestUserAttention(.informationalRequest)
        Self.log("Update \(manifest.version) is staged & verified — waiting for the user to restart.")
    }

    /// Spawn the embedded helper, then quit. The helper swaps the bundle and
    /// relaunches the updated app. Called only from `restartToInstall`.
    private func installAndRelaunch(dmgPath: URL) {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/dsh-updater")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            presentOK(title: "Update Failed",
                      message: "The updater helper is missing from this build.")
            return
        }
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/dsh-desktop-update.log").path
        let proc = Process()
        proc.executableURL = helper
        proc.arguments = [
            "--app", Bundle.main.bundlePath,
            "--dmg", dmgPath.path,
            "--pid", "\(ProcessInfo.processInfo.processIdentifier)",
            "--log", logPath,
        ]
        do {
            try proc.run()
        } catch {
            presentOK(title: "Update Failed",
                      message: "Could not launch the updater: \(error.localizedDescription)")
            return
        }
        // Give the helper a moment to register, then quit so it can swap us.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    private func sha256OfFile(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func log(_ message: String) {
        let line = "\(Date()) [UpdateManager] \(message)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/dsh-desktop-update.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }

    // MARK: - Progress UI

    private func showProgress(title: String, indeterminate: Bool = false) {
        if progressWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 112),
                               styleMask: [.titled], backing: .buffered, defer: false)
            win.title = "Update"
            win.isReleasedWhenClosed = false
            win.center()

            let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 112))
            let label = NSTextField(labelWithString: "")
            label.frame = NSRect(x: 20, y: 84, width: 360, height: 18)
            label.font = .systemFont(ofSize: 13)

            let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 44, width: 360, height: 20))
            bar.style = .bar
            bar.isIndeterminate = false
            bar.minValue = 0
            bar.maxValue = 1
            bar.doubleValue = 0

            let detail = NSTextField(labelWithString: "")
            detail.frame = NSRect(x: 20, y: 22, width: 360, height: 16)
            detail.font = .systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor

            content.addSubview(label)
            content.addSubview(bar)
            content.addSubview(detail)
            win.contentView = content

            progressWindow = win
            progressIndicator = bar
            progressLabel = label
            progressDetail = detail
        }
        guard let win = progressWindow else { return }
        progressIndicator?.isIndeterminate = indeterminate
        progressIndicator?.doubleValue = 0
        if indeterminate {
            progressIndicator?.startAnimation(nil)
        }
        progressLabel?.stringValue = title
        progressDetail?.stringValue = ""
        win.center()
        if let key = NSApp.keyWindow {
            key.beginSheet(win)
        } else {
            win.makeKeyAndOrderFront(nil)
        }
    }

    private func updateProgress(received: Int64, expected: Int64) {
        guard let bar = progressIndicator else { return }
        if expected > 0 {
            bar.isIndeterminate = false
            bar.maxValue = Double(expected)
            bar.doubleValue = Double(received)
            progressDetail?.stringValue = String(format: "%.1f MB of %.1f MB",
                                                 Double(received) / 1_048_576,
                                                 Double(expected) / 1_048_576)
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
    }

    private func hideProgress() {
        progressIndicator?.stopAnimation(nil)
        if let win = progressWindow {
            if win.sheetParent != nil {
                win.sheetParent?.endSheet(win)
            }
            win.orderOut(nil)
        }
        progressDetail?.stringValue = ""
    }

    // MARK: - Alerts

    private func presentOK(title: String, message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    private func failDownload(_ message: String) {
        isDownloading = false
        pendingManifest = nil
        hideProgress()
        Self.log("Update download/verification failed: \(message)")
        presentOK(title: "Update Failed", message: message)
    }
}
