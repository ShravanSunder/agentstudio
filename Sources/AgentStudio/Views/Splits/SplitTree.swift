import AppKit

/// SplitTree represents a tree of views that can be divided into panes.
/// Adapted from Ghostty's SplitTree — holds NSView references directly.
///
/// The tree is immutable - all operations return a new tree.
struct SplitTree<ViewType: NSView & Identifiable> {

    /// The root of the tree. Can be nil to indicate an empty tree.
    let root: Node?

    /// A single node in the tree is either a leaf (a view) or a split (has left/right children).
    indirect enum Node {
        case leaf(view: ViewType)
        case split(Split)

        struct Split: Equatable {
            let id: UUID
            let direction: SplitViewDirection
            let ratio: Double  // 0.0-1.0, position of divider
            let left: Node
            let right: Node

            init(id: UUID = UUID(), direction: SplitViewDirection, ratio: Double, left: Node, right: Node) {
                self.id = id
                self.direction = direction
                self.ratio = ratio
                self.left = left
                self.right = right
            }
        }
    }

    /// Direction for creating new splits
    enum NewDirection {
        case left
        case right
        case up
        case down
    }

    enum SplitError: Error {
        case viewNotFound
        case emptyTree
    }

    // MARK: - Initialization

    init() {
        self.root = nil
    }

    init(root: Node?) {
        self.root = root
    }

    init(view: ViewType) {
        self.root = .leaf(view: view)
    }

    // MARK: - Properties

    var isEmpty: Bool { root == nil }

    var isSplit: Bool {
        if case .split = root { return true }
        return false
    }

    // MARK: - Operations

    /// Insert a new view at the given view point by creating a split in the given direction.
    func inserting(view: ViewType, at target: ViewType, direction: NewDirection) throws -> Self {
        guard let root else { throw SplitError.emptyTree }
        return Self(root: try root.inserting(view: view, at: target, direction: direction))
    }

    /// Remove a view from the tree. If removing results in empty tree, returns nil.
    func removing(view: ViewType) -> Self? {
        guard let root else { return nil }
        if let newRoot = root.removing(view: view) {
            return Self(root: newRoot)
        }
        return nil
    }

    /// Update the ratio of a split node identified by split ID.
    func resizing(splitId: UUID, ratio: Double) -> Self {
        guard let root else { return self }
        return Self(root: root.resizing(splitId: splitId, ratio: ratio))
    }

    /// Update the ratio of a split node containing the given view (legacy pane-based lookup).
    func resizing(view: ViewType, ratio: Double) -> Self {
        guard let root else { return self }
        return Self(root: root.resizing(view: view, ratio: ratio))
    }

    /// Equalize splits so all panes have equal ratios.
    func equalized() -> Self {
        guard let root else { return self }
        return Self(root: root.equalized())
    }

    /// Find a view by its ID.
    func find(id: ViewType.ID) -> ViewType? {
        root?.find(id: id)
    }

    /// Get all leaf views in the tree (left to right traversal).
    var allViews: [ViewType] {
        guard let root else { return [] }
        return root.allViews
    }
}

// MARK: - Node Operations

extension SplitTree.Node {
    typealias NewDirection = SplitTree.NewDirection
    typealias SplitError = SplitTree.SplitError

    /// Insert a new view relative to a target view.
    func inserting(view: ViewType, at target: ViewType, direction: NewDirection) throws -> Self {
        switch self {
        case .leaf(let existingView):
            guard existingView.id == target.id else {
                throw SplitError.viewNotFound
            }

            // Determine split direction and position
            let splitDirection: SplitViewDirection
            let newViewOnLeft: Bool

            switch direction {
            case .left:
                splitDirection = .horizontal
                newViewOnLeft = true
            case .right:
                splitDirection = .horizontal
                newViewOnLeft = false
            case .up:
                splitDirection = .vertical
                newViewOnLeft = true
            case .down:
                splitDirection = .vertical
                newViewOnLeft = false
            }

            // Create new split with 50/50 ratio
            let newLeaf = Self.leaf(view: view)
            let existingLeaf = Self.leaf(view: existingView)

            return .split(
                Split(
                    direction: splitDirection,
                    ratio: 0.5,
                    left: newViewOnLeft ? newLeaf : existingLeaf,
                    right: newViewOnLeft ? existingLeaf : newLeaf
                ))

        case .split(let split):
            // Try to find target in left subtree
            if split.left.contains(id: target.id) {
                return .split(
                    Split(
                        id: split.id,
                        direction: split.direction,
                        ratio: split.ratio,
                        left: try split.left.inserting(view: view, at: target, direction: direction),
                        right: split.right
                    ))
            }

            // Try right subtree
            if split.right.contains(id: target.id) {
                return .split(
                    Split(
                        id: split.id,
                        direction: split.direction,
                        ratio: split.ratio,
                        left: split.left,
                        right: try split.right.inserting(view: view, at: target, direction: direction)
                    ))
            }

            throw SplitError.viewNotFound
        }
    }

