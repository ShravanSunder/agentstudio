import Foundation

enum BridgeProductSessionRevocationState: Sendable {
    case idle
    case inFlight(BridgeProductSessionRevocationBarrier)
    case succeeded(id: UUID)
}

struct BridgeProductSessionRevocationBarrier: Equatable, Sendable {
    private enum Storage: Sendable {
        case completed(Bool)
        case inFlight(Task<Bool, Never>)
    }

    private let id: UUID
    private let storage: Storage

    init(id: UUID, task: Task<Bool, Never>) {
        self.id = id
        self.storage = .inFlight(task)
    }

    init(id: UUID, completedResult: Bool) {
        self.id = id
        self.storage = .completed(completedResult)
    }

    func wait() async -> Bool {
        switch storage {
        case .completed(let result):
            return result
        case .inFlight(let task):
            return await task.value
        }
    }

    static func == (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        lhs.id == rhs.id
    }
}
