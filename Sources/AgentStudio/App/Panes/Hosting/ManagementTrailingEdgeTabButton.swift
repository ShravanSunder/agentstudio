import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import SwiftUI

struct ManagementTrailingEdgeTabButton: View {
    let systemName: String
    let isHovered: Bool
    let isEnabled: Bool
    let tooltip: ControlTooltipRenderValue
    let accessibilityIdentifier: String
    let onAnchorViewChanged: ((NSView?) -> Void)?
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: AppStyles.Shell.PaneChrome.paneSplitIconSize, weight: .bold))
                .foregroundStyle(
                    .white.opacity(AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: isHovered))
                )
                .frame(
                    width: AppStyles.Shell.PaneChrome.paneSplitButtonSize,
                    height: AppStyles.Shell.PaneChrome.paneEdgeButtonHeight
                )
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppStyles.General.CornerRadius.panel + 4,
                        bottomLeadingRadius: AppStyles.General.CornerRadius.panel + 4,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(
                        Color.black.opacity(
                            AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: isHovered)
                        )
                    )
                )
                .contentShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppStyles.General.CornerRadius.panel + 4,
                        bottomLeadingRadius: AppStyles.General.CornerRadius.panel + 4,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .controlHelp(tooltip)
        .accessibilityHidden(true)
        .background {
            ZStack {
                AccessibilityPressBridge(
                    identifier: accessibilityIdentifier,
                    label: tooltip.text,
                    isEnabled: isEnabled,
                    action: action
                )
                if let onAnchorViewChanged {
                    ManagementEdgeTabAnchorBridge(onViewChanged: onAnchorViewChanged)
                }
            }
        }
    }
}

@MainActor
final class PaneMoveDestinationMenuPresenter: NSObject {
    struct Destination {
        let title: String
        let perform: @MainActor () -> Void
    }

    private var destinations: [Destination] = []

    func present(destinations: [Destination], from anchorView: NSView) {
        self.destinations = destinations
        let menu = NSMenu()
        menu.autoenablesItems = false

        for (index, destination) in destinations.enumerated() {
            let item = NSMenuItem(
                title: destination.title,
                action: #selector(activateDestination(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.isEnabled = true
            menu.addItem(item)
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: anchorView.bounds.minX, y: anchorView.bounds.maxY),
            in: anchorView
        )
        self.destinations = []
    }

    @objc
    private func activateDestination(_ sender: NSMenuItem) {
        guard destinations.indices.contains(sender.tag) else { return }
        destinations[sender.tag].perform()
    }
}

private struct ManagementEdgeTabAnchorBridge: NSViewRepresentable {
    let onViewChanged: (NSView?) -> Void

    func makeNSView(context _: Context) -> ManagementEdgeTabAnchorView {
        let view = ManagementEdgeTabAnchorView()
        view.onViewChanged = onViewChanged
        return view
    }

    func updateNSView(_ nsView: ManagementEdgeTabAnchorView, context _: Context) {
        nsView.onViewChanged = onViewChanged
    }

    static func dismantleNSView(_ nsView: ManagementEdgeTabAnchorView, coordinator _: ()) {
        nsView.onViewChanged(nil)
    }
}

private final class ManagementEdgeTabAnchorView: NSView {
    var onViewChanged: (NSView?) -> Void = { _ in }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onViewChanged(window == nil ? nil : self)
    }
}
