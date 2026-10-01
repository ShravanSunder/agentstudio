import AgentStudioAppIPC
import AgentStudioCLIStore
import AgentStudioCore
import AgentStudioProgrammaticControl
import Foundation

struct AppCLIStoreReadThroughReader: AppIPCCLIStoreReadThroughPort {
    let storeURL: URL
    let expectedChannel: CLIStoreChannel
    let datastore: WorkspaceSQLiteDatastoreActor

    func readThrough() async -> IPCCLIStoreReadThrough? {
        // S3 red stand-in: no cursor read before the real login tests are red.
        nil
    }
}
