import AppKit
import SwiftUI

private enum SurfaceStartupOverlayState {
    case preparing
    case restoring
}

private struct SurfaceStartupOverlay: View {
    let state: SurfaceStartupOverlayState

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.98)

            VStack(spacing: AppStyles.WorkspaceFocus.Terminal.startupOverlaySpacing) {
                ProgressView()
                    .controlSize(.regular)

                switch state {
                case .preparing:
                    Text("Preparing terminal...")
                        .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
                case .restoring:
                    Text("Restoring terminal…")
                        .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
                }

                Text(detailText)
                    .font(.system(size: AppStyles.General.Typography.textSm))
                    .foregroundStyle(.secondary)
            }
            .padding(AppStyles.WorkspaceFocus.Terminal.startupOverlayPadding)
        }
    }

    private var detailText: String {
        switch state {
        case .preparing:
            return "Waiting for trusted pane geometry before creating the terminal."
        case .restoring:
            return "Waiting for the terminal session to attach cleanly."
        }
    }
}

final class SurfaceStartupOverlayView: NSView {
    private var hostingView: NSHostingView<SurfaceStartupOverlay>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        isHidden = true
    }

    func showRestoring() {
        show(state: .restoring)
    }

    func showPreparing() {
        show(state: .preparing)
    }

    func hide() {
        isHidden = true
        hostingView?.removeFromSuperview()
        hostingView = nil
    }

    private func show(state: SurfaceStartupOverlayState) {
        hostingView?.removeFromSuperview()
        let hostingView = NSHostingView(rootView: SurfaceStartupOverlay(state: state))
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        self.hostingView = hostingView
        isHidden = false
    }
}
