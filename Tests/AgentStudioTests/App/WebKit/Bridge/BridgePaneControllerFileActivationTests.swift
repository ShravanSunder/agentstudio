import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

extension WebKitSerializedTests {
    /// Controller-side edges of the navigation barrier and exact File
    /// activation that hold without a loaded page.
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerFileActivationTests {
        init() {
            installTestCoreAtomsIfNeeded()
        }

        @Test("the editor barrier reports no live page before the product session is installed")
        func editorBarrierWithoutLivePage() async throws {
            // Arrange
            let fixture = try FileActivationFixture()
            defer { fixture.remove() }
            let controller = fixture.makeController(openedDocuments: [])
            defer { _ = controller.beginTeardown() }  // fire-and-forget: defer cannot await; cleanup only

            // Act
            let outcome = await controller.prepareActiveEditorsForNavigation()

            // Assert
            #expect(outcome == .noLivePage)
            #expect(outcome.allowsContentToLeave, "no page editor can hold unflushed text")
        }

        @Test("a document the collection does not list is refused before any page request")
        func unlistedDocumentIsNotListed() async throws {
            // Arrange
            let fixture = try FileActivationFixture()
            defer { fixture.remove() }
            let controller = fixture.makeController(openedDocuments: [])
            defer { _ = controller.beginTeardown() }  // fire-and-forget: defer cannot await; cleanup only
            let unlisted = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/not-opened/plan.md"))

            // Act
            let arrival = await controller.activateFileDocument(unlisted)

            // Assert
            #expect(arrival == .notListed)
        }

        @Test("a listed document without a live Files source is cancelled, not guessed")
        func listedDocumentWithoutLiveSourceIsCancelled() async throws {
            // Arrange
            let fixture = try FileActivationFixture()
            defer { fixture.remove() }
            let controller = fixture.makeController(openedDocuments: [fixture.looseNotes])
            defer { _ = controller.beginTeardown() }  // fire-and-forget: defer cannot await; cleanup only

            // Act
            let arrival = await controller.activateFileDocument(fixture.looseNotes)

            // Assert
            #expect(arrival == .cancelled)
        }
    }
}

@MainActor
private struct FileActivationFixture {
    let root: URL
    let member: Worktree
    let looseNotes: BridgeDocumentLocation

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "bridge-file-activation-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let memberRoot = root.appending(path: "frontend", directoryHint: .isDirectory)
        let looseDirectory = root.appending(path: "outside-git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: memberRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: looseDirectory, withIntermediateDirectories: true)
        let notesURL = looseDirectory.appending(path: "notes.md")
        try Data("# Notes\n".utf8).write(to: notesURL)
        member = Worktree(id: UUIDv7.generate(), repoId: UUIDv7.generate(), name: "frontend", path: memberRoot)
        looseNotes = try #require(
            BridgeDocumentLocation(
                canonicalPath: DarwinFSEventPathCanonicalizer.canonicalURL(notesURL).path
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func makeController(openedDocuments: [BridgeDocumentLocation]) -> BridgePaneController {
        let paneId = UUIDv7.generate()
        return BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(panelKind: .fileViewer),
            sourceConfiguration: BridgePaneSourceConfiguration(
                review: nil,
                files: BridgeFilesSourceBinding(
                    collectionToken: BridgeFilesSourceBinding.collectionToken(forReceiverPaneId: paneId),
                    members: [member],
                    openedDocuments: openedDocuments
                )
            ),
            appRootURL: testBridgeAppRootURL(),
            metadata: PaneMetadata(
                contentType: .diff,
                title: "Bridge File Activation",
                facets: PaneContextFacets(worktreeId: member.id)
            ),
            gitReadContext: makeBridgeGitReadContext(rootURL: member.path),
            worktreeProductConstructionCoordinator: BridgeWorktreeProductConstructionCoordinator(),
            gitWorkingTreeStatusProvider: AgentStudioGitWorkingTreeStatusProvider(
                physicalGate: AgentStudioGitStatusPhysicalGate()
            ),
            initialPaneActivity: .foreground
        )
    }
}
