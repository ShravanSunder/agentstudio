import Foundation

extension IPCSidebarSurface: IPCSchemaProviding {}
extension IPCSidebarGroupingMode: IPCSchemaProviding {}
extension IPCCommandBarScope: IPCSchemaProviding {}

extension IPCSidebarGroupingResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "surface", description: "Sidebar surface whose grouping was read or changed",
                schema: try IPCSidebarSurface.ipcSchema()),
            .init(
                name: "mode", description: "Effective sidebar grouping mode",
                schema: try IPCSidebarGroupingMode.ipcSchema()),
            uiCorrelationField(),
        ])
    }
}

extension IPCSidebarSurfaceResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "surface", description: "Effective visible sidebar surface",
                schema: try IPCSidebarSurface.ipcSchema()),
            uiCorrelationField(),
        ])
    }
}

extension IPCCommandBarOpenResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "workspaceWindowId", description: "Workspace window UUID presenting the command bar",
                schema: IPCSchemaScalars.uuid),
            .init(
                name: "scope", description: "Command bar search scope presented",
                schema: try IPCCommandBarScope.ipcSchema()),
            uiCorrelationField(),
        ])
    }
}

extension IPCArrangementsOpenResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "workspaceWindowId", description: "Workspace window UUID presenting arrangements",
                schema: IPCSchemaScalars.uuid),
            .init(name: "tabId", description: "Tab UUID providing arrangement context", schema: IPCSchemaScalars.uuid),
            .optional(
                "contextPaneId", description: "Pane UUID providing arrangement context", schema: IPCSchemaScalars.uuid),
            uiCorrelationField(),
        ])
    }
}

private func uiCorrelationField() -> IPCObjectField {
    .optional("correlationId", description: "Caller correlation UUID when supplied", schema: IPCSchemaScalars.uuid)
}
