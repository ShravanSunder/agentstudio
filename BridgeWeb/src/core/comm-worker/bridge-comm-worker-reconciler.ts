import type { BridgeWorkerContentMetadata } from './bridge-worker-contracts.js';

export type BridgeCommWorkerDemandMember =
	| {
			readonly itemId: string;
			readonly role: 'selected';
			readonly selectedDemandEpoch: number;
	  }
	| {
			readonly itemId: string;
			readonly role: 'background' | 'nearby' | 'speculative' | 'visible';
	  };

export interface BridgeCommWorkerDemandMembership {
	readonly membersByItemId: ReadonlyMap<string, BridgeCommWorkerDemandMember>;
}

export interface ReconcileBridgeCommWorkerDemandMembershipProps {
	readonly contentMetadataByItemId: ReadonlyMap<string, BridgeWorkerContentMetadata>;
	readonly hoveredItemId?: string | null;
	readonly orderedItemIds?: readonly string[];
	readonly selectedDemandEpoch: number | null;
	readonly selectedId: string | null;
	readonly viewportDirection?: 'backward' | 'forward' | 'unknown';
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
	for (const itemId of nearbyReviewDemandItemIds(props)) {
		if (!membersByItemId.has(itemId)) {
			membersByItemId.set(itemId, { itemId, role: 'nearby' });
		}
	}
	const hoveredItemId = props.hoveredItemId ?? null;
	if (
		hoveredItemId !== null &&
		!membersByItemId.has(hoveredItemId) &&
		isBridgeCommWorkerDemandEligibleContentMetadata(
			props.contentMetadataByItemId.get(hoveredItemId) ?? null,
		)
	) {
		membersByItemId.set(hoveredItemId, {
			itemId: hoveredItemId,
			role: 'speculative',
		});
	}
	for (const itemId of props.orderedItemIds ?? []) {
		if (
			!membersByItemId.has(itemId) &&
			isBridgeCommWorkerReviewDemandEligibleContentMetadata(
				props.contentMetadataByItemId.get(itemId) ?? null,
			)
		) {
			membersByItemId.set(itemId, { itemId, role: 'background' });
		}
	}
	return { membersByItemId };
}

function nearbyReviewDemandItemIds(
	props: ReconcileBridgeCommWorkerDemandMembershipProps,
): readonly string[] {
	const orderedItemIds = props.orderedItemIds;
	if (orderedItemIds === undefined || props.visibleIds.length === 0) {
		return [];
	}
	const orderedIndexByItemId = new Map(
		orderedItemIds.map((itemId, orderedIndex) => [itemId, orderedIndex]),
	);
	const visibleIndexes = props.visibleIds.flatMap((itemId) => {
		const orderedIndex = orderedIndexByItemId.get(itemId);
		return orderedIndex === undefined ? [] : [orderedIndex];
	});
	if (visibleIndexes.length === 0) {
		return [];
	}
	const viewportLength = visibleIndexes.length;
	const direction = props.viewportDirection ?? 'unknown';
	const behindCount = viewportLength * (direction === 'backward' ? 2 : 1);
	const aheadCount = viewportLength * (direction === 'forward' ? 2 : 1);
	const firstVisibleIndex = visibleIndexes.reduce((minimumIndex, visibleIndex) =>
		Math.min(minimumIndex, visibleIndex),
	);
	const lastVisibleIndex = visibleIndexes.reduce((maximumIndex, visibleIndex) =>
		Math.max(maximumIndex, visibleIndex),
	);
	const nearbyItemIds = [
		...orderedItemIds.slice(Math.max(0, firstVisibleIndex - behindCount), firstVisibleIndex),
		...orderedItemIds.slice(lastVisibleIndex + 1, lastVisibleIndex + 1 + aheadCount),
	];
	return nearbyItemIds.filter((itemId) =>
		isBridgeCommWorkerReviewDemandEligibleContentMetadata(
			props.contentMetadataByItemId.get(itemId) ?? null,
		),
	);
}

export function serializeBridgeCommWorkerDemandMembership(
	membership: BridgeCommWorkerDemandMembership,
): Map<string, string> {
	const demandByKey = new Map<string, string>();
	for (const member of membership.membersByItemId.values()) {
		demandByKey.set(member.itemId, demandKeyForBridgeCommWorkerDemandMember(member));
	}
	return demandByKey;
}

function demandKeyForBridgeCommWorkerDemandMember(member: BridgeCommWorkerDemandMember): string {
	return member.role === 'selected' ? `selected:${member.selectedDemandEpoch}` : member.role;
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

function isBridgeCommWorkerReviewDemandEligibleContentMetadata(
	metadata: BridgeWorkerContentMetadata | null,
): boolean {
	return (
		metadata !== null &&
		'availableContentRoles' in metadata &&
		metadata.availableContentRoles.length > 0
	);
}
