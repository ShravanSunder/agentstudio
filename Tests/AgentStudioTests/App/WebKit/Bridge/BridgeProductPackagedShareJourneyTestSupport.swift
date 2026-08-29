import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
import WebKit

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioTestSupport

struct BridgeProductPackagedShareJourneyProof: Sendable {
    let clipboardBytes: Data
    let exportedJSON: Data
    let fileHistoryCount: Int
    let fileUnavailableCommentsExcluded: Bool
    let hostWidth: Double
    let reviewHistoryCount: Int
    let reviewPendingCount: Int
}

extension WebKitSerializedTests.BridgeProductRealGitFileAndReviewWebKitTests {
    @Test("packaged File and Review Share performs exact App effects and durable unhandle")
    func packagedFileAndReviewSharePerformsExactEffectsAndUnhandle() async throws {
        let proof = try await BridgeProductPackagedShareJourneyTestSupport.run(self)

        #expect(proof.reviewPendingCount == 1)
        #expect(proof.reviewHistoryCount == 1)
        #expect(proof.fileUnavailableCommentsExcluded)
        #expect(proof.fileHistoryCount == 2)
        #expect(proof.clipboardBytes.contains(Data("Packaged Share comment".utf8)))
        #expect(proof.exportedJSON.contains(Data("Packaged Share comment".utf8)))
        #expect(proof.hostWidth == 640)
    }
}

@MainActor
enum BridgeProductPackagedShareJourneyTestSupport {
    private struct JourneyHarness {
        let controller: BridgePaneController
        let exportedJSONURL: URL
        let pasteboard: NSPasteboard
        let repositoryURL: URL
        let stateRoot: URL
        let store: WorktreeAnnotationServiceActor

        func destroy() {
            FilesystemTestGitRepo.destroy(repositoryURL)
            try? FileManager.default.removeItem(at: stateRoot)
        }
    }

    private struct ShareDOMSnapshot: Decodable {
        let allCount: Int
        let historyCount: Int
        let pendingCount: Int
        let otherSavedCommentsVisible: Bool
        let shareVisible: Bool
    }

    static func run(
        _ testOwner: WebKitSerializedTests.BridgeProductRealGitFileAndReviewWebKitTests
    ) async throws -> BridgeProductPackagedShareJourneyProof {
        let harness = try await makeJourneyHarness(testOwner)
        defer { harness.destroy() }

        return try await BridgeProductWebKitCarrierTestSupport.withHostedController(
            harness.controller,
            frame: NSRect(x: 0, y: 0, width: 640, height: 720)
        ) { hostedController in
            hostedController.loadApp()
            try await requirePackagedReviewReady(hostedController)
            _ = try await seedReviewAnnotation(
                controller: hostedController,
                repositoryURL: harness.repositoryURL,
                store: harness.store
            )
            try await requireEnabledButton(hostedController.page, label: "Share comments")
            try await clickButton(hostedController.page, label: "Share comments")
            _ = try await requireShareSnapshot(hostedController.page, stage: "review-pending") {
                $0.shareVisible && $0.pendingCount == 1
            }
            try await clickButton(hostedController.page, label: "Copy Markdown")
            _ = try await requireShareSnapshot(hostedController.page, stage: "review-copy-dismiss") {
                !$0.shareVisible
            }
            let clipboardBytes = try #require(harness.pasteboard.data(forType: .string))

            try await clickButton(hostedController.page, label: "Share comments")
            _ = try await requireShareSnapshot(hostedController.page, stage: "review-history") {
                $0.shareVisible && $0.historyCount == 1
            }
            try await clickButton(hostedController.page, label: "History (1)")
            try await clickButton(hostedController.page, label: "Mark as not handled")
            let reviewAfterUnhandle = try await requireShareSnapshot(
                hostedController.page,
                stage: "review-unhandle"
            ) {
                $0.pendingCount == 1
            }
            try await clickButton(hostedController.page, label: "Close Share comments")

            let fileProof = try await performFileExport(
                controller: hostedController,
                exportedJSONURL: harness.exportedJSONURL
            )
            return BridgeProductPackagedShareJourneyProof(
                clipboardBytes: clipboardBytes,
                exportedJSON: fileProof.exportedJSON,
                fileHistoryCount: fileProof.history.historyCount,
                fileUnavailableCommentsExcluded: !fileProof.beforeExport.otherSavedCommentsVisible,
                hostWidth: 640,
                reviewHistoryCount: reviewAfterUnhandle.historyCount,
                reviewPendingCount: reviewAfterUnhandle.pendingCount
            )
        }.value
    }

