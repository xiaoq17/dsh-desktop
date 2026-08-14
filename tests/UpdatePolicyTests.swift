// UpdatePolicy unit tests — standalone executable, run by CI and locally via
// `swiftc src/UpdatePolicy.swift tests/UpdatePolicyTests.swift -o /tmp/up-tests`
// then run (spec S-0001 §8.6 T-2/T-5).
//
// UpdatePolicy is Foundation-only by design (no AppKit/UI/IO), so it compiles
// with this file into a plain CLI test runner. Every assertion failure prints
// a message and the process exits non-zero (CI treats that as a build failure).

import Foundation

// MARK: - Minimal assertion harness

private var failures = 0
private var assertions = 0

func expect(_ condition: Bool,
            _ message: @autoclosure () -> String = "assertion failed",
            file: String = #file, line: Int = #line) {
    assertions += 1
    guard !condition else { return }
    failures += 1
    print("✗ \(file):\(line): \(message())")
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                               _ message: @autoclosure () -> String = "",
                               file: String = #file, line: Int = #line) {
    assertions += 1
    guard actual == expected else {
        failures += 1
        let suffix = message().isEmpty ? "" : " — \(message())"
        print("✗ \(file):\(line): expected \(expected), got \(actual)\(suffix)")
        return
    }
}

