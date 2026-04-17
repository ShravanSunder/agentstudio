import AppKit
import SwiftUI

enum CollapsedPaneBarButtonId: Equatable {
    case expand
    case arrangementPopover
}

struct CollapsedPaneBar: View {
    let paneId: UUID
    let tabId: UUID
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let dropTargetCoordinateSpace: String?
    let useDrawerFramePreference: Bool

    @State private var isHovered = false
    @State private var isExpandHovered = false

    static let barWidth: CGFloat = AppStyle.collapsedBarWidth
    static let barHeight: CGFloat = AppStyle.collapsedBarWidth

    /// Ordered list of primary action buttons this bar renders.
    /// Asserted by `CollapsedPaneBarTests` — the tab-bar arrangement chip
    /// is the single entry point for arrangement management; the collapsed
    /// bar stays focused on per-pane actions.
    static let primaryButtonIdentifiers: [CollapsedPaneBarButtonId] = [.expand]

    init(
        paneId: UUID,
        tabId: UUID,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        actionDispatcher: PaneActionDispatching,
        dropTargetCoordinateSpace: String? = nil,
        useDrawerFramePreference: Bool = false
    ) {
        self.paneId = paneId
        self.tabId = tabId
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.actionDispatcher = actionDispatcher
        self.dropTargetCoordinateSpace = dropTargetCoordinateSpace
        self.useDrawerFramePreference = useDrawerFramePreference
    }

    private var isClosing: Bool {
        closeTransitionCoordinator.closingPaneIds.contains(paneId)
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