    private static func makeJourneyHarness(
        _ testOwner: WebKitSerializedTests.BridgeProductRealGitFileAndReviewWebKitTests
    ) async throws -> JourneyHarness {
        let repositoryURL = try FilesystemTestGitRepo.create(named: "bridge-packaged-share-webkit")
        let stateRoot = FileManager.default.temporaryDirectory.appending(
            path: "bridge-packaged-share-state-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let exportedJSONURL = stateRoot.appending(path: "review-comments.json")
        try FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let alternateFileURL = repositoryURL.appending(path: "alternate.txt")
        try "alternate initial\n".write(to: alternateFileURL, atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["add", "alternate.txt"])
        try FilesystemTestGitRepo.runGit(
            at: repositoryURL,
            args: ["commit", "-m", "Add alternate packaged Share file"]
        )
        try "alternate initial\nalternate updated\n".write(
            to: alternateFileURL,
            atomically: true,
            encoding: .utf8
        )

        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: stateRoot.appending(path: "core.sqlite"),
            localDatabaseURL: stateRoot.appending(path: "local.sqlite")
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            throw WorktreeAnnotationServiceError.unavailable
        }
        let store = WorktreeAnnotationServiceActor(
            sqliteAdapter: .init(workspaceID: UUIDv7.generate(), datastore: datastore)
        )
        let pasteboard = NSPasteboard(
            name: .init("agentstudio.packaged-share.\(UUIDv7.generate().uuidString)")
        )
        let savePanel = PackagedShareJSONDestinationPanel(url: exportedJSONURL)
        let outputCoordinator = WorktreeAnnotationOutputCoordinatorActor(
            store: store,
            effect: WorktreeAnnotationOutputEffects(
                pasteboard: pasteboard,
                makeSavePanel: { savePanel }
            )
        )
        let traceRecorder = BridgeProductWebKitCarrierTraceRecorder()
        let controller = testOwner.makeController(
            repoURL: repositoryURL,
            traceRecorder: traceRecorder,
            worktreeAnnotationStore: store,
            worktreeAnnotationOutputCoordinator: outputCoordinator
        )
        return JourneyHarness(
            controller: controller,
            exportedJSONURL: exportedJSONURL,
            pasteboard: pasteboard,
            repositoryURL: repositoryURL,
            stateRoot: stateRoot,
            store: store
        )
    }

    private static func performFileExport(
        controller: BridgePaneController,
        exportedJSONURL: URL
    ) async throws -> (
        beforeExport: ShareDOMSnapshot,
        exportedJSON: Data,
        history: ShareDOMSnapshot
    ) {
        guard await BridgeProductWebKitCarrierTestSupport.activateFileMode(controller.page) else {
            throw PackagedShareJourneyError.fileModeUnavailable
        }
        let selectedDifferentFile = await BridgeProductWebKitCarrierTestSupport.waitUntil(
            timeout: .seconds(20)
        ) {
            guard
                await BridgeProductWebKitCarrierTestSupport.selectFilePath(
                    controller.page,
                    path: "alternate.txt"
                )
            else { return false }
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            return dom?.fileReadableText.contains("alternate updated") == true
        }
        guard selectedDifferentFile else {
            throw PackagedShareJourneyError.fileSelectionUnavailable
        }
        try await requireEnabledButton(controller.page, label: "Share comments")
        try await clickButton(controller.page, label: "Share comments")
        try await clickButtonWithPrefix(controller.page, prefix: "All")
        let beforeExport = try await requireShareSnapshot(controller.page, stage: "file-other") {
            $0.shareVisible && !$0.otherSavedCommentsVisible && $0.allCount == 1
        }
        try await clickButton(controller.page, label: "Export JSON")
        try await requireFile(exportedJSONURL)
        _ = try await requireShareSnapshot(controller.page, stage: "file-export-dismiss") {
            !$0.shareVisible
        }
        let exportedJSON = try Data(contentsOf: exportedJSONURL)

        try await clickButton(controller.page, label: "Share comments")
        let history = try await requireShareSnapshot(controller.page, stage: "file-history") {
            $0.shareVisible && $0.historyCount == 2
        }
        return (beforeExport, exportedJSON, history)
    }

