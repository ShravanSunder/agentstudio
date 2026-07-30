final class WorkspaceTabLayoutAtom {
    private lazy var richTabSnapshotValue = DerivedValue<Int>(
        inputRevisions: { [revision.value] },
        isContentEqual: ==,
        compute: { sourceValue }
    )

    let revision = AtomRevision()
    let sourceValue = 42
}
