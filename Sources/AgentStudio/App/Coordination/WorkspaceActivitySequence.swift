import Foundation

@MainActor
enum WorkspaceActivitySequence {
    private static var nextSeq: UInt64 = 0

    static func next() -> UInt64 {
        nextSeq += 1
        return nextSeq
    }
}
