import Testing
import Foundation

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
        #expect(FileManager.default.fileExists(atPath: terminfoDir, isDirectory: &isDir) && isDir.boolValue, "terminfo must be a directory at: \(terminfoDir)")
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
        #expect(computedTerminfo == resourcesDir + "/terminfo", "dirname(GHOSTTY_RESOURCES_DIR) + /terminfo should resolve to Resources/terminfo")

        // And the xterm-ghostty entry must exist there
        #expect(FileManager.default.fileExists(atPath: computedTerminfo + "/78/xterm-ghostty"), "xterm-ghostty must exist at the computed TERMINFO path: \(computedTerminfo)/78/xterm-ghostty")
    }

    // MARK: - SPM Bundle Layout (post-build)

    @Test
    func test_spmBundle_containsTerminfoIfPresent() {
        // After `swift build`, the SPM bundle at .build/debug/AgentStudio_AgentStudio.bundle
        // should also contain terminfo. This test verifies the built artifact if it exists.
        let bundlePath = projectRoot + "/.build/debug/AgentStudio_AgentStudio.bundle"
        let sentinel = bundlePath + "/terminfo/78/xterm-ghostty"

        guard FileManager.default.fileExists(atPath: bundlePath) else {
            // Bundle not built yet — skip (not a failure, just a build-order issue)
            return
        }

        #expect(FileManager.default.fileExists(atPath: sentinel), "SPM bundle should contain xterm-ghostty at: \(sentinel)")

        // Verify dirname convention holds for the bundle path too
        let simulatedDir = bundlePath + "/ghostty"
        let computedTerminfo = (simulatedDir as NSString).deletingLastPathComponent + "/terminfo"
        #expect(FileManager.default.fileExists(atPath: computedTerminfo + "/78/xterm-ghostty"), "dirname convention must hold for SPM bundle: \(computedTerminfo)/78/xterm-ghostty")
    }
}
