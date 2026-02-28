import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("SwiftPaneRuntime lifecycle")
struct SwiftPaneRuntimeTests {
    @Test("swift pane runtime openFile loads content and emits fileOpened")
    func swiftRuntimeOpenFile() async throws {
        let tempFile = try makeTemporarySwiftFile(content: "print(\"hi\")\n")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let paneEventBus = EventBus<PaneEventEnvelope>()
        let runtime = makeRuntime(
            fileDirectory: tempFile.deletingLastPathComponent(),
            paneEventBus: paneEventBus
        )
        runtime.transitionToReady()

        let busStream = await paneEventBus.subscribe()
        var busIterator = busStream.makeAsyncIterator()

        let openCommandId = UUID()
        let commandResult = await runtime.handleCommand(
            makeEnvelope(
                commandId: openCommandId,
                command: .editor(.openFile(path: tempFile.path, line: 1, column: nil)),
                paneId: runtime.paneId
            )
        )

        let busEnvelope = await busIterator.next()
        let replay = await runtime.eventsSince(seq: 0)

        #expect(commandResult == .success(commandId: openCommandId))
        #expect(runtime.openedFilePath == tempFile.path)
        #expect(runtime.displayedText == "print(\"hi\")\n")

        #expect(busEnvelope?.source == .pane(runtime.paneId))
        #expect(busEnvelope?.paneKind == .codeViewer)
        #expect(busEnvelope?.seq == 1)

        guard let busEnvelope else {
            Issue.record("Expected fileOpened envelope on pane event bus")
            return
        }
        guard case .editor(.fileOpened(let openedPath, let language)) = busEnvelope.event else {
            Issue.record("Expected editor.fileOpened event for openFile command")
            return
        }
        #expect(openedPath == tempFile.path)
        #expect(language == "swift")

        #expect(replay.events.count == 1)
        #expect(replay.nextSeq == 1)
        #expect(!replay.gapDetected)
    }

    @Test("save emits contentSaved without mutating on-disk content")
    func saveEmitsContentSavedWithoutDiskMutation() async throws {
        let tempFile = try makeTemporarySwiftFile(content: "print(\"before\")\n")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let runtime = makeRuntime(fileDirectory: tempFile.deletingLastPathComponent())
        runtime.transitionToReady()
        _ = await runtime.handleCommand(
            makeEnvelope(
                command: .editor(.openFile(path: tempFile.path, line: nil, column: nil)),
                paneId: runtime.paneId
            )
        )

        let saveCommandId = UUID()
        let saveResult = await runtime.handleCommand(
            makeEnvelope(
                commandId: saveCommandId,
                command: .editor(.save),
                paneId: runtime.paneId
            )
        )
        let replay = await runtime.eventsSince(seq: 1)
        let onDiskContent = try String(contentsOf: tempFile, encoding: .utf8)

        #expect(saveResult == .success(commandId: saveCommandId))
        #expect(onDiskContent == "print(\"before\")\n")
        #expect(replay.events.count == 1)
        guard let replayEnvelope = replay.events.first else {
            Issue.record("Expected replay envelope for save command")
            return
        }
        guard case .editor(.contentSaved(let savedPath)) = replayEnvelope.event else {
            Issue.record("Expected editor.contentSaved event for save command")
            return
        }
        #expect(savedPath == tempFile.path)
    }

    @Test("revert reloads file content and emits fileOpened")
    func revertReloadsContent() async throws {
        let tempFile = try makeTemporarySwiftFile(content: "print(\"before\")\n")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let paneEventBus = EventBus<PaneEventEnvelope>()
        let runtime = makeRuntime(
            fileDirectory: tempFile.deletingLastPathComponent(),
            paneEventBus: paneEventBus
        )
        runtime.transitionToReady()
        _ = await runtime.handleCommand(
            makeEnvelope(
                command: .editor(.openFile(path: tempFile.path, line: nil, column: nil)),
                paneId: runtime.paneId
            )
        )

        try "print(\"after\")\n".write(to: tempFile, atomically: true, encoding: .utf8)

        let busStream = await paneEventBus.subscribe()
        var busIterator = busStream.makeAsyncIterator()

        let revertCommandId = UUID()
        let revertResult = await runtime.handleCommand(
            makeEnvelope(
                commandId: revertCommandId,
                command: .editor(.revert),
                paneId: runtime.paneId
            )
        )

        let busEnvelope = await busIterator.next()

        #expect(revertResult == .success(commandId: revertCommandId))
        #expect(runtime.displayedText == "print(\"after\")\n")

        guard let busEnvelope else {
            Issue.record("Expected fileOpened envelope on pane event bus for revert")
            return
        }
        guard case .editor(.fileOpened(let openedPath, let language)) = busEnvelope.event else {
            Issue.record("Expected editor.fileOpened event for revert command")
            return
        }
        #expect(openedPath == tempFile.path)
        #expect(language == "swift")
    }

    @Test("handleCommand rejects when runtime is not ready")
    func handleCommandRejectsWhenNotReady() async throws {
        let tempFile = try makeTemporarySwiftFile(content: "print(\"hi\")\n")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let runtime = makeRuntime(fileDirectory: tempFile.deletingLastPathComponent())
        let commandEnvelope = makeEnvelope(
            command: .editor(.openFile(path: tempFile.path, line: nil, column: nil)),
            paneId: runtime.paneId
        )

        let result = await runtime.handleCommand(commandEnvelope)

        #expect(result == .failure(.runtimeNotReady(lifecycle: .created)))
    }

    private func makeRuntime(
        fileDirectory: URL,
        paneEventBus: EventBus<PaneEventEnvelope> = PaneRuntimeEventBus.shared
    ) -> SwiftPaneRuntime {
        let paneId = PaneId()
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .codeViewer,
            source: .floating(workingDirectory: fileDirectory, title: "Code"),
            title: "Code"
        )
        return SwiftPaneRuntime(
            paneId: paneId,
            metadata: metadata,
            paneEventBus: paneEventBus
        )
    }

    private func makeEnvelope(
        commandId: UUID = UUID(),
        command: RuntimeCommand,
        paneId: PaneId
    ) -> RuntimeCommandEnvelope {
        RuntimeCommandEnvelope(
            commandId: commandId,
            correlationId: nil,
            targetPaneId: paneId,
            command: command,
            timestamp: ContinuousClock().now
        )
    }

    private func makeTemporarySwiftFile(content: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "swift-pane-runtime-\(UUID().uuidString).swift")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
