import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    var windowController: MainWindowController?
    private weak var restartUpdateItem: NSMenuItem?

    static func main() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DLog("applicationDidFinishLaunching called")
        buildMenu()

        // Re-surface an update staged by a previous session (if any), and keep
        // the "Restart to Install…" menu item in sync with the update state.
        UpdateManager.shared.onPendingUpdateChanged = { [weak self] pending in
            self?.restartUpdateItem?.isEnabled = (pending != nil)
            // Show version + build rev so a same-version different-build
            // update is distinguishable (spec S-0001 FR-9.10).
            let rev = (pending?.build?.isEmpty == false) ? " (rev:\(pending!.build!))" : ""
            self?.restartUpdateItem?.title = pending.map {
                "Restart to Install dsh-desktop v\($0.version)\(rev)…"
            } ?? "Restart to Install dsh-desktop…"
        }
        UpdateManager.shared.restorePendingIfAny()

        let wc = MainWindowController()
        windowController = wc
        wc.showWindow(nil)
        wc.makeWebViewFirstResponder()
        DLog("after showWindow: isVisible=\(wc.window?.isVisible ?? false) frame=\(String(describing: wc.window?.frame))")
        NSApp.activate(ignoringOtherApps: true)

        // Silent update check shortly after launch (respects its own interval).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UpdateManager.shared.autoCheck()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ServerManager.shared.stopServer()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About dsh-desktop",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let checkForUpdates = appMenu.addItem(withTitle: "Check for Updates…",
                                              action: #selector(UpdateManager.checkForUpdates(_:)),
                                              keyEquivalent: "")
        checkForUpdates.target = UpdateManager.shared
        let restartUpdate = appMenu.addItem(withTitle: "Restart to Install dsh-desktop…",
                                            action: #selector(UpdateManager.restartToInstall(_:)),
                                            keyEquivalent: "")
        restartUpdate.target = UpdateManager.shared
        restartUpdate.isEnabled = false
        restartUpdateItem = restartUpdate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide dsh-desktop",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit dsh-desktop",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // File
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open in Browser",
                         action: #selector(MainWindowController.openInBrowser(_:)),
                         keyEquivalent: "b")

        // Edit (required for Cmd+C/Cmd+A/Cmd+V etc. — routed to WKWebView)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo",
                         action: Selector(("undo:")),
                         keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo",
                         action: Selector(("redo:")),
                         keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "Paste and Match Style",
                         action: #selector(NSTextView.pasteAsPlainText(_:)),
                         keyEquivalent: "V")
        editMenu.addItem(withTitle: "Delete",
                         action: #selector(NSTextView.delete(_:)),
                         keyEquivalent: "\u{8}")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")

        // View
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload",
                         action: #selector(MainWindowController.reload(_:)),
                         keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Enter Full Screen",
                         action: #selector(NSWindow.toggleFullScreen(_:)),
                         keyEquivalent: "f")

        // Server
        let serverMenuItem = NSMenuItem()
        mainMenu.addItem(serverMenuItem)
        let serverMenu = NSMenu(title: "Server")
        serverMenuItem.submenu = serverMenu
        serverMenu.addItem(withTitle: "Restart Server",
                           action: #selector(MainWindowController.restartServer(_:)),
                           keyEquivalent: "")
        serverMenu.addItem(withTitle: "Stop Server",
                           action: #selector(MainWindowController.stopServer(_:)),
                           keyEquivalent: "")
        serverMenu.addItem(.separator())
        serverMenu.addItem(withTitle: "Server Status…",
                           action: #selector(MainWindowController.showServerStatus(_:)),
                           keyEquivalent: "")

        // Window
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")

        NSApp.mainMenu = mainMenu
        DLog("menu built")
    }
}

/// Append a line to ~/Library/Logs/dsh-desktop-app.log
func DLog(_ message: String) {
    let line = "\(Date()) [DSHDesktop] \(message)\n"
    let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/dsh-desktop-app.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.data(using: .utf8)?.write(to: url)
    }
}
