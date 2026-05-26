import SwiftUI

struct TransientKeyboardSurfaceRegistrationModifier: ViewModifier {
    let kind: TransientKeyboardSurfaceKind
    let workspaceWindowId: UUID?
    let policy: TransientKeyboardSurfacePolicy?
    let onDismiss: (() -> Void)?

    @State private var token: TransientKeyboardSurfaceToken?
    @State private var registeredWindowId: UUID?

    private var resolvedPolicy: TransientKeyboardSurfacePolicy {
        policy ?? kind.defaultPolicy
    }

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
            .onChange(of: resolvedPolicy) { _, _ in
                replace(with: kind)
            }
            .background(
                TransientKeyboardSurfaceDismissBridge(
                    policy: resolvedPolicy,
                    isEnabled: token != nil,
                    onDismiss: onDismiss
                )
                .frame(width: 0, height: 0)
            )
    }

    private func register(_ kind: TransientKeyboardSurfaceKind) {
        guard token == nil else { return }
        let resolvedWindowId = workspaceWindowId ?? registeredWindowId ?? resolveCurrentWorkspaceWindowId()
        // Transient surfaces are workspace-window scoped; without a resolved
        // workspace owner, there is no safe policy domain to suppress.
        guard let resolvedWindowId else { return }
        token = atom(\.transientKeyboardSurface).present(
            kind,
            workspaceWindowId: resolvedWindowId,
            policy: resolvedPolicy
        )
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
        atom(\.transientKeyboardSurface).replace(
            token,
            with: kind,
            workspaceWindowId: stableWindowId,
            policy: resolvedPolicy
        )
    }

    private func resolveCurrentWorkspaceWindowId() -> UUID? {
        atom(\.windowLifecycle).focusedWindowId ?? atom(\.windowLifecycle).keyWindowId
    }
}

extension View {
    func transientKeyboardSurface(
        _ kind: TransientKeyboardSurfaceKind,
        workspaceWindowId: UUID? = nil,
        policy: TransientKeyboardSurfacePolicy? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            TransientKeyboardSurfaceRegistrationModifier(
                kind: kind,
                workspaceWindowId: workspaceWindowId,
                policy: policy,
                onDismiss: onDismiss
            )
        )
    }
}
