import AppKit
import SwiftUI
import UniformTypeIdentifiers
import os.log

private let splitContainerDropLogger = Logger(subsystem: "com.agentstudio", category: "SplitContainerDrop")

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

private func loadDataRepresentation(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
    await withCheckedContinuation { continuation in
        _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
            if let error {
                splitContainerDropLogger.warning(
                    "Failed to load drop data for \(typeIdentifier, privacy: .public): \(error.localizedDescription)"
                )
            }
            continuation.resume(returning: data)
        }
    }
}

/// Central split drop delegate attached at tab-container level.
struct SplitContainerDropDelegate: DropDelegate {
    static let supportedDropTypes: [UTType] = [
        .agentStudioTab,
        .agentStudioPane,
        .agentStudioNewTab,
    ]

    let paneFrames: [UUID: CGRect]
    @Binding var target: PaneDropTarget?
    let isManagementModeActive: Bool
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard isManagementModeActive else { return false }
        return info.hasItemsConforming(to: Self.supportedDropTypes)
    }

    func dropEntered(info: DropInfo) {
        _ = updateTarget(using: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard updateTarget(using: info) else {
            return DropProposal(operation: .cancel)
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        target = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isManagementModeActive,
            let target,
            shouldAcceptDrop(target.paneId, target.zone)
        else {
            self.target = nil
            return false
        }

        let providers = info.itemProviders(for: Self.supportedDropTypes)
        guard !providers.isEmpty else {
            self.target = nil
            return false
        }

        self.target = nil
        Task { @MainActor in
            guard let payload = await decodeSplitDropPayload(from: providers) else { return }
            onDrop(payload, target.paneId, target.zone)
        }
        return true
    }

    private func updateTarget(using info: DropInfo) -> Bool {
        guard isManagementModeActive else {
            target = nil
            return false
        }

        if let resolvedTarget = PaneDragCoordinator.resolveLatchedTarget(
            location: info.location,
            paneFrames: paneFrames,
            currentTarget: target,
            shouldAcceptDrop: shouldAcceptDrop
        ) {
            target = resolvedTarget
            return true
        }

        target = nil
        return false
    }
}
