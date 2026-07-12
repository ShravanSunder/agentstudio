extension BoundedGatherMailbox {
    static func mergeAgeWatermarks(
        _ first: AgeWatermark?,
        _ second: AgeWatermark?
    ) -> AgeWatermark? {
        switch (first, second) {
        case (.none, .none):
            return nil
        case (.some(let watermark), .none), (.none, .some(let watermark)):
            return watermark
        case (.some(let first), .some(let second)):
            if first.retainedAt < second.retainedAt { return first }
            if second.retainedAt < first.retainedAt { return second }
            let precision: AgePrecision =
                first.precision == .exact || second.precision == .exact
                ? .exact
                : .pressureConservative
            return AgeWatermark(retainedAt: first.retainedAt, precision: precision)
        }
    }

    static func ageWatermarkAfterPotentialRemoval(
        removedOldestRetainedAt: Duration,
        remainingCount: Int,
        current: AgeWatermark?
    ) -> AgeWatermark? {
        guard remainingCount > 0 else { return nil }
        guard let current else {
            preconditionFailure("Retained gather custody is missing its age watermark")
        }
        guard removedOldestRetainedAt <= current.retainedAt else { return current }
        return AgeWatermark(
            retainedAt: current.retainedAt,
            precision: .pressureConservative
        )
    }

    static func ageMeasurement(
        from watermark: AgeWatermark?,
        to now: Duration
    ) -> AdmissionAgeMeasurement? {
        guard let watermark else { return nil }
        let age = Swift.max(.zero, now - watermark.retainedAt)
        return switch watermark.precision {
        case .exact: .exact(age)
        case .pressureConservative: .pressureConservative(age)
        }
    }
}
