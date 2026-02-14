import Foundation

/// Pure value type split tree. Leaves reference panes by ID.
/// No NSView references, no embedded objects. All operations are immutable.
struct Layout: Codable, Hashable {

    /// The root of the tree. Nil indicates an empty layout.
    let root: Node?

    /// A single node in the tree is either a leaf (pane reference) or a split.
    indirect enum Node: Codable, Hashable {
        case leaf(paneId: UUID)
        case split(Split)
    }

    /// A split node with two children and a resize ratio.
    struct Split: Codable, Hashable {
        let id: UUID
        let direction: SplitDirection
        /// Position of divider, clamped to 0.1–0.9.
        let ratio: Double
        let left: Node
        let right: Node

        init(
            id: UUID = UUID(),
            direction: SplitDirection,
            ratio: Double = 0.5,
            left: Node,
            right: Node
        ) {
            self.id = id
            self.direction = direction
            self.ratio = min(0.9, max(0.1, ratio))
            self.left = left
            self.right = right
        }
    }

    /// Direction of a split.
    enum SplitDirection: String, Codable, Hashable {
        case horizontal
        case vertical
    }

    /// Position for inserting a new pane relative to a target.
    enum Position {
        /// Left (horizontal) or up (vertical).
        case before
        /// Right (horizontal) or down (vertical).
        case after
    }

    // MARK: - Init

    init() {
        self.root = nil
    }

    init(root: Node?) {
        self.root = root
    }

    /// Single-pane layout.
    init(paneId: UUID) {
        self.root = .leaf(paneId: paneId)
    }

    // MARK: - Properties

    var isEmpty: Bool { root == nil }

    var isSplit: Bool {
        if case .split = root { return true }
        return false
    }

    /// All leaf pane IDs in left-to-right traversal order.
    var paneIds: [UUID] {
        guard let root else { return [] }
        return root.paneIds
    }

    // MARK: - Queries

    func contains(_ paneId: UUID) -> Bool {
        root?.contains(paneId) ?? false
    }

    // MARK: - Immutable Operations (return new Layout)

    /// Insert a pane relative to a target pane.
    func inserting(
        paneId: UUID,
        at target: UUID,
        direction: SplitDirection,
        position: Position
    ) -> Layout {
        guard let root else { return self }
        guard let newRoot = root.inserting(
            paneId: paneId,
            at: target,
            direction: direction,
            position: position
        ) else {
            return self
        }
        return Layout(root: newRoot)
    }

    /// Remove a pane from the layout. Returns nil if the layout becomes empty.
    func removing(paneId: UUID) -> Layout? {
        guard let root else { return nil }
        guard let newRoot = root.removing(paneId: paneId) else {
            return nil
        }
        return Layout(root: newRoot)
    }

    /// Update the ratio of a split node by ID.
    func resizing(splitId: UUID, ratio: Double) -> Layout {
        guard let root else { return self }
        return Layout(root: root.resizing(splitId: splitId, ratio: ratio))
    }

    /// Set all split ratios to 0.5.
    func equalized() -> Layout {
        guard let root else { return self }
        return Layout(root: root.equalized())
    }

    // MARK: - Resize Target

    /// Find the nearest ancestor split where the given pane can grow in the given direction.
    /// Returns (splitId, shouldIncreaseRatio).
    func resizeTarget(for paneId: UUID, direction: SplitResizeDirection) -> (splitId: UUID, increase: Bool)? {
        guard let root else { return nil }
        return root.resizeTarget(for: paneId, direction: direction)
    }

    /// Get the current ratio for a split by ID.
    func ratioForSplit(_ splitId: UUID) -> Double? {
        root?.ratioForSplit(splitId)
    }

    // MARK: - Navigation

    /// Find the neighbor pane in the given direction.
    func neighbor(of paneId: UUID, direction: FocusDirection) -> UUID? {
        root?.neighbor(of: paneId, direction: direction)
    }

    /// Get the next pane in left-to-right order (wraps around).
    func next(after paneId: UUID) -> UUID? {
        let ids = paneIds
        guard let index = ids.firstIndex(of: paneId) else { return nil }
        let nextIndex = (index + 1) % ids.count
        return ids[nextIndex]
    }

    /// Get the previous pane in left-to-right order (wraps around).
    func previous(before paneId: UUID) -> UUID? {
        let ids = paneIds
        guard let index = ids.firstIndex(of: paneId) else { return nil }
        let prevIndex = (index - 1 + ids.count) % ids.count
        return ids[prevIndex]
    }

}

// MARK: - Focus Direction

/// Direction for pane focus navigation.
enum FocusDirection: Equatable, Hashable {
    case left, right, up, down
}

// MARK: - Node Operations

extension Layout.Node {

    /// All leaf pane IDs in left-to-right order.
    var paneIds: [UUID] {
        switch self {
        case .leaf(let paneId):
            return [paneId]
        case .split(let split):
            return split.left.paneIds + split.right.paneIds
        }
    }

    /// Check if this node or its descendants contain a pane.
    func contains(_ paneId: UUID) -> Bool {
        switch self {
        case .leaf(let id):
            return id == paneId
        case .split(let split):
            return split.left.contains(paneId) || split.right.contains(paneId)
        }
    }

