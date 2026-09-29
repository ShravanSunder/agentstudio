import AgentStudioBridge
import AgentStudioInfrastructure
import AgentStudioTestHarness
import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorktreeAnnotationOutputEffectsTests {
    @Test("clipboard output replaces stale contents with exact UTF-8 Markdown bytes")
    func clipboardOutputReplacesStaleContentsWithExactMarkdownBytes() async throws {
        let pasteboard = NSPasteboard(
            name: .init("agentstudio.annotation-output.\(UUIDv7.generate().uuidString)")
        )
        let staleType = NSPasteboard.PasteboardType("com.agentstudio.tests.stale-annotation-output")
        pasteboard.clearContents()
        #expect(pasteboard.setString("stale", forType: staleType))
        let exactBytes = Data("# Review comments\n\nPreserve café behavior.\n".utf8)
        let effect = WorktreeAnnotationOutputEffects(pasteboard: pasteboard)

        let outcome = await effect.perform(
            outputRequest(kind: .clipboardMarkdown, exactBytes: exactBytes)
        )

        #expect(outcome == .succeeded(destinationPath: nil))
        #expect(pasteboard.data(forType: .string) == exactBytes)
        #expect(pasteboard.string(forType: staleType) == nil)
    }

    @Test("clipboard output reports failure when the pasteboard does not prove the write")
    func clipboardOutputReportsUnprovenWrite() async {
        let pasteboard = RejectingAnnotationPasteboard()
        let effect = WorktreeAnnotationOutputEffects(pasteboard: pasteboard)

        let outcome = await effect.perform(
            outputRequest(
                kind: .clipboardMarkdown,
                exactBytes: Data("# Review comments\n".utf8)
            )
        )

        guard case .failed(let message) = outcome else {
            Issue.record("Expected a typed pasteboard failure")
            return
        }
        #expect(!message.isEmpty)
        #expect(pasteboard.didClearContents)
    }

    @Test("JSON folder picker is modeless and remembers the selected folder")
    func jsonDestinationConfiguresFolderPanel() async {
        let destination = URL(filePath: "/tmp/agentstudio-selected-output-folder", directoryHint: .isDirectory)
        let panel = TestJSONFolderPanel(response: .OK, selectedURL: destination)
        let effect = WorktreeAnnotationOutputEffects(makeFolderPanel: { panel })

        let outcome = await effect.chooseJSONDestination()

        #expect(outcome == .selected(path: destination.path))
        #expect(panel.didBegin)
        #expect(panel.canChooseDirectories)
        #expect(!panel.canChooseFiles)
        #expect(!panel.allowsMultipleSelection)
        #expect(effect.rememberedJSONFolder() == destination.path)
    }

    @Test("JSON destination cancellation is typed cancellation")
    func jsonDestinationCancellationIsTyped() async {
        let panel = TestJSONFolderPanel(response: .cancel, selectedURL: nil)
        let effect = WorktreeAnnotationOutputEffects(makeFolderPanel: { panel })

        let outcome = await effect.chooseJSONDestination()

        #expect(outcome == .cancelled)
    }

    @Test("ending a picker operation cancels the held panel exactly once")
    func heldFolderPickerCancelsWithItsTask() async {
        let panel = HoldingJSONFolderPanel()
        let preference = InMemoryWorktreeAnnotationOutputFolderPreference(
            folderURL: URL(filePath: "/tmp/original-folder", directoryHint: .isDirectory)
        )
        let effect = WorktreeAnnotationOutputEffects(
            makeFolderPanel: { panel },
            folderPreference: preference
        )
        var beginnings = panel.beginnings.makeAsyncIterator()
        let choice = Task { await effect.chooseJSONDestination() }
        _ = await beginnings.next()

        let independentClipboard = await effect.perform(
            outputRequest(kind: .clipboardMarkdown, exactBytes: Data("independent".utf8))
        )
        #expect(independentClipboard == .succeeded(destinationPath: nil))

        choice.cancel()
        #expect(await choice.value == .cancelled)
        panel.complete(.OK)
        #expect(panel.cancelCount == 1)
        #expect(effect.rememberedJSONFolder() == "/tmp/original-folder")
    }

    @Test("a revoked operation cannot begin a write after folder selection")
    func cancelledAfterSelectionDoesNotStartWriter() async throws {
        let panel = TestJSONFolderPanel(
            response: .OK,
            selectedURL: URL(filePath: "/tmp/selected-folder", directoryHint: .isDirectory)
        )
        let writer = RecordingJSONWriter()
        let gate = HeldStep<Void>("after-folder-selection", cancellation: .holdThroughCancellation)
        let effect = WorktreeAnnotationOutputEffects(
            makeFolderPanel: { panel },
            writeJSONData: { data, destination, filename in
                await writer.record(data: data, destination: destination, filename: filename)
            }
        )
        let operation = Task {
            _ = await effect.chooseJSONDestination()
            try? await gate.arrive(())
            return await effect.perform(
                outputRequest(
                    kind: .jsonFile,
                    exactBytes: Data("{}".utf8),
                    destinationPath: "/tmp/selected-folder/comments.json",
                    suggestedFilename: "comments.json"
                )
            )
        }
        try await gate.firstArrival()

        operation.cancel()
        gate.release()

        #expect(await operation.value == .cancelled)
        #expect(await writer.writeCount == 0)
    }

    @Test("a write admitted before session cancellation finishes")
    func begunWriteCompletesAfterCancellation() async throws {
        let writeGate = HeldStep<Void>("application-owned-write", cancellation: .holdThroughCancellation)
        let effect = WorktreeAnnotationOutputEffects(
            writeJSONData: { data, destination, filename in
                _ = (data, filename)
                try await writeGate.arrive(())
                return destination
            }
        )
        let operation = Task {
            await effect.perform(
                outputRequest(
                    kind: .jsonFile,
                    exactBytes: Data("{}".utf8),
                    destinationPath: "/tmp/selected-folder/comments.json",
                    suggestedFilename: "comments.json"
                )
            )
        }
        try await writeGate.firstArrival()

        operation.cancel()
        writeGate.release()

        #expect(await operation.value == .succeeded(destinationPath: "/tmp/selected-folder/comments.json"))
    }

    @Test("JSON destination panel errors are typed failures")
    func jsonDestinationPanelErrorIsTypedFailure() async {
        let effect = WorktreeAnnotationOutputEffects(makeFolderPanel: {
            throw TestOutputEffectFailure.forced
        })

        let outcome = await effect.chooseJSONDestination()

        guard case .failed(let message) = outcome else {
            Issue.record("Expected a typed save-panel failure")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("JSON output creates a suffixed file exclusively without overwriting")
    func jsonOutputNeverOverwritesAnExistingFile() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-annotation-output-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let destination = temporaryRoot.appending(path: "review-comments.json")
        try Data("existing".utf8).write(to: destination)
        let exactBytes = Data("{\"formatVersion\":1,\"comments\":[]}".utf8)
        let effect = WorktreeAnnotationOutputEffects()

        let outcome = await effect.perform(
            outputRequest(
                kind: .jsonFile,
                exactBytes: exactBytes,
                destinationPath: destination.path,
                suggestedFilename: "review-comments.json"
            )
        )

        #expect(outcome == .succeeded(destinationPath: temporaryRoot.appending(path: "review-comments-2.json").path))
        #expect(try Data(contentsOf: destination) == Data("existing".utf8))
        #expect(try Data(contentsOf: temporaryRoot.appending(path: "review-comments-2.json")) == exactBytes)
    }

    @Test("JSON output fails without the persisted selected path")
    func jsonOutputRejectsMissingPersistedPath() async {
        let effect = WorktreeAnnotationOutputEffects()

        let outcome = await effect.perform(
            outputRequest(kind: .jsonFile, exactBytes: Data("{}".utf8))
        )

        guard case .failed(let message) = outcome else {
            Issue.record("Expected a typed missing-path failure")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("a removed remembered folder returns a visible failure and creates no file")
    func jsonOutputRejectsMissingFolder() async {
        let missingFolder = FileManager.default.temporaryDirectory.appending(
            path: "missing-annotation-output-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let effect = WorktreeAnnotationOutputEffects()

        let outcome = await effect.perform(
            outputRequest(
                kind: .jsonFile,
                exactBytes: Data("{}".utf8),
                destinationPath: missingFolder.appending(path: "comments.json").path,
                suggestedFilename: "comments.json"
            )
        )

        guard case .fileFailure(let code, let message) = outcome else {
            Issue.record("Expected a typed missing-folder failure")
            return
        }
        #expect(code == .missingFolder)
        #expect(message.contains("folder no longer exists"))
        #expect(!FileManager.default.fileExists(atPath: missingFolder.path))
    }

    @Test("JSON output reports one known failure without retrying")
    func jsonOutputDoesNotRetryKnownWriteFailure() async {
        let writer = RecordingFailingJSONWriter()
        let effect = WorktreeAnnotationOutputEffects(
            writeJSONData: { data, destination, _ in
                try await writer.write(data, to: destination)
                return destination
            }
        )

        let outcome = await effect.perform(
            outputRequest(
                kind: .jsonFile,
                exactBytes: Data("{}".utf8),
                destinationPath: "/tmp/agentstudio-known-failure.json"
            )
        )

        guard case .failed(let message) = outcome else {
            Issue.record("Expected a typed file-write failure")
            return
        }
        #expect(!message.isEmpty)
        #expect(await writer.writeCount == 1)
    }

    private func outputRequest(
        kind: WorktreeAnnotationOutputEffectKind,
        exactBytes: Data,
        destinationPath: String? = nil,
        suggestedFilename: String? = nil
    ) -> WorktreeAnnotationOutputEffectRequest {
        .init(
            attemptID: UUIDv7.generate(),
            outputKind: kind,
            contentType: kind == .clipboardMarkdown
                ? "text/markdown; charset=utf-8"
                : "application/json; charset=utf-8",
            exactBytes: exactBytes,
            destinationPath: destinationPath,
            suggestedFilename: suggestedFilename
        )
    }
}

@MainActor
private final class RejectingAnnotationPasteboard: WorktreeAnnotationPasteboardWriting {
    private(set) var didClearContents = false

    func clearContents() -> Int {
        didClearContents = true
        return 1
    }

    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        _ = (data, dataType)
        return false
    }
}

@MainActor
private final class TestJSONFolderPanel: WorktreeAnnotationJSONFolderPanel {
    var canChooseDirectories = false
    var canChooseFiles = true
    var allowsMultipleSelection = true
    private(set) var didBegin = false
    let url: URL?

    private let response: NSApplication.ModalResponse
    init(
        response: NSApplication.ModalResponse,
        selectedURL: URL?
    ) {
        self.response = response
        self.url = selectedURL
    }

    func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
        didBegin = true
        completionHandler(response)
    }

    func cancel(_ sender: Any?) {
        _ = sender
    }
}

@MainActor
private final class HoldingJSONFolderPanel: WorktreeAnnotationJSONFolderPanel {
    var canChooseDirectories = false
    var canChooseFiles = true
    var allowsMultipleSelection = true
    let url: URL? = URL(filePath: "/tmp/late-selection", directoryHint: .isDirectory)
    let beginnings: AsyncStream<Void>
    private let beginningContinuation: AsyncStream<Void>.Continuation
    private var completionHandler: ((NSApplication.ModalResponse) -> Void)?
    private(set) var cancelCount = 0

    init() {
        let stream = AsyncStream.makeStream(of: Void.self)
        beginnings = stream.stream
        beginningContinuation = stream.continuation
    }

    func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
        self.completionHandler = completionHandler
        beginningContinuation.yield(())
    }

    func cancel(_ sender: Any?) {
        _ = sender
        cancelCount += 1
        completionHandler?(.cancel)
    }

    func complete(_ response: NSApplication.ModalResponse) {
        completionHandler?(response)
    }
}

private actor RecordingFailingJSONWriter {
    private(set) var writeCount = 0

    func write(_ data: Data, to destination: URL) throws {
        _ = (data, destination)
        writeCount += 1
        throw TestOutputEffectFailure.forced
    }
}

private actor RecordingJSONWriter {
    private(set) var writeCount = 0

    func record(data: Data, destination: URL, filename: String?) -> URL {
        _ = (data, filename)
        writeCount += 1
        return destination
    }
}

private enum TestOutputEffectFailure: Error {
    case forced
}
