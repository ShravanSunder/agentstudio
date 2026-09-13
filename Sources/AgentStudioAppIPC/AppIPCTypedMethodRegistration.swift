import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

package enum AppIPCTypedMethodRegistrationError: Error, Equatable, Sendable {
    case correlationPolicyMismatch
    case correlationMismatch
    case targetKindNotAllowed
    case parameterTransportEncodingFailed
    case resultTransportDecodingFailed
}

package enum AppIPCCorrelation<Parameters: Sendable>: Sendable {
    case notRequired
    case required(@Sendable (Parameters) -> UUID)
}

package struct AppIPCTargetResolution<Parameters: Sendable>: Sendable {
    package let parameters: Parameters
    package let canonicalHandle: IPCHandle?
    package let target: IPCTargetScope

    package init(
        parameters: Parameters,
        canonicalHandle: IPCHandle?,
        target: IPCTargetScope
    ) {
        self.parameters = parameters
        self.canonicalHandle = canonicalHandle
        self.target = target
    }
}

package struct AppIPCTargetResolutionTools: Sendable {
    private let paneHandleCanonicalizer: @Sendable (String) async throws -> IPCHandle

    package init(
        canonicalizePaneHandle: @escaping @Sendable (String) async throws -> IPCHandle
    ) {
        self.paneHandleCanonicalizer = canonicalizePaneHandle
    }

    package func canonicalizePaneHandle(_ rawHandle: String) async throws -> IPCHandle {
        try await paneHandleCanonicalizer(rawHandle)
    }
}

package struct AppIPCMethodAuthorizationRequest: Equatable, Sendable {
    package let methodName: String
    package let requiredPrivileges: Set<IPCPrivilegeClass>
    package let dataScope: IPCDataScope
    package let target: IPCTargetScope
}

package struct AppIPCTypedMethodRegistration<
    Parameters: Codable & Sendable,
    Result: Codable & Sendable
