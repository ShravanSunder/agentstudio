import AppKit
import SwiftUI

struct CollapsedPaneBar: View {
    let paneId: UUID
    let tabId: UUID
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let onSaveArrangement: (() -> Void)?
    let dropTargetCoordinateSpace: String?
    let useDrawerFramePreference: Bool

    @State private var isHovered = false
    @State private var isExpandHovered = false
    @State private var isArrangementHovered = false
    @State private var isArrangementPanelPresented = false
    @State private var arrangementPopoverToggleGate = PopoverToggleGate()

    static let barWidth: CGFloat = AppStyle.collapsedBarWidth
    static let barHeight: CGFloat = AppStyle.collapsedBarWidth

    init(
        paneId: UUID,
        tabId: UUID,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        actionDispatcher: PaneActionDispatching,
        onSaveArrangement: (() -> Void)? = nil,
        dropTargetCoordinateSpace: String? = nil,
        useDrawerFramePreference: Bool = false
    ) {
        self.paneId = paneId
        self.tabId = tabId
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.actionDispatcher = actionDispatcher
        self.onSaveArrangement = onSaveArrangement
        self.dropTargetCoordinateSpace = dropTargetCoordinateSpace
        self.useDrawerFramePreference = useDrawerFramePreference
    }

    private var isClosing: Bool {
        closeTransitionCoordinator.closingPaneIds.contains(paneId)
    }

    private var isDrawerChild: Bool {
        atom(\.workspacePane).pane(paneId)?.isDrawerChild ?? false
    }

