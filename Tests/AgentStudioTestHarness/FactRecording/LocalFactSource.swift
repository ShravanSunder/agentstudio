import Synchronization

/// A synchronous local sink that retains facts until the recorder consumes them.
package final class LocalFactSource<Scope: Hashable & Sendable, Fact: Sendable>: Sendable {
    private let recorder: FactRecorder<Scope, Fact>
    private let attached = Mutex(false)

    package init(vocabulary: FactVocabulary<Scope, Fact>) {
        recorder = FactRecorder(vocabulary: vocabulary)
    }

    package var sink: @Sendable (Scope, Fact) -> Void {
        { [recorder] scope, fact in recorder.append(scope: scope, fact: fact) }
    }

    package func attach() -> FactRecorder<Scope, Fact> {
        attached.withLock { wasAttached in
            precondition(!wasAttached, "A LocalFactSource may attach to only one recorder")
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
