import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

extension WebKitSerializedTests.BridgePaneControllerIPCProjectionTests {
    @Test("IPC revealPath reads a worktree-relative path against the receiver's first member")
    func ipcRevealPath_readsRelativePathAgainstFirstMember() async throws {
        // Arrange — two members list the same relative path under their own groups.
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "bridge-ipc-reveal-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let frontend = try makeRevealPathMember(named: "frontend", in: fixtureRoot)
        let backend = try makeRevealPathMember(named: "backend", in: fixtureRoot)
        let controller = makeRevealPathController(members: [frontend, backend])
        defer { controller.teardown() }

        // Act
        let revealed = try await controller.fileCollectionAddressedPageControl(
            .fileTreeRevealPath(path: "src/index.ts")
        )
        let search = try await controller.fileCollectionAddressedPageControl(
            .fileTreeSearch(searchText: "src/index.ts")
        )

        // Assert
        #expect(revealed == .fileTreeRevealPath(path: "frontend/src/index.ts"))
        #expect(search == .fileTreeSearch(searchText: "src/index.ts"))
    }

    @Test("IPC revealPath is not found when the receiver lists no Files collection")
    func ipcRevealPath_isNotFoundWithoutFilesCollection() async throws {
        // Arrange
        let controller = makeRevealPathController(members: [])
        defer { controller.teardown() }

        // Act / Assert
        await #expect(throws: BridgeIPCProjectionError(reason: .itemNotFound)) {
            _ = try await controller.fileCollectionAddressedPageControl(
                .fileTreeRevealPath(path: "src/index.ts")
            )
        }
    }

    private func makeRevealPathMember(named name: String, in fixtureRoot: URL) throws -> Worktree {
        let rootURL = fixtureRoot.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return Worktree(id: UUIDv7.generate(), repoId: UUIDv7.generate(), name: name, path: rootURL)
    }

    private func makeRevealPathController(members: [Worktree]) -> BridgePaneController {
        let paneId = UUIDv7.generate()
        let statusPhysicalGate = AgentStudioGitStatusPhysicalGate()
        let gitReadContext = members.first.map { makeBridgeGitReadContext(rootURL: $0.path) }
        return BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(panelKind: .fileViewer),
            sourceConfiguration: BridgePaneSourceConfiguration(
                review: nil,
                files: members.isEmpty
                    ? nil
                    : BridgeFilesSourceBinding(
                        collectionToken: BridgeFilesSourceBinding.collectionToken(forReceiverPaneId: paneId),
                        members: members,
                        openedDocuments: []
                    )
            ),
            appRootURL: testBridgeAppRootURL(),
            metadata: PaneMetadata(
                contentType: .diff,
                title: "Bridge Reveal Path",
                facets: PaneContextFacets(worktreeId: members.first?.id)
            ),
            gitReadContext: gitReadContext,
            worktreeProductConstructionCoordinator: BridgeWorktreeProductConstructionCoordinator(),
            gitWorkingTreeStatusProvider: AgentStudioGitWorkingTreeStatusProvider(
                physicalGate: statusPhysicalGate
            ),
            initialPaneActivity: .foreground
        )
    }
}
