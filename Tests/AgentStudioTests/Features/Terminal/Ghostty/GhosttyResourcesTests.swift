import Foundation
import Testing

@testable import AgentStudio

/// Tests that the terminfo resource layout satisfies GhosttyKit's dirname convention.
///
/// GhosttyKit computes `TERMINFO = dirname(GHOSTTY_RESOURCES_DIR) + "/terminfo"`,
/// so any resolved GHOSTTY_RESOURCES_DIR must be a subdirectory whose parent
/// contains `terminfo/78/xterm-ghostty`.
///
/// These tests verify the source-tree layout directly (using #file to find the
/// project root) because `Bundle.main` in the test runner context doesn't resolve
/// to the app bundle.
@Suite(.serialized)
final class GhosttyResourcesTests {

    /// Project root derived from compile-time source path.
    private var projectRoot: String {
        // #file → /Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyResourcesTests.swift
        // Walk up to the enclosing repo containing Package.swift, regardless of layout.
        TestPathResolver.projectRoot(from: #filePath)
    }

    /// Path to the Resources directory in the source tree.
    private var resourcesDir: String {
        projectRoot + "/Sources/AgentStudio/Resources"
    }

    /// Discover the SPM-built AgentStudio resource bundle across local build directories.
    private func findBuiltResourceBundlePath() -> String? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        var candidateRoots: [String] = []
        if let swiftBuildDir = environment["SWIFT_BUILD_DIR"], !swiftBuildDir.isEmpty {
            candidateRoots.append(swiftBuildDir)
        }
        if let swiftPMBuildDir = environment["SWIFTPM_BUILD_DIR"], !swiftPMBuildDir.isEmpty {
            candidateRoots.append(swiftPMBuildDir)
        }

        if let entries = try? fileManager.contentsOfDirectory(atPath: projectRoot) {
            let localBuildRoots =
                entries
                .filter { $0.hasPrefix(".build") }
                .map { projectRoot + "/" + $0 }
            candidateRoots.append(contentsOf: localBuildRoots)
        }

        // Derive likely build roots from the running test executable location.
        // This supports custom `swift test --build-path <path>` locations.
        if let executablePath = CommandLine.arguments.first, !executablePath.isEmpty {
            var cursor = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
            for _ in 0..<6 {
                candidateRoots.append(cursor.path)
                let parent = cursor.deletingLastPathComponent()
                if parent.path == cursor.path {
                    break
                }
                cursor = parent
            }
        }

        var seen: Set<String> = []
        for root in candidateRoots where seen.insert(root).inserted {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let directCandidate = root + "/AgentStudio_AgentStudio.bundle"
            if fileManager.fileExists(atPath: directCandidate, isDirectory: &isDirectory), isDirectory.boolValue {
                return directCandidate
            }

            guard let enumerator = fileManager.enumerator(atPath: root) else {
                continue
            }

            for case let relativePath as String in enumerator {
                guard relativePath.hasSuffix("AgentStudio_AgentStudio.bundle") else {
                    continue
                }
                return root + "/" + relativePath
            }
        }

        return nil
    }

    // MARK: - Source Tree Layout

    @Test
    func test_sourceTree_containsTerminfoSentinel() {
        // The build script (build-ghostty.sh) copies terminfo into Resources.
        // This file must exist for the GHOSTTY_RESOURCES_DIR resolution to work.
        let sentinel = resourcesDir + "/terminfo/78/xterm-ghostty"
        #expect(FileManager.default.fileExists(atPath: sentinel), "xterm-ghostty terminfo must exist at: \(sentinel)")
    }

    @Test
    func test_sourceTree_terminfoDirectoryIsDirectory() {
        let terminfoDir = resourcesDir + "/terminfo"
        var isDir: ObjCBool = false
        #expect(
            FileManager.default.fileExists(atPath: terminfoDir, isDirectory: &isDir) && isDir.boolValue,
            "terminfo must be a directory at: \(terminfoDir)")
    }

    // MARK: - Dirname Convention

    @Test
    func test_ghosttyDirnameConvention_holdsForResourcesSlashGhostty() {
        // resolveGhosttyResourcesDir() returns `<resourcesDir>/ghostty`.
        // Verify that dirname(<resourcesDir>/ghostty) + "/terminfo" resolves correctly.
        let simulatedGhosttyResourcesDir = resourcesDir + "/ghostty"
        let computedTerminfo =
            (simulatedGhosttyResourcesDir as NSString)
            .deletingLastPathComponent + "/terminfo"

        // computedTerminfo should equal <resourcesDir>/terminfo
        #expect(
            computedTerminfo == resourcesDir + "/terminfo",
            "dirname(GHOSTTY_RESOURCES_DIR) + /terminfo should resolve to Resources/terminfo")

        // And the xterm-ghostty entry must exist there
        #expect(
            FileManager.default.fileExists(atPath: computedTerminfo + "/78/xterm-ghostty"),
            "xterm-ghostty must exist at the computed TERMINFO path: \(computedTerminfo)/78/xterm-ghostty")
    }

    // MARK: - SPM Bundle Layout (post-build)

    @Test
    func test_spmBundle_containsTerminfoIfPresent() {
        // After `swift build`/`swift test`, the SPM bundle should also contain terminfo.
        // Build products may live under `.build` or a custom `--build-path`.
        guard let bundlePath = findBuiltResourceBundlePath() else {
            Issue.record(
                """
                Could not find AgentStudio_AgentStudio.bundle under local build roots.
                Ensure tests are run after a successful SwiftPM build in this workspace.
                """
            )
            return
        }
        let sentinel = bundlePath + "/terminfo/78/xterm-ghostty"

        #expect(FileManager.default.fileExists(atPath: bundlePath), "SPM bundle should exist at: \(bundlePath)")

        #expect(
            FileManager.default.fileExists(atPath: sentinel), "SPM bundle should contain xterm-ghostty at: \(sentinel)")

        // Verify dirname convention holds for the bundle path too
        let simulatedDir = bundlePath + "/ghostty"
        let computedTerminfo = (simulatedDir as NSString).deletingLastPathComponent + "/terminfo"
        #expect(
            FileManager.default.fileExists(atPath: computedTerminfo + "/78/xterm-ghostty"),
            "dirname convention must hold for SPM bundle: \(computedTerminfo)/78/xterm-ghostty")
    }
}
