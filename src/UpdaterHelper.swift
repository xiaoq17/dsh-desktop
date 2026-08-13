import Foundation

/// dsh-updater — standalone helper that applies a downloaded update.
///
/// It must be a separate executable because the running app cannot replace
/// its own bundle on disk. The main app spawns this helper just before
/// quitting; the helper:
///
///   1. waits for the main app (--pid) to fully exit
///   2. mounts the downloaded .dmg and copies the new .app over the old bundle
///   3. relaunches the updated app
///
/// Usage:
///   dsh-updater --app "/Applications/dsh-desktop.app" \
///               --dmg "/path/to/dsh-desktop-0.1.0.0-arm64.dmg" \
///               --pid 12345 --log "~/Library/Logs/dsh-desktop-update.log"

// MARK: - Helpers

private func log(_ message: String, to path: String) {
    let line = "\(Date()) \(message)\n"
    let url = URL(fileURLWithPath: path)
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.data(using: .utf8)?.write(to: url)
    }
}

/// Run a command synchronously, log it, return whether it succeeded.
private func run(_ args: [String], logPath: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do {
        try p.run()
        p.waitUntilExit()
    } catch {
        log("FAILED to launch \(args.joined(separator: " ")): \(error)", to: logPath)
        return false
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let out = String(data: data, encoding: .utf8) ?? ""
    if p.terminationStatus != 0 || !out.isEmpty {
        log("$ \(args.joined(separator: " ")) -> \(p.terminationStatus)\n\(out)", to: logPath)
    }
    return p.terminationStatus == 0
}

/// Poll until the given PID is gone or the timeout elapses.
private func waitForExit(pid: Int32, timeout: TimeInterval, logPath: String) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if kill(pid, 0) != 0 { return true }   // process no longer exists
        usleep(500_000)
    }
    log("Timed out after \(Int(timeout))s waiting for pid \(pid)", to: logPath)
    return false
}

// MARK: - Main

private func main() {
    let args = CommandLine.arguments

    var appPath = ""
    var dmgPath = ""
    var logPath = ""
    var pidStr = ""

    var i = 1
    while i < args.count {
        let flag = args[i]
        let next = i + 1 < args.count ? args[i + 1] : ""
        switch flag {
        case "--app": appPath = next; i += 1
        case "--dmg": dmgPath = next; i += 1
        case "--pid": pidStr = next; i += 1
        case "--log": logPath = next; i += 1
        default: break
        }
        i += 1
    }

    if logPath.isEmpty {
        logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/dsh-desktop-update.log").path
    }

    log("dsh-updater start app=\(appPath) dmg=\(dmgPath) pid=\(pidStr)", to: logPath)

    guard !appPath.isEmpty, !dmgPath.isEmpty, let pid = Int32(pidStr), pid > 0 else {
        log("Bad arguments — expected --app --dmg --pid [--log]", to: logPath)
        exit(1)
    }

    // 1. Wait for the main app to quit.
    guard waitForExit(pid: pid, timeout: 120, logPath: logPath) else {
        log("Update aborted: app did not exit in time.", to: logPath)
        exit(1)
    }
    log("Main app exited; applying update.", to: logPath)

    // 2. Mount the DMG read-only at a unique mount point.
    let mountBase = FileManager.default.temporaryDirectory
        .appendingPathComponent("dsh-update-mount", isDirectory: true)
    try? FileManager.default.removeItem(at: mountBase)
    try? FileManager.default.createDirectory(at: mountBase, withIntermediateDirectories: true)
    let mountPoint = mountBase.appendingPathComponent(UUID().uuidString)

    var mounted = false
    defer {
        if mounted {
            _ = run(["hdiutil", "detach", mountPoint.path, "-quiet", "-force"], logPath: logPath)
            log("Detached DMG.", to: logPath)
        }
    }

    guard run(["hdiutil", "attach", dmgPath, "-nobrowse", "-readonly",
               "-mountpoint", mountPoint.path], logPath: logPath) else {
        log("Update aborted: failed to mount DMG.", to: logPath)
        exit(1)
    }
    mounted = true

    // 3. Locate the .app inside the DMG whose bundle id matches the RUNNING app
    // (dsh-desktop vs dsh-desktop-light). This is also the safety net: never
    // swap in a different variant's bundle.
    guard let runningID = Bundle(path: appPath)?.bundleIdentifier else {
        log("Update aborted: could not read bundle id from \(appPath).", to: logPath)
        exit(1)
    }
    let dmgRoot = try? FileManager.default.contentsOfDirectory(
        at: mountPoint, includingPropertiesForKeys: nil)
    let candidate = dmgRoot?.first(where: {
        $0.pathExtension == "app" && Bundle(path: $0.path)?.bundleIdentifier == runningID
    })
    guard let candidate = candidate,
          FileManager.default.fileExists(atPath: candidate.path) else {
        log("Update aborted: no .app matching bundle id \(runningID) in DMG.", to: logPath)
        exit(1)
    }

    // 4. Swap the bundle.
    let dest = URL(fileURLWithPath: appPath)
    do {
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: candidate, to: dest)
    } catch {
        log("Update FAILED: could not replace app bundle: \(error)", to: logPath)
        exit(1)
    }
    log("App bundle replaced at \(appPath).", to: logPath)

    // Best effort: drop quarantine so Gatekeeper doesn't nag (ad-hoc build).
    _ = run(["xattr", "-dr", "com.apple.quarantine", appPath], logPath: logPath)

    // 5. Relaunch the updated app.
    if run(["open", appPath], logPath: logPath) {
        log("Relaunched updated app.", to: logPath)
    } else {
        log("Warning: could not relaunch automatically; open \(appPath) manually.", to: logPath)
    }
    exit(0)
}

main()
