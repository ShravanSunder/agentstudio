typealias JournalRawLock<State> = OSAllocatedUnfairLock<State>

extension OrderedFactJournal {
    func consumeCanonicalRawLock(lock: OSAllocatedUnfairLock<State>) {
        _ = lock
    }
}

extension OrderedFactJournal {
    func consumeAliasedRawLock(lock: JournalRawLock<State>) {
        _ = lock
    }
}

struct UnrelatedLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        body()
    }
}

extension OrderedFactJournal {
    func retainUnrelatedWithLock(lock: UnrelatedLock) {
        _ = lock.withLock { "clean" }
    }
}

extension OrderedFactJournal {
    func retainLocalRawLockShadow() {
        typealias OSAllocatedUnfairLock<State> = String
        let lock: OSAllocatedUnfairLock<String>? = nil
        _ = lock
    }
}

enum OtherLockNamespace {
    typealias OSAllocatedUnfairLock<State> = String
}

extension OrderedFactJournal {
    func retainOtherRawLock(lock: OtherLockNamespace.OSAllocatedUnfairLock<String>) {
        _ = lock
    }
}
