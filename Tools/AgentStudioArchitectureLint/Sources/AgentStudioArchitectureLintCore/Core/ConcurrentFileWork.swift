import Dispatch
import Synchronization

/// Runs one independent piece of work per file on every core and returns the
/// results in input order.
///
/// Parsing and per-file validation are pure functions of one file (and, for
/// validation, of rules that are immutable after `prepared(for:)`), so the only
/// shared state is the result slot each iteration writes once.
enum ConcurrentFileWork {
    static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        _ transform: @Sendable (Input) throws -> Output
    ) throws -> [Output] {
        let slots = Mutex<[Result<Output, any Error>?]>(Array(repeating: nil, count: inputs.count))
        DispatchQueue.concurrentPerform(iterations: inputs.count) { index in
            let result = Result { try transform(inputs[index]) }
            slots.withLock { $0[index] = result }
        }
        let results = slots.withLock { $0 }
        return try results.enumerated().map { index, slot in
            guard let slot else {
                throw ConcurrentFileWorkError.missingResult(index: index)
            }
            return try slot.get()
        }
    }
}

enum ConcurrentFileWorkError: Error, CustomStringConvertible {
    case missingResult(index: Int)

    var description: String {
        switch self {
        case .missingResult(let index):
            "concurrent file work produced no result for input \(index)"
        }
    }
}
