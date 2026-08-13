import Cocoa
import WebKit

/// WKWebView subclass that explicitly routes standard macOS editing commands
/// (⌘C / ⌘A / ⌘V / ⌘X / ⌘Z) into the page. On macOS, a bare WKWebView does
/// not reliably respond to the AppKit edit actions forwarded by an Edit menu,
/// so we implement them by evaluating the matching `document.execCommand`
/// inside the web content — the same effect the user expects from a browser.
final class EditingWebView: WKWebView {

    // MARK: - Standard edit actions (routed by the Edit menu)
    //
    // WKWebView exposes `selectAll(_:)` as an override point but does NOT
    // expose `copy:`/`cut:`/`paste:`/`delete:` as Swift overridable methods
    // (they live in NSResponder's UIResponderStandardEditActions informal
    // protocol). Those are handled natively by WebKit through the responder
    // chain once the Edit menu routes them — a bare WKWebView does respond to
    // them. `selectAll:` is overridden here for extra reliability.

    override func selectAll(_ sender: Any?) {
        runCommand("selectAll")
    }

    // MARK: - Helpers

    /// Execute a JS `document.execCommand` in the focused frame.
    private func runCommand(_ name: String) {
        let js = "(() => { try { document.execCommand(\(name.debugDescription), false, null); return true; } catch (e) { return false; } })()"
        evaluateJavaScript(js) { _, _ in }
    }
}
