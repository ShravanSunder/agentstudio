import Foundation

package struct WorktreeCommandLineInvocation: Sendable, Equatable {
    package let request: WorktreeOperationRequest
    package let usesJSONOutput: Bool

    package init(request: WorktreeOperationRequest, usesJSONOutput: Bool) {
        self.request = request
        self.usesJSONOutput = usesJSONOutput
    }
}

package enum WorktreeCommandLineArgumentError: Error, Equatable, Sendable {
    case missingSubcommand
    case unknownSubcommand
    case missingBranch
    case unexpectedArgument
    case unknownOption
    case unsupportedOption
    case missingOptionValue(String)
    case emptyOptionValue(String)
    case duplicateOption(String)

    package var message: String {
        switch self {
        case .missingSubcommand:
            "usage: agentstudio worktree new|fork|list"
        case .unknownSubcommand:
            "unknown worktree subcommand; expected new, fork, or list"
        case .missingBranch:
            "a branch name is required for worktree new and fork"
        case .unexpectedArgument:
            "unexpected positional argument"
        case .unknownOption:
            "unknown worktree option"
        case .unsupportedOption:
            "option is not supported for this worktree subcommand"
        case .missingOptionValue(let option):
            "\(option) requires a path"
        case .emptyOptionValue(let option):
            "\(option) path must not be empty"
        case .duplicateOption(let option):
            "\(option) may be specified only once"
        }
    }
}

package enum WorktreeCommandLineArgumentParser {
    package static func parse(
        _ arguments: [String],
        currentDirectory: URL
    ) throws -> WorktreeCommandLineInvocation {
        guard let subcommand = arguments.first else {
            throw WorktreeCommandLineArgumentError.missingSubcommand
        }

        let allowedPathOptions: Set<String>
        switch subcommand {
        case "new", "list":
            allowedPathOptions = ["--repo"]
        case "fork":
            allowedPathOptions = ["--from"]
        default:
            throw WorktreeCommandLineArgumentError.unknownSubcommand
        }

        var positionalArguments: [String] = []
        var repositoryPath: URL?
        var sourcePath: URL?
        var usesJSONOutput = false
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--json" {
                usesJSONOutput = true
                index += 1
                continue
            }

            guard argument == "--repo" || argument == "--from" else {
                if argument.hasPrefix("-") {
                    throw WorktreeCommandLineArgumentError.unknownOption
                }
                positionalArguments.append(argument)
                index += 1
                continue
            }

            guard allowedPathOptions.contains(argument) else {
                throw WorktreeCommandLineArgumentError.unsupportedOption
            }
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw WorktreeCommandLineArgumentError.missingOptionValue(argument)
            }
            let pathValue = arguments[valueIndex]
            guard !pathValue.isEmpty else {
                throw WorktreeCommandLineArgumentError.emptyOptionValue(argument)
            }
            guard !pathValue.hasPrefix("-") else {
                throw WorktreeCommandLineArgumentError.missingOptionValue(argument)
            }

            let path = URL(fileURLWithPath: pathValue, relativeTo: currentDirectory).standardizedFileURL
            if argument == "--repo" {
                guard repositoryPath == nil else {
                    throw WorktreeCommandLineArgumentError.duplicateOption(argument)
                }
                repositoryPath = path
            } else {
                guard sourcePath == nil else {
                    throw WorktreeCommandLineArgumentError.duplicateOption(argument)
                }
                sourcePath = path
            }
            index += 2
        }

        let request: WorktreeOperationRequest
        switch subcommand {
        case "new":
            guard let branch = positionalArguments.first else {
                throw WorktreeCommandLineArgumentError.missingBranch
            }
            guard positionalArguments.count == 1 else {
                throw WorktreeCommandLineArgumentError.unexpectedArgument
            }
            request = .createFromDefault(start: repositoryPath ?? currentDirectory, branch: branch)
        case "fork":
            guard let branch = positionalArguments.first else {
                throw WorktreeCommandLineArgumentError.missingBranch
            }
            guard positionalArguments.count == 1 else {
                throw WorktreeCommandLineArgumentError.unexpectedArgument
            }
            request = .fork(start: sourcePath ?? currentDirectory, branch: branch)
        case "list":
            guard positionalArguments.isEmpty else {
                throw WorktreeCommandLineArgumentError.unexpectedArgument
            }
            request = .list(start: repositoryPath ?? currentDirectory)
        default:
            throw WorktreeCommandLineArgumentError.unknownSubcommand
        }

        return WorktreeCommandLineInvocation(request: request, usesJSONOutput: usesJSONOutput)
    }
}
