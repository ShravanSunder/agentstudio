@testable import AgentStudio

func invokeRemovedRawMailboxOffer(
    mailbox: FilesystemObservationMailbox,
    offer: FilesystemObservationOffer,
    binding: FilesystemObservationSlotBinding
) -> Any {
    mailbox.offer(offer, for: binding)
}
