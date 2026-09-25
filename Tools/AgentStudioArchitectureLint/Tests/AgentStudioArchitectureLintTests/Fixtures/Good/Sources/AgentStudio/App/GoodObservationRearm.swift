import Observation

final class GoodObservationRearm {
    var observationGeneration = 0
    var isObserving = false
    var isStopped = false
    var source = 0

    func observeWithGenerationGuard() {
        observationGeneration += 1
        let generation = observationGeneration
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped, self.observationGeneration == generation else {
                    return
                }
                self.observeWithGenerationGuard()
            }
        }
    }

    func observeWithNestedGenerationCheck(generation: Int) {
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            guard let self else { return }
            if self.observationGeneration == generation {
                self.observeWithNestedGenerationCheck(generation: generation)
            }
        }
    }

    func observeWithStaleGenerationExit() {
        let generation = observationGeneration
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            guard let self else { return }
            if self.observationGeneration != generation { return }
            self.observeWithStaleGenerationExit()
        }
    }

    func observeWithArmLatch() {
        guard !isStopped, !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.observeWithArmLatch()
            }
        }
    }

    func observeOnce(onInvalidate: @escaping @Sendable () -> Void) {
        withObservationTracking {
            _ = source
        } onChange: {
            onInvalidate()
        }
    }
}
