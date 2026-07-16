import AppKit
import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    /// Mount one nonterminal pane selected by a steady-state user action.
    ///
    /// Bridge source selection may use current repository topology. Prepared
    /// startup content must use a separate topology-independent admission port.
    @discardableResult
    func mountCurrentNonterminalContent(pane: Pane) -> NSView? {
        viewRegistry.ensureSlot(for: pane.id)

        switch pane.content {
        case .terminal:
            preconditionFailure("terminal pane entered the nonterminal content owner")

        case .webview(let state):
            let view = WebviewPaneMountView(paneId: pane.id, state: state)
            let paneID = pane.id
            view.controller.onTitleChange = { [weak self] title in
                self?.store.paneAtom.updatePaneTitle(paneID, title: title)
            }
            registerHostedView(mountedView: view, for: pane.id)
            registerRuntimeIfNeeded(runtime: view.runtime, for: pane)
            Self.logger.info("Created webview pane \(pane.id)")
            return view

        case .codeViewer(let state):
            let initialText: String?
            if let codeViewerRuntime = registerCodeViewerRuntimeIfNeeded(for: pane) {
                if codeViewerRuntime.lifecycle == .created {
                    let transitioned = codeViewerRuntime.transitionToReady()
                    if !transitioned {
                        Self.logger.warning(
                            "Code viewer runtime for pane \(pane.id.uuidString, privacy: .public) failed ready transition"
                        )
                    }
                }
                initialText = codeViewerRuntime.displayedText.isEmpty ? nil : codeViewerRuntime.displayedText
            } else {
                initialText = nil
            }

            let view = CodeViewerPaneMountView(
                paneId: pane.id,
                state: state,
                initialText: initialText
            )
            registerHostedView(mountedView: view, for: pane.id)
            Self.logger.info("Created code viewer pane \(pane.id)")
            return view

        case .bridgePanel(let state):
            let controller = BridgePaneController(
                paneId: pane.id,
                state: state,
                reviewSourceProvider: bridgeReviewSourceProvider(for: pane, state: state),
                traceRuntime: traceRuntime
            )
            let view = BridgePaneMountView(paneId: pane.id, controller: controller)
            registerHostedView(mountedView: view, for: pane.id)
            registerRuntimeIfNeeded(runtime: view.runtime, for: pane)
            controller.loadApp()
            Self.logger.info("Created bridge panel view for pane \(pane.id)")
            return view

        case .unsupported:
            Self.logger.warning("Cannot create view for unsupported content type — pane \(pane.id)")
            return nil
        }
    }
}
