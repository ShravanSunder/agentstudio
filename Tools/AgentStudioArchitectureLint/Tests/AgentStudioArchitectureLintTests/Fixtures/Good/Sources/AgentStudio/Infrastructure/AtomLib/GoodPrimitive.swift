struct GoodPrimitive<Value> {
    let value: Value

    func read(workspace: WorkspaceLabel) -> String {
        workspace.value
    }
}

struct WorkspaceLabel {
    let value: String
}
