import AppKit
import SwiftUI

struct DrawerSplitContainerDropCaptureOverlay: NSViewRepresentable {
    let paneFrames: [UUID: CGRect]
    @Binding var target: DrawerPaneDropTarget?
    let isManagementLayerActive: Bool
    let shouldAcceptDrop: (SplitDropPayload, UUID, DrawerDropZone) -> Bool
    let handleDrop: (SplitDropPayload, UUID, DrawerDropZone) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            targetBinding: $target,
            shouldAcceptDrop: shouldAcceptDrop,
            handleDrop: handleDrop
        )
    }

    func makeNSView(context: Context) -> DrawerSplitContainerDropCaptureView {
        let view = DrawerSplitContainerDropCaptureView()
        view.coordinator = context.coordinator
        context.coordinator.updateHandlers(
            targetBinding: $target,
            shouldAcceptDrop: shouldAcceptDrop,
            handleDrop: handleDrop
        )
        context.coordinator.updateLayout(
            paneFrames: paneFrames,
            isManagementLayerActive: isManagementLayerActive
        )
        view.updateDropRegistration(isManagementLayerActive: isManagementLayerActive)
        return view
    }

    func updateNSView(_ nsView: DrawerSplitContainerDropCaptureView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.updateHandlers(
            targetBinding: $target,
            shouldAcceptDrop: shouldAcceptDrop,
            handleDrop: handleDrop
        )
        context.coordinator.updateLayout(
            paneFrames: paneFrames,
            isManagementLayerActive: isManagementLayerActive
        )
        nsView.updateDropRegistration(isManagementLayerActive: isManagementLayerActive)
        if !isManagementLayerActive {
            context.coordinator.finalizeDragSession()
        }
    }

    @MainActor
    final class Coordinator {
        private var targetBinding: Binding<DrawerPaneDropTarget?>
        private var shouldAcceptDropClosure: (SplitDropPayload, UUID, DrawerDropZone) -> Bool
        private var handleDropClosure: (SplitDropPayload, UUID, DrawerDropZone) -> Void

        private(set) var paneFrames: [UUID: CGRect] = [:]
        private(set) var isManagementLayerActive: Bool = false

        init(
            targetBinding: Binding<DrawerPaneDropTarget?>,
            shouldAcceptDrop: @escaping (SplitDropPayload, UUID, DrawerDropZone) -> Bool,
            handleDrop: @escaping (SplitDropPayload, UUID, DrawerDropZone) -> Void
        ) {
            self.targetBinding = targetBinding
            self.shouldAcceptDropClosure = shouldAcceptDrop
            self.handleDropClosure = handleDrop
        }

        func updateHandlers(
            targetBinding: Binding<DrawerPaneDropTarget?>,
            shouldAcceptDrop: @escaping (SplitDropPayload, UUID, DrawerDropZone) -> Bool,
            handleDrop: @escaping (SplitDropPayload, UUID, DrawerDropZone) -> Void
        ) {
            self.targetBinding = targetBinding
            self.shouldAcceptDropClosure = shouldAcceptDrop
            self.handleDropClosure = handleDrop
        }

        func updateLayout(
            paneFrames: [UUID: CGRect],
            isManagementLayerActive: Bool
        ) {
            self.paneFrames = paneFrames
            self.isManagementLayerActive = isManagementLayerActive
        }

        func setTarget(_ target: DrawerPaneDropTarget?) {
            if targetBinding.wrappedValue != target {
                targetBinding.wrappedValue = target
            }
        }

        func finalizeDragSession() {
            setTarget(nil)
        }

        func hasSupportedTypes(in pasteboard: NSPasteboard) -> Bool {
            guard let types = pasteboard.types else { return false }
            return types.contains(where: { SplitContainerDropCaptureOverlay.supportedPasteboardTypes.contains($0) })
        }

        func handleDragUpdate(from pasteboard: NSPasteboard, location: CGPoint) -> DrawerPaneDropTarget? {
            guard let payload = decodeSplitDropPayload(from: pasteboard) else { return nil }

            return DrawerPaneDragCoordinator.resolveLatchedTarget(
                location: location,
                paneFrames: paneFrames,
                currentTarget: targetBinding.wrappedValue,
                shouldAcceptDrop: { paneId, zone in
                    shouldAcceptDropClosure(payload, paneId, zone)
                }
            )
        }

        func performDrop(from pasteboard: NSPasteboard, location: CGPoint) -> Bool {
            guard isManagementLayerActive else { return false }
            guard let payload = decodeSplitDropPayload(from: pasteboard) else { return false }
            guard
                let resolvedTarget = DrawerPaneDragCoordinator.resolveTarget(
                    location: location,
                    paneFrames: paneFrames
                ),
                shouldAcceptDropClosure(payload, resolvedTarget.paneId, resolvedTarget.zone)
            else {
                return false
            }

            handleDropClosure(payload, resolvedTarget.paneId, resolvedTarget.zone)
            return true
        }
    }
}

@MainActor
final class DrawerSplitContainerDropCaptureView: NSView {
    weak var coordinator: DrawerSplitContainerDropCaptureOverlay.Coordinator?

    private var isRegisteredForManagementLayer = false

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
        guard isRegisteredForManagementLayer != isManagementLayerActive else { return }
        if isManagementLayerActive {
            registerForDraggedTypes(SplitContainerDropCaptureOverlay.supportedPasteboardTypes)
        } else {
            unregisterDraggedTypes()
        }
        isRegisteredForManagementLayer = isManagementLayerActive
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        routeDragUpdate(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        routeDragUpdate(sender)
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
        coordinator.setTarget(target)
        return target == nil ? [] : .move
    }
}