    /// Remove a view from the tree. Returns nil if this node should be removed entirely.
    func removing(view: ViewType) -> Self? {
        switch self {
        case .leaf(let existingView):
            if existingView.id == view.id {
                return nil
            }
            return self

        case .split(let split):
            let newLeft = split.left.removing(view: view)
            let newRight = split.right.removing(view: view)

            if let left = newLeft, let right = newRight {
                return .split(
                    Split(
                        id: split.id,
                        direction: split.direction,
                        ratio: split.ratio,
                        left: left,
                        right: right
                    ))
            }

            if let left = newLeft {
                return left
            }
            if let right = newRight {
                return right
            }

            return nil
        }
    }

    /// Update ratio for the split with the given ID.
    func resizing(splitId: UUID, ratio: Double) -> Self {
        switch self {
        case .leaf:
            return self

        case .split(let split):
            if split.id == splitId {
                return .split(
                    Split(
                        id: split.id,
                        direction: split.direction,
                        ratio: max(0.1, min(0.9, ratio)),
                        left: split.left,
                        right: split.right
                    ))
            }

            return .split(
                Split(
                    id: split.id,
                    direction: split.direction,
                    ratio: split.ratio,
                    left: split.left.resizing(splitId: splitId, ratio: ratio),
                    right: split.right.resizing(splitId: splitId, ratio: ratio)
                ))
        }
    }

    /// Update ratio for a split containing the given view (legacy pane-based lookup).
    func resizing(view: ViewType, ratio: Double) -> Self {
        switch self {
        case .leaf:
            return self

        case .split(let split):
            let leftContains = split.left.containsDirectly(id: view.id)
            let rightContains = split.right.containsDirectly(id: view.id)

            if leftContains || rightContains {
                return .split(
                    Split(
                        id: split.id,
                        direction: split.direction,
                        ratio: max(0.1, min(0.9, ratio)),
                        left: split.left,
                        right: split.right
                    ))
            }

            return .split(
                Split(
                    id: split.id,
                    direction: split.direction,
                    ratio: split.ratio,
                    left: split.left.resizing(view: view, ratio: ratio),
                    right: split.right.resizing(view: view, ratio: ratio)
                ))
        }
    }

    /// Equalize all splits to 0.5 ratio.
    func equalized() -> Self {
        switch self {
        case .leaf:
            return self

        case .split(let split):
            return .split(
                Split(
                    id: split.id,
                    direction: split.direction,
                    ratio: 0.5,
                    left: split.left.equalized(),
                    right: split.right.equalized()
                ))
        }
    }

    /// Check if this node or its children contain a view with the given ID.
    func contains(id: ViewType.ID) -> Bool {
        switch self {
        case .leaf(let view):
            return view.id == id

        case .split(let split):
            return split.left.contains(id: id) || split.right.contains(id: id)
        }
    }

    /// Check if this node is a leaf with the given view ID (does not recurse into children).
    func containsDirectly(id: ViewType.ID) -> Bool {
        if case .leaf(let view) = self {
            return view.id == id
        }
        return false
    }

    /// Find a view by ID.
    func find(id: ViewType.ID) -> ViewType? {
        switch self {
        case .leaf(let view):
            return view.id == id ? view : nil

        case .split(let split):
            if let found = split.left.find(id: id) {
                return found
            }
            return split.right.find(id: id)
        }
    }

    /// Get all leaf views in order.
    var allViews: [ViewType] {
        switch self {
        case .leaf(let view):
            return [view]

        case .split(let split):
            return split.left.allViews + split.right.allViews
        }
    }
}

// MARK: - Node Equatable (Object Identity)

extension SplitTree.Node: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.leaf(let view1), .leaf(let view2)):
            return view1 === view2  // Object identity for NSView references

        case (.split(let split1), .split(let split2)):
            return split1 == split2

        default:
            return false
        }
    }
}

// MARK: - Equatable

