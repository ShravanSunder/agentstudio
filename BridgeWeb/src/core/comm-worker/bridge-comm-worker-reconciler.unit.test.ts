import { describe, expect, test } from 'vitest';

import {
	reconcileBridgeCommWorkerDemandMembership,
	serializeBridgeCommWorkerDemandMembership,
} from './bridge-comm-worker-reconciler.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerReviewContentMetadata,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker demand reconciler', () => {
	test('worker owns demand membership without membership caps or parked retry versions', () => {
		const visibleContentMetadata = Array.from({ length: 16 }, (_, index) =>
			makeReviewContentMetadata(`visible-${index}`),
		);
		const selectedContentMetadata = makeReviewContentMetadata('selected');

		const membership = reconcileBridgeCommWorkerDemandMembership({
			contentMetadataByItemId: new Map(
				[...visibleContentMetadata, selectedContentMetadata].map((metadata) => [
					metadata.itemId,
					metadata,
				]),
			),
			selectedDemandEpoch: 8,
			selectedId: selectedContentMetadata.itemId,
			visibleIds: visibleContentMetadata.map((metadata) => metadata.itemId),
		});

		expect([...membership.membersByItemId.keys()]).toEqual([
			'selected',
			...visibleContentMetadata.map((metadata) => metadata.itemId),
		]);
		expect(serializeBridgeCommWorkerDemandMembership(membership)).toEqual(
			new Map([
				['selected', 'selected:8'],
				...visibleContentMetadata.map((metadata): readonly [string, string] => [
					metadata.itemId,
					'visible',
				]),
			]),
		);
		expect(JSON.stringify(Object.fromEntries(membership.membersByItemId))).not.toMatch(
			/retryAfterVersion|parked|membershipCap|pendingEviction/u,
		);
	});

	test('filters unavailable metadata without dropping other visible members', () => {
		const fetchableFile = makeFileViewContentMetadata('file-ready');
		const binaryFile = makeFileViewContentMetadata('file-binary', { canFetchContent: false });
		const metadataOnlyReviewItem = makeReviewContentMetadata('metadata-only', {
			availableContentRoles: [],
		});

		const membership = reconcileBridgeCommWorkerDemandMembership({
			contentMetadataByItemId: new Map(
				[fetchableFile, binaryFile, metadataOnlyReviewItem].map((metadata) => [
					metadata.itemId,
					metadata,
				]),
			),
			selectedDemandEpoch: 4,
			selectedId: metadataOnlyReviewItem.itemId,
			visibleIds: [fetchableFile.itemId, binaryFile.itemId, metadataOnlyReviewItem.itemId],
		});

		expect([...membership.membersByItemId.values()]).toEqual([
			{
				itemId: fetchableFile.itemId,
				role: 'visible',
			},
		]);
	});

	test('reconciles hover as speculative below selected and visible membership', () => {
		// Arrange
		const selected = makeReviewContentMetadata('selected');
		const visible = makeReviewContentMetadata('visible');
		const hovered = makeReviewContentMetadata('hovered');
		const contentMetadataByItemId = new Map(
			[selected, visible, hovered].map((metadata) => [metadata.itemId, metadata]),
		);

		// Act
		const speculativeMembership = reconcileBridgeCommWorkerDemandMembership({
			contentMetadataByItemId,
			hoveredItemId: hovered.itemId,
			selectedDemandEpoch: 12,
			selectedId: selected.itemId,
			visibleIds: [visible.itemId],
		});
		const visiblePrecedenceMembership = reconcileBridgeCommWorkerDemandMembership({
			contentMetadataByItemId,
			hoveredItemId: visible.itemId,
			selectedDemandEpoch: 12,
			selectedId: selected.itemId,
			visibleIds: [visible.itemId],
		});
		const selectedPrecedenceMembership = reconcileBridgeCommWorkerDemandMembership({
			contentMetadataByItemId,
			hoveredItemId: selected.itemId,
			selectedDemandEpoch: 12,
			selectedId: selected.itemId,
			visibleIds: [visible.itemId],
		});

		// Assert
		expect(serializeBridgeCommWorkerDemandMembership(speculativeMembership)).toEqual(
			new Map([
				['selected', 'selected:12'],
				['visible', 'visible'],
				['hovered', 'speculative'],
			]),
		);
		expect(visiblePrecedenceMembership.membersByItemId.get('visible')).toEqual({
			itemId: 'visible',
			role: 'visible',
		});
		expect(selectedPrecedenceMembership.membersByItemId.get('selected')).toEqual({
			itemId: 'selected',
			role: 'selected',
			selectedDemandEpoch: 12,
		});
	});

	test('projects one highest role across all five Review demand roles', () => {
		const orderedItemIds = [
			'nearby-before-1',
			'nearby-before-2',
			'selected',
			'visible',
			'nearby-after-1',
			'nearby-after-2',
			'hovered',
			'background',
		];
		const contentMetadataByItemId = new Map(
			orderedItemIds.map((itemId) => {
				const metadata = makeReviewContentMetadata(itemId);
				return [metadata.itemId, metadata] as const;
			}),
		);

		const membership = reconcileBridgeCommWorkerDemandMembership({
			contentMetadataByItemId,
			hoveredItemId: 'hovered',
			orderedItemIds,
			selectedDemandEpoch: 13,
			selectedId: 'selected',
			viewportDirection: 'unknown',
			visibleIds: ['selected', 'visible'],
		});

		expect([...membership.membersByItemId.values()]).toEqual([
			{ itemId: 'selected', role: 'selected', selectedDemandEpoch: 13 },
			{ itemId: 'visible', role: 'visible' },
			{ itemId: 'nearby-before-1', role: 'nearby' },
			{ itemId: 'nearby-before-2', role: 'nearby' },
			{ itemId: 'nearby-after-1', role: 'nearby' },
			{ itemId: 'nearby-after-2', role: 'nearby' },
			{ itemId: 'hovered', role: 'speculative' },
			{ itemId: 'background', role: 'background' },
		]);
	});

	test('visibility without eligible Review metadata never creates body demand', () => {
		const reviewItem = makeReviewContentMetadata('review-item');

		const membership = reconcileBridgeCommWorkerDemandMembership({
			contentMetadataByItemId: new Map([[reviewItem.itemId, reviewItem]]),
			orderedItemIds: [reviewItem.itemId],
			selectedDemandEpoch: null,
			selectedId: null,
			viewportDirection: 'unknown',
			visibleIds: ['tree-only-row'],
		});

		expect(membership.membersByItemId.has('tree-only-row')).toBe(false);
		expect(membership.membersByItemId.get('review-item')).toEqual({
			itemId: 'review-item',
			role: 'background',
		});
	});

	test.each([
		{
			direction: 'unknown' as const,
			expectedNearbyIds: ['item-2', 'item-3', 'item-6', 'item-7'],
		},
		{
			direction: 'forward' as const,
			expectedNearbyIds: ['item-2', 'item-3', 'item-6', 'item-7', 'item-8', 'item-9'],
		},
		{
			direction: 'backward' as const,
			expectedNearbyIds: ['item-0', 'item-1', 'item-2', 'item-3', 'item-6', 'item-7'],
		},
	])(
		'derives $direction nearby geometry from exact visible IDs and authoritative order',
		({ direction, expectedNearbyIds }) => {
			const orderedItemIds = Array.from({ length: 12 }, (_, index) => `item-${index}`);
			const contentMetadataByItemId = new Map(
				orderedItemIds.map((itemId) => {
					const metadata = makeReviewContentMetadata(itemId);
					return [metadata.itemId, metadata] as const;
				}),
			);

			const membership = reconcileBridgeCommWorkerDemandMembership({
				contentMetadataByItemId,
				orderedItemIds,
				selectedDemandEpoch: null,
				selectedId: null,
				viewportDirection: direction,
				visibleIds: ['item-4', 'item-5'],
			});

			expect(
				[...membership.membersByItemId.values()]
					.filter(({ role }) => role === 'nearby')
					.map(({ itemId }) => itemId),
			).toEqual(expectedNearbyIds);
		},
	);
});

