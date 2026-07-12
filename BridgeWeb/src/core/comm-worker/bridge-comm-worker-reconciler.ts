import type { BridgeWorkerContentMetadata } from './bridge-worker-contracts.js';

export type BridgeCommWorkerDemandMember =
	| {
			readonly itemId: string;
			readonly role: 'selected';
			readonly selectedDemandEpoch: number;
	  }
	| {
			readonly itemId: string;
			readonly role: 'visible';
	  };

export interface BridgeCommWorkerDemandMembership {
	readonly membersByItemId: ReadonlyMap<string, BridgeCommWorkerDemandMember>;
}

export interface ReconcileBridgeCommWorkerDemandMembershipProps {
	readonly contentMetadataByItemId: ReadonlyMap<string, BridgeWorkerContentMetadata>;
	readonly selectedDemandEpoch: number | null;
	readonly selectedId: string | null;
	readonly visibleIds: readonly string[];
}

export function reconcileBridgeCommWorkerDemandMembership(
	props: ReconcileBridgeCommWorkerDemandMembershipProps,
): BridgeCommWorkerDemandMembership {
	const membersByItemId = new Map<string, BridgeCommWorkerDemandMember>();
	if (
		props.selectedId !== null &&
		props.selectedDemandEpoch !== null &&
		isBridgeCommWorkerDemandEligibleContentMetadata(
			props.contentMetadataByItemId.get(props.selectedId) ?? null,
		)
	) {
		membersByItemId.set(props.selectedId, {
			itemId: props.selectedId,
			role: 'selected',
			selectedDemandEpoch: props.selectedDemandEpoch,
		});
	}
	for (const itemId of props.visibleIds) {
		if (membersByItemId.has(itemId)) {
			continue;
		}
		if (
			!isBridgeCommWorkerDemandEligibleContentMetadata(
				props.contentMetadataByItemId.get(itemId) ?? null,
			)
		) {
			continue;
		}
		membersByItemId.set(itemId, { itemId, role: 'visible' });
	}
	return { membersByItemId };
}

export function serializeBridgeCommWorkerDemandMembership(
	membership: BridgeCommWorkerDemandMembership,
): Map<string, string> {
	const demandByKey = new Map<string, string>();
	for (const member of membership.membersByItemId.values()) {
		demandByKey.set(
			member.itemId,
			member.role === 'selected' ? `selected:${member.selectedDemandEpoch}` : member.role,
		);
	}
	return demandByKey;
}

export function isBridgeCommWorkerDemandEligibleContentMetadata(
	metadata: BridgeWorkerContentMetadata | null,
): boolean {
	if (metadata === null) {
		return false;
	}
	if ('availableContentRoles' in metadata) {
		return metadata.availableContentRoles.length > 0;
	}
	return metadata.canFetchContent;
}
