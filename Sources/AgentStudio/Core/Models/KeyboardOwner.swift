import Foundation

// swiftlint:disable discouraged_none_name
/// Who currently owns keyboard interpretation in the app.
///
/// Derived value. Never stored, never manually set. Computed by
/// `KeyboardOwnerDerived` from `WindowLifecycleAtom`,
/// `ManagementLayerAtom`, and `UIStateAtom`.
///
/// Consumed by CommandBar default-scope logic and future keyboard
/// routing observers.
enum KeyboardOwner: Equatable, Sendable {
    /// Some non-workspace window is key (CommandBar panel, sheet,
    /// alert). AppKit routes keys there; the workspace is passive.
    case otherWindow

    /// Management Layer is active. Its monitor interprets keys.
    case managementLayer

    /// Sidebar is visible, has responder focus, and is showing a
    /// surface. The surface's local shortcuts are live.
    case sidebar(SidebarSurface)

    /// Main window is key and nothing above applies. Responder
    /// chain handles keys normally (pane content, etc.).
    case none
}
// swiftlint:enable discouraged_none_name
