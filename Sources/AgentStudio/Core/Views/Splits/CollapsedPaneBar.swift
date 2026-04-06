import SwiftUI

/// A narrow vertical bar representing a minimized pane.
/// Shows an expand button (top), hamburger menu, and sideways title text (bottom-to-top).
/// Clicking the body also expands the pane.
struct CollapsedPaneBar: View {
    let paneId: UUID
    let tabId: UUID
    let title: String
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let dropTargetCoordinateSpace: String?
    let useDrawerFramePreference: Bool

    @State private var isHovered: Bool = false

    /// Fixed width for the collapsed bar (used in horizontal splits).
    static let barWidth: CGFloat = 30
    /// Fixed height for the collapsed bar (used in vertical splits).
    static let barHeight: CGFloat = 30

    init(
        paneId: UUID,
        tabId: UUID,
        title: String,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        actionDispatcher: PaneActionDispatching,
        dropTargetCoordinateSpace: String? = nil,
        useDrawerFramePreference: Bool = false
    ) {
        self.paneId = paneId
        self.tabId = tabId
        self.title = title
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.actionDispatcher = actionDispatcher
        self.dropTargetCoordinateSpace = dropTargetCoordinateSpace
        self.useDrawerFramePreference = useDrawerFramePreference
    }

    private var isClosing: Bool {
        closeTransitionCoordinator.closingPaneIds.contains(paneId)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Expand button (top)
            Button {
                actionDispatcher.dispatch(.expandPane(tabId: tabId, paneId: paneId))
            } label: {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: AppStyle.textXs, weight: .medium))
                    .foregroundStyle(.white.opacity(AppStyle.foregroundSecondary))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(AppCommand.expandPane.definition.helpText)

            // Hamburger menu
            Menu {
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
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: AppStyle.textSm))
                    .foregroundStyle(.white.opacity(AppStyle.foregroundDim))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 4)

            // Sideways text (bottom-to-top)
            Text(title)
                .font(.system(size: AppStyle.textBase, weight: .bold))
                .foregroundStyle(.white.opacity(AppStyle.foregroundSecondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .rotationEffect(Angle(degrees: -90))
                .fixedSize()
                .frame(maxHeight: .infinity, alignment: .center)

            Spacer(minLength: 4)
        }
        .frame(width: Self.barWidth)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius)
                .fill(Color.black.opacity(isHovered ? AppStyle.foregroundDim : 0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius)
                .strokeBorder(
                    Color.white.opacity(isHovered ? AppStyle.strokeHover : AppStyle.strokeSubtle), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            actionDispatcher.dispatch(.expandPane(tabId: tabId, paneId: paneId))
        }
        .opacity(isClosing ? 0.58 : 1)
        .scaleEffect(isClosing ? 0.985 : 1)
        .animation(.easeOut(duration: AppStyle.animationFast), value: isClosing)
        .allowsHitTesting(!isClosing)
        .padding(AppStyle.paneGap)
        .background(
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
        )
    }

    private func beginCloseTransition() {
        closeTransitionCoordinator.beginClosingPane(paneId) {
            actionDispatcher.dispatch(.closePane(tabId: tabId, paneId: paneId))
        }
    }
}
