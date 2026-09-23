import Observation

final class BadObservationRearm {
    var generation = 0
    var isObserving = false
    var source = 0

    func observeUnfenced() {
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeUnfenced()
            }
        }
    }

    func observeWithComparisonThatDoesNotControl() {
        let captured = generation
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            guard let self else { return }
            let isCurrent = self.generation == captured
            print(isCurrent)
            self.observeWithComparisonThatDoesNotControl()
        }
    }

    func observeWithGenerationCheckedThenRearmedAnyway() {
        let captured = generation
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            guard let self else { return }
            if self.generation != captured {
                print("stale")
            }
            _ = (self.generation == captured)
            self.observeWithGenerationCheckedThenRearmedAnyway()
        }
    }

    func observeWithLatchNeverCleared() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            self?.observeWithLatchNeverCleared()
        }
    }
}
