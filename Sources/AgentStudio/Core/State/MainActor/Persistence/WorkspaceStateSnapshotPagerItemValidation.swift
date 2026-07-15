extension WorkspaceStateSnapshotPager {
    func validateProjectedItemIdentity(
        _ item: Item,
        expectedItemID: Item.SnapshotItemID,
        participantID: ParticipantID
    ) -> WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>? {
        let itemID = item.snapshotItemID
        guard item.snapshotParticipantID == participantID else {
            return .itemParticipantMismatch(
                expected: participantID,
                actual: item.snapshotParticipantID,
                itemID: itemID
            )
        }
        guard itemID == expectedItemID else {
            return .itemIdentityMismatch(
                participantID: participantID,
                expected: expectedItemID,
                actual: itemID
            )
        }
        return nil
    }
}
