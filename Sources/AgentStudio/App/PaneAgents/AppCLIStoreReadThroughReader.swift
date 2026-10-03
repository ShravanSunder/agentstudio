import AgentStudioAppIPC
import AgentStudioCLIStore
import AgentStudioCore
import AgentStudioProgrammaticControl
import Foundation
import GRDB
import os.log

struct AppCLIStoreReadThroughReader: AppIPCCLIStoreReadThroughPort {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "CLIStoreReadThrough")
    let storeURL: URL
    let expectedChannel: CLIStoreChannel
    let datastore: WorkspaceSQLiteDatastoreActor

    func readThrough() async -> IPCCLIStoreReadThrough? {
        let identity: CLIStoreIdentity
        switch await Self.readStoreIdentity(url: storeURL, channel: expectedChannel) {
        case .success(let value): identity = value
        case .failure(.unavailable): return nil
        case .failure(let failure):
            Self.logger.info("CLI store read-through refused: \(String(describing: failure), privacy: .public)")
            return nil
        }
        do {
            let storeID = identity.storeID.uuidString
            let cursors = try await datastore.performApplicationLocalRead { database throws -> (Int64?, Int64?) in
                let outbox: Int64?
                if try database.tableExists("pane_context_cli_outbox_cursor") {
                    outbox = try Int64.fetchOne(
                        database,
                        sql: "SELECT last_handled_id FROM pane_context_cli_outbox_cursor WHERE store_id=?",
                        arguments: [storeID])
                } else {
                    outbox = nil
                }
                let lifecycle: Int64?
                if try database.tableExists("sessions_cli_report_cursor") {
                    lifecycle = try Int64.fetchOne(
                        database,
                        sql: "SELECT last_handled_sequence FROM sessions_cli_report_cursor WHERE store_id=?",
                        arguments: [storeID])
                } else {
                    lifecycle = nil
                }
                return (outbox, lifecycle)
            }
            guard cursors.0 != nil || cursors.1 != nil else { return nil }
            guard (0...IPCSchemaScalars.maximumExactInteger).contains(cursors.0 ?? 0),
                (0...IPCSchemaScalars.maximumExactInteger).contains(cursors.1 ?? 0)
            else {
                Self.logger.warning("CLI store read-through refused: invalid cursor")
                return nil
            }
            return IPCCLIStoreReadThrough(
                storeId: identity.storeID, outbox: cursors.0 ?? 0,
                lifecycleReport: cursors.1)
        } catch {
            Self.logger.warning("CLI store read-through unavailable: local cursor read failed")
            return nil
        }
    }

    @concurrent private nonisolated static func readStoreIdentity(url: URL, channel: CLIStoreChannel) async
        -> Result<CLIStoreIdentity, CLIStoreFailure>
    {
        CLIStore.openReader(url: url, expectedChannel: channel).map(\.identity)
    }
}
