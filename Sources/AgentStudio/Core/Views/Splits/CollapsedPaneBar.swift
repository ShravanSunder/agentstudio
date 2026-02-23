import SwiftUI

/// A narrow vertical bar representing a minimized pane.
/// Shows an expand button (top), hamburger menu, and sideways title text (bottom-to-top).
/// Clicking the body also expands the pane.
struct CollapsedPaneBar: View {
    let paneId: UUID
    let tabId: UUID
    let title: String
    let action: (PaneAction) -> Void

    @State private var isHovered: Bool = false

    /// Fixed width for the collapsed bar (used in horizontal splits).
    static let barWidth: CGFloat = 30
    /// Fixed height for the collapsed bar (used in vertical splits).
    static let barHeight: CGFloat = 30

    var body: some View {
        VStack(spacing: 4) {
            // Expand button (top)
            Button {
                action(.expandPane(tabId: tabId, paneId: paneId))
            } label: {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: AppStyle.textXs, weight: .medium))
                    .foregroundStyle(.white.opacity(AppStyle.foregroundSecondary))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Expand pane")

            // Hamburger menu
            Menu {
                Button {
                    action(.expandPane(tabId: tabId, paneId: paneId))
                } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Divider()

                Button(role: .destructive) {
                    action(.closePane(tabId: tabId, paneId: paneId))
                } label: {
                    Label("Close", systemImage: "xmark")
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
            action(.expandPane(tabId: tabId, paneId: paneId))
        }
        .padding(AppStyle.paneGap)
    }
}
