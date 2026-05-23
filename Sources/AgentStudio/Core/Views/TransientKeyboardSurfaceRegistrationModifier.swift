import SwiftUI

struct TransientKeyboardSurfaceRegistrationModifier: ViewModifier {
    let kind: TransientKeyboardSurfaceKind
    let workspaceWindowId: UUID?

    @State private var token: TransientKeyboardSurfaceToken?
    @State private var registeredWindowId: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                register(kind)
            }
            .onDisappear {
                dismiss()
                registeredWindowId = nil
            }
            .onChange(of: kind) { _, newKind in
                replace(with: newKind)
            }
    }

    private func register(_ kind: TransientKeyboardSurfaceKind) {
        guard token == nil else { return }
        let resolvedWindowId = workspaceWindowId ?? registeredWindowId ?? resolveCurrentWorkspaceWindowId()
        // Transient surfaces are workspace-window scoped; without a resolved
        // workspace owner, there is no safe policy domain to suppress.
        guard let resolvedWindowId else { return }
        token = atom(\.transientKeyboardSurface).present(kind, workspaceWindowId: resolvedWindowId)
        registeredWindowId = resolvedWindowId
    }

    private func dismiss() {
        guard let token else { return }
        atom(\.transientKeyboardSurface).dismiss(token)
        self.token = nil
    }

    private func replace(with kind: TransientKeyboardSurfaceKind) {
        let stableWindowId = registeredWindowId ?? workspaceWindowId ?? resolveCurrentWorkspaceWindowId()
        guard let stableWindowId else {
            dismiss()
            return
        }
        registeredWindowId = stableWindowId
        guard let token else {
            register(kind)
            return
        }
        atom(\.transientKeyboardSurface).replace(token, with: kind, workspaceWindowId: stableWindowId)
    }

    private func resolveCurrentWorkspaceWindowId() -> UUID? {
        atom(\.windowLifecycle).focusedWindowId ?? atom(\.windowLifecycle).keyWindowId
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
