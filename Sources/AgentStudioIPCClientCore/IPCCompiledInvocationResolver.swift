import AgentStudioProgrammaticControl

/// Selects compiled recipes at the CLI boundary; the index is the real production default.
package struct IPCCompiledInvocationResolver: Sendable {
    private let index: IPCBuiltInMethodIndex

    package init(index: IPCBuiltInMethodIndex = IPCBuiltInMethodIndex()) {
        self.index = index
    }

    package func resolve(
        arguments: [String], authenticated: Bool, inputs: IPCBuiltInMethodCatalogInputs
    ) throws -> [IPCAnyMethodDescriptor] {
        // S6b RED: retain the current eager traversal until the selective-resolution gate is observed.
        let descriptors = try index.makeRepresentations(inputs: inputs).map(\.erasedDescriptor)
        guard let name = arguments.first else { throw unknownMethod() }
        let selected: IPCAnyMethodDescriptor
        if let exact = descriptors.first(where: { $0.metadata.name == name }) {
            selected = exact
        } else {
            let candidates = descriptors.flatMap { descriptor in
                descriptor.metadata.modelCalls.compactMap { projection -> (IPCAnyMethodDescriptor, Int)? in
                    let prefix = projection.variant.rawValue.split(separator: " ").map(String.init)
                    return arguments.starts(with: prefix) ? (descriptor, prefix.count) : nil
                }
            }
            guard let longest = candidates.map({ $0.1 }).max() else { throw unknownMethod() }
            let matches = candidates.filter { $0.1 == longest }
            guard matches.count == 1, let candidate = matches.first else {
                throw IPCDescriptorInvocationError(
                    reason: .ambiguousInvocation, fieldPath: "$", expected: "one descriptor model projection")
            }
            selected = candidate.0
        }
        guard authenticated, selected.metadata.name != "auth.login",
            let authentication = descriptors.first(where: { $0.metadata.name == "auth.login" })
        else { return [selected] }
        return [authentication, selected]
    }

    package func localHelp(arguments: [String], inputs: IPCBuiltInMethodCatalogInputs) throws -> String? {
        // S6b RED: help still pays descriptor construction, as the existing runner does.
        let descriptors = try index.makeRepresentations(inputs: inputs).map(\.erasedDescriptor)
        return try IPCDescriptorCLIHelp.localHelp(arguments: arguments, descriptors: descriptors)
    }

    private func unknownMethod() -> IPCDescriptorInvocationError {
        IPCDescriptorInvocationError(
            reason: .unknownMethod, fieldPath: "$", expected: "a declared method or model invocation")
    }
}
