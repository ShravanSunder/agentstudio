import AppKit

@MainActor
package protocol PaneMountedContent: NSView {
    func setContentInteractionEnabled(_ enabled: Bool)

    /// Called once, before the host permanently unmounts this content. Drop strong references
    /// to renderer resources here.
    func paneHostWillRetire()
}

extension PaneMountedContent {
    package func paneHostWillRetire() {}
}
