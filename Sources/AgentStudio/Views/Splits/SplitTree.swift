import AppKit

/// SplitTree represents a tree of views that can be divided into panes.
/// This is a simplified version adapted from Ghostty's SplitTree.
///
/// The tree is immutable - all operations return a new tree.
struct SplitTree<ViewType: Identifiable & Codable>: Codable, Equatable where ViewType: Equatable {

    /// The root of the tree. Can be nil to indicate an empty tree.
    let root: Node?

    /// A single node in the tree is either a leaf (a view) or a split (has left/right children).
    indirect enum Node: Codable, Equatable {
        case leaf(view: ViewType)
        case split(Split)

        struct Split: Codable, Equatable {
            let direction: SplitViewDirection
            var ratio: Double  // 0.0-1.0, position of divider
            let left: Node
            let right: Node
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
        return SplitTree(root: try root.inserting(view: view, at: target, direction: direction))
    }

    /// Remove a view from the tree. If removing results in empty tree, returns nil.
    func removing(view: ViewType) -> Self? {
        guard let root else { return nil }
        if let newRoot = root.removing(view: view) {
            return SplitTree(root: newRoot)
        }
        return nil
    }

    /// Update the ratio of a split node containing the given view.
    func resizing(view: ViewType, ratio: Double) -> Self {
        guard let root else { return self }
        return SplitTree(root: root.resizing(view: view, ratio: ratio))
    }

    /// Equalize splits so all panes have equal ratios.
    func equalized() -> Self {
        guard let root else { return self }
        return SplitTree(root: root.equalized())
    }

    /// Find a view by its ID.
    func find(id: ViewType.ID) -> ViewType? {
        return root?.find(id: id)
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

            return .split(.init(
                direction: splitDirection,
                ratio: 0.5,
                left: newViewOnLeft ? newLeaf : existingLeaf,
                right: newViewOnLeft ? existingLeaf : newLeaf
            ))

        case .split(let split):
            // Try to find target in left subtree
            if split.left.contains(id: target.id) {
                return .split(.init(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: try split.left.inserting(view: view, at: target, direction: direction),
                    right: split.right
                ))
            }

            // Try right subtree
            if split.right.contains(id: target.id) {
                return .split(.init(
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
            // If this is the view to remove, return nil
            if existingView.id == view.id {
                return nil
            }
            return self

        case .split(let split):
            let newLeft = split.left.removing(view: view)
            let newRight = split.right.removing(view: view)

            // If both children still exist, return updated split
            if let left = newLeft, let right = newRight {
                return .split(.init(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: left,
                    right: right
                ))
            }

            // If one child was removed, return the other
            if let left = newLeft {
                return left
            }
            if let right = newRight {
                return right
            }

            // Both children removed (shouldn't happen normally)
            return nil
        }
    }

    /// Update ratio for a split containing the given view.
    func resizing(view: ViewType, ratio: Double) -> Self {
        switch self {
        case .leaf:
            return self

        case .split(let split):
            // If this split contains the view as a direct child, update ratio
            let leftContains = split.left.containsDirectly(id: view.id)
            let rightContains = split.right.containsDirectly(id: view.id)

            if leftContains || rightContains {
                return .split(.init(
                    direction: split.direction,
                    ratio: max(0.1, min(0.9, ratio)),
                    left: split.left,
                    right: split.right
                ))
            }

            // Otherwise recurse
            return .split(.init(
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
            return .split(.init(
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

    /// Check if this node directly contains a view (not in children).
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

// MARK: - Codable

extension SplitTree {
    private enum CodingKeys: String, CodingKey {
        case version
        case root
    }

    private static var currentVersion: Int { 1 }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported SplitTree version: \(version)"
                )
            )
        }

        self.root = try container.decodeIfPresent(Node.self, forKey: .root)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encodeIfPresent(root, forKey: .root)
    }
}
