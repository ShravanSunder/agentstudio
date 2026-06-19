import AgentStudioProgrammaticControl
import Foundation

public struct AgentStudioIPCClientInvocation: Equatable, Sendable {
    public let configuration: AgentStudioIPCClientConfiguration
    public let readsAuthTokenFromStandardInput: Bool
    public let command: AgentStudioIPCClientCommand

    public init(
        configuration: AgentStudioIPCClientConfiguration,
        readsAuthTokenFromStandardInput: Bool = false,
        command: AgentStudioIPCClientCommand
    ) {
        self.configuration = configuration
        self.readsAuthTokenFromStandardInput = readsAuthTokenFromStandardInput
        self.command = command
    }
}

public enum AgentStudioIPCClientArguments {
    public static func parse(
        _ arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AgentStudioIPCClientInvocation {
        var index = 0
        var explicitSocketPath: String?
        var metadataURL: URL?
        var readsAuthTokenFromStandardInput = false

        while index < arguments.count, arguments[index].hasPrefix("--") {
            let option = arguments[index]
            index += 1
            switch option {
            case "--socket":
                explicitSocketPath = try takeValue(arguments, index: &index)
            case "--metadata":
                metadataURL = URL(fileURLWithPath: try takeValue(arguments, index: &index))
            case "--token-stdin":
                readsAuthTokenFromStandardInput = true
            default:
                throw AgentStudioIPCClientError(reason: .invalidArguments)
            }
        }

        guard index < arguments.count else {
            throw AgentStudioIPCClientError(reason: .invalidArguments)
        }

        let commandName = arguments[index]
        index += 1
        let command = try parseCommand(commandName, remainingArguments: Array(arguments[index...]))
        let socketPath = try AgentStudioIPCClientDiscovery.socketPath(
            explicitSocketPath: explicitSocketPath,
            environment: environment,
            metadataURL: metadataURL
        )

        return AgentStudioIPCClientInvocation(
            configuration: AgentStudioIPCClientConfiguration(socketPath: socketPath),
            readsAuthTokenFromStandardInput: readsAuthTokenFromStandardInput,
            command: command
        )
    }

    private static func parseCommand(
        _ commandName: String,
        remainingArguments: [String]
    ) throws -> AgentStudioIPCClientCommand {
        switch commandName {
        case "auth-login":
            try requireCount(remainingArguments, 0)
            return .authLogin
        case "auth-status":
            try requireCount(remainingArguments, 0)
            return .authStatus
        case "identify":
            try requireCount(remainingArguments, 0)
            return .identify
        case "capabilities":
            try requireCount(remainingArguments, 0)
            return .capabilities
        case "list-windows":
            try requireCount(remainingArguments, 0)
            return .listWindows
        case "list-workspaces":
            try requireCount(remainingArguments, 0)
            return .listWorkspaces
        case "list-panes":
            try requireCount(remainingArguments, 0)
            return .listPanes
        case "current-pane":
            try requireCount(remainingArguments, 0)
            return .currentPane
        case "pane-snapshot":
            let values = try requireCount(remainingArguments, 1)
            return .paneSnapshot(handle: values[0])
        case "pane-focus":
            let values = try requireCount(remainingArguments, 1)
            return .paneFocus(handle: values[0])
        case "command-list":
            try requireCount(remainingArguments, 0)
            return .commandList
        case "command-execute":
            let values = try requireCount(remainingArguments, 1)
            let commandId = IPCCommandIdentifier(rawValue: values[0])
            return .commandExecute(IPCCommandExecuteParams(commandId: commandId, targetHandle: nil))
        case "terminal-status":
            let values = try requireCount(remainingArguments, 1)
            return .terminalStatus(handle: values[0])
        case "terminal-send":
            let values = try requireCount(remainingArguments, 2)
            return .terminalSend(handle: values[0], input: values[1], correlationId: nil)
        case "terminal-wait":
            guard remainingArguments.count == 3 || remainingArguments.count == 4 else {
                throw AgentStudioIPCClientError(reason: .invalidArguments)
            }
            let values = remainingArguments
            guard let condition = IPCTerminalWaitCondition(rawValue: values[1]),
                let timeoutSeconds = Double(values[2])
            else {
                throw AgentStudioIPCClientError(reason: .invalidArguments)
            }
            let afterSequence: UInt64?
            if values.count == 4 {
                guard let parsedAfterSequence = UInt64(values[3]) else {
                    throw AgentStudioIPCClientError(reason: .invalidArguments)
                }
                afterSequence = parsedAfterSequence
            } else {
                afterSequence = nil
            }
            return .terminalWait(
                handle: values[0],
                condition: condition,
                timeoutSeconds: timeoutSeconds,
                afterSequence: afterSequence
            )
        case "events-subscribe":
            let values = try requireCount(remainingArguments, 1)
            let eventNames = try values[0].split(separator: ",").map { rawName -> IPCEventName in
                guard let eventName = IPCEventName(rawValue: String(rawName)) else {
                    throw AgentStudioIPCClientError(reason: .invalidArguments)
                }
                return eventName
            }
            guard !eventNames.isEmpty else {
                throw AgentStudioIPCClientError(reason: .invalidArguments)
            }
            return .eventsSubscribe(eventNames: eventNames)
        case "events-unsubscribe":
            let values = try requireCount(remainingArguments, 1)
            guard let subscriptionId = UUID(uuidString: values[0]) else {
                throw AgentStudioIPCClientError(reason: .invalidArguments)
            }
            return .eventsUnsubscribe(subscriptionId: subscriptionId)
        default:
            throw AgentStudioIPCClientError(reason: .invalidArguments)
        }
    }

    @discardableResult
    private static func requireCount(_ values: [String], _ count: Int) throws -> [String] {
        guard values.count == count else {
            throw AgentStudioIPCClientError(reason: .invalidArguments)
        }
        return values
    }

    private static func takeValue(_ arguments: [String], index: inout Int) throws -> String {
        guard index < arguments.count else {
            throw AgentStudioIPCClientError(reason: .invalidArguments)
        }
        defer {
            index += 1
        }
        return arguments[index]
    }
}