    /// Insert a new pane relative to a target. Returns nil if target not found.
    func inserting(
        paneId: UUID,
        at target: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) -> Layout.Node? {
        switch self {
        case .leaf(let existingId):
            guard existingId == target else { return nil }
            let newLeaf = Layout.Node.leaf(paneId: paneId)
            let existingLeaf = self
            let isNewOnLeft = position == .before
            return .split(Layout.Split(
                direction: direction,
                left: isNewOnLeft ? newLeaf : existingLeaf,
                right: isNewOnLeft ? existingLeaf : newLeaf
            ))

        case .split(let split):
            if split.left.contains(target) {
                guard let newLeft = split.left.inserting(
                    paneId: paneId, at: target,
                    direction: direction, position: position
                ) else { return nil }
                return .split(Layout.Split(
                    id: split.id,
                    direction: split.direction,
                    ratio: split.ratio,
                    left: newLeft,
                    right: split.right
                ))
            }
            if split.right.contains(target) {
                guard let newRight = split.right.inserting(
                    paneId: paneId, at: target,
                    direction: direction, position: position
                ) else { return nil }
                return .split(Layout.Split(
                    id: split.id,
                    direction: split.direction,
                    ratio: split.ratio,
                    left: split.left,
                    right: newRight
                ))
            }
            return nil
        }
    }

    /// Remove a pane. Returns nil if this node should be removed entirely.
    func removing(paneId: UUID) -> Layout.Node? {
        switch self {
        case .leaf(let existingId):
            return existingId == paneId ? nil : self

        case .split(let split):
            let newLeft = split.left.removing(paneId: paneId)
            let newRight = split.right.removing(paneId: paneId)

            if let left = newLeft, let right = newRight {
                return .split(Layout.Split(
                    id: split.id,
                    direction: split.direction,
                    ratio: split.ratio,
                    left: left,
                    right: right
                ))
            }
            // Collapse: one side removed → promote the other
            return newLeft ?? newRight
        }
    }

    /// Update the ratio for a split with the given ID.
    func resizing(splitId: UUID, ratio: Double) -> Layout.Node {
        switch self {
        case .leaf:
            return self
        case .split(let split):
            if split.id == splitId {
                return .split(Layout.Split(
                    id: split.id,
                    direction: split.direction,
                    ratio: ratio,
                    left: split.left,
                    right: split.right
                ))
            }
            return .split(Layout.Split(
                id: split.id,
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.resizing(splitId: splitId, ratio: ratio),
                right: split.right.resizing(splitId: splitId, ratio: ratio)
            ))
        }
    }

    /// Set all split ratios to 0.5.
    func equalized() -> Layout.Node {
        switch self {
        case .leaf:
            return self
        case .split(let split):
            return .split(Layout.Split(
                id: split.id,
                direction: split.direction,
                ratio: 0.5,
                left: split.left.equalized(),
                right: split.right.equalized()
            ))
        }
    }

    /// Get the current ratio for a split by ID.
    func ratioForSplit(_ splitId: UUID) -> Double? {
        switch self {
        case .leaf: return nil
        case .split(let split):
            if split.id == splitId { return split.ratio }
            return split.left.ratioForSplit(splitId) ?? split.right.ratioForSplit(splitId)
        }
    }

    /// Find the nearest enclosing split where a pane can grow in the given direction.
    /// Returns (splitId, shouldIncreaseRatio).
    ///
    /// Algorithm: Recurse into the subtree containing the pane FIRST to find the
    /// nearest (innermost) matching split. Only if no child split handles the resize
    /// do we check whether THIS split can handle it as a fallback.
    func resizeTarget(for paneId: UUID, direction: SplitResizeDirection) -> (splitId: UUID, increase: Bool)? {
        guard case .split(let split) = self else { return nil }

        let inLeft = split.left.contains(paneId)
        let inRight = split.right.contains(paneId)
        guard inLeft || inRight else { return nil }

        // Recurse into the subtree containing the pane FIRST (nearest match wins)
        let subtree = inLeft ? split.left : split.right
        if let result = subtree.resizeTarget(for: paneId, direction: direction) {
            return result
        }

        // Then check if THIS split handles it as a fallback
        if split.direction == direction.axis {
            switch direction {
            case .right, .down:
                if inLeft { return (split.id, true) }
            case .left, .up:
                if inRight { return (split.id, false) }
            }
        }

        return nil
    }

    /// Find the neighbor in the given direction.
    func neighbor(of paneId: UUID, direction: FocusDirection) -> UUID? {
        switch self {
        case .leaf:
            return nil

        case .split(let split):
            let leftContains = split.left.contains(paneId)
            let rightContains = split.right.contains(paneId)

            switch direction {
            case .left:
                if split.direction == .horizontal && rightContains {
                    return split.left.paneIds.last
                }
            case .right:
                if split.direction == .horizontal && leftContains {
                    return split.right.paneIds.first
                }
            case .up:
                if split.direction == .vertical && rightContains {
                    return split.left.paneIds.last
                }
            case .down:
                if split.direction == .vertical && leftContains {
                    return split.right.paneIds.first
                }
            }

            if leftContains {
                return split.left.neighbor(of: paneId, direction: direction)
            }
            if rightContains {
                return split.right.neighbor(of: paneId, direction: direction)
            }
            return nil
        }
    }
}

// MARK: - Node Codable

extension Layout.Node {
    private enum NodeCodingKeys: String, CodingKey {
        case paneId
        case sessionId // legacy key from pre-pane-model schema
        case split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NodeCodingKeys.self)
        if container.contains(.paneId) {
            let id = try container.decode(UUID.self, forKey: .paneId)
            self = .leaf(paneId: id)
        } else if container.contains(.sessionId) {
            // Migration: old format used "sessionId" instead of "paneId"
            let id = try container.decode(UUID.self, forKey: .sessionId)
            self = .leaf(paneId: id)
        } else if container.contains(.split) {
            let split = try container.decode(Layout.Split.self, forKey: .split)
            self = .split(split)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "No valid Layout.Node type found"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: NodeCodingKeys.self)
        switch self {
        case .leaf(let paneId):
            try container.encode(paneId, forKey: .paneId)
        case .split(let split):
            try container.encode(split, forKey: .split)
        }
    }
}
