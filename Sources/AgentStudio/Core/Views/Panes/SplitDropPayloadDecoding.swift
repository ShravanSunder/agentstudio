import AppKit
import Foundation
import UniformTypeIdentifiers
import os.log

private let splitDropDecodingLogger = Logger(subsystem: "com.agentstudio", category: "SplitDropDecoding")

/// Decodes split drop payloads from providers using precedence:
/// pane payload > tab payload > new terminal payload.
func decodeSplitDropPayload(from providers: [NSItemProvider]) async -> SplitDropPayload? {
    if let paneProvider = providers.first(where: {
        $0.hasItemConformingToTypeIdentifier(UTType.agentStudioPane.identifier)
    }),
        let paneData = await loadDataRepresentation(
            from: paneProvider,
            typeIdentifier: UTType.agentStudioPane.identifier
        ),
        let panePayload = try? JSONDecoder().decode(PaneDragPayload.self, from: paneData)
    {
        return SplitDropPayload(
            kind: .existingPane(paneId: panePayload.paneId, sourceTabId: panePayload.tabId)
        )
    }

    if let tabProvider = providers.first(where: {
        $0.hasItemConformingToTypeIdentifier(UTType.agentStudioTab.identifier)
    }),
        let tabData = await loadDataRepresentation(
            from: tabProvider,
            typeIdentifier: UTType.agentStudioTab.identifier
        ),
        let tabPayload = try? JSONDecoder().decode(TabDragPayload.self, from: tabData)
    {
        return SplitDropPayload(kind: .existingTab(tabId: tabPayload.tabId))
    }

    if providers.contains(where: {
        $0.hasItemConformingToTypeIdentifier(UTType.agentStudioNewTab.identifier)
    }) {
        return SplitDropPayload(kind: .newTerminal)
    }

    return nil
}

/// Decodes split drop payloads directly from AppKit pasteboard data.
/// Precedence matches provider decoding:
/// pane payload > tab payload > new terminal payload.
func decodeSplitDropPayload(from pasteboard: NSPasteboard) -> SplitDropPayload? {
    if let paneData = pasteboard.data(forType: .agentStudioPaneDrop),
        let panePayload = try? JSONDecoder().decode(PaneDragPayload.self, from: paneData)
    {
        return SplitDropPayload(
            kind: .existingPane(paneId: panePayload.paneId, sourceTabId: panePayload.tabId)
        )
    }

    if let tabData = pasteboard.data(forType: .agentStudioTabDrop),
        let tabPayload = try? JSONDecoder().decode(TabDragPayload.self, from: tabData)
    {
        return SplitDropPayload(kind: .existingTab(tabId: tabPayload.tabId))
    }

    if let tabIdString = pasteboard.string(forType: .agentStudioTabInternal),
        let tabId = UUID(uuidString: tabIdString)
    {
        return SplitDropPayload(kind: .existingTab(tabId: tabId))
    }

    if pasteboard.data(forType: .agentStudioNewTabDrop) != nil
        || pasteboard.string(forType: .agentStudioNewTabDrop) != nil
    {
        return SplitDropPayload(kind: .newTerminal)
    }

    return nil
}

private func loadDataRepresentation(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
    await withCheckedContinuation { continuation in
        _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
            if let error {
                splitDropDecodingLogger.warning(
                    "Failed to load drop data for \(typeIdentifier, privacy: .public): \(error.localizedDescription)"
                )
            }
            continuation.resume(returning: data)
        }
    }
}
