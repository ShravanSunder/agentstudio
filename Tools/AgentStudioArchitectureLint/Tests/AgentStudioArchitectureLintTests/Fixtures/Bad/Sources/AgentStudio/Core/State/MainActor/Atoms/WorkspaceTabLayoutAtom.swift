final class WorkspaceTabLayoutAtom {
    private(set) lazy var richTabSnapshotValue: DerivedValue<Int> = {
        DerivedValue<Int>(
            inputRevisions: { [revision.value] },
            isContentEqual: ==,
            compute: { sourceValue }
        )
    }()

    func makePerAccessSnapshot() -> Int {
        let richTabSnapshotValue = DerivedValue<Int>(
            inputRevisions: { [revision.value] },
            isContentEqual: ==,
            compute: { sourceValue }
        )
        return richTabSnapshotValue.value
    }

    let revision = AtomRevision()
    let sourceValue = 42
}
