import XCTest
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
final class GhosttyResourcesTests: XCTestCase {

    /// Project root derived from compile-time source path.
    private var projectRoot: String {
        // #file → .../Tests/AgentStudioTests/Session/GhosttyResourcesTests.swift
        // Walk up 4 levels to reach the project root.
        var url = URL(fileURLWithPath: #file)
        for _ in 0..<4 { url = url.deletingLastPathComponent() }
        return url.path
    }

    /// Path to the Resources directory in the source tree.
    private var resourcesDir: String {
        projectRoot + "/Sources/AgentStudio/Resources"
    }

    // MARK: - Source Tree Layout

    func test_sourceTree_containsTerminfoSentinel() {
        // The build script (build-ghostty.sh) copies terminfo into Resources.
        // This file must exist for the GHOSTTY_RESOURCES_DIR resolution to work.
        let sentinel = resourcesDir + "/terminfo/78/xterm-ghostty"
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sentinel),
            "xterm-ghostty terminfo must exist at: \(sentinel)"
        )
    }

    func test_sourceTree_terminfoDirectoryIsDirectory() {
        let terminfoDir = resourcesDir + "/terminfo"
        var isDir: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: terminfoDir, isDirectory: &isDir) && isDir.boolValue,
            "terminfo must be a directory at: \(terminfoDir)"
        )
    }

    // MARK: - Dirname Convention

    func test_ghosttyDirnameConvention_holdsForResourcesSlashGhostty() {
        // resolveGhosttyResourcesDir() returns `<resourcesDir>/ghostty`.
        // Verify that dirname(<resourcesDir>/ghostty) + "/terminfo" resolves correctly.
        let simulatedGhosttyResourcesDir = resourcesDir + "/ghostty"
        let computedTerminfo = (simulatedGhosttyResourcesDir as NSString)
            .deletingLastPathComponent + "/terminfo"

        // computedTerminfo should equal <resourcesDir>/terminfo
        XCTAssertEqual(
            computedTerminfo,
            resourcesDir + "/terminfo",
            "dirname(GHOSTTY_RESOURCES_DIR) + /terminfo should resolve to Resources/terminfo"
        )

        // And the xterm-ghostty entry must exist there
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: computedTerminfo + "/78/xterm-ghostty"),
            "xterm-ghostty must exist at the computed TERMINFO path: \(computedTerminfo)/78/xterm-ghostty"
        )
    }

    // MARK: - SPM Bundle Layout (post-build)

    func test_spmBundle_containsTerminfoIfPresent() {
        // After `swift build`, the SPM bundle at .build/debug/AgentStudio_AgentStudio.bundle
        // should also contain terminfo. This test verifies the built artifact if it exists.
        let bundlePath = projectRoot + "/.build/debug/AgentStudio_AgentStudio.bundle"
        let sentinel = bundlePath + "/terminfo/78/xterm-ghostty"

        guard FileManager.default.fileExists(atPath: bundlePath) else {
            // Bundle not built yet — skip (not a failure, just a build-order issue)
            return
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sentinel),
            "SPM bundle should contain xterm-ghostty at: \(sentinel)"
        )

        // Verify dirname convention holds for the bundle path too
        let simulatedDir = bundlePath + "/ghostty"
        let computedTerminfo = (simulatedDir as NSString).deletingLastPathComponent + "/terminfo"
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: computedTerminfo + "/78/xterm-ghostty"),
            "dirname convention must hold for SPM bundle: \(computedTerminfo)/78/xterm-ghostty"
        )
    }
}
