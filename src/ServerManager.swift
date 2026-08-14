import Foundation

/// Manages the embedded DeepSeek Harness backend that ships inside dsh-desktop.
///
/// The app is fully self-contained: it bundles its own Node runtime and the
/// `@deepseek-ai/dsh` package (with all production dependencies) under
/// `Contents/Resources/`. On launch we start
/// `dsh --profile desktop --port 0` (the OS assigns a free port) and parse the
/// actual URL from its stdout. Nothing depends on an external `dsh` CLI, a
/// system Node install, or a fixed port like 3080.
final class ServerManager {

    static let shared = ServerManager()

    let host = "127.0.0.1"
    private(set) var activePort: Int?

    var serverURL: URL? {
        guard let p = activePort else { return nil }
        return URL(string: "http://\(host):\(p)")
    }

    private(set) var process: Process?
    private var logFileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/dsh-desktop-server.log")

    private init() {
        try? FileManager.default.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    // MARK: - Runtime resolution

    /// Probe the user's login-shell PATH so the embedded dsh backend (and the
    /// bash tools it spawns) can find brew / user-level CLIs such as `gh`.
    /// macOS GUI apps inherit a minimal PATH from launchd
    /// (`/usr/bin:/bin:/usr/sbin:/sbin`); we ask the login shell instead so we
    /// never hard-code machine paths (spec S-0002 FR-1/2).
    ///
    /// Returns the first non-empty `$PATH` from `/bin/zsh -l` or
    /// `/bin/bash -l`, or nil when both fail or time out (~5s) so startup is
    /// never blocked by a slow user shell config (spec S-0002 NFR-1).
    static func loginShellPath() -> String? {
        for shell in ["/bin/zsh", "/bin/bash"] {
            guard FileManager.default.isExecutableFile(atPath: shell) else { continue }
            if let path = Self.shellPath(from: shell) { return path }
        }
        return nil
    }

    /// Run a login shell once and return its `$PATH`, with a timeout guard so
    /// a slow/broken login script never blocks startup (spec S-0002 NFR-1).
    private static func shellPath(from shell: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-l", "-c", "echo \"$PATH\""]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()   // swallow errors from login scripts
        do {
            try proc.run()
        } catch {
            return nil
        }
        // Timeout guard: terminate a stuck login shell after ~5s.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak proc] in
            if proc?.isRunning == true { proc?.terminate() }
        }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    /// Absolute path to the bundled Node binary inside this .app (full build).
    static var bundledNodePath: String? {
        guard let res = Bundle.main.resourceURL?.path else { return nil }
        let p = "\(res)/runtime/bin/node"
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    /// Absolute path to the bundled `dsh` CLI entry (lib/bin.js) (full build).
    static var bundledDSHPath: String? {
        guard let res = Bundle.main.resourceURL?.path else { return nil }
        let p = "\(res)/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js"
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }

    /// Resolve `node` for the light build from the SYSTEM (no full-app fallback,
    /// spec S-0001 §8.5). Order: `DSH_NODE` env → UserDefaults `DSHNodePath` →
    /// PATH search → common install locations.
    static func systemNodePath() -> String? {
        if let e = ProcessInfo.processInfo.environment["DSH_NODE"], !e.isEmpty,
           FileManager.default.isExecutableFile(atPath: e) { return e }
        if let u = UserDefaults.standard.string(forKey: "DSHNodePath"), !u.isEmpty,
           FileManager.default.isExecutableFile(atPath: u) { return u }
        if let p = PATHExecutable("node") { return p }
        for p in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Resolve the `dsh` CLI entry for the light build from the SYSTEM.
    /// Order: `DSH_DSH` env → UserDefaults `DSHDSHPath` → PATH search →
    /// common install locations.
    static func systemDSHPath() -> String? {
        if let e = ProcessInfo.processInfo.environment["DSH_DSH"], !e.isEmpty,
           FileManager.default.isExecutableFile(atPath: e) { return e }
        if let u = UserDefaults.standard.string(forKey: "DSHDSHPath"), !u.isEmpty,
           FileManager.default.isExecutableFile(atPath: u) { return u }
        if let p = PATHExecutable("dsh") { return p }
        for p in ["/opt/homebrew/bin/dsh", "/usr/local/bin/dsh"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Search $PATH for an executable by name.
    private static func PATHExecutable(_ name: String) -> String? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in path.split(separator: ":") {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Resolved Node binary: bundled (full build) first, else the system's node
    /// (light build).
    static func resolvedNodePath() -> String? { bundledNodePath ?? systemNodePath() }

    /// Resolved `dsh` CLI entry: bundled (full build) first, else the system's
    /// dsh CLI (light build).
    static func resolvedDSHPath() -> String? { bundledDSHPath ?? systemDSHPath() }

    /// True when a usable runtime is available (bundled or system).
    static var isRuntimeAvailable: Bool {
        resolvedNodePath() != nil && resolvedDSHPath() != nil
    }

    // MARK: - Desktop profile

    /// Name of the desktop-owned dsh profile, booted via `--profile desktop`.
    static let profileName = "desktop"

    /// Bundle-relative template dir for seeding the profile on first launch.
    static var bundledProfileTemplateURL: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let p = res.appendingPathComponent("desktop-profile")
        return FileManager.default.fileExists(atPath: p.path) ? p : nil
    }

    /// The DSH_HOME the embedded backend will use: env override or the default.
    static func resolvedHomePath() -> String {
        ProcessInfo.processInfo.environment["DSH_HOME"] ?? Platform.defaultHomePath
    }

    /// Ensure `$DSH_HOME/profiles/desktop` exists, seeding it from the bundled
    /// template on first launch. Never overwrites an existing user layer.
    /// Returns false when the profile cannot be prepared.
    func ensureDesktopProfile() -> Bool {
        guard let template = ServerManager.bundledProfileTemplateURL else { return false }
        let home = ServerManager.resolvedHomePath()
        let profileDir = URL(fileURLWithPath: home)
            .appendingPathComponent("profiles/\(ServerManager.profileName)", isDirectory: true)
        let marker = profileDir.appendingPathComponent("cordis.yml")
        if FileManager.default.fileExists(atPath: marker.path) { return true }
        do {
            try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
            for name in ["package.json", "cordis.yml", "cordis.patch.yml", "pnpm-workspace.yaml"] {
                let src = template.appendingPathComponent(name)
                let dst = profileDir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: src.path) {
                    try FileManager.default.copyItem(at: src, to: dst)
                }
            }
            return true
        } catch {
            ServerManager.appendToLog("Failed to seed desktop profile: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Detection

    func isServerReachable(timeout: TimeInterval = 1.0) -> Bool {
        guard let url = serverURL else { return false }
        let sem = DispatchSemaphore(value: 0)
        var reachable = false
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse,
               (200..<400).contains(http.statusCode) {
                reachable = true
            }
            _ = error
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout)
        return reachable
    }

    // MARK: - Start / Stop

    /// Start the embedded server detached. Returns immediately; readiness is
    /// reported through `onPort`/`onReady`/`onExit` callbacks.
    func startServer(
        onPort: @escaping (Int) -> Void = { _ in },
        onReady: @escaping () -> Void = {},
        onExit: @escaping (String) -> Void = { _ in }
    ) {
        guard process == nil || process!.isRunning == false else { return }
        guard let node = ServerManager.resolvedNodePath(),
              let dsh = ServerManager.resolvedDSHPath() else {
            onExit("Runtime not found. The full build needs its bundled Resources; "
                + "the light build (dsh-desktop-light) needs a system `dsh` CLI and "
                + "`node` on PATH (npm install -g @deepseek-ai/dsh).")
            return
        }

        // Seed the desktop profile on first launch (never touches an existing one).
        guard ensureDesktopProfile() else {
            onExit("Could not prepare the desktop profile under DSH_HOME.")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = [dsh, "--profile", ServerManager.profileName,
                          "--host", host, "--port", "0"]

        // Inherit the user's DSH_HOME so profiles/settings/sessions are reused.
        var env = ProcessInfo.processInfo.environment
        if env["DSH_HOME"] == nil {
            env["DSH_HOME"] = ServerManager.resolvedHomePath()
        }
        // Prefer the user's login-shell PATH so the embedded backend (and the
        // bash tools it spawns) can reach brew / user-level CLIs such as `gh`
        // — a GUI app's launchd PATH is just the system dirs (spec S-0002).
        if let loginPath = ServerManager.loginShellPath() {
            env["PATH"] = loginPath
        } else if env["PATH"] == nil {
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var buffer = Data()
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
            let text = String(data: buffer, encoding: .utf8) ?? ""
            // Find the printed URL: "dsh web: http://127.0.0.1:PORT"
            if let port = Self.parsePort(from: text) {
                self?.activePort = port
                DispatchQueue.main.async { onPort(port) }
                // Once reachable, report ready.
                self?.waitUntilReady(onReady: onReady)
            }
            Self.appendToLog(String(data: data, encoding: .utf8) ?? "")
        }
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            Self.appendToLog(String(data: data, encoding: .utf8) ?? "")
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.activePort = nil
                self?.process = nil
                if p.terminationReason == .exit, p.terminationStatus != 0 {
                    onExit("Server exited with status \(p.terminationStatus)")
                }
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            onExit("Failed to launch embedded server: \(error)")
        }
    }

    private func waitUntilReady(onReady: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var attempts = 0
            while attempts < 60 {
                if self.isServerReachable() {
                    DispatchQueue.main.async { onReady() }
                    return
                }
                attempts += 1
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    static func parsePort(from text: String) -> Int? {
        // Match "http://127.0.0.1:PORT" anywhere in the output.
        let pattern = #"https?://[^:/]+:(\d+)"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            let matched = String(text[range])
            if let port = Int(matched.split(separator: ":").last ?? "") {
                return port
            }
        }
        return nil
    }

    /// Stop the embedded server (kills the whole process tree).
    func stopServer() {
        if let p = process, p.isRunning {
            p.terminate()
            // Give it a moment, then hard-kill the tree if needed.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if p.isRunning {
                    kill(-p.processIdentifier, SIGKILL)
                }
            }
        }
        process = nil
        activePort = nil
    }

    func serverLog() -> String {
        guard let data = try? Data(contentsOf: logFileURL) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func appendToLog(_ s: String) {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/dsh-desktop-server.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(s.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? s.data(using: .utf8)?.write(to: url)
        }
    }
}
