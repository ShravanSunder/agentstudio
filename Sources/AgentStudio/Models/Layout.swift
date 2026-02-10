import Foundation

/// Pure value type split tree. Leaves reference sessions by ID.
/// No NSView references, no embedded objects. All operations are immutable.
struct Layout: Codable, Hashable {

    /// The root of the tree. Nil indicates an empty layout.
    let root: Node?

    /// A single node in the tree is either a leaf (session reference) or a split.
    indirect enum Node: Codable, Hashable {
        case leaf(sessionId: UUID)
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

    /// Position for inserting a new session relative to a target.
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

    /// Single-session layout.
    init(sessionId: UUID) {
        self.root = .leaf(sessionId: sessionId)
    }

    // MARK: - Properties

    var isEmpty: Bool { root == nil }

    var isSplit: Bool {
        if case .split = root { return true }
        return false
    }

    /// All leaf session IDs in left-to-right traversal order.
    var sessionIds: [UUID] {
        guard let root else { return [] }
        return root.sessionIds
    }

    // MARK: - Queries

    func contains(_ sessionId: UUID) -> Bool {
        root?.contains(sessionId) ?? false
    }

    // MARK: - Immutable Operations (return new Layout)

    /// Insert a session relative to a target session.
    func inserting(
        sessionId: UUID,
        at target: UUID,
        direction: SplitDirection,
        position: Position
    ) -> Layout {
        guard let root else { return self }
        guard let newRoot = root.inserting(
            sessionId: sessionId,
            at: target,
            direction: direction,
            position: position
        ) else {
            return self
        }
        return Layout(root: newRoot)
    }

    /// Remove a session from the layout. Returns nil if the layout becomes empty.
    func removing(sessionId: UUID) -> Layout? {
        guard let root else { return nil }
        guard let newRoot = root.removing(sessionId: sessionId) else {
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

    // MARK: - Navigation

    /// Find the neighbor session in the given direction.
    func neighbor(of sessionId: UUID, direction: FocusDirection) -> UUID? {
        root?.neighbor(of: sessionId, direction: direction)
    }

    /// Get the next session in left-to-right order (wraps around).
    func next(after sessionId: UUID) -> UUID? {
        let ids = sessionIds
        guard let index = ids.firstIndex(of: sessionId) else { return nil }
        let nextIndex = (index + 1) % ids.count
        return ids[nextIndex]
    }

    /// Get the previous session in left-to-right order (wraps around).
    func previous(before sessionId: UUID) -> UUID? {
        let ids = sessionIds
        guard let index = ids.firstIndex(of: sessionId) else { return nil }
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

    /// All leaf session IDs in left-to-right order.
    var sessionIds: [UUID] {
        switch self {
        case .leaf(let sessionId):
            return [sessionId]
        case .split(let split):
            return split.left.sessionIds + split.right.sessionIds
        }
    }

    /// Check if this node or its descendants contain a session.
    func contains(_ sessionId: UUID) -> Bool {
        switch self {
        case .leaf(let id):
            return id == sessionId
        case .split(let split):
            return split.left.contains(sessionId) || split.right.contains(sessionId)
        }
    }

    /// Insert a new session relative to a target. Returns nil if target not found.
    func inserting(
        sessionId: UUID,
        at target: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) -> Layout.Node? {
        switch self {
        case .leaf(let existingId):
            guard existingId == target else { return nil }
            let newLeaf = Layout.Node.leaf(sessionId: sessionId)
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
                    sessionId: sessionId, at: target,
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
                    sessionId: sessionId, at: target,
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

    /// Remove a session. Returns nil if this node should be removed entirely.
    func removing(sessionId: UUID) -> Layout.Node? {
        switch self {
        case .leaf(let existingId):
            return existingId == sessionId ? nil : self

        case .split(let split):
            let newLeft = split.left.removing(sessionId: sessionId)
            let newRight = split.right.removing(sessionId: sessionId)

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

    /// Find the neighbor in the given direction.
    func neighbor(of sessionId: UUID, direction: FocusDirection) -> UUID? {
        switch self {
        case .leaf:
            return nil

        case .split(let split):
            let leftContains = split.left.contains(sessionId)
            let rightContains = split.right.contains(sessionId)

            switch direction {
            case .left:
                if split.direction == .horizontal && rightContains {
                    return split.left.sessionIds.last
                }
            case .right:
                if split.direction == .horizontal && leftContains {
                    return split.right.sessionIds.first
                }
            case .up:
                if split.direction == .vertical && rightContains {
                    return split.left.sessionIds.last
                }
            case .down:
                if split.direction == .vertical && leftContains {
                    return split.right.sessionIds.first
                }
            }

            if leftContains {
                return split.left.neighbor(of: sessionId, direction: direction)
            }
            if rightContains {
                return split.right.neighbor(of: sessionId, direction: direction)
            }
            return nil
        }
    }
}

// MARK: - Node Codable

extension Layout.Node {
    private enum NodeCodingKeys: String, CodingKey {
        case sessionId
        case split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NodeCodingKeys.self)
        if container.contains(.sessionId) {
            let id = try container.decode(UUID.self, forKey: .sessionId)
            self = .leaf(sessionId: id)
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
        case .leaf(let sessionId):
            try container.encode(sessionId, forKey: .sessionId)
        case .split(let split):
            try container.encode(split, forKey: .split)
        }
    }
}
