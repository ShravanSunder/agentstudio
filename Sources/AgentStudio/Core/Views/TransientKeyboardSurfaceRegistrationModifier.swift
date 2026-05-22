import SwiftUI

struct TransientKeyboardSurfaceRegistrationModifier: ViewModifier {
    let kind: TransientKeyboardSurfaceKind
    let workspaceWindowId: UUID?

    @State private var token: TransientKeyboardSurfaceToken?

    func body(content: Content) -> some View {
        content
            .onAppear {
                register(kind)
            }
            .onDisappear {
                dismiss()
            }
            .onChange(of: kind) { _, newKind in
                // SwiftUI delivers this synchronously on the main actor. Keep
                // replacement scoped to one UI update so keystrokes cannot
                // interleave between the old and new transient kinds.
                dismiss()
                register(newKind)
            }
    }

    private func register(_ kind: TransientKeyboardSurfaceKind) {
        guard token == nil else { return }
        let resolvedWindowId =
            workspaceWindowId
            ?? atom(\.windowLifecycle).focusedWindowId
            ?? atom(\.windowLifecycle).keyWindowId
        // Transient surfaces are workspace-window scoped; without a resolved
        // workspace owner, there is no safe policy domain to suppress.
        guard let resolvedWindowId else { return }
        token = atom(\.transientKeyboardSurface).present(kind, workspaceWindowId: resolvedWindowId)
    }

    private func dismiss() {
        guard let token else { return }
        atom(\.transientKeyboardSurface).dismiss(token)
        self.token = nil
    }
}

extension View {
    func transientKeyboardSurface(
        _ kind: TransientKeyboardSurfaceKind,
        workspaceWindowId: UUID? = nil
    ) -> some View {
        modifier(
            TransientKeyboardSurfaceRegistrationModifier(
                kind: kind,
                workspaceWindowId: workspaceWindowId
            )
        )
    }
}
