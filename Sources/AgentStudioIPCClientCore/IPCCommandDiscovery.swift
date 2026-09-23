import AgentStudioProgrammaticControl
import Foundation

package struct IPCCommandDiscoveryError: Error, Equatable, Sendable,
    CustomStringConvertible
{
    package enum Reason: String, Equatable, Sendable {
        case missingCommandList
        case missingCommandExecute
        case incompatibleMethodMetadata
        case invalidCommandCatalog
        case unknownCommandIdentifier
        case argumentVariantNotAllowed
        case invalidCommandResult
        case resultVariantNotAllowed
        case resultCommandIdentifierMismatch
        case resultCorrelationMismatch
    }

    package let reason: Reason
    package let fieldPath: String
    package let expected: String

    package var description: String {
        "\(reason.rawValue) at \(fieldPath): expected \(expected)"
    }
}

/// Compiles the two dynamic command methods from an already validated live
/// method catalog. General received metadata never becomes an invocation path.
package struct IPCCommandDiscovery: Sendable {
    package let commandListInvocation: IPCDescriptorInvocation

    private let advertisedList: IPCMethodCatalogEntry
    private let advertisedExecute: IPCMethodCatalogEntry

    package init(methodCatalog: IPCMethodCatalogResult) throws {
        guard methodCatalog.compatibility == .current else {
            throw Self.failure(
                .incompatibleMethodMetadata,
                fieldPath: "$.compatibility",
                expected: "the current protocol and catalog compatibility identity"
            )
        }
        advertisedList = try Self.uniqueEntry(
            named: "command.list",
            in: methodCatalog,
            missingReason: .missingCommandList
        )
        advertisedExecute = try Self.uniqueEntry(
            named: "command.execute",
            in: methodCatalog,
            missingReason: .missingCommandExecute
        )
        try Self.validateInvariantMetadata(
            list: advertisedList,
            execute: advertisedExecute
        )

        let listDescriptor: IPCMethodDescriptor<IPCEmptyParams, IPCCommandCatalogResult>
        do {
            listDescriptor = try IPCMethodDescriptor(
                name: advertisedList.name,
                description: advertisedList.description,
                parameterSchema: advertisedList.parameterSchema,
                resultSchema: advertisedList.resultSchema,
                examples: [],
                exposure: advertisedList.exposure,
                requiredPrivileges: Set(advertisedList.requiredPrivileges),
                dataScope: advertisedList.dataScope,
                allowedTargetKinds: Set(advertisedList.allowedTargetKinds),
                commandRelationship: advertisedList.commandRelationship,
                executionOwner: advertisedList.executionOwner,
                principalAvailability: advertisedList.principalAvailability,
                resultSemantics: advertisedList.resultSemantics,
                documentedErrors: advertisedList.documentedErrors,
                isMutating: advertisedList.isMutating,
                correlationPolicy: advertisedList.correlationPolicy,
                responseDelivery: advertisedList.responseDelivery,
                offlineEligibility: advertisedList.offlineEligibility,
                modelCalls: advertisedList.modelCalls
            )
        } catch {
            throw Self.failure(
                .incompatibleMethodMetadata,
                fieldPath: "$.methods",
                expected: "the typed command.list contract"
            )
        }
        let erasedList: IPCAnyMethodDescriptor
        do {
            erasedList = try IPCAnyMethodDescriptor(erasing: listDescriptor)
        } catch {
            throw Self.failure(
                .incompatibleMethodMetadata,
                fieldPath: "$.methods",
                expected: "the typed command.list contract"
            )
        }
        let normalizedParameters: Data
        do {
            normalizedParameters = try erasedList.normalizeParameters(Data("{}".utf8))
        } catch {
            throw Self.failure(
                .incompatibleMethodMetadata,
                fieldPath: "$.methods",
                expected: "command.list with empty typed parameters"
            )
        }
        commandListInvocation = IPCDescriptorInvocation(
            descriptor: erasedList,
            normalizedParameters: normalizedParameters,
            presentation: .tooling
        )
    }

    package func decodeCommandCatalog(
        from originalResult: Data
    ) throws -> IPCDiscoveredCommandCatalog {
        let catalog: IPCCommandCatalogResult
        do {
            let normalized = try advertisedList.resultSchema.normalize(originalResult)
            catalog = try JSONDecoder().decode(IPCCommandCatalogResult.self, from: normalized)
        } catch {
            throw Self.failure(
                .invalidCommandCatalog,
                fieldPath: "$.commands",
                expected: "the advertised typed command catalog"
            )
        }

        guard catalog.compatibility == .current else {
            throw Self.failure(
                .invalidCommandCatalog,
                fieldPath: "$.compatibility",
                expected: "the current protocol and catalog compatibility identity"
            )
        }
        let identifiers = catalog.commands.map(\.id.rawValue)
        guard !identifiers.isEmpty,
            Set(identifiers).count == identifiers.count,
            identifiers == identifiers.sorted()
        else {
            throw Self.failure(
                .invalidCommandCatalog,
                fieldPath: "$.commands",
                expected: "unique command identifiers in ascending order"
            )
        }

        let validatedCommands: [IPCCommandDescriptor]
        do {
            validatedCommands = try catalog.commands.map { command in
                let validated = try IPCCommandDescriptorFactory.make(
                    IPCCommandDescriptorInput(
                        id: command.id,
                        title: command.title,
                        description: command.description,
                        exposure: command.exposure,
                        executionMode: command.executionMode,
                        argumentVariants: command.argumentVariants,
                        requiredPrivileges: Set(command.requiredPrivileges),
                        dataScope: command.dataScope,
                        allowedTargetKinds: Set(command.allowedTargetKinds),
                        resultVariants: command.resultVariants,
                        examples: command.examples,
                        agentEligibility: command.agentEligibility
                    )
                )
                guard validated == command else {
                    throw Self.failure(
                        .invalidCommandCatalog,
                        fieldPath: "$.commands",
                        expected: "command metadata derived from its typed variants and examples"
                    )
                }
                return validated
            }
        } catch let error as IPCCommandDiscoveryError {
            throw error
        } catch {
            throw Self.failure(
                .invalidCommandCatalog,
                fieldPath: "$.commands",
                expected: "validated typed command descriptors"
            )
        }

        let composition: IPCCommandMethodComposition
        let erasedList: IPCAnyMethodDescriptor
        let erasedExecute: IPCAnyMethodDescriptor
        do {
            composition = try IPCCommandMethodComposition(
                compatibility: catalog.compatibility,
                commands: validatedCommands
            )
            erasedList = try IPCAnyMethodDescriptor(erasing: composition.list)
            erasedExecute = try IPCAnyMethodDescriptor(erasing: composition.execute)
        } catch {
            throw Self.failure(
                .invalidCommandCatalog,
                fieldPath: "$.commands",
                expected: "one composable typed command catalog"
            )
        }
        guard erasedList.metadata == advertisedList,
            erasedExecute.metadata == advertisedExecute
        else {
            throw Self.failure(
                .incompatibleMethodMetadata,
                fieldPath: "$.methods",
                expected: "command.list and command.execute metadata exactly composed from the live command catalog"
            )
        }

        return IPCDiscoveredCommandCatalog(
            commands: validatedCommands,
            executeDescriptor: erasedExecute
        )
    }

    private static func uniqueEntry(
        named name: String,
        in catalog: IPCMethodCatalogResult,
        missingReason: IPCCommandDiscoveryError.Reason
    ) throws -> IPCMethodCatalogEntry {
        let matches = catalog.methods.filter { $0.name == name }
        guard let entry = matches.first else {
            throw failure(
                missingReason,
                fieldPath: "$.methods",
                expected: "exactly one \(name) method"
            )
        }
        guard matches.count == 1 else {
            throw failure(
                .incompatibleMethodMetadata,
                fieldPath: "$.methods",
                expected: "unique method names"
            )
        }
        return entry
    }

    private static func validateInvariantMetadata(
        list: IPCMethodCatalogEntry,
        execute: IPCMethodCatalogEntry
    ) throws {
        let listIsCompatible =
            list.parameterSchema == (try IPCEmptyParams.ipcSchema())
            && list.exposure == .allChannels
            && list.requiredPrivileges == [.systemRead]
            && list.dataScope == .unspecified
            && list.allowedTargetKinds.isEmpty
            && list.commandRelationship == .noInteractiveIdentity
            && list.executionOwner == .queryReader
            && list.principalAvailability == .authenticated
            && list.resultSemantics == .applied
            && list.documentedErrors.isEmpty
            && !list.isMutating
            && list.correlationPolicy == .notAccepted
            && list.responseDelivery == .single
            && list.offlineEligibility == .never
            && list.modelCalls.isEmpty
        let executeIsCompatible =
            execute.exposure == .allChannels
            && execute.requiredPrivileges == [.appCommandExecute]
            && execute.dataScope == .unspecified
            && execute.commandRelationship == .appCommandParameter(field: "commandId")
            && execute.executionOwner == .appCommand
            && execute.principalAvailability == .authenticated
            && execute.resultSemantics == .discriminated
            && execute.documentedErrors == IPCCommandMethodComposition.executionErrors
            && execute.isMutating
            && execute.correlationPolicy == .required
            && execute.responseDelivery == .single
            && execute.offlineEligibility == .never
            && execute.modelCalls.isEmpty
        guard listIsCompatible, executeIsCompatible else {
            throw failure(
                .incompatibleMethodMetadata,
                fieldPath: "$.methods",
                expected: "the invariant typed command method metadata"
            )
        }
    }

    fileprivate static func failure(
        _ reason: IPCCommandDiscoveryError.Reason,
        fieldPath: String,
        expected: String
    ) -> IPCCommandDiscoveryError {
        IPCCommandDiscoveryError(
            reason: reason,
            fieldPath: fieldPath,
            expected: expected
        )
    }
}

