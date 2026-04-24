import AppKit
import SwiftUI

struct DrawerSplitContainerDropCaptureOverlay: NSViewRepresentable {
    let paneFrames: [UUID: CGRect]
    let layout: DrawerGridLayout
    let minimizedPaneIds: Set<UUID>
    let containerBounds: CGRect
    @Binding var target: DrawerRearrangeTarget?
    let isManagementLayerActive: Bool
    let shouldAcceptDrop: (SplitDropPayload, DrawerRearrangeTarget, DropSizingMode) -> Bool
    let handleDrop: (SplitDropPayload, DrawerRearrangeTarget, DropSizingMode) -> Void

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
            layout: layout,
            minimizedPaneIds: minimizedPaneIds,
            containerBounds: containerBounds,
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
            layout: layout,
            minimizedPaneIds: minimizedPaneIds,
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
        private var targetBinding: Binding<DrawerRearrangeTarget?>
        private var shouldAcceptDropClosure: (SplitDropPayload, DrawerRearrangeTarget, DropSizingMode) -> Bool
        private var handleDropClosure: (SplitDropPayload, DrawerRearrangeTarget, DropSizingMode) -> Void

        private(set) var paneFrames: [UUID: CGRect] = [:]
        private(set) var layout = DrawerGridLayout()
        private(set) var minimizedPaneIds: Set<UUID> = []
        private(set) var containerBounds: CGRect = .zero
        private(set) var isManagementLayerActive: Bool = false

        init(
            targetBinding: Binding<DrawerRearrangeTarget?>,
            shouldAcceptDrop: @escaping (SplitDropPayload, DrawerRearrangeTarget, DropSizingMode) -> Bool,
            handleDrop: @escaping (SplitDropPayload, DrawerRearrangeTarget, DropSizingMode) -> Void
        ) {
            self.targetBinding = targetBinding
            self.shouldAcceptDropClosure = shouldAcceptDrop
            self.handleDropClosure = handleDrop
        }

        func updateHandlers(
            targetBinding: Binding<DrawerRearrangeTarget?>,
            shouldAcceptDrop: @escaping (SplitDropPayload, DrawerRearrangeTarget, DropSizingMode) -> Bool,
            handleDrop: @escaping (SplitDropPayload, DrawerRearrangeTarget, DropSizingMode) -> Void
        ) {
            self.targetBinding = targetBinding
            self.shouldAcceptDropClosure = shouldAcceptDrop
            self.handleDropClosure = handleDrop
        }

        func updateLayout(
            paneFrames: [UUID: CGRect],
            layout: DrawerGridLayout,
            minimizedPaneIds: Set<UUID>,
            containerBounds: CGRect,
            isManagementLayerActive: Bool
        ) {
            self.paneFrames = paneFrames
            self.layout = layout
            self.minimizedPaneIds = minimizedPaneIds
            self.containerBounds = containerBounds
            self.isManagementLayerActive = isManagementLayerActive
        }

        func setTarget(_ target: DrawerRearrangeTarget?) {
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

        func handleDragUpdate(from pasteboard: NSPasteboard, location: CGPoint) -> DrawerRearrangeTarget? {
            guard let payload = decodeSplitDropPayload(from: pasteboard) else {
                let pasteboardTypes = pasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "nil"
                RestoreTrace.log(
                    "DrawerSplit.handleDragUpdate decode=nil location=\(NSStringFromPoint(location)) types=\(pasteboardTypes)"
                )
                return nil
            }

            let target = DrawerPaneDragCoordinator.resolveLatchedTarget(
                location: location,
                geometry: drawerPaneDragGeometry,
                currentTarget: targetBinding.wrappedValue,
                shouldAcceptDrop: { target in
                    shouldAcceptDropClosure(
                        payload,
                        target,
                        DrawerPaneDragCoordinator.sizingMode(
                            for: target,
                            isShiftHeld: NSEvent.modifierFlags.contains(.shift)
                        )
                    )
                }
            )
            RestoreTrace.log(
                "DrawerSplit.handleDragUpdate location=\(NSStringFromPoint(location)) payload=\(String(describing: payload)) target=\(String(describing: target)) paneFrameCount=\(paneFrames.count)"
            )
            return target
        }

        func performDrop(from pasteboard: NSPasteboard, location: CGPoint) -> Bool {
            guard isManagementLayerActive else { return false }
            guard let payload = decodeSplitDropPayload(from: pasteboard) else {
                RestoreTrace.log(
                    "DrawerSplit.performDrop decode=nil location=\(NSStringFromPoint(location))"
                )
                return false
            }
            guard
                let resolvedTarget = DrawerPaneDragCoordinator.resolveTarget(
                    location: location,
                    geometry: drawerPaneDragGeometry
                ),
                shouldAcceptDropClosure(
                    payload,
                    resolvedTarget,
                    DrawerPaneDragCoordinator.sizingMode(
                        for: resolvedTarget,
                        isShiftHeld: NSEvent.modifierFlags.contains(.shift)
                    )
                )
            else {
                RestoreTrace.log(
                    "DrawerSplit.performDrop rejected location=\(NSStringFromPoint(location)) payload=\(String(describing: payload))"
                )
                return false
            }

            RestoreTrace.log(
                "DrawerSplit.performDrop target=\(String(describing: resolvedTarget)) location=\(NSStringFromPoint(location))"
            )
            handleDropClosure(
                payload,
                resolvedTarget,
                DrawerPaneDragCoordinator.sizingMode(
                    for: resolvedTarget,
                    isShiftHeld: NSEvent.modifierFlags.contains(.shift)
                )
            )
            return true
        }

        private var drawerPaneDragGeometry: DrawerPaneDragGeometry {
            DrawerPaneDragGeometry(
                paneFrames: paneFrames,
                layout: layout,
                containerBounds: containerBounds,
                minimizedPaneIds: minimizedPaneIds
            )
        }
    }
}

