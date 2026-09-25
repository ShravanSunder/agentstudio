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

    func observeWithConstantFence() {
        let captured = generation
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            guard let self else { return }
            guard captured == 0 else { return }
            self.observeWithConstantFence()
        }
    }

    func observeWithLatchSetAfterArming() {
        guard !isObserving else { return }
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            self?.isObserving = false
            self?.observeWithLatchSetAfterArming()
        }
        isObserving = true
    }

    func observeWithLatchSetOnlyInBranch(force: Bool) {
        guard !isObserving else { return }
        if force {
            isObserving = true
        }
        withObservationTracking {
            _ = source
        } onChange: { [weak self] in
            self?.isObserving = false
            self?.observeWithLatchSetOnlyInBranch(force: force)
        }
    }
}
