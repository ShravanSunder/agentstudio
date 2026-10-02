import AgentStudioCLIStore
import AgentStudioPrimitives
import Darwin
import Foundation

/// A real second CLI writer process, without linking the app or its runtime.
@main
struct CLIStoreProcessFixture {
    static func main() throws {
        guard CommandLine.arguments.count == 3,
            let paneID = UUID(uuidString: CommandLine.arguments[2])
        else {
            Darwin.exit(64)
        }
        let store = try CLIStore.openWriter(
            url: URL(fileURLWithPath: CommandLine.arguments[1]), channel: .debug
        ).get()
        // A busy writer may fail open. Report every successful id and every
        // busy disposition; the parent proves precisely the committed effects.
        for _ in 0..<16 {
            switch store.appendNotice(
                paneID: paneID, messageID: UUIDv7.generate(),
                payloadJSON: #"{"method":"session.message"}"#,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ) {
            case .success(let entry):
                print(entry.id)
            case .failure(.busy):
                print("busy")
            case .failure(let failure):
                throw failure
            }
        }
    }
}
