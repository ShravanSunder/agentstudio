extension WorktreeAnnotationStore {
    static func sourceRefreshSnapshot(
        from detail: WorktreeAnnotationSessionDetail
    ) -> WorktreeAnnotationSourceRefreshSnapshot {
        let orderedThreads = detail.threads.sorted { left, right in
            if left.thread.createdOrdinal != right.thread.createdOrdinal {
                return left.thread.createdOrdinal < right.thread.createdOrdinal
            }
            return left.thread.id.rawValue.uuidString < right.thread.id.rawValue.uuidString
        }
        return WorktreeAnnotationSourceRefreshSnapshot(
            sessionID: detail.session.id,
            acceptedSourceFingerprint: detail.session.acceptedSourceFingerprint,
            requirements: orderedThreads.map {
                WorktreeAnnotationSourceRefreshRequirement(
                    threadID: $0.thread.id,
                    origin: $0.thread.origin
                )
            }
        )
    }
}
