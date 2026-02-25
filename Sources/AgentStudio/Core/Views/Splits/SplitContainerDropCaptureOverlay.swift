import AppKit
import SwiftUI

/// AppKit-owned drag destination overlay for split drop targeting.
///
/// This overlay is the single owner for agent studio custom drop types in
/// management mode. Keeping drag routing in one AppKit destination avoids
/// divergence across pane internals (WKWebView/Ghostty/etc.).
struct SplitContainerDropCaptureOverlay: NSViewRepresentable {
    let paneFrames: [UUID: CGRect]
    let containerBounds: CGRect
    @Binding var target: PaneDropTarget?
    let isManagementModeActive: Bool
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    static let supportedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .agentStudioTabDrop,
        .agentStudioPaneDrop,
        .agentStudioNewTabDrop,
        .agentStudioTabInternal,
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(
            targetBinding: $target,
            shouldAcceptDrop: shouldAcceptDrop,
            onDrop: onDrop
        )
    }

    func makeNSView(context: Context) -> SplitContainerDropCaptureView {
        let view = SplitContainerDropCaptureView()
        view.coordinator = context.coordinator
        context.coordinator.updateHandlers(
            targetBinding: $target,
            shouldAcceptDrop: shouldAcceptDrop,
            onDrop: onDrop
        )
        context.coordinator.updateLayout(
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            isManagementModeActive: isManagementModeActive
        )
        view.updateDropRegistration(isManagementModeActive: isManagementModeActive)
        return view
    }

    func updateNSView(_ nsView: SplitContainerDropCaptureView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.updateHandlers(
            targetBinding: $target,
            shouldAcceptDrop: shouldAcceptDrop,
            onDrop: onDrop
        )
        context.coordinator.updateLayout(
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            isManagementModeActive: isManagementModeActive
        )
        nsView.updateDropRegistration(isManagementModeActive: isManagementModeActive)
        if !isManagementModeActive {
            context.coordinator.setTarget(nil)
        }
    }

    @MainActor
    final class Coordinator {
        private var targetBinding: Binding<PaneDropTarget?>
        private var shouldAcceptDrop: (UUID, DropZone) -> Bool
        private var onDrop: (SplitDropPayload, UUID, DropZone) -> Void

        private(set) var paneFrames: [UUID: CGRect] = [:]
        private(set) var containerBounds: CGRect = .zero
        private(set) var isManagementModeActive: Bool = false

        init(
            targetBinding: Binding<PaneDropTarget?>,
            shouldAcceptDrop: @escaping (UUID, DropZone) -> Bool,
            onDrop: @escaping (SplitDropPayload, UUID, DropZone) -> Void
        ) {
            self.targetBinding = targetBinding
            self.shouldAcceptDrop = shouldAcceptDrop
            self.onDrop = onDrop
        }

        func updateHandlers(
            targetBinding: Binding<PaneDropTarget?>,
            shouldAcceptDrop: @escaping (UUID, DropZone) -> Bool,
            onDrop: @escaping (SplitDropPayload, UUID, DropZone) -> Void
        ) {
            self.targetBinding = targetBinding
            self.shouldAcceptDrop = shouldAcceptDrop
            self.onDrop = onDrop
        }

        func updateLayout(
            paneFrames: [UUID: CGRect],
            containerBounds: CGRect,
            isManagementModeActive: Bool
        ) {
            self.paneFrames = paneFrames
            self.containerBounds = containerBounds
            self.isManagementModeActive = isManagementModeActive
        }

        func setTarget(_ target: PaneDropTarget?) {
            if targetBinding.wrappedValue != target {
                targetBinding.wrappedValue = target
            }
        }

        func hasSupportedTypes(in pasteboard: NSPasteboard) -> Bool {
            guard let types = pasteboard.types else { return false }
            return types.contains(where: { Self.supportedTypeSet.contains($0) })
        }

        func resolveTarget(at location: CGPoint) -> PaneDropTarget? {
            PaneDragCoordinator.resolveLatchedTarget(
                location: location,
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                currentTarget: targetBinding.wrappedValue,
                shouldAcceptDrop: shouldAcceptDrop
            )
        }

        func performDrop(from pasteboard: NSPasteboard, location: CGPoint) -> Bool {
            guard isManagementModeActive else {
                setTarget(nil)
                return false
            }

            guard let resolvedTarget = resolveTarget(at: location),
                shouldAcceptDrop(resolvedTarget.paneId, resolvedTarget.zone),
                let payload = decodeSplitDropPayload(from: pasteboard)
            else {
                setTarget(nil)
                return false
            }

            setTarget(nil)
            onDrop(payload, resolvedTarget.paneId, resolvedTarget.zone)
            return true
        }

        private static let supportedTypeSet: Set<NSPasteboard.PasteboardType> = Set(
            SplitContainerDropCaptureOverlay.supportedPasteboardTypes
        )
    }
}

@MainActor
final class SplitContainerDropCaptureView: NSView {
    weak var coordinator: SplitContainerDropCaptureOverlay.Coordinator?

    private var isRegisteredForManagementMode = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func updateDropRegistration(isManagementModeActive: Bool) {
        guard isRegisteredForManagementMode != isManagementModeActive else { return }
        if isManagementModeActive {
            registerForDraggedTypes(SplitContainerDropCaptureOverlay.supportedPasteboardTypes)
        } else {
            unregisterDraggedTypes()
        }
        isRegisteredForManagementMode = isManagementModeActive
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        routeDragUpdate(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        routeDragUpdate(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        coordinator?.setTarget(nil)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        coordinator?.setTarget(nil)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let coordinator else { return false }
        let location = convert(sender.draggingLocation, from: nil)
        return coordinator.performDrop(
            from: sender.draggingPasteboard,
            location: location
        )
    }

    private func routeDragUpdate(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let coordinator else { return [] }
        guard coordinator.isManagementModeActive else {
            coordinator.setTarget(nil)
            return []
        }
        guard coordinator.hasSupportedTypes(in: sender.draggingPasteboard) else {
            coordinator.setTarget(nil)
            return []
        }

        let location = convert(sender.draggingLocation, from: nil)
        let target = coordinator.resolveTarget(at: location)
        coordinator.setTarget(target)
        return target == nil ? [] : .move
    }
}
