import AppKit

@MainActor
package protocol PaneMountedContent: NSView {
    func setContentInteractionEnabled(_ enabled: Bool)
}