extension SplitTree: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.root, rhs.root) {
        case (nil, nil):
            return true
        case (let l?, let r?):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - Sequence Conformance

extension SplitTree: Sequence {
    func makeIterator() -> AnyIterator<ViewType> {
        let views = allViews
        var index = 0
        return AnyIterator {
            guard index < views.count else { return nil }
            let view = views[index]
            index += 1
            return view
        }
    }
}

// MARK: - Navigation

/// Direction for pane focus navigation.
/// Standalone type decoupled from SplitTree's generic parameter.
enum SplitFocusDirection {
    case left, right, up, down
}

extension SplitTree {
    /// Find the neighbor pane in the given direction from the pane with the given ID.
    func neighbor(of id: ViewType.ID, direction: SplitFocusDirection) -> ViewType? {
        guard let root else { return nil }
        return root.neighbor(of: id, direction: direction)
    }

    /// Get the next pane in left-to-right order (wraps around).
    func nextView(after id: ViewType.ID) -> ViewType? {
        let views = allViews
        guard let index = views.firstIndex(where: { $0.id == id }) else { return nil }
        let nextIndex = (index + 1) % views.count
        return views[nextIndex]
    }

    /// Get the previous pane in left-to-right order (wraps around).
    func previousView(before id: ViewType.ID) -> ViewType? {
        let views = allViews
        guard let index = views.firstIndex(where: { $0.id == id }) else { return nil }
        let prevIndex = (index - 1 + views.count) % views.count
        return views[prevIndex]
    }
}

extension SplitTree.Node {
    /// Find a neighbor in a given direction from the node with the given ID.
    /// Recursively descends through splits: when the target is in one subtree and
    /// the split direction matches, the nearest leaf in the opposite subtree is returned.
    func neighbor(of id: ViewType.ID, direction: SplitFocusDirection) -> ViewType? {
        switch self {
        case .leaf:
            return nil

        case .split(let split):
            let leftContains = split.left.contains(id: id)
            let rightContains = split.right.contains(id: id)

            switch direction {
            case .left:
                if split.direction == .horizontal && rightContains {
                    // Target is on the right, neighbor is rightmost leaf of left subtree
                    return split.left.allViews.last
                }
            case .right:
                if split.direction == .horizontal && leftContains {
                    // Target is on the left, neighbor is leftmost leaf of right subtree
                    return split.right.allViews.first
                }
            case .up:
                if split.direction == .vertical && rightContains {
                    // Target is on the bottom, neighbor is bottom-most of top subtree
                    return split.left.allViews.last
                }
            case .down:
                if split.direction == .vertical && leftContains {
                    // Target is on the top, neighbor is top-most of bottom subtree
                    return split.right.allViews.first
                }
            }

            // Recurse into the subtree containing the target
            if leftContains {
                return split.left.neighbor(of: id, direction: direction)
            }
            if rightContains {
                return split.right.neighbor(of: id, direction: direction)
            }

            return nil
        }
    }
}

// MARK: - Structural Identity

extension SplitTree.Node {
    /// Returns a hashable representation that captures this node's structural identity.
    /// Used with SwiftUI's `.id()` modifier to prevent unnecessary view recreation.
    /// Hashes tree structure and view object identity, but NOT ratios.
    var structuralIdentity: StructuralIdentity {
        StructuralIdentity(self)
    }

    struct StructuralIdentity: Hashable {
        private let node: SplitTree.Node

        init(_ node: SplitTree.Node) {
            self.node = node
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.node.isStructurallyEqual(to: rhs.node)
        }

        func hash(into hasher: inout Hasher) {
            node.hashStructure(into: &hasher)
        }
    }

    /// Checks if this node is structurally equal to another node.
    /// Two nodes are structurally equal if they have the same tree structure
    /// and the same views (by object identity) in the same positions.
    /// Ratios are intentionally excluded — ratio changes should not cause view recreation.
    fileprivate func isStructurallyEqual(to other: SplitTree.Node) -> Bool {
        switch (self, other) {
        case (.leaf(let view1), .leaf(let view2)):
            return view1 === view2

        case (.split(let split1), .split(let split2)):
            return split1.direction == split2.direction
                && split1.left.isStructurallyEqual(to: split2.left)
                && split1.right.isStructurallyEqual(to: split2.right)

        default:
            return false
        }
    }

    /// Hashes the structural identity of this node.
    /// Includes tree structure and view object identities, but NOT ratios.
    fileprivate func hashStructure(into hasher: inout Hasher) {
        switch self {
        case .leaf(let view):
            hasher.combine(UInt8(0))  // leaf marker
            hasher.combine(ObjectIdentifier(view))

        case .split(let split):
            hasher.combine(UInt8(1))  // split marker
            hasher.combine(split.direction)
            // ratio intentionally excluded
            split.left.hashStructure(into: &hasher)
            split.right.hashStructure(into: &hasher)
        }
    }
}