function makeReviewContentMetadata(
	itemId: string,
	props: {
		readonly availableContentRoles?: BridgeWorkerReviewContentMetadata['availableContentRoles'];
	} = {},
): BridgeWorkerReviewContentMetadata {
	return {
		itemId,
		path: `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `review:sha256:${itemId}`,
		sizeBytes: 128,
		availableContentRoles: props.availableContentRoles ?? ['head'],
		contentLineCountsByRole: {},
	};
}

function makeFileViewContentMetadata(
	itemId: string,
	props: { readonly canFetchContent?: boolean } = {},
): BridgeWorkerFileViewContentMetadata {
	return {
		metadataKind: 'fileView',
		itemId,
		path: `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `file-view:sha256:${itemId}`,
		sizeBytes: 128,
		descriptorId: `descriptor-${itemId}`,
		contentHash: `sha256:${itemId}`,
		encoding: props.canFetchContent === false ? null : 'utf-8',
		endsMidLine: false,
		endsWithNewline: props.canFetchContent !== false,
		virtualizedExtentKind: 'exactLineCount',
		payloadByteCount: props.canFetchContent === false ? 0 : 128,
		payloadLineCount: props.canFetchContent === false ? 0 : 7,
		totalLineCount: props.canFetchContent === false ? null : 7,
		truncationKind: 'none',
		isBinary: props.canFetchContent === false,
		canFetchContent: props.canFetchContent ?? true,
	};
}