>: Sendable {
    private let descriptor: IPCMethodDescriptor<Parameters, Result>
    private let correlation: AppIPCCorrelation<Parameters>
    private let resolveTarget:
        @Sendable (
            Parameters,
            IPCPrincipal,
            AppIPCTargetResolutionTools
        ) async throws -> AppIPCTargetResolution<Parameters>
    private let handler: @Sendable (Parameters, IPCPrincipal, IPCTargetScope) async throws -> Result

    package init(
        descriptor: IPCMethodDescriptor<Parameters, Result>,
        correlation: AppIPCCorrelation<Parameters>,
        resolveTarget:
            @escaping @Sendable (
                Parameters,
                IPCPrincipal,
                AppIPCTargetResolutionTools
            ) async throws -> AppIPCTargetResolution<Parameters>,
        handler:
            @escaping @Sendable (
                Parameters,
                IPCPrincipal,
                IPCTargetScope
            ) async throws -> Result
    ) {
        self.descriptor = descriptor
        self.correlation = correlation
        self.resolveTarget = resolveTarget
        self.handler = handler
    }

    package func erase() throws -> AnyAppIPCMethodRegistration {
        try validateCorrelationPolicy()
        let erasedDescriptor = try IPCAnyMethodDescriptor(erasing: descriptor)

        return AnyAppIPCMethodRegistration(
            descriptor: erasedDescriptor,
            invocation: { parameters, principal, tools, authorization in
                let parameterData: Data
                do {
                    parameterData = try JSONEncoder().encode(parameters)
                } catch {
                    throw AppIPCTypedMethodRegistrationError.parameterTransportEncodingFailed
                }

                let normalizedParameterData = try descriptor.contract.parameterSchema.normalize(parameterData)
                let typedParameters = try descriptor.decodeParameters(from: normalizedParameterData)
                let normalizedWireCorrelation = try normalizedWireCorrelationId(
                    from: normalizedParameterData
                )
                try validateCorrelation(
                    in: typedParameters,
                    matches: normalizedWireCorrelation
                )

                let resolution = try await resolveTarget(typedParameters, principal, tools)
                try validateCorrelation(
                    in: resolution.parameters,
                    matches: normalizedWireCorrelation
                )
                try validateTarget(resolution.canonicalHandle)

                try await authorization.authorize(
                    principal,
                    request: AppIPCMethodAuthorizationRequest(
                        methodName: descriptor.name,
                        requiredPrivileges: descriptor.requiredPrivileges,
                        dataScope: descriptor.dataScope,
                        target: resolution.target
                    )
                )

                let typedResult = try await handler(
                    resolution.parameters,
                    principal,
                    resolution.target
                )
                let resultData = try descriptor.encodeResult(typedResult)
                do {
                    return try JSONDecoder().decode(JSONValue.self, from: resultData)
                } catch {
                    throw AppIPCTypedMethodRegistrationError.resultTransportDecodingFailed
                }
            })
    }

    private func validateCorrelationPolicy() throws {
        switch (descriptor.correlationPolicy, correlation) {
        case (.required, .required), (.optional, .notRequired), (.notAccepted, .notRequired):
            return
        case (.required, .notRequired), (.optional, .required), (.notAccepted, .required):
            throw AppIPCTypedMethodRegistrationError.correlationPolicyMismatch
        }
    }

    private func normalizedWireCorrelationId(from normalizedParameters: Data) throws -> UUID? {
        guard descriptor.correlationPolicy == .required else { return nil }
        do {
            return try JSONDecoder().decode(
                AppIPCRequiredCorrelationEnvelope.self,
                from: normalizedParameters
            ).correlationId
        } catch {
            throw AppIPCTypedMethodRegistrationError.correlationMismatch
        }
    }

    private func validateCorrelation(
        in parameters: Parameters,
        matches normalizedWireCorrelation: UUID?
    ) throws {
        switch correlation {
        case .notRequired:
            return
        case .required(let extractCorrelation):
            guard extractCorrelation(parameters) == normalizedWireCorrelation else {
                throw AppIPCTypedMethodRegistrationError.correlationMismatch
            }
        }
    }

    private func validateTarget(_ canonicalHandle: IPCHandle?) throws {
        guard let canonicalHandle else {
            guard descriptor.allowedTargetKinds.isEmpty else {
                throw AppIPCTypedMethodRegistrationError.targetKindNotAllowed
            }
            return
        }

        guard case .canonicalUUID = canonicalHandle.reference,
            descriptor.allowedTargetKinds.contains(canonicalHandle.kind)
        else {
            throw AppIPCTypedMethodRegistrationError.targetKindNotAllowed
        }
    }
}

package struct AnyAppIPCMethodRegistration: Sendable {
    package let descriptor: IPCAnyMethodDescriptor
    private let invocation:
        @Sendable (
            JSONValue,
            IPCPrincipal,
            AppIPCTargetResolutionTools,
            AppIPCTypedMethodAuthorization
        ) async throws -> JSONValue

    fileprivate init(
        descriptor: IPCAnyMethodDescriptor,
        invocation:
            @escaping @Sendable (
                JSONValue,
                IPCPrincipal,
                AppIPCTargetResolutionTools,
                AppIPCTypedMethodAuthorization
            ) async throws -> JSONValue
    ) {
        self.descriptor = descriptor
        self.invocation = invocation
    }

    package func invoke(
        parameters: JSONValue,
        principal: IPCPrincipal,
        targetResolutionTools: AppIPCTargetResolutionTools,
        authorize:
            @escaping @Sendable (
                IPCPrincipal,
                AppIPCMethodAuthorizationRequest
            ) async throws -> Void
    ) async throws -> JSONValue {
        try await invocation(
            parameters,
            principal,
            targetResolutionTools,
            AppIPCTypedMethodAuthorization(authorize: authorize)
        )
    }
}

private struct AppIPCTypedMethodAuthorization: Sendable {
    private let authorization: @Sendable (IPCPrincipal, AppIPCMethodAuthorizationRequest) async throws -> Void

    init(
        authorize:
            @escaping @Sendable (
                IPCPrincipal,
                AppIPCMethodAuthorizationRequest
            ) async throws -> Void
    ) {
        self.authorization = authorize
    }

    func authorize(
        _ principal: IPCPrincipal,
        request: AppIPCMethodAuthorizationRequest
    ) async throws {
        try await authorization(principal, request)
    }
}

private struct AppIPCRequiredCorrelationEnvelope: Decodable {
    let correlationId: UUID
}
