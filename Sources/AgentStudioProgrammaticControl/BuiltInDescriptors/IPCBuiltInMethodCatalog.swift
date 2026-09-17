import Foundation

package struct IPCBuiltInMethodCatalog: Sendable {
    package let systemAndAuth: IPCSystemAndAuthMethodDescriptors
    package let workspaceQueries: IPCWorkspaceQueryMethodDescriptors
    package let layout: IPCLayoutMethodDescriptors
    package let terminal: IPCTerminalMethodDescriptors
    package let bridge: IPCBridgeMethodDescriptors
    package let presentationAndSidebar: IPCPresentationAndSidebarMethodDescriptors
    package let events: IPCEventMethodDescriptors
    package let sessions: IPCSessionMethodDescriptors
    package let erasedDescriptors: [IPCAnyMethodDescriptor]

    package init(inputs: IPCBuiltInMethodCatalogInputs) throws {
        systemAndAuth = try IPCSystemAndAuthMethodDescriptors(examples: inputs.examples)
        workspaceQueries = try IPCWorkspaceQueryMethodDescriptors(examples: inputs.examples)
        layout = try IPCLayoutMethodDescriptors(inputs: inputs)
        terminal = try IPCTerminalMethodDescriptors(inputs: inputs)
        bridge = try IPCBridgeMethodDescriptors(inputs: inputs)
        presentationAndSidebar = try IPCPresentationAndSidebarMethodDescriptors(examples: inputs.examples)
        events = try IPCEventMethodDescriptors(examples: inputs.examples)
        sessions = try IPCSessionMethodDescriptors(examples: inputs.examples)
        erasedDescriptors = try
            (systemAndAuth.erased
            + workspaceQueries.erased
            + layout.erased
            + terminal.erased
            + bridge.erased
            + presentationAndSidebar.erased
            + events.erased
            + sessions.erased).sorted { $0.metadata.name < $1.metadata.name }
    }
}
