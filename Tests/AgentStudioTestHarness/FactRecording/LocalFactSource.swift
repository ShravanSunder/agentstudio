import Synchronization

/// A synchronous local sink that retains facts until the recorder consumes them.
package final class LocalFactSource<Scope: Hashable & Sendable, Fact: Sendable>: Sendable {
    private let recorder: FactRecorder<Scope, Fact>
    private let attached = Mutex(false)

    package init(vocabulary: FactVocabulary<Scope, Fact>) {
        recorder = FactRecorder(vocabulary: vocabulary)
        recorder.installSourceHandle(LocalFactSourceHandle())
    }

    package var sink: @Sendable (Scope, Fact) -> Void {
        { [recorder] scope, fact in recorder.append(scope: scope, fact: fact) }
    }

    package func attach() throws -> FactRecorder<Scope, Fact> {
        try attached.withLock { wasAttached in
            guard !wasAttached else { throw FactSourceAlreadyAttached() }
            wasAttached = true
        }
        return recorder
    }

    package func end() {
        recorder.receive(.ended)
    }

    package func lose(_ description: String) {
        recorder.receive(.lost(description: description))
    }

    package func cancel() {
        recorder.receive(.cancelled)
    }
}

private struct LocalFactSourceHandle: FactSourceHandle {
    func stop() async {}

    func settleEnqueued() async {}
}
