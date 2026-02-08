import Foundation

/// Type alias for the split tree used in Agent Studio.
/// Tree holds AgentStudioTerminalView references directly (matching Ghostty's pattern).
typealias TerminalSplitTree = SplitTree<AgentStudioTerminalView>
