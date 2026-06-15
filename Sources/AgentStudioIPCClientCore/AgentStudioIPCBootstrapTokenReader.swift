import Foundation

#if canImport(Darwin)
    import Darwin
#endif

public enum AgentStudioIPCBootstrapTokenReader {
    public static let bootstrapFileDescriptorEnvironmentKey = "AGENTSTUDIO_IPC_BOOTSTRAP_FD"

    public static func bootstrapFileDescriptor(environment: [String: String]) throws -> Int32 {
        guard
            let rawValue = environment[bootstrapFileDescriptorEnvironmentKey],
            let fileDescriptor = Int32(rawValue)
        else {
            throw AgentStudioIPCClientError(reason: .invalidArguments)
        }
        return fileDescriptor
    }

    public static func readTokenAndClose(fileDescriptor: Int32) throws -> String {
        #if canImport(Darwin)
            var bytes: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 256)
            while true {
                let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
                if count == 0 {
                    break
                }
                if count < 0 {
                    if errno == EINTR {
                        continue
                    }
                    _ = Darwin.close(fileDescriptor)
                    throw AgentStudioIPCClientError(reason: .emptyResponse)
                }
                bytes.append(contentsOf: buffer.prefix(count))
                if bytes.contains(UInt8(ascii: "\n")) {
                    break
                }
            }

            guard
                let rawToken = String(bytes: bytes, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !rawToken.isEmpty
            else {
                _ = Darwin.close(fileDescriptor)
                throw AgentStudioIPCClientError(reason: .invalidArguments)
            }
            _ = Darwin.close(fileDescriptor)
            return rawToken
        #else
            throw AgentStudioIPCClientError(reason: .invalidArguments)
        #endif
    }
}
