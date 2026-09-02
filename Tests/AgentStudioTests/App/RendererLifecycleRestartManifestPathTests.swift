import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio

@Suite("Renderer lifecycle restart manifest path")
@MainActor
struct RendererLifecycleRestartManifestPathTests {
    @Test("accepts canonical and symlinked dedicated tmp roots")
    func acceptsDedicatedTmpRoots() {
        let canonicalPath =
            "/private/tmp/agentstudio-renderer-lifecycle.proof/restart-manifest.json"
        let symlinkedPath =
            "/tmp/agentstudio-renderer-lifecycle.proof/restart-manifest.json"

        #expect(
            AppDelegate.validatedRendererLifecycleRestartManifestURL(rawPath: canonicalPath)?.path
                == canonicalPath
        )
        #expect(
            AppDelegate.validatedRendererLifecycleRestartManifestURL(rawPath: symlinkedPath)?.path
                == canonicalPath
        )
    }

    @Test("accepts an existing manifest after Foundation resolves the tmp alias")
    func acceptsExistingManifestAfterTmpAliasResolution() throws {
        let proofRoot = URL(
            fileURLWithPath:
                "/private/tmp/agentstudio-renderer-lifecycle.\(UUIDv7.generate().uuidString)"
        )
        let manifestURL = proofRoot.appending(path: "restart-manifest.json")
        try FileManager.default.createDirectory(at: proofRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: proofRoot) }
        try Data().write(to: manifestURL)

        #expect(
            AppDelegate.validatedRendererLifecycleRestartManifestURL(rawPath: manifestURL.path) != nil
        )
    }

    @Test("rejects paths outside the dedicated proof root")
    func rejectsPathsOutsideDedicatedProofRoot() {
        #expect(
            AppDelegate.validatedRendererLifecycleRestartManifestURL(
                rawPath: "/private/tmp/restart-manifest.json"
            ) == nil
        )
        #expect(
            AppDelegate.validatedRendererLifecycleRestartManifestURL(
                rawPath: "/private/tmp/agentstudio-renderer-lifecycle.proof/../restart-manifest.json"
            ) == nil
        )
        #expect(AppDelegate.validatedRendererLifecycleRestartManifestURL(rawPath: nil) == nil)
    }
}