    private static func requirePackagedReviewReady(_ controller: BridgePaneController) async throws {
        let ready = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(20)) {
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            guard let productAdmission = controller.productAdmissionGate.acquire(),
                let publication = controller.reviewPublicationCoordinator
                    .committedPublicationForReplay(productAdmission: productAdmission)
            else { return false }
            return dom?.hasAppRoot == true
                && dom?.hasReviewShell == true
                && !publication.package.itemsById.isEmpty
        }
        guard ready else { throw PackagedShareJourneyError.reviewUnavailable }
    }

    private static func seedReviewAnnotation(
        controller: BridgePaneController,
        repositoryURL: URL,
        store: WorktreeAnnotationServiceActor
    ) async throws -> String {
        let productAdmission = try #require(controller.productAdmissionGate.acquire())
        let publication = try #require(
            controller.reviewPublicationCoordinator.committedPublicationForReplay(
                productAdmission: productAdmission
            )
        )
        let fingerprint = try await WorktreeAnnotationSourceCapture.reviewRefresh(
            identity: BridgeProductReviewAnnotationPublicationIdentity(
                packageId: publication.package.packageId,
                publicationId: publication.publicationId,
                reviewGeneration: publication.package.reviewGeneration.rawValue,
                revision: publication.package.revision,
                sourceIdentity: publication.package.query.queryId
            ),
            publicationCoordinator: controller.reviewPublicationCoordinator,
            contentLoaderCache: controller.reviewContentLoaderCache,
            requirements: [],
            productAdmission: productAdmission
        ).fingerprint
        let item = try #require(
            publication.package.itemsById.values.first {
                $0.headPath == "tracked.txt" && $0.contentRoles.head != nil
            }
        )
        let path = try #require(item.headPath)
        let handle = try #require(item.contentRoles.head)
        let source = try String(
            contentsOf: repositoryURL.appending(path: path),
            encoding: .utf8
        )
        let sourceLines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLine = sourceLines.first.map(String.init) ?? ""
        let secondLine = sourceLines.dropFirst().first.map(String.init)
        var detail = try await store.createRootDraft(
            .init(
                admission: .implicitOrSingle,
                repositoryID: fingerprint.repositoryID,
                worktreeID: fingerprint.worktreeID,
                sourceFingerprint: fingerprint,
                origin: .located(
                    .init(
                        repositoryRelativePath: path,
                        startLine: 1,
                        endLine: 1,
                        sourceRole: .reviewHead,
                        diffSide: .additions,
                        sourceIdentity: handle.handleId,
                        selectedExcerpt: firstLine,
                        contextBefore: nil,
                        contextAfter: secondLine
                    )
                ),
                body: "## Packaged Share comment\n\nPreserve exact output bytes.",
                editToken: "packaged-share-editor",
                now: Date(timeIntervalSince1970: 1)
            )
        )
        let message = try #require(detail.threads.first?.messages.first)
        let draft = try #require(message.draft)
        detail = try await store.saveDraft(
            .init(
                sessionID: detail.session.id,
                messageID: message.id,
                editToken: try #require(draft.activeEditToken),
                expectedMessageRevision: message.semanticRevision,
                expectedDraftRevision: draft.draftRevision,
                now: Date(timeIntervalSince1970: 2)
            )
        )
        _ = detail
        return path
    }

    private static func requireEnabledButton(_ page: WebPage, label: String) async throws {
        let found = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(20)) {
            (try? await page.callJavaScript(
                """
                const buttonLabel = String(label);
                const button = Array.from(document.querySelectorAll('button')).find(
                  candidate =>
                    candidate.getAttribute('aria-label') === buttonLabel ||
                    candidate.textContent?.trim() === buttonLabel
                );
                return button instanceof HTMLButtonElement && !button.disabled;
                """,
                arguments: ["label": label]
            )) as? Bool == true
        }
        guard found else { throw PackagedShareJourneyError.missingButton(label) }
    }

    private static func clickButton(_ page: WebPage, label: String) async throws {
        let clicked =
            try await page.callJavaScript(
                """
                const buttonLabel = String(label);
                const button = Array.from(document.querySelectorAll('button')).find(
                  candidate =>
                    candidate.getAttribute('aria-label') === buttonLabel ||
                    candidate.textContent?.trim() === buttonLabel
                );
                if (!(button instanceof HTMLButtonElement) || button.disabled) return false;
                button.click();
                return true;
                """,
                arguments: ["label": label]
            ) as? Bool
        guard clicked == true else { throw PackagedShareJourneyError.missingButton(label) }
    }

    private static func clickButtonWithPrefix(_ page: WebPage, prefix: String) async throws {
        let clicked =
            try await page.callJavaScript(
                """
                const buttonPrefix = String(prefix);
                const button = Array.from(document.querySelectorAll('button')).find(
                  candidate => candidate.textContent?.trim().startsWith(buttonPrefix)
                );
                if (!(button instanceof HTMLButtonElement) || button.disabled) return false;
                button.click();
                return true;
                """,
                arguments: ["prefix": prefix]
            ) as? Bool
        guard clicked == true else { throw PackagedShareJourneyError.missingButton(prefix) }
    }

    private static func requireShareSnapshot(
        _ page: WebPage,
        stage: String,
        predicate: @escaping @Sendable (ShareDOMSnapshot) -> Bool
    ) async throws -> ShareDOMSnapshot {
        var observed: ShareDOMSnapshot?
        let found = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(20)) {
            observed = try? await shareSnapshot(page)
            return observed.map(predicate) == true
        }
        guard found, let observed else {
            throw PackagedShareJourneyError.shareDidNotConverge(
                stage: stage,
                observed: String(describing: observed)
            )
        }
        return observed
    }

    private static func shareSnapshot(_ page: WebPage) async throws -> ShareDOMSnapshot {
        let encoded = try await page.callJavaScript(
            """
            const buttons = Array.from(document.querySelectorAll('button'));
            const textForPrefix = prefix => buttons.find(
              button => button.textContent?.trim().startsWith(prefix)
            )?.textContent?.trim() ?? '';
            const integerIn = value => Number(value.match(/\\d+/)?.[0] ?? '0');
            return JSON.stringify({
              allCount: integerIn(textForPrefix('All')),
              historyCount: integerIn(textForPrefix('History (')),
              pendingCount: integerIn(textForPrefix('Pending')),
              otherSavedCommentsVisible:
                document.querySelector('[aria-label="Other saved comments"]') !== null,
              shareVisible:
                document.querySelector('[data-testid="worktree-annotation-share-mode"]') !== null
            });
            """
        )
        let string = try #require(encoded as? String)
        return try JSONDecoder().decode(ShareDOMSnapshot.self, from: Data(string.utf8))
    }

    private static func requireFile(_ url: URL) async throws {
        let exists = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(20)) {
            FileManager.default.fileExists(atPath: url.path)
        }
        guard exists else { throw PackagedShareJourneyError.exportMissing }
    }
}

@MainActor
private final class PackagedShareJSONDestinationPanel: WorktreeAnnotationJSONDestinationPanel {
    var allowedContentTypes: [UTType] = []
    var nameFieldStringValue = ""
    var canCreateDirectories = false
    var isExtensionHidden = true
    let url: URL?

    init(url: URL) {
        self.url = url
    }

    func runModal() throws -> NSApplication.ModalResponse { .OK }
}

private enum PackagedShareJourneyError: Error {
    case exportMissing
    case fileModeUnavailable
    case fileSelectionUnavailable
    case missingButton(String)
    case reviewUnavailable
    case shareDidNotConverge(stage: String, observed: String)
}
