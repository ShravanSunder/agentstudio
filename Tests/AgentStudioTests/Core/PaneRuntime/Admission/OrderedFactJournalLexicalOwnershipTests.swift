import Foundation
import Testing

@Suite("Admission OrderedFactJournal lexical ownership")
struct AdmissionOrderedFactJournalLexicalOwnershipTests {
    @Test("journal owner stays within its local line and wrapper budget")
    func journalOwnerStaysWithinLocalLineAndWrapperBudget() throws {
        // Arrange
        let owner = try ownerSource()

        // Act
        let ownerLineCount = owner.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        let tokenFactoryCount = occurrenceCount(
            of: "AdmissionProtectedRegion.withToken",
            in: owner
        )
        let rawLockEntryCount = occurrenceCount(of: "lock.withLock", in: owner)
        let ownerHasPrivateState = owner.contains("private struct State")
        let ownerHasPrivateLock = owner.contains("private let lock: OSAllocatedUnfairLock<State>")
        let ownerHasPrivateWrapper = owner.contains("private func withAdmissionProtectedState")
        let ownerHasExternalStateAlias = owner.contains(
            "typealias State = OrderedFactJournalState"
        )

        // Assert
        #expect(ownerLineCount <= 1250)
        #expect(ownerHasPrivateState)
        #expect(ownerHasPrivateLock)
        #expect(ownerHasPrivateWrapper)
        #expect(ownerHasExternalStateAlias == false)
        #expect(tokenFactoryCount == 1)
        #expect(rawLockEntryCount == 1)
    }

    private func ownerSource() throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/RuntimeEventSystem/Admission/OrderedFactJournal.swift"
            ),
            encoding: .utf8
        )
    }

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }
}
