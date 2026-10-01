import Foundation

/// Compile-only conformer for S3 red; no query is implemented yet.
extension WorkspaceSQLiteDatastoreActor: ScrollbackPaneBindingReading {
    package func scrollbackPaneBindings(workspaceID: UUID) async throws -> [ScrollbackPaneBinding] {
        []
    }
}