package struct IPCDiscoveredCommandCatalog: Sendable {
    package let executeDescriptor: IPCAnyMethodDescriptor

    private let commandsByIdentifier: [IPCCommandIdentifier: IPCCommandDescriptor]

    fileprivate init(
        commands: [IPCCommandDescriptor],
        executeDescriptor: IPCAnyMethodDescriptor
    ) {
        commandsByIdentifier = Dictionary(
            uniqueKeysWithValues: commands.map { ($0.id, $0) }
        )
        self.executeDescriptor = executeDescriptor
    }

    package func makeInvocation(
        commandId: IPCCommandIdentifier,
        correlationId: UUID,
        arguments: IPCCommandArguments
    ) throws -> IPCDescriptorInvocation {
        guard let command = commandsByIdentifier[commandId] else {
            throw IPCCommandDiscovery.failure(
                .unknownCommandIdentifier,
                fieldPath: "$.commandId",
                expected: "an identifier advertised by command.list"
            )
        }
        guard command.argumentVariants.contains(arguments.variant) else {
            throw IPCCommandDiscovery.failure(
                .argumentVariantNotAllowed,
                fieldPath: "$.arguments.kind",
                expected: "an argument variant advertised for the selected command"
            )
        }
        let request = IPCCommandExecutionRequest(
            commandId: commandId,
            correlationId: correlationId,
            arguments: arguments
        )
        let normalizedParameters: Data
        do {
            normalizedParameters = try executeDescriptor.normalizeParameters(
                JSONEncoder().encode(request)
            )
        } catch {
            throw IPCCommandDiscovery.failure(
                .argumentVariantNotAllowed,
                fieldPath: "$.arguments",
                expected: "arguments matching the selected command descriptor"
            )
        }
        return IPCDescriptorInvocation(
            descriptor: executeDescriptor,
            normalizedParameters: normalizedParameters,
            presentation: .tooling
        )
    }

    package func decodeResult(
        _ originalResult: Data,
        for invocation: IPCDescriptorInvocation
    ) throws -> IPCCommandExecutionResult {
        guard invocation.descriptor.metadata == executeDescriptor.metadata else {
            throw IPCCommandDiscovery.failure(
                .invalidCommandResult,
                fieldPath: "$",
                expected: "the command.execute descriptor used by this live catalog"
            )
        }
        let request: IPCCommandExecutionRequest
        let result: IPCCommandExecutionResult
        do {
            let normalizedRequest = try executeDescriptor.normalizeParameters(
                invocation.normalizedParameters
            )
            request = try JSONDecoder().decode(
                IPCCommandExecutionRequest.self,
                from: normalizedRequest
            )
            let normalizedResult = try executeDescriptor.normalizeResult(originalResult)
            result = try JSONDecoder().decode(
                IPCCommandExecutionResult.self,
                from: normalizedResult
            )
        } catch {
            throw IPCCommandDiscovery.failure(
                .invalidCommandResult,
                fieldPath: "$",
                expected: "the typed command.execute result"
            )
        }
        guard let command = commandsByIdentifier[request.commandId] else {
            throw IPCCommandDiscovery.failure(
                .unknownCommandIdentifier,
                fieldPath: "$.commandId",
                expected: "an identifier advertised by command.list"
            )
        }
        guard command.resultVariants.contains(result.variant) else {
            throw IPCCommandDiscovery.failure(
                .resultVariantNotAllowed,
                fieldPath: "$.kind",
                expected: "a result variant advertised for the selected command"
            )
        }
        guard result.commandId == request.commandId else {
            throw IPCCommandDiscovery.failure(
                .resultCommandIdentifierMismatch,
                fieldPath: "$.commandId",
                expected: "the initiating command identifier"
            )
        }
        guard result.correlationId == request.correlationId else {
            throw IPCCommandDiscovery.failure(
                .resultCorrelationMismatch,
                fieldPath: "$.correlationId",
                expected: "the initiating command correlation"
            )
        }
        return result
    }
}
