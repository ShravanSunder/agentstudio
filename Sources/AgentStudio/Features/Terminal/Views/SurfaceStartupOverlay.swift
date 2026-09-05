import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import SwiftUI

private enum SurfaceStartupOverlayState {
    case preparing
    case restoring
    /// SPEC R5's settled deferral state: the scheduler has parked this
    /// member until later geometry arrives. Indefinite, not imminent, so
    /// this renders with no progress indicator and no focusable control —
    /// there is nothing in flight to show progress on, and no retry action
    /// this overlay could offer (only later geometry resolves it).
    case waitingForGeometry
}

private struct SurfaceStartupOverlay: View {
    let state: SurfaceStartupOverlayState

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.98)

            VStack(spacing: AppStyles.WorkspaceFocus.Terminal.startupOverlaySpacing) {
                if showsProgressIndicator {
                    ProgressView()
                        .controlSize(.regular)
                }

                switch state {
                case .preparing:
                    Text("Preparing terminal...")
                        .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
                case .restoring:
                    Text("Restoring terminal…")
                        .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
                case .waitingForGeometry:
                    Text("Terminal deferred")
                        .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
                }

                Text(detailText)
                    .font(.system(size: AppStyles.General.Typography.textSm))
                    .foregroundStyle(.secondary)
            }
            .padding(AppStyles.WorkspaceFocus.Terminal.startupOverlayPadding)
        }
    }

    private var showsProgressIndicator: Bool {
        switch state {
        case .preparing, .restoring:
            return true
        case .waitingForGeometry:
            return false
        }
    }

    private var detailText: String {
        switch state {
        case .preparing:
            return "Waiting for trusted pane geometry before creating the terminal."
        case .restoring:
            return "Waiting for the terminal session to attach cleanly."
        case .waitingForGeometry:
            return "This terminal will finish preparing once its layout position becomes available."
        }
    }
}

final class SurfaceStartupOverlayView: NSView {
    private var hostingView: NSHostingView<AnyView>?

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

    func showWaitingForGeometry() {
        show(state: .waitingForGeometry)
    }

    func hide() {
        isHidden = true
        hostingView?.removeFromSuperview()
        hostingView = nil
    }

    private func show(state: SurfaceStartupOverlayState) {
        hostingView?.removeFromSuperview()
        let hostingView = NSHostingView(
            rootView: AnyView(
                SurfaceStartupOverlay(state: state)
                    .tint(AppStyles.General.Accent.primaryColor)))
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        self.hostingView = hostingView
        isHidden = false
    }
}
