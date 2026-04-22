import AppKit
import SwiftUI

/// AppKit-owned drag destination overlay for split drop targeting.
///
/// This overlay is the single owner for agent studio custom drop types in
/// management layer. Keeping drag routing in one AppKit destination avoids
/// divergence across pane internals (WKWebView/Ghostty/etc.).
struct SplitContainerDropCaptureOverlay: NSViewRepresentable {
    let paneFrames: [UUID: CGRect]
    let containerBounds: CGRect
    @Binding var target: PaneDropTarget?
    let isManagementLayerActive: Bool
    let actionDispatcher: PaneActionDispatching

    static let supportedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .agentStudioTabDrop,
        .agentStudioPaneDrop,
        .agentStudioNewTabDrop,
        .agentStudioTabInternal,
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(
            targetBinding: $target,
            actionDispatcher: actionDispatcher
        )
    }

    func makeNSView(context: Context) -> SplitContainerDropCaptureView {
        let view = SplitContainerDropCaptureView()
        view.coordinator = context.coordinator
        context.coordinator.updateHandlers(
            targetBinding: $target,
            actionDispatcher: actionDispatcher
        )
        context.coordinator.updateLayout(
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            isManagementLayerActive: isManagementLayerActive
        )
        view.updateDropRegistration(isManagementLayerActive: isManagementLayerActive)
        return view
    }

    func updateNSView(_ nsView: SplitContainerDropCaptureView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.updateHandlers(
            targetBinding: $target,
            actionDispatcher: actionDispatcher
        )
        context.coordinator.updateLayout(
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            isManagementLayerActive: isManagementLayerActive
        )
        nsView.updateDropRegistration(isManagementLayerActive: isManagementLayerActive)
        if !isManagementLayerActive {
            context.coordinator.finalizeDragSession()
        }
    }

    @MainActor
    final class Coordinator {
        private var targetBinding: Binding<PaneDropTarget?>
        private var actionDispatcher: PaneActionDispatching

        private(set) var paneFrames: [UUID: CGRect] = [:]
        private(set) var containerBounds: CGRect = .zero
        private(set) var isManagementLayerActive: Bool = false
        private(set) var dragSession: DragSessionState = .idle

        init(
            targetBinding: Binding<PaneDropTarget?>,
            actionDispatcher: PaneActionDispatching
        ) {
            self.targetBinding = targetBinding
            self.actionDispatcher = actionDispatcher
        }

        func updateHandlers(
            targetBinding: Binding<PaneDropTarget?>,
            actionDispatcher: PaneActionDispatching
        ) {
            self.targetBinding = targetBinding
            self.actionDispatcher = actionDispatcher
        }

        func updateLayout(
            paneFrames: [UUID: CGRect],
            containerBounds: CGRect,
            isManagementLayerActive: Bool
        ) {
            self.paneFrames = paneFrames
            self.containerBounds = containerBounds
            self.isManagementLayerActive = isManagementLayerActive
        }

        func setTarget(_ target: PaneDropTarget?) {
            if targetBinding.wrappedValue != target {
                targetBinding.wrappedValue = target
            }
        }

        func finalizeDragSession() {
            setTarget(nil)
            dragSession = .idle
        }

        func hasSupportedTypes(in pasteboard: NSPasteboard) -> Bool {
            guard let types = pasteboard.types else { return false }
            return types.contains(where: { Self.supportedTypeSet.contains($0) })
        }

        private func resolveTarget(
            at location: CGPoint,
            payload: SplitDropPayload
        ) -> PaneDropTarget? {
            PaneDragCoordinator.resolveLatchedTarget(
                location: location,
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                currentTarget: targetBinding.wrappedValue,
                shouldAcceptDrop: { paneId, zone in
                    actionDispatcher.shouldAcceptDrop(payload, destinationPaneId: paneId, zone: zone)
                }
            )
        }

        func handleDragUpdate(from pasteboard: NSPasteboard, location: CGPoint) -> PaneDropTarget? {
            guard let payload = decodeSplitDropPayload(from: pasteboard) else {
                let pasteboardTypes = pasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "nil"
                RestoreTrace.log(
                    "SplitContainer.handleDragUpdate decode=nil location=\(NSStringFromPoint(location)) types=\(pasteboardTypes)"
                )
                dragSession = .idle
                return nil
            }
            guard actionDispatcher.shouldHandleSplitDragPayload(payload) else {
                RestoreTrace.log(
                    "SplitContainer.handleDragUpdate rejectedByDispatcher location=\(NSStringFromPoint(location)) payload=\(String(describing: payload))"
                )
                dragSession = .previewing(payload: payload)
                return nil
            }

            if let resolvedTarget = resolveTarget(at: location, payload: payload) {
                RestoreTrace.log(
                    "SplitContainer.handleDragUpdate target=\(resolvedTarget.paneId) zone=\(resolvedTarget.zone) location=\(NSStringFromPoint(location))"
                )
                let candidate = DragSessionCandidate(payload: payload, target: resolvedTarget)
                dragSession = .armed(candidate: candidate)
                return resolvedTarget
            }

            RestoreTrace.log(
                "SplitContainer.handleDragUpdate target=nil location=\(NSStringFromPoint(location)) payload=\(String(describing: payload))"
            )
            dragSession = .previewing(payload: payload)
            return nil
        }

        func performDrop(from pasteboard: NSPasteboard, location: CGPoint) -> Bool {
            guard isManagementLayerActive else {
                dragSession = .teardown
                return false
            }

            guard let payload = decodeSplitDropPayload(from: pasteboard) else {
                dragSession = .teardown
                return false
            }
            guard actionDispatcher.shouldHandleSplitDragPayload(payload) else {
                dragSession = .teardown
                return false
            }
            guard
                let resolvedTarget = resolveTarget(at: location, payload: payload)
            else {
                dragSession = .teardown
                return false
            }

            let candidate = DragSessionCandidate(payload: payload, target: resolvedTarget)
            dragSession = .committing(candidate: candidate)
            actionDispatcher.handleDrop(
                payload,
                destinationPaneId: resolvedTarget.paneId,
                zone: resolvedTarget.zone
            )
            dragSession = .teardown
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

    private var isRegisteredForManagementLayer = false
    private var isManagementLayerActiveRequest = false

    override var isFlipped: Bool { true }

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

    func updateDropRegistration(isManagementLayerActive: Bool) {
        isManagementLayerActiveRequest = isManagementLayerActive
        applyDropRegistration()
    }

    /// Registers/unregisters for dragged types based on the management-layer request
    /// AND on whether the view has a non-empty frame. AppKit's drag destination
    /// traversal skips views with empty bounds; gating on `!bounds.isEmpty` plus
    /// re-applying on every frame change keeps registration in sync with layout.
    private func applyDropRegistration() {
        let shouldRegister = isManagementLayerActiveRequest && !bounds.isEmpty
        guard isRegisteredForManagementLayer != shouldRegister else { return }
        if shouldRegister {
            registerForDraggedTypes(SplitContainerDropCaptureOverlay.supportedPasteboardTypes)
            let windowFrame = superview.map { $0.convert(frame, to: nil) } ?? .zero
            let hasWindow = window != nil
            RestoreTrace.log(
                "SplitContainer.updateDropRegistration registered flipped=\(isFlipped) local=\(NSStringFromRect(frame)) windowFrame=\(NSStringFromRect(windowFrame)) hasWindow=\(hasWindow)"
            )
        } else {
            unregisterDraggedTypes()
            RestoreTrace.log(
                "SplitContainer.updateDropRegistration unregistered managementActive=\(isManagementLayerActiveRequest) boundsEmpty=\(bounds.isEmpty)"
            )
        }
        isRegisteredForManagementLayer = shouldRegister
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyDropRegistration()
    }

    override func layout() {
        super.layout()
        applyDropRegistration()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        RestoreTrace.log(
            "SplitContainer.draggingEntered raw=\(NSStringFromPoint(sender.draggingLocation))"
        )
        return routeDragUpdate(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        RestoreTrace.log(
            "SplitContainer.draggingUpdated raw=\(NSStringFromPoint(sender.draggingLocation))"
        )
        return routeDragUpdate(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        coordinator?.finalizeDragSession()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        coordinator?.finalizeDragSession()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let coordinator else { return false }
        defer { coordinator.finalizeDragSession() }
        let location = convert(sender.draggingLocation, from: nil)
        return coordinator.performDrop(
            from: sender.draggingPasteboard,
            location: location
        )
    }

    private func routeDragUpdate(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let coordinator else { return [] }
        guard coordinator.isManagementLayerActive else {
            coordinator.finalizeDragSession()
            return []
        }
        guard coordinator.hasSupportedTypes(in: sender.draggingPasteboard) else {
            coordinator.finalizeDragSession()
            return []
        }

        let location = convert(sender.draggingLocation, from: nil)
        let target = coordinator.handleDragUpdate(
            from: sender.draggingPasteboard,
            location: location
        )
        RestoreTrace.log(
            "SplitContainer.routeDragUpdate converted=\(NSStringFromPoint(location)) target=\(String(describing: target))"
        )
        coordinator.setTarget(target)
        return target == nil ? [] : .move
    }
}
