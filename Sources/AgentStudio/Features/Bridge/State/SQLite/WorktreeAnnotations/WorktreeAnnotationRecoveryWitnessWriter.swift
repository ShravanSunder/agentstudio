import AgentStudioCore

package enum WorktreeAnnotationRecoveryWitnessWriter {
    package static func write(
        repository: WorkspaceLocalRepository,
        replacement: WorkspaceLocalDatabaseReplacement
    ) throws {
        let annotationRepository = WorktreeAnnotationSQLiteRepository(
            databaseWriter: repository.databaseWriter
        )
        _ = try annotationRepository.recordRecoveryProvenance(
            quarantinedFilenames: replacement.quarantinedFilenames,
            reason: replacement.reason,
            recoveredAt: replacement.recoveredAt
        )
    }
}
