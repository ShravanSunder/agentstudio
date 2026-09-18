import Foundation

package struct IPCLayoutMethodDescriptors: Sendable {
    package let paneFocus: IPCMethodDescriptor<IPCPaneControlParams, IPCPaneFocusResult>
    package let paneSplit: IPCMethodDescriptor<IPCPaneSplitParams, IPCPaneSplitResult>
    package let paneClose: IPCMethodDescriptor<IPCPaneCloseParams, IPCPaneCloseResult>
    package let drawerToggle: IPCMethodDescriptor<IPCDrawerToggleParams, IPCDrawerToggleResult>
    package let drawerAddPane: IPCMethodDescriptor<IPCDrawerAddPaneParams, IPCDrawerAddPaneResult>

    init(inputs: IPCBuiltInMethodCatalogInputs) throws {
        let example = inputs.examples
        let relationship = inputs.relationships
        paneFocus = try IPCBuiltInDescriptorSupport.mutation(
            name: "pane.focus",
            description: "Focus one explicit pane in an explicit workspace window context.",
            parameters: IPCPaneControlParams(handle: "self", correlationId: example.correlationId),
            result: IPCPaneFocusResult(paneId: example.paneId, focused: true),
            metadata: .init(
                privilege: .layoutMutate,
                dataScope: .paneContext,
                targetKinds: [.pane],
                relationship: relationship.paneFocus,
                owner: .workspaceAction)
        )
        paneSplit = try IPCBuiltInDescriptorSupport.mutation(
            name: "pane.split",
            description: "Split one explicit pane in the requested direction.",
            parameters: IPCPaneSplitParams(
                handle: "self",
                direction: .right,
                correlationId: example.correlationId
            ),
            result: IPCPaneSplitResult(
                targetPaneId: example.paneId,
                direction: .right,
                correlationId: example.correlationId
            ),
            metadata: .init(
                privilege: .layoutMutate,
                dataScope: .paneContext,
                targetKinds: [.pane],
                owner: .workspaceAction)
        )
        paneClose = try IPCBuiltInDescriptorSupport.mutation(
            name: "pane.close",
            description: "Close one explicit pane.",
            parameters: IPCPaneCloseParams(handle: "self", correlationId: example.correlationId),
            result: IPCPaneCloseResult(paneId: example.paneId, correlationId: example.correlationId),
            metadata: .init(
                privilege: .layoutMutate,
                dataScope: .paneContext,
                targetKinds: [.pane],
                relationship: relationship.paneClose,
                owner: .workspaceAction)
        )
        drawerToggle = try IPCBuiltInDescriptorSupport.mutation(
            name: "drawer.toggle",
            description: "Toggle the drawer belonging to one explicit parent pane.",
            parameters: IPCDrawerToggleParams(
                parentPaneHandle: "self",
                correlationId: example.correlationId
            ),
            result: IPCDrawerToggleResult(
                parentPaneId: example.paneId,
                correlationId: example.correlationId
            ),
            metadata: .init(
                privilege: .layoutMutate,
                dataScope: .paneContext,
                targetKinds: [.pane],
                relationship: relationship.drawerToggle,
                owner: .workspaceAction)
        )
        drawerAddPane = try IPCBuiltInDescriptorSupport.mutation(
            name: "drawer.addPane",
            description: "Add a terminal pane to one explicit parent pane's drawer.",
            parameters: IPCDrawerAddPaneParams(
                parentPaneHandle: "self",
                correlationId: example.correlationId
            ),
            result: IPCDrawerAddPaneResult(
                parentPaneId: example.paneId,
                correlationId: example.correlationId
            ),
            metadata: .init(
                privilege: .layoutMutate,
                dataScope: .paneContext,
                targetKinds: [.pane],
                relationship: relationship.drawerAddPane,
                owner: .workspaceAction)
        )
    }

    var erased: [IPCAnyMethodDescriptor] {
        get throws {
            try [
                IPCAnyMethodDescriptor(erasing: paneFocus),
                IPCAnyMethodDescriptor(erasing: paneSplit),
                IPCAnyMethodDescriptor(erasing: paneClose),
                IPCAnyMethodDescriptor(erasing: drawerToggle),
                IPCAnyMethodDescriptor(erasing: drawerAddPane),
            ]
        }
    }
}
