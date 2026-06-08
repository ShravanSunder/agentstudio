import Darwin

enum GhosttyLaunchArguments {
    static func sanitized(_ arguments: [String]) -> [String] {
        guard let executablePath = arguments.first else {
            return []
        }

        let ghosttyArguments =
            arguments
            .dropFirst()
            .filter { !isLaunchServicesProcessSerialNumber($0) }

        return [executablePath] + ghosttyArguments
    }

    static func withUnsafeArgv<Result>(
        from arguments: [String],
        _ body: (
            UInt,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> Result
    ) -> Result {
        var cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        cArguments.append(nil)
        defer {
            for argumentPointer in cArguments {
                free(argumentPointer)
            }
        }

        return cArguments.withUnsafeMutableBufferPointer { buffer in
            body(UInt(arguments.count), buffer.baseAddress)
        }
    }

    private static func isLaunchServicesProcessSerialNumber(
        _ argument: String
    ) -> Bool {
        argument.hasPrefix("-psn_")
    }
}