    var body: some View {
        let paneDisplay = atom(\.paneDisplay)
        let displayParts = paneDisplay.displayParts(for: paneId)
        let iconTint =
            paneDisplay.accentColorHex(for: paneId)
            .flatMap { NSColor(hex: $0) }
            .map(Color.init(nsColor:))
            ?? Color.secondary.opacity(0.92)

        VStack(spacing: AppStyle.spacingStandard) {
            expandButton

            if !isDrawerChild {
                arrangementButton
            }

            GeometryReader { geo in
                collapsedLabel(availableHeight: geo.size.height, iconTint: iconTint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.vertical, AppStyle.spacingLoose)
        .frame(width: Self.barWidth)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.panelCornerRadius)
                .fill(Color.white.opacity(isHovered ? AppStyle.fillHover : AppStyle.fillMuted))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.panelCornerRadius)
                .strokeBorder(
                    Color.white.opacity(isHovered ? AppStyle.strokeHover : AppStyle.fillActive),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(displayParts.primaryLabel)
        .contextMenu {
            Button {
                actionDispatcher.dispatch(.expandPane(tabId: tabId, paneId: paneId))
            } label: {
                Label(AppCommand.expandPane.definition.label, systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Divider()

            Button(role: .destructive) {
                beginCloseTransition()
            } label: {
                Label(AppCommand.closePane.definition.label, systemImage: "xmark")
            }
        }
        .opacity(isClosing ? 0.58 : 1)
        .scaleEffect(isClosing ? 0.985 : 1)
        .animation(.easeOut(duration: AppStyle.animationFast), value: isClosing)
        .allowsHitTesting(!isClosing)
        .padding(AppStyle.paneGap)
        .background(framePreferenceBackground)
    }

    private var expandButton: some View {
        Button {
            actionDispatcher.dispatch(.expandPane(tabId: tabId, paneId: paneId))
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                .foregroundStyle(isExpandHovered ? .primary : .secondary)
                .frame(width: AppStyle.compactButtonSize, height: AppStyle.compactButtonSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isExpandHovered ? AppStyle.fillPressed : AppStyle.fillMuted))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isExpandHovered = $0 }
        .help(AppCommand.expandPane.definition.helpText)
    }

    private var arrangementButton: some View {
        let arrangement = atom(\.arrangement)
        let panes = arrangement.paneVisibilityItems(for: tabId)
        let arrangements = arrangement.arrangementItems(for: tabId)

        return Button {
            arrangementPopoverToggleGate.toggle(isPresented: &isArrangementPanelPresented)
        } label: {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                .foregroundStyle(isArrangementHovered ? .primary : .secondary)
                .frame(width: AppStyle.compactButtonSize, height: AppStyle.compactButtonSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isArrangementHovered ? AppStyle.fillPressed : AppStyle.fillMuted))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isArrangementHovered = $0 }
        .help(LocalActionSpec.arrangements.actionSpec.helpText)
        .popover(
            isPresented: Binding(
                get: { isArrangementPanelPresented },
                set: { newValue in
                    if !newValue && isArrangementPanelPresented {
                        isArrangementPanelPresented = false
                        arrangementPopoverToggleGate.recordSystemDismissal()
                    } else {
                        isArrangementPanelPresented = newValue
                    }
                }
            ),
            attachmentAnchor: .point(.center),
            arrowEdge: .leading
        ) {
            ArrangementPanel(
                tabId: tabId,
                panes: panes,
                arrangements: arrangements,
                onPaneAction: { action in
                    isArrangementPanelPresented = false
                    actionDispatcher.dispatch(action)
                },
                onSaveArrangement: { onSaveArrangement?() },
                showMinimizedBarsBinding: Binding(
                    get: { atom(\.uiState).showMinimizedBars },
                    set: { atom(\.uiState).setShowMinimizedBars($0) }
                ),
                highlightPaneId: paneId,
                showsMinimizedBarToggle: false
            )
        }
    }

    @ViewBuilder
    private func collapsedLabel(availableHeight: CGFloat, iconTint: Color) -> some View {
        let labelParts = atom(\.paneDisplay).collapsedBarLabelParts(for: paneId)
        let maxLabelWidth = availableHeight * 0.82
        let allocatedTextWidths = CollapsedBarTextAllocator.allocatedTextWidths(
            for: labelParts,
            availableLabelWidth: maxLabelWidth
        )

        HStack(spacing: CollapsedBarTextAllocator.segmentSpacing) {
            ForEach(Array(labelParts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text("·")
                        .font(.system(size: AppStyle.textSm))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: AppStyle.spacingTight) {
                    iconView(for: part.icon)
                        .foregroundStyle(iconTint)

                    Text(part.text)
                        .font(.system(size: AppStyle.textBase, weight: fontWeight(for: part.weight)))
                        .foregroundStyle(textColor(for: part.weight))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.9)
                        .frame(
                            width: allocatedTextWidths[index],
                            alignment: .leading
                        )
                }
            }
        }
        .frame(maxWidth: maxLabelWidth, alignment: .leading)
        .fixedSize()
        .rotationEffect(.degrees(-90))
        .frame(
            width: Self.barWidth - AppStyle.spacingStandard * 2,
            height: availableHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    private func iconView(for icon: CollapsedBarLabelPart.IconKind) -> some View {
        switch icon {
        case .octicon(let name):
            OcticonImage(name: name, size: AppStyle.textBase)
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: AppStyle.textBase, weight: .medium))
        }
    }

    private func fontWeight(for weight: CollapsedBarLabelPart.TextWeight) -> Font.Weight {
        switch weight {
        case .semibold:
            .semibold
        case .regular:
            .regular
        }
    }

    private func textColor(for weight: CollapsedBarLabelPart.TextWeight) -> Color {
        switch weight {
        case .semibold:
            return Color.primary.opacity(0.92)
        case .regular:
            return Color.secondary.opacity(0.92)
        }
    }

    private var framePreferenceBackground: some View {
        GeometryReader { geo in
            if let dropTargetCoordinateSpace {
                let frame = geo.frame(in: .named(dropTargetCoordinateSpace))
                if useDrawerFramePreference {
                    Color.clear
                        .preference(
                            key: DrawerPaneFramePreferenceKey.self,
                            value: [paneId: frame]
                        )
                        .preference(
                            key: PaneFramePreferenceKey.self,
                            value: [paneId: geo.frame(in: .named("tabContainer"))]
                        )
                } else {
                    Color.clear.preference(
                        key: PaneFramePreferenceKey.self,
                        value: [paneId: frame]
                    )
                }
            } else {
                Color.clear
            }
        }
    }

    private func beginCloseTransition() {
        closeTransitionCoordinator.beginClosingPane(paneId) {
            actionDispatcher.dispatch(.closePane(tabId: tabId, paneId: paneId))
        }
    }
}
