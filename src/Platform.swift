import Foundation

/// Central point for platform-dependent decisions in the shell.
///
/// The shell is deliberately kept thin: its logic is OS-agnostic and every
/// platform-specific detail (identity token, path defaults) lives here. A
/// future port — e.g. a Tauri Rust shell targeting Windows — has a single,
/// small place to mirror when reusing the shared core (embedded Node backend,
/// web GUI, update protocol, versioning).
enum Platform {

    /// Stable platform token used in the update manifest (`platform` field).
    /// Values follow Node's `process.platform` convention (`darwin`, `win32`).
    static var current: String {
        #if os(macOS)
        return "darwin"
        #elseif os(Windows)
        return "win32"
        #else
        return "other"
        #endif
    }

    /// Default user-data directory for the profile (the `DSH_HOME` concept).
    /// On macOS this is `~/.dsh`; a Windows port would use `%APPDATA%`.
    static var defaultHomePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh").path
    }
}
