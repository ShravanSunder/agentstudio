import AgentStudioInfrastructure
import SwiftUI

private struct DividerLayoutPublicationKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

package struct DividerFrameMeasurementState {
    private var pendingCorrelationId: UUID?

    package init() {}

    @discardableResult
    package mutating func admitSample(
        using interactionProbe: AgentStudioInteractionPerformanceProbe?
    ) -> Bool {
        guard pendingCorrelationId == nil, let interactionProbe else { return false }
        let correlationId = UUIDv7.generate()
        interactionProbe.beginInteraction(.dividerFrame, correlationId: correlationId)
        pendingCorrelationId = correlationId
        return true
    }

    package mutating func layoutDidPublish(
        using interactionProbe: AgentStudioInteractionPerformanceProbe?
    ) {
        guard let pendingCorrelationId else { return }
        self.pendingCorrelationId = nil
        interactionProbe?.settleInteraction(correlationId: pendingCorrelationId)
    }
}

package struct FlatPaneDivider: View {
    let dividerId: UUID
    let frame: CGRect
    let resizeIntent: FlatTabStripMetrics.DividerSegment.ResizeIntent
    let resizeLeftPaneWidth: CGFloat
    let resizeRightPaneWidth: CGFloat
    let layout: Layout
    @Binding var isSplitResizing: Bool
    let tabId: UUID
    let actionDispatcher: PaneActionDispatching

    private let splitterHitSize: CGFloat = 6
    private let minSize: CGFloat = AppPolicies.DragAndDrop.splitMinimumPaneSize

    @State private var hasStartedResize = false
    @State private var initialLeftWidth: CGFloat = 0
    @State private var initialRightWidth: CGFloat = 0
    @State private var frameMeasurement = DividerFrameMeasurementState()
    @Environment(\.agentStudioInteractionPerformanceProbe) private var interactionProbe

    package init(
        dividerId: UUID,
        frame: CGRect,
        resizeIntent: FlatTabStripMetrics.DividerSegment.ResizeIntent,
        resizeLeftPaneWidth: CGFloat,
        resizeRightPaneWidth: CGFloat,
        layout: Layout,
        isSplitResizing: Binding<Bool>,
        tabId: UUID,
        actionDispatcher: PaneActionDispatching
    ) {
        self.dividerId = dividerId
        self.frame = frame
        self.resizeIntent = resizeIntent
        self.resizeLeftPaneWidth = resizeLeftPaneWidth
        self.resizeRightPaneWidth = resizeRightPaneWidth
        self.layout = layout
        _isSplitResizing = isSplitResizing
        self.tabId = tabId
        self.actionDispatcher = actionDispatcher
    }

    /// Pure computation for drag-resize ratio. Extracted for testability.
    nonisolated static func computeResizeRatio(
        initialLeftWidth: CGFloat,
        initialRightWidth: CGFloat,
        translationWidth: CGFloat,
        minSize: CGFloat
    ) -> Double {
        let totalWidth = initialLeftWidth + initialRightWidth
        guard totalWidth > 0 else { return 0.5 }
        let clampedLeftWidth = min(
            max(initialLeftWidth + translationWidth, minSize),
            totalWidth - minSize
        )
        return clampedLeftWidth / totalWidth
    }

    nonisolated static func resizeCommand(
        for intent: FlatTabStripMetrics.DividerSegment.ResizeIntent,
        tabId: UUID,
        ratio: Double
    ) -> WorkspaceActionCommand? {
        switch intent {
        case .structural(let splitId):
            return .resizePane(tabId: tabId, splitId: splitId, ratio: ratio)
        case .visiblePanePair(let leftPaneId, let rightPaneId):
            return .resizeVisiblePanePair(
                tabId: tabId,
                leftPaneId: leftPaneId,
                rightPaneId: rightPaneId,
                ratio: ratio
            )
        case .noResize:
            return nil
        }
    }

    package var body: some View {
        Group {
            if case .noResize = resizeIntent {
                Color.clear
                    .frame(width: splitterHitSize, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            } else {
                Color.clear
                    .frame(width: splitterHitSize, height: frame.height)
                    .contentShape(Rectangle())
                    .position(x: frame.midX, y: frame.midY)
                    .backport.pointerStyle(.resizeLeftRight)
                    .preference(key: DividerLayoutPublicationKey.self, value: frame)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                guard layout.dividerIds.contains(dividerId) else { return }
                                if !hasStartedResize {
                                    hasStartedResize = true
                                    initialLeftWidth = resizeLeftPaneWidth
                                    initialRightWidth = resizeRightPaneWidth
                                    isSplitResizing = true
                                }

                                frameMeasurement.admitSample(using: interactionProbe)
                                let localRatio = Self.computeResizeRatio(
                                    initialLeftWidth: initialLeftWidth,
                                    initialRightWidth: initialRightWidth,
                                    translationWidth: gesture.translation.width,
                                    minSize: minSize
                                )
                                guard
                                    let command = Self.resizeCommand(
                                        for: resizeIntent,
                                        tabId: tabId,
                                        ratio: localRatio
                                    )
                                else { return }
                                actionDispatcher.dispatch(command)
                            }
                            .onEnded { _ in
                                hasStartedResize = false
                                isSplitResizing = false
                            }
                    )
            }
        }
        .onPreferenceChange(DividerLayoutPublicationKey.self) { _ in
            frameMeasurement.layoutDidPublish(using: interactionProbe)
        }
    }
}