@MainActor
final class DrawerSplitContainerDropCaptureView: NSView {
    weak var coordinator: DrawerSplitContainerDropCaptureOverlay.Coordinator?

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

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        RestoreTrace.log(
            "DrawerSplit.viewDidMoveToSuperview super=\(superview.map { "\(type(of: $0))" } ?? "nil") bounds=\(NSStringFromRect(bounds))"
        )
        applyDropRegistration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        RestoreTrace.log(
            "DrawerSplit.viewDidMoveToWindow window=\(window != nil) bounds=\(NSStringFromRect(bounds))"
        )
        applyDropRegistration()
    }

    func updateDropRegistration(isManagementLayerActive: Bool) {
        isManagementLayerActiveRequest = isManagementLayerActive
        applyDropRegistration()
    }

    /// Registers/unregisters for dragged types based on the management-layer request
    /// AND on whether the view has a non-empty frame. AppKit's drag destination
    /// traversal skips views with empty bounds, so registering during SwiftUI's
    /// initial zero-sized mount silently leaves the drawer invisible to drag routing.
    /// Gating on `!bounds.isEmpty` plus re-applying on every frame change closes
    /// that window.
    private func applyDropRegistration() {
        let shouldRegister = isManagementLayerActiveRequest && !bounds.isEmpty
        guard isRegisteredForManagementLayer != shouldRegister else { return }
        if shouldRegister {
            registerForDraggedTypes(SplitContainerDropCaptureOverlay.supportedPasteboardTypes)
            let windowFrame = superview.map { $0.convert(frame, to: nil) } ?? .zero
            let hasWindow = window != nil
            var ancestors: [String] = []
            var current: NSView? = superview
            while let view = current {
                let maskInfo: String
                if let layer = view.layer {
                    maskInfo =
                        "mask=\(layer.mask != nil) masksToBounds=\(layer.masksToBounds) alpha=\(layer.opacity)"
                } else {
                    maskInfo = "noLayer"
                }
                ancestors.append(
                    "(\(type(of: view)) flipped=\(view.isFlipped) hidden=\(view.isHidden) alpha=\(view.alphaValue) clipsToBounds=\(view.layer?.masksToBounds ?? false) \(maskInfo))"
                )
                current = view.superview
            }
            RestoreTrace.log(
                "DrawerSplit.updateDropRegistration registered flipped=\(isFlipped) local=\(NSStringFromRect(frame)) windowFrame=\(NSStringFromRect(windowFrame)) hasWindow=\(hasWindow) ancestors=[\(ancestors.joined(separator: " -> "))]"
            )
        } else {
            unregisterDraggedTypes()
            RestoreTrace.log(
                "DrawerSplit.updateDropRegistration unregistered managementActive=\(isManagementLayerActiveRequest) boundsEmpty=\(bounds.isEmpty)"
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
            "DrawerSplit.draggingEntered session=\(DragSession.current) raw=\(NSStringFromPoint(sender.draggingLocation))"
        )
        return routeDragUpdate(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        RestoreTrace.log(
            "DrawerSplit.draggingUpdated session=\(DragSession.current) raw=\(NSStringFromPoint(sender.draggingLocation))"
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
            "DrawerSplit.routeDragUpdate converted=\(NSStringFromPoint(location)) target=\(String(describing: target))"
        )
        coordinator.setTarget(target)
        return target == nil ? [] : .move
    }
}
