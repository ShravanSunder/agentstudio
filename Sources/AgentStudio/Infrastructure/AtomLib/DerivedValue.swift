@MainActor
package final class DerivedValue<Value> {
    let revision = AtomRevision()

    private let inputRevisions: () -> [Int]
    private let isContentEqual: (Value, Value) -> Bool
    private let compute: () -> Value
    private var cachedInputRevisions: [Int]?
    private var cachedValue: Value?

    package init(
        inputRevisions: @escaping () -> [Int],
        isContentEqual: @escaping (Value, Value) -> Bool,
        compute: @escaping () -> Value
    ) {
        self.inputRevisions = inputRevisions
        self.isContentEqual = isContentEqual
        self.compute = compute
    }

    package var value: Value {
        let currentInputRevisions = inputRevisions()
        if let cachedInputRevisions,
            cachedInputRevisions == currentInputRevisions,
            let cachedValue
        {
            AtomPerformanceTelemetry.shared.recordDerived(
                operation: "cache_hit",
                inputRevisionCount: currentInputRevisions.count,
                cacheHit: true
            )
            return cachedValue
        }

        let clock = ContinuousClock()
        let computeStart = clock.now
        let newValue = compute()
        let computeDuration = computeStart.duration(to: clock.now)
        let previousValue = cachedValue
        cachedInputRevisions = currentInputRevisions
        cachedValue = newValue

        if let previousValue, !isContentEqual(previousValue, newValue) {
            revision.bump()
        }

        AtomPerformanceTelemetry.shared.recordDerived(
            operation: "compute",
            inputRevisionCount: currentInputRevisions.count,
            cacheHit: false,
            computeDuration: computeDuration
        )
        return newValue
    }
}
