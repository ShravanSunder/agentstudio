import Foundation

/// Type alias for the split tree used in Agent Studio.
/// Tree holds PaneView references — terminal, webview, and code viewer can all
/// appear as leaves in the same split tree.
typealias PaneSplitTree = SplitTree<PaneView>

/// Backwards-compatible alias.
typealias TerminalSplitTree = PaneSplitTree
