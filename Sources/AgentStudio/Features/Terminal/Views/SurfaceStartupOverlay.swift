import AppKit
import SwiftUI

private enum SurfaceStartupOverlayState {
    case restoring
}

private struct SurfaceStartupOverlay: View {
    let state: SurfaceStartupOverlayState

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.98)

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.regular)

                switch state {
                case .restoring:
                    Text("Restoring terminal…")
                        .font(.system(size: AppStyle.textLg, weight: .semibold))
                }

                Text("Waiting for the terminal session to attach cleanly.")
                    .font(.system(size: AppStyle.textSm))
                    .foregroundStyle(.secondary)
            }
            .padding(28)
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
