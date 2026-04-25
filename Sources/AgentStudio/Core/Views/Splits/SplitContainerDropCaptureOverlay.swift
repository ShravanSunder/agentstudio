import AppKit
import SwiftUI
import os.log

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
    var traceRuntime: AgentStudioTraceRuntime? = .shared

    static let supportedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .agentStudioTabDrop,
        .agentStudioPaneDrop,
        .agentStudioNewTabDrop,
        .agentStudioTabInternal,
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(
            targetBinding: $target,
            actionDispatcher: actionDispatcher,
            traceRuntime: traceRuntime
        )
    }

    func makeNSView(context: Context) -> SplitContainerDropCaptureView {
        let view = SplitContainerDropCaptureView()
        view.coordinator = context.coordinator
        context.coordinator.updateHandlers(
            targetBinding: $target,
            actionDispatcher: actionDispatcher,
            traceRuntime: traceRuntime
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
            actionDispatcher: actionDispatcher,
            traceRuntime: traceRuntime
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
        private var traceRuntime: AgentStudioTraceRuntime?
        private var dragCorrelationID: String?

        private(set) var paneFrames: [UUID: CGRect] = [:]
        private(set) var containerBounds: CGRect = .zero
        private(set) var isManagementLayerActive: Bool = false
        private(set) var dragSession: DragSessionState = .idle

        init(
            targetBinding: Binding<PaneDropTarget?>,
            actionDispatcher: PaneActionDispatching,
            traceRuntime: AgentStudioTraceRuntime? = nil
        ) {
            self.targetBinding = targetBinding
            self.actionDispatcher = actionDispatcher
            self.traceRuntime = traceRuntime
        }

        func updateHandlers(
            targetBinding: Binding<PaneDropTarget?>,
            actionDispatcher: PaneActionDispatching,
            traceRuntime: AgentStudioTraceRuntime?
        ) {
            self.targetBinding = targetBinding
            self.actionDispatcher = actionDispatcher
            self.traceRuntime = traceRuntime
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
            if dragSession != .idle {
                traceDragEvent(body: "drag.end", attributes: dragSessionTraceAttributes())
            }
            setTarget(nil)
            dragSession = .idle
            dragCorrelationID = nil
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
                traceDragEvent(
                    body: "drag.decode_failed",
                    attributes: pasteboardTraceAttributes(pasteboard)
                )
                dragSession = .idle
                return nil
            }

            if let resolvedTarget = resolveTarget(at: location, payload: payload) {
                let candidate = DragSessionCandidate(payload: payload, target: resolvedTarget)
                dragSession = .armed(candidate: candidate)
                traceDragEvent(
                    body: "drag.update",
                    attributes: dragTraceAttributes(
                        payload: payload,
                        location: location,
                        target: resolvedTarget,
                        accepted: true
                    )
                )
                return resolvedTarget
            }

            dragSession = .previewing(payload: payload)
            traceDragEvent(
                body: "drag.update",
                attributes: dragTraceAttributes(
                    payload: payload,
                    location: location,
                    target: nil,
                    accepted: false
                )
            )
            return nil
        }

        func performDrop(from pasteboard: NSPasteboard, location: CGPoint) -> Bool {
            guard isManagementLayerActive else {
                dragSession = .teardown
                traceDragEvent(
                    body: "drag.drop_rejected", attributes: ["drag.reject_reason": .string("management-layer-inactive")]
                )
                return false
            }

            guard let payload = decodeSplitDropPayload(from: pasteboard),
                let resolvedTarget = resolveTarget(at: location, payload: payload)
            else {
                dragSession = .teardown
                traceDragEvent(
                    body: "drag.drop_rejected",
                    attributes: pasteboardTraceAttributes(pasteboard)
                )
                return false
            }

            let candidate = DragSessionCandidate(payload: payload, target: resolvedTarget)
            dragSession = .committing(candidate: candidate)
            actionDispatcher.handleDrop(
                payload,
                destinationPaneId: resolvedTarget.paneId,
                zone: resolvedTarget.zone
            )
            traceDragEvent(
                body: "drag.drop_committed",
                attributes: dragTraceAttributes(
                    payload: payload,
                    location: location,
                    target: resolvedTarget,
                    accepted: true
                )
            )
            dragSession = .teardown
            return true
        }

        private func traceDragEvent(body: String, attributes: [String: AgentStudioTraceValue]) {
            guard let traceRuntime, traceRuntime.isEnabled(.drag) else { return }
            let correlationID = dragCorrelationID ?? UUID().uuidString
            dragCorrelationID = correlationID
            var mergedAttributes = attributes
            mergedAttributes["drag.session_id"] = .string(correlationID)
            let eventAttributes = mergedAttributes

            Task {
                do {
                    try await traceRuntime.record(
                        tag: .drag,
                        body: body,
                        correlationID: correlationID,
                        attributes: eventAttributes
                    )
                    try await traceRuntime.flush()
                } catch {
                    splitContainerDragTraceLogger.warning(
                        "Failed to write drag trace event \(body, privacy: .public): \(error.localizedDescription)"
                    )
                }
            }
        }

        private func dragSessionTraceAttributes() -> [String: AgentStudioTraceValue] {
            switch dragSession {
            case .idle:
                return ["drag.state": .string("idle")]
            case .previewing(let payload):
                return [
                    "drag.payload.kind": .string(payload.traceKind),
                    "drag.state": .string("previewing"),
                ]
            case .armed(let candidate):
                return dragTraceAttributes(
                    payload: candidate.payload,
                    location: nil,
                    target: candidate.target,
                    accepted: true
                ).merging(["drag.state": .string("armed")]) { current, _ in current }
            case .committing(let candidate):
                return dragTraceAttributes(
                    payload: candidate.payload,
                    location: nil,
                    target: candidate.target,
                    accepted: true
                ).merging(["drag.state": .string("committing")]) { current, _ in current }
            case .teardown:
                return ["drag.state": .string("teardown")]
            }
        }

        private func dragTraceAttributes(
            payload: SplitDropPayload,
            location: CGPoint?,
            target: PaneDropTarget?,
            accepted: Bool
        ) -> [String: AgentStudioTraceValue] {
            var attributes: [String: AgentStudioTraceValue] = [
                "drag.accepted": .bool(accepted),
                "drag.payload.kind": .string(payload.traceKind),
            ]
            if let location {
                attributes["drag.location.x"] = .double(location.x)
                attributes["drag.location.y"] = .double(location.y)
            }
            if let target {
                attributes["drag.target.pane_id"] = .string(target.paneId.uuidString)
                attributes["drag.target.zone"] = .string(target.zone.rawValue)
            }
            return attributes
        }

        private func pasteboardTraceAttributes(_ pasteboard: NSPasteboard) -> [String: AgentStudioTraceValue] {
            [
                "drag.pasteboard.types": .stringArray((pasteboard.types ?? []).map(\.rawValue))
            ]
        }

        private static let supportedTypeSet: Set<NSPasteboard.PasteboardType> = Set(
            SplitContainerDropCaptureOverlay.supportedPasteboardTypes
        )
    }
}

private let splitContainerDragTraceLogger = Logger(subsystem: "com.agentstudio", category: "SplitContainerDragTrace")

extension SplitDropPayload {
    fileprivate var traceKind: String {
        switch kind {
        case .existingTab:
            return "existing_tab"
        case .existingPane:
            return "existing_pane"
        case .newTerminal:
            return "new_terminal"
        }
    }
}

@MainActor
final class SplitContainerDropCaptureView: NSView {
    weak var coordinator: SplitContainerDropCaptureOverlay.Coordinator?

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
