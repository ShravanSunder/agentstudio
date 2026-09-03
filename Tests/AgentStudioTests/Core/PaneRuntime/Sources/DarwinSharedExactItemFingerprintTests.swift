import AgentStudioInfrastructure
import Darwin
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Darwin shared exact-item fingerprints")
struct DarwinSharedExactItemFingerprintTests {
    @Test("SHA-256 v1 reads duplicate canonical items once")
    func sha256ReadsDuplicateCanonicalItemsOnce() async throws {
        let fixture = try FingerprintFixture()
        defer { fixture.remove() }
        let itemPath = fixture.root.appending(path: "configuration")
        try Data("abc".utf8).write(to: itemPath)

        let outcome = await DarwinSharedExactItemFingerprintReader().read(
            canonicalItemPaths: [itemPath.path, itemPath.path]
        )
        let snapshot = try #require(outcome.snapshot)
        let fingerprint = try #require(snapshot.fingerprintsByCanonicalPath[itemPath.path])

        #expect(fingerprint.algorithm == .sha256V1)
        #expect(
            fingerprint.algorithm.rawValue
                == AppPolicies.GitRefresh.sharedExactItemFingerprintAlgorithm
        )
        #expect(
            fingerprint.digestHex
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        #expect(snapshot.uniqueItemCount == 1)
        #expect(snapshot.bytesRead == 3)
    }

    @Test("same-length content changes do not compare equal")
    func sameLengthContentChangesDoNotCompareEqual() async throws {
        let fixture = try FingerprintFixture()
        defer { fixture.remove() }
        let itemPath = fixture.root.appending(path: "configuration")
        try Data("abc".utf8).write(to: itemPath)
        let reader = DarwinSharedExactItemFingerprintReader()

        let first = try #require(
            await reader.read(canonicalItemPaths: [itemPath.path]).snapshot
        )
        try Data("abd".utf8).write(to: itemPath)
        let second = try #require(
            await reader.read(canonicalItemPaths: [itemPath.path]).snapshot
        )

        #expect(first != second)
    }

    @Test("atomic path replacement cannot hide behind the opened descriptor")
    func atomicReplacementFailsStableRead() async throws {
        let fixture = try FingerprintFixture()
        defer { fixture.remove() }
        let itemPath = fixture.root.appending(path: "configuration")
        let replacementPath = fixture.root.appending(path: "replacement")
        try Data("old".utf8).write(to: itemPath)
        try Data("new".utf8).write(to: replacementPath)
        let replacementState = FingerprintAtomicValue(false)
        let reader = DarwinSharedExactItemFingerprintReader(
            regularFileOpened: { openedPath in
                guard openedPath == itemPath.path else { return }
                replacementState.withValue { hasReplaced in
                    guard !hasReplaced else { return }
                    hasReplaced = true
                    _ = replacementPath.path.withCString { source in
                        itemPath.path.withCString { destination in
                            Darwin.rename(source, destination)
                        }
                    }
                }
            }
        )

        let outcome = await reader.read(canonicalItemPaths: [itemPath.path])

        #expect(outcome.failure == .unstableItem)
    }

    @Test("missing items and symbolic-link targets have distinct stable fingerprints")
    func missingAndSymbolicLinkTargetsAreDistinct() async throws {
        let fixture = try FingerprintFixture()
        defer { fixture.remove() }
        let missingPath = fixture.root.appending(path: "missing")
        let linkPath = fixture.root.appending(path: "configuration-link")
        try FileManager.default.createSymbolicLink(
            at: linkPath,
            withDestinationURL: URL(fileURLWithPath: "first-target")
        )
        let reader = DarwinSharedExactItemFingerprintReader()

        let first = try #require(
            await reader.read(canonicalItemPaths: [missingPath.path, linkPath.path]).snapshot
        )
        try FileManager.default.removeItem(at: linkPath)
        try FileManager.default.createSymbolicLink(
            at: linkPath,
            withDestinationURL: URL(fileURLWithPath: "other-target")
        )
        let second = try #require(
            await reader.read(canonicalItemPaths: [missingPath.path, linkPath.path]).snapshot
        )

        #expect(first.fingerprintsByCanonicalPath[missingPath.path]?.kind == .missing)
        #expect(first.fingerprintsByCanonicalPath[linkPath.path]?.kind == .symbolicLink)
        #expect(first != second)
    }

    @Test("item, count, transaction, and unsupported-type bounds fail closed")
    func boundsAndUnsupportedTypesFailClosed() async throws {
        let fixture = try FingerprintFixture()
        defer { fixture.remove() }
        let firstPath = fixture.root.appending(path: "first")
        let secondPath = fixture.root.appending(path: "second")
        let directoryPath = fixture.root.appending(path: "directory", directoryHint: .isDirectory)
        try Data("abc".utf8).write(to: firstPath)
        try Data("de".utf8).write(to: secondPath)
        try FileManager.default.createDirectory(at: directoryPath, withIntermediateDirectories: true)

        let itemLimited = await DarwinSharedExactItemFingerprintReader(
            policy: .init(maximumItemBytes: 2, maximumUniqueItems: 8, maximumTransactionBytes: 8)
        ).read(canonicalItemPaths: [firstPath.path])
        let countLimited = await DarwinSharedExactItemFingerprintReader(
            policy: .init(maximumItemBytes: 8, maximumUniqueItems: 1, maximumTransactionBytes: 8)
        ).read(canonicalItemPaths: [firstPath.path, secondPath.path])
        let transactionLimited = await DarwinSharedExactItemFingerprintReader(
            policy: .init(maximumItemBytes: 8, maximumUniqueItems: 8, maximumTransactionBytes: 4)
        ).read(canonicalItemPaths: [firstPath.path, secondPath.path])
        let unsupported = await DarwinSharedExactItemFingerprintReader().read(
            canonicalItemPaths: [directoryPath.path]
        )

        #expect(itemLimited.failure == .itemByteLimitExceeded)
        #expect(countLimited.failure == .itemCountLimitExceeded)
        #expect(transactionLimited.failure == .transactionByteLimitExceeded)
        #expect(unsupported.failure == .unsupportedItemType)
        #expect(itemLimited.bytesRead == 0)
        #expect(countLimited.bytesRead == 0)
        #expect(transactionLimited.bytesRead <= 4)
    }

    @Test("production fingerprint I/O escapes MainActor")
    @MainActor
    func productionFingerprintIOEscapesMainActor() async throws {
        let fixture = try FingerprintFixture()
        defer { fixture.remove() }
        let itemPath = fixture.root.appending(path: "configuration")
        try Data("abc".utf8).write(to: itemPath)
        let observedMainThread = FingerprintAtomicValue<Bool?>(nil)
        let reader = DarwinSharedExactItemFingerprintReader(
            regularFileOpened: { _ in
                observedMainThread.withValue { value in
                    value = Thread.isMainThread
                }
            }
        )

        _ = await reader.read(canonicalItemPaths: [itemPath.path])

        #expect(observedMainThread.value == false)
    }
}

private struct FingerprintFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "shared-item-fingerprint-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class FingerprintAtomicValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.withLock {
            body(&storedValue)
        }
    }
}
