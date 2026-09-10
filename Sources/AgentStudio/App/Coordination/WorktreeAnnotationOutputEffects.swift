import AgentStudioBridge
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol WorktreeAnnotationPasteboardWriting: AnyObject {
    @discardableResult
    func clearContents() -> Int

    @discardableResult
    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: WorktreeAnnotationPasteboardWriting {}

@MainActor
protocol WorktreeAnnotationJSONDestinationPanel: AnyObject {
    var allowedContentTypes: [UTType] { get set }
    var nameFieldStringValue: String { get set }
    var canCreateDirectories: Bool { get set }
    var isExtensionHidden: Bool { get set }
    var url: URL? { get }

    func runModal() throws -> NSApplication.ModalResponse
}

extension NSSavePanel: WorktreeAnnotationJSONDestinationPanel {}

/// App-owned implementation of the Bridge output-effect boundary.
///
/// Bridge supplies already validated exact bytes and a persisted destination.
/// This owner performs only AppKit selection/clipboard work and the atomic file
/// replacement; it never inspects or rebuilds annotation meaning.
@MainActor
final class WorktreeAnnotationOutputEffects: WorktreeAnnotationOutputEffect {
    typealias SavePanelFactory = @MainActor () throws -> any WorktreeAnnotationJSONDestinationPanel
    typealias JSONDataWriter = @Sendable (Data, URL) async throws -> Void

    private let pasteboard: any WorktreeAnnotationPasteboardWriting
    private let makeSavePanel: SavePanelFactory
    private let writeJSONData: JSONDataWriter

    init(
        pasteboard: any WorktreeAnnotationPasteboardWriting = NSPasteboard.general,
        makeSavePanel: @escaping SavePanelFactory = { NSSavePanel() },
        writeJSONData: @escaping JSONDataWriter = WorktreeAnnotationOutputEffects.atomicJSONDataWriter
    ) {
        self.pasteboard = pasteboard
        self.makeSavePanel = makeSavePanel
        self.writeJSONData = writeJSONData
    }

    func chooseJSONDestination(
        suggestedFilename: String
    ) async -> WorktreeAnnotationOutputDestinationOutcome {
        guard !suggestedFilename.isEmpty else {
            return .failed("The suggested JSON export filename was empty.")
        }
        do {
            let panel = try makeSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = suggestedFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false

            let response = try panel.runModal()
            if response == .cancel {
                return .cancelled
            }
            guard response == .OK else {
                return .failed("The JSON export panel returned an unexpected response.")
            }
            guard let selectedURL = panel.url else {
                return .failed("The JSON export panel did not return a destination.")
            }
            return .selected(path: selectedURL.path)
        } catch {
            return .failed("The JSON export destination could not be selected: \(error.localizedDescription)")
        }
    }

    func perform(
        _ request: WorktreeAnnotationOutputEffectRequest
    ) async -> WorktreeAnnotationOutputEffectOutcome {
        switch request.outputKind {
        case .clipboardMarkdown:
            pasteboard.clearContents()
            guard pasteboard.setData(request.exactBytes, forType: .string) else {
                return .failed("The system pasteboard did not confirm the Markdown write.")
            }
            return .succeeded
        case .jsonFile:
            guard let destinationPath = request.destinationPath, !destinationPath.isEmpty else {
                return .failed("The prepared JSON output has no selected destination.")
            }
            do {
                try await writeJSONData(
                    request.exactBytes,
                    URL(fileURLWithPath: destinationPath)
                )
                return .succeeded
            } catch {
                return .failed("The JSON export could not be written: \(error.localizedDescription)")
            }
        }
    }

    private static func atomicJSONDataWriter(_ data: Data, _ destination: URL) async throws {
        // Atomic file I/O must not block the MainActor UI owner.
        // swiftlint:disable:next no_task_detached
        try await Task.detached(priority: .userInitiated) {
            try data.write(to: destination, options: .atomic)
        }.value
    }
}
