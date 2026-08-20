import Cocoa
import WebKit

final class MainWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate {

    private let webView = EditingWebView()
    private var offlineView: NSView?
    private var isWebShowing = false

    private let server = ServerManager.shared
    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatQueue = DispatchQueue(label: "com.deepseek.dsh.heartbeat")

    // MARK: - Version

    /// Marketing version from CFBundleShortVersionString, e.g. "0.1.0.0".
    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0.0"
    }

    /// Build number from CFBundleVersion, e.g. "0".
    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Git short revision embedded at build time (DSHGitRevision), e.g. "ba9e4a1".
    /// Falls back to the build number outside a git checkout.
    private var gitRevision: String {
        Bundle.main.infoDictionary?["DSHGitRevision"] as? String ?? buildString
    }

    /// True for the light variant (dsh-desktop-light, spec S-0001 §8.5).
    private var isLightVariant: Bool {
        Bundle.main.bundleIdentifier == "com.deepseek.dsh.desktop.light"
    }

    /// Base product title for the window: "DeepSeek Harness Desktop" (full) or
    /// "DeepSeek Harness Desktop Light" (light variant).
    private var productTitle: String {
        isLightVariant ? "DeepSeek Harness Desktop Light" : "DeepSeek Harness Desktop"
    }

    /// Title-bar text: "<product> v<version> (rev:<git>)" (spec S-0001 FR-2.2).
    private var titledVersion: String {
        "\(productTitle) v\(versionString) (rev:\(gitRevision))"
    }

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = false
        window.center()
        window.minSize = NSSize(width: 720, height: 480)
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("MainWindow")

        self.init(window: window)
        window.title = titledVersion
        DLog("MainWindowController init, window frame=\(window.frame)")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = dshUserAgent()
        // Enable the Web Inspector for the embedded GUI: right-click "Inspect
        // Element" and attach from Safari's Develop menu (spec FR-2.3).
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        window.contentView = webView

        bootstrap()
    }

    deinit {
        heartbeatTimer?.cancel()
    }

    private func dshUserAgent() -> String {
        let base = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 " +
            "Safari/605.1.15"
        let sys = ProcessInfo.processInfo.operatingSystemVersion
        let ver = "\(sys.majorVersion).\(sys.minorVersion).\(sys.patchVersion)"
        return "\(base) DSHDesktop/\(ver)"
    }

    /// Start the embedded server, then load the GUI once it is ready.
    private func bootstrap() {
        guard ServerManager.isRuntimeAvailable else {
            if isLightVariant {
                // FR-1.4: light needs a system dsh CLI + node (spec §8.5).
                showOffline(
                    message: "Light 版依赖系统的 dsh 与 node，当前未找到。请先安装："
                        + "npm install -g @deepseek-ai/dsh，然后重试。",
                    buttonTitle: "复制安装命令",
                    buttonAction: #selector(copyInstallCommand(_:)))
            } else {
                showOffline(message: "内嵌运行时缺失，请重新安装。")
            }
            return
        }
        setStatus("Starting embedded dsh-desktop…")
        showStarting()

        server.startServer(
            onPort: { [weak self] port in
                self?.setStatus("Server up on port \(port) — loading GUI…")
            },
            onReady: { [weak self] in
                self?.showWeb()
                self?.startHeartbeat()
            },
            onExit: { [weak self] msg in
                self?.showOffline(message: msg)
            }
        )
    }

    // MARK: - Heartbeat: detect server going up/down while running

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let reachable = self.server.isServerReachable()
            DispatchQueue.main.async {
                self.onHeartbeat(reachable: reachable)
            }
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func onHeartbeat(reachable: Bool) {
        if isWebShowing {
            if !reachable {
                DLog("heartbeat: server went offline → showing recovery view")
                showOffline(message: "Server stopped responding.")
            }
        } else {
            if reachable {
                DLog("heartbeat: server back online → reloading GUI")
                showWeb()
            }
        }
    }

    // MARK: - First responder

    /// Make the WKWebView the first responder so Cmd+C/A/V etc. reach the page.
    func makeWebViewFirstResponder() {
        window?.makeFirstResponder(webView)
    }

    // MARK: - State rendering

    private func showStarting() {
        offlineView?.removeFromSuperview()
        offlineView = nil
        isWebShowing = false
        webView.isHidden = true
        window?.title = titledVersion
        window?.subtitle = ""

        let v = makeMessageView(
            icon: "🛰",
            title: "Starting dsh-desktop…",
            detail: "Launching the embedded server (this is fully self-contained).",
            showButton: false,
            statusTag: 4242)
        offlineView = v
        installOfflineConstraints(v)
    }

    private func showWeb() {
        offlineView?.removeFromSuperview()
        offlineView = nil
        isWebShowing = true
        webView.isHidden = false
        if let url = server.serverURL {
            if webView.url?.host != url.host || webView.url?.port != url.port {
                webView.load(URLRequest(url: url))
            } else {
                webView.reload()
            }
        }
        window?.title = titledVersion
        window?.subtitle = ""
    }

    private func showOffline(message: String,
                             buttonTitle: String = "Restart Server",
                             buttonAction: Selector = #selector(restartServer(_:))) {
        isWebShowing = false
        webView.isHidden = true

        if offlineView == nil {
            let hint = (buttonAction == #selector(copyInstallCommand(_:)))
                ? "\n\n请在终端粘贴执行，然后用菜单 Server ▸ Restart Server 重试。"
                : "\n\nClick Restart to launch the embedded server again."
            let v = makeMessageView(
                icon: "🛰",
                title: "dsh-desktop server is offline",
                detail: "\(message)\(hint)",
                showButton: true,
                statusTag: 4242,
                buttonTitle: buttonTitle,
                buttonAction: buttonAction)
            offlineView = v
        }
        if let v = offlineView {
            installOfflineConstraints(v)
        }
        window?.title = titledVersion
        window?.subtitle = "Server Offline"
    }

    private func installOfflineConstraints(_ v: NSView) {
        if v.superview == nil {
            webView.superview?.addSubview(v)
            v.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: webView.topAnchor),
                v.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
            ])
        }
    }

    private func makeMessageView(icon: String, title: String, detail: String,
                                 showButton: Bool, statusTag: Int,
                                 buttonTitle: String = "Restart Server",
                                 buttonAction: Selector = #selector(restartServer(_:))) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconLbl = NSTextField(labelWithString: icon)
        iconLbl.font = .systemFont(ofSize: 56)
        iconLbl.alignment = .center

        let titleLbl = NSTextField(labelWithString: title)
        titleLbl.font = .boldSystemFont(ofSize: 20)
        titleLbl.alignment = .center

        let detailLbl = NSTextField(wrappingLabelWithString: detail)
        detailLbl.font = .systemFont(ofSize: 13)
        detailLbl.textColor = .secondaryLabelColor
        detailLbl.alignment = .center

        [iconLbl, titleLbl, detailLbl].forEach { stack.addArrangedSubview($0) }

        if showButton {
            let restartButton = NSButton(title: buttonTitle,
                                         target: self,
                                         action: buttonAction)
            restartButton.bezelStyle = .rounded
            restartButton.keyEquivalent = "\r"
            stack.addArrangedSubview(restartButton)
        }

        let status = NSTextField(labelWithString: "")
        status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        status.textColor = .tertiaryLabelColor
        status.alignment = .center
        status.tag = statusTag
        stack.addArrangedSubview(status)

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 560)
        ])
        return view
    }

    private func setStatus(_ text: String) {
        if let v = offlineView?.viewWithTag(4242) as? NSTextField {
            v.stringValue = text
        }
    }

    // MARK: - Actions (menu + button)

    /// FR-1.4: copy the light build's install command to the pasteboard so the
    /// user can run `npm install -g @deepseek-ai/dsh` in a Terminal.
    @objc func copyInstallCommand(_ sender: Any?) {
        let cmd = "npm install -g @deepseek-ai/dsh"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        setStatus("✓ 已复制：\(cmd) — 在终端执行后，用菜单 Server ▸ Restart Server 重试")
        DLog("Copied install command to pasteboard: \(cmd)")
    }

    @objc func restartServer(_ sender: Any?) {
        showStarting()
        setStatus("Restarting embedded server…")
        server.stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.server.startServer(
                onPort: { [weak self] port in
                    self?.setStatus("Server up on port \(port) — loading GUI…")
                },
                onReady: { [weak self] in
                    self?.showWeb()
                    self?.startHeartbeat()
                },
                onExit: { [weak self] msg in
                    self?.showOffline(message: msg)
                }
            )
        }
    }

    @objc func stopServer(_ sender: Any?) {
        server.stopServer()
        setStatus("Server stopped.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if self.server.serverURL == nil {
                self.showOffline(message: "Server stopped.")
            }
        }
    }

    @objc func reload(_ sender: Any?) {
        if server.isServerReachable() {
            showWeb()
        } else {
            showOffline(message: "Server not reachable.")
        }
    }

    @objc func openInBrowser(_ sender: Any?) {
        if let url = server.serverURL {
            NSWorkspace.shared.open(url)
        } else {
            NSSound.beep()
        }
    }

    @objc func showServerStatus(_ sender: Any?) {
        let ok = server.isServerReachable()
        let status: String
        if let url = server.serverURL {
            status = ok ? "Running at \(url.absoluteString)" : "Starting at \(url.absoluteString)…"
        } else {
            status = "Not running"
        }
        let alert = NSAlert()
        alert.messageText = "Server Status"
        alert.informativeText = "\(titledVersion)\n\n\(status)"
        if ok {
            alert.addButton(withTitle: "Open in Browser")
            alert.addButton(withTitle: "OK")
        } else {
            alert.addButton(withTitle: "Restart Server")
            alert.addButton(withTitle: "OK")
        }
        let resp = alert.runModal()
        if ok {
            if resp == .alertFirstButtonReturn { openInBrowser(sender) }
        } else {
            if resp == .alertFirstButtonReturn { restartServer(sender) }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Keep the title bar free of the page <title> ("DeepSeek Harness" would
        // render as a redundant "- DeepSeek Harness" suffix).
        window?.title = titledVersion
        window?.subtitle = ""
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        if ns.code != NSURLErrorCancelled {
            showOffline(message: "Could not load the GUI: \(ns.localizedDescription)")
        }
    }

    // MARK: - WKUIDelegate (external links)

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}
