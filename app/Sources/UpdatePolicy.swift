import Foundation

/// Pure update-policy logic, extracted from `UpdateManager` so it can be unit
/// tested without AppKit/UI/IO coupling (spec S-0001 §8.6 T-1/T-2).
///
/// Every decision here is a pure function of its inputs — no UserDefaults,
/// no Bundle, no filesystem — so the same policy is exercised by tests and by
/// the app alike.
enum UpdatePolicy {

    // MARK: - Version comparison

    /// Compare two dot-separated numeric version strings component-wise.
    /// Missing trailing components are treated as 0 (`1.0` == `1.0.0`).
    /// A prerelease suffix (`-rc.6`) is stripped before comparing, so
    /// `1.0.0.0-rc.6` compares equal to `1.0.0.0` — mirrors how `build.sh`
    /// derives the desktop triple from the dsh `package.json`.
    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let ac = a.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        let bc = b.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        for i in 0..<max(ac.count, bc.count) {
            let av = i < ac.count ? ac[i] : 0
            let bv = i < bc.count ? bc[i] : 0
            if av != bv { return av > bv ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }

    /// Newer when the manifest's four-part version is greater, or — as a
    /// tiebreaker for equal versions — when its `build` differs from the
    /// current build. Version-string comparison takes precedence: the desktop
    /// version is `dshMajor.dshMinor.dshPatch.desktopRev`, and the desktopRev
    /// resets to 0 on a dsh upgrade, so the `build` alone would wrongly report
    /// a downgrade in that case (spec S-0001 §7.2).
    static func isNewer(version: String, build: String?,
                        thanCurrentVersion currentVersion: String,
                        currentBuild: String) -> Bool {
        let c = compareVersions(version, currentVersion)
        if c != .orderedSame { return c == .orderedDescending }
        // Same version (desktop rev equal): any different build = new build.
        // A missing build means "same as current" (no update).
        if let build { return build != currentBuild }
        return false
    }

    // MARK: - Skip / pending keys

    /// Composite identity of an update for skip/pending bookkeeping:
    /// `version@build` when the manifest carries a build, plain `version`
    /// otherwise (backwards compatible with manifests that predate `build`).
    /// A same-version different-build release is therefore a DIFFERENT update
    /// and is never shadowed by a skip or a staged update of another build
    /// (spec S-0001 §7.2).
    static func skipKey(version: String, build: String?) -> String {
        if let build { return "\(version)@\(build)" }
        return version
    }

    /// Whether a stored skip value should suppress a given manifest.
    /// Returns a decision plus any store mutation needed:
    /// - `.skip` — suppress this update;
    /// - `.proceed` — offer/start the update;
    /// - `.clearStaleSkip` — proceed AND drop the stale legacy skip value
    ///   (it can only express "skip this whole version" and would otherwise
    ///   swallow a same-version new build).
    enum SkipDecision: Equatable {
        case skip
        case proceed
        case clearStaleSkip
    }

    static func skipDecision(storedSkip: String?,
                             version: String,
                             build: String?) -> SkipDecision {
        guard let storedSkip else { return .proceed }
        if storedSkip.contains("@") {
            // New-style composite key (version@build): exact match only.
            return storedSkip == skipKey(version: version, build: build) ? .skip : .proceed
        }
        if build == nil {
            // Old-format manifest (no build) + legacy plain-version skip:
            // keep the legacy "skip this version" behaviour.
            return storedSkip == version ? .skip : .proceed
        }
        if storedSkip == version {
            // Legacy plain-version skip meets a build-carrying manifest of the
            // SAME version: drop the stale value so the same-version new build
            // is offered. Skips of other versions are left untouched.
            return .clearStaleSkip
        }
        return .proceed
    }

    // MARK: - Manifest applicability

    /// Whether a build on this platform should apply an update whose manifest
    /// targets `platform`. A `nil`/empty value means "any platform" and is
    /// always accepted (backwards compatible with older manifests).
    static func acceptsPlatform(_ platform: String?, currentPlatform: String) -> Bool {
        guard let platform, !platform.isEmpty else { return true }
        return platform == currentPlatform
    }

    /// Whether an update targeting variant `app` applies to this build's
    /// `productName`. A missing `app` means the full build (backwards
    /// compatible with manifests that predate this field).
    static func acceptsApp(_ app: String?, productName: String) -> Bool {
        (app ?? "dsh-desktop") == productName
    }

    // MARK: - Pending restore

    /// Whether a persisted pending update (from a previous session) should be
    /// re-surfaced: newer version, OR same version with a different build
    /// (spec S-0001 §7.2 build tiebreaker). A missing persisted build is
    /// treated as "same build" to stay backwards compatible.
    static func shouldRestorePending(version: String,
                                     build: String?,
                                     currentVersion: String,
                                     currentBuild: String) -> Bool {
        switch compareVersions(version, currentVersion) {
        case .orderedDescending: return true
        case .orderedSame: return build.map { $0 != currentBuild } ?? false
        case .orderedAscending: return false
        }
    }

    // MARK: - Presentation

    /// User-facing "v<version> (rev:<build>)" label (spec S-0001 FR-9.10).
    /// Falls back to version-only when the build is missing.
    static func revLabel(version: String, build: String?) -> String {
        if let build, !build.isEmpty { return "v\(version) (rev:\(build))" }
        return "v\(version)"
    }
}