@main
struct UpdatePolicyTestsRunner {
    static func main() {

// MARK: - compareVersions

// Four-part comparisons.
expectEqual(UpdatePolicy.compareVersions("1.0.0.0", "1.0.0.0"), .orderedSame, "identical")
expectEqual(UpdatePolicy.compareVersions("1.0.0.1", "1.0.0.0"), .orderedDescending, "rev bump")
expectEqual(UpdatePolicy.compareVersions("1.0.0.0", "1.0.0.1"), .orderedAscending, "older")
expectEqual(UpdatePolicy.compareVersions("0.1.0.0", "1.0.0.0"), .orderedAscending, "major")
expectEqual(UpdatePolicy.compareVersions("2.0.0.0", "1.9.9.9"), .orderedDescending, "major wins")

// Component-wise (not lexicographic): 1.10 vs 1.9.
expectEqual(UpdatePolicy.compareVersions("1.10.0.0", "1.9.0.0"), .orderedDescending, "10 > 9 numeric")
expectEqual(UpdatePolicy.compareVersions("1.9.0.0", "1.10.0.0"), .orderedAscending, "9 < 10 numeric")

// Missing trailing components are treated as 0 (padding).
expectEqual(UpdatePolicy.compareVersions("1.0", "1.0.0"), .orderedSame, "pad equal")
expectEqual(UpdatePolicy.compareVersions("1.0", "1.0.0.1"), .orderedAscending, "pad less")
expectEqual(UpdatePolicy.compareVersions("1.0.0.1", "1.0"), .orderedDescending, "pad more")

// Non-numeric components are dropped (compactMap) — malformed input compares by
// the numeric prefix only; keep the historical behaviour.
expectEqual(UpdatePolicy.compareVersions("1.0.0.0", "1.0.0.0-rc.6"), .orderedSame, "prerelease dropped")

// MARK: - isNewer

// Version strictly greater → new, regardless of build.
expect(UpdatePolicy.isNewer(version: "1.0.0.1", build: "aaa",
                            thanCurrentVersion: "1.0.0.0", currentBuild: "bbb"), "rev bump is new")
expect(!UpdatePolicy.isNewer(version: "1.0.0.0", build: "bbb",
                             thanCurrentVersion: "1.0.0.1", currentBuild: "bbb"), "older is not new")

// Same version: different build → new; same build → not new.
expect(UpdatePolicy.isNewer(version: "1.0.0.0", build: "abc",
                            thanCurrentVersion: "1.0.0.0", currentBuild: "def"), "same version, new build")
expect(!UpdatePolicy.isNewer(version: "1.0.0.0", build: "abc",
                             thanCurrentVersion: "1.0.0.0", currentBuild: "abc"), "same version, same build")
expect(!UpdatePolicy.isNewer(version: "1.0.0.0", build: nil,
                             thanCurrentVersion: "1.0.0.0", currentBuild: "abc"), "no build = same")

// MARK: - skipKey

expectEqual(UpdatePolicy.skipKey(version: "0.1.0.0", build: "abc123"), "0.1.0.0@abc123", "composite key")
expectEqual(UpdatePolicy.skipKey(version: "0.1.0.0", build: nil), "0.1.0.0", "bare version")

// MARK: - skipDecision

// No stored skip → proceed.
expectEqual(UpdatePolicy.skipDecision(storedSkip: nil, version: "0.1.0.0", build: "abc"),
            .proceed, "no skip")

// New-style composite key: exact match → skip; different build → proceed.
expectEqual(UpdatePolicy.skipDecision(storedSkip: "0.1.0.0@abc", version: "0.1.0.0", build: "abc"),
            .skip, "composite exact match skips")
expectEqual(UpdatePolicy.skipDecision(storedSkip: "0.1.0.0@abc", version: "0.1.0.0", build: "def"),
            .proceed, "composite different build proceeds")
expectEqual(UpdatePolicy.skipDecision(storedSkip: "0.1.0.0@abc", version: "0.2.0.0", build: "xyz"),
            .proceed, "composite different version proceeds")

// Legacy bare-version skip + manifest WITHOUT build: legacy semantics.
expectEqual(UpdatePolicy.skipDecision(storedSkip: "0.1.0.0", version: "0.1.0.0", build: nil),
            .skip, "legacy bare matches no-build manifest")
expectEqual(UpdatePolicy.skipDecision(storedSkip: "0.1.0.0", version: "0.2.0.0", build: nil),
            .proceed, "legacy bare different version no-build proceeds")

// Legacy bare-version skip + build-carrying manifest of SAME version: clear.
expectEqual(UpdatePolicy.skipDecision(storedSkip: "0.1.0.0", version: "0.1.0.0", build: "abc"),
            .clearStaleSkip, "legacy bare + same-version build-carrying clears")

// Legacy bare-version skip + build-carrying manifest of DIFFERENT version:
// leave untouched, proceed (must NOT act as whole-version wildcard).
expectEqual(UpdatePolicy.skipDecision(storedSkip: "0.1.0.0", version: "0.2.0.0", build: "abc"),
            .proceed, "legacy bare + different-version build-carrying proceeds")

// MARK: - acceptsPlatform / acceptsApp

expect(UpdatePolicy.acceptsPlatform(nil, currentPlatform: "darwin"), "nil platform = any")
expect(UpdatePolicy.acceptsPlatform("", currentPlatform: "darwin"), "empty platform = any")
expect(UpdatePolicy.acceptsPlatform("darwin", currentPlatform: "darwin"), "matching platform")
expect(!UpdatePolicy.acceptsPlatform("win32", currentPlatform: "darwin"), "mismatched platform")

expect(UpdatePolicy.acceptsApp(nil, productName: "dsh-desktop"), "nil app = full build")
expect(UpdatePolicy.acceptsApp("dsh-desktop", productName: "dsh-desktop"), "full matches full")
expect(UpdatePolicy.acceptsApp("dsh-desktop-light", productName: "dsh-desktop-light"), "light matches light")
expect(!UpdatePolicy.acceptsApp("dsh-desktop-light", productName: "dsh-desktop"), "light does not match full")

// MARK: - shouldRestorePending

expect(UpdatePolicy.shouldRestorePending(version: "1.0.0.1", build: "aaa",
                                         currentVersion: "1.0.0.0", currentBuild: "bbb"),
       "newer version restores")
expect(UpdatePolicy.shouldRestorePending(version: "1.0.0.0", build: "aaa",
                                         currentVersion: "1.0.0.0", currentBuild: "bbb"),
       "same version different build restores")
expect(!UpdatePolicy.shouldRestorePending(version: "1.0.0.0", build: "aaa",
                                          currentVersion: "1.0.0.0", currentBuild: "aaa"),
       "same version same build does not restore")
expect(!UpdatePolicy.shouldRestorePending(version: "1.0.0.0", build: nil,
                                          currentVersion: "1.0.0.0", currentBuild: "aaa"),
       "no persisted build = same build, no restore")
expect(!UpdatePolicy.shouldRestorePending(version: "1.0.0.0", build: "aaa",
                                          currentVersion: "1.0.0.1", currentBuild: "bbb"),
       "older version does not restore")

// MARK: - revLabel

expectEqual(UpdatePolicy.revLabel(version: "0.1.0.0", build: "abc"), "v0.1.0.0 (rev:abc)", "with build")
expectEqual(UpdatePolicy.revLabel(version: "0.1.0.0", build: nil), "v0.1.0.0", "no build")
expectEqual(UpdatePolicy.revLabel(version: "0.1.0.0", build: ""), "v0.1.0.0", "empty build")

// MARK: - Summary

        print("\(assertions) assertions, \(failures) failure(s)")
        if failures > 0 {
            print("UpdatePolicy tests FAILED")
            exit(1)
        } else {
            print("UpdatePolicy tests PASSED")
        }
    }
}
