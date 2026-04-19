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
    @State private var arrangementInlineRenameState = ArrangementInlineRenameState()

    static let barWidth: CGFloat = AppStyles.Shell.PaneChrome.collapsedBarWidth
    static let barHeight: CGFloat = AppStyles.Shell.PaneChrome.collapsedBarWidth

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

        VStack(spacing: AppStyles.General.Spacing.standard) {
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
        .padding(.vertical, AppStyles.General.Spacing.loose)
        .frame(width: Self.barWidth)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.panel)
                .fill(Color.white.opacity(isHovered ? AppStyles.General.Fill.hover : AppStyles.General.Fill.muted))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.panel)
                .strokeBorder(
                    Color.white.opacity(isHovered ? AppStyles.General.Stroke.hover : AppStyles.General.Fill.active),
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
        .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: isClosing)
        .allowsHitTesting(!isClosing)
        .padding(AppStyles.General.Layout.paneGap)
        .background(framePreferenceBackground)
    }

    private var expandButton: some View {
        Button {
            actionDispatcher.dispatch(.expandPane(tabId: tabId, paneId: paneId))
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                .foregroundStyle(isExpandHovered ? .primary : .secondary)
                .frame(width: AppStyles.General.Button.compact, height: AppStyles.General.Button.compact)
                .background(
                    Circle()
                        .fill(
                            Color.white.opacity(
                                isExpandHovered
                                    ? AppStyles.General.Fill.pressed
                                    : AppStyles.General.Fill.muted
                            )
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isExpandHovered = $0 }
        .help(AppCommand.expandPane.definition.controlToolTip)
    }

    private var arrangementButton: some View {
        let arrangement = atom(\.arrangement)
        let panes = arrangement.paneVisibilityItems(for: tabId)
        let arrangements = arrangement.arrangementItems(for: tabId)

        return Button {
            arrangementPopoverToggleGate.toggle(isPresented: &isArrangementPanelPresented)
        } label: {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                .foregroundStyle(isArrangementHovered ? .primary : .secondary)
                .frame(width: AppStyles.General.Button.compact, height: AppStyles.General.Button.compact)
                .background(
                    Circle()
                        .fill(
                            Color.white.opacity(
                                isArrangementHovered
                                    ? AppStyles.General.Fill.pressed
                                    : AppStyles.General.Fill.muted
                            )
                        )
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
            attachmentAnchor: ArrangementPanelPopoverPlacement.minimizedBar.attachmentAnchor,
            arrowEdge: ArrangementPanelPopoverPlacement.minimizedBar.arrowEdge
        ) {
            ArrangementPanel(
                tabId: tabId,
                panes: panes,
                arrangements: arrangements,
                inlineRenameState: arrangementInlineRenameState,
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
        let partsWithWidths = Array(zip(labelParts, allocatedTextWidths).enumerated())

        HStack(spacing: CollapsedBarTextAllocator.segmentSpacing) {
            ForEach(partsWithWidths, id: \.offset) { index, element in
                let (part, textWidth) = element
                if index > 0 {
                    Text("·")
                        .font(.system(size: AppStyles.General.Typography.textSm))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: AppStyles.General.Spacing.tight) {
                    iconView(for: part.icon)
                        .foregroundStyle(iconTint)

                    Text(part.text)
                        .font(
                            .system(
                                size: AppStyles.General.Typography.textBase,
                                weight: fontWeight(for: part.weight)
                            )
                        )
                        .foregroundStyle(textColor(for: part.weight))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.9)
                        .frame(
                            width: textWidth,
                            alignment: .leading
                        )
                }
            }
        }
        .frame(maxWidth: maxLabelWidth, alignment: .leading)
        .fixedSize()
        .rotationEffect(.degrees(-90))
        .frame(
            width: Self.barWidth - AppStyles.General.Spacing.standard * 2,
            height: availableHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    private func iconView(for icon: CollapsedBarLabelPart.IconKind) -> some View {
        switch icon {
        case .octicon(let name):
            OcticonImage(name: name, size: AppStyles.General.Typography.textBase)
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
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
