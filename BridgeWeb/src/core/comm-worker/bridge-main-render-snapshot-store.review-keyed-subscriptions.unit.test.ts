import { describe, expect, test } from 'vitest';

import {
	type BridgeMainCodeViewItem,
	createBridgeMainRenderSnapshotStore,
} from './bridge-main-render-snapshot-store.js';

const REVIEW_ITEM_COUNT = 4_096;
const REVIEW_PATCH_ITEM_COUNT = 64;
const REVIEW_PATCH_START_INDEX = 1_024;

interface ReviewKeyedSubscriptionStoreContract {
	readonly getReviewAvailabilitySnapshot: (itemId: string) => unknown;
	readonly getReviewCatalogSnapshot: () => {
		readonly itemOrderLength: number;
		readonly revision: number;
		readonly treeRowOrderLength: number;
	};
	readonly getReviewCodeViewItemSnapshot: (itemId: string) => unknown;
	readonly getReviewItemIdAtIndex: (itemIndex: number) => string | null | undefined;
	readonly getReviewItemSnapshot: (itemId: string) => unknown;
	readonly getReviewTreeRowAtIndex: (treeRowIndex: number) => unknown;
	readonly subscribeReviewAvailability: (itemId: string, listener: () => void) => () => void;
	readonly subscribeReviewCatalog: (listener: () => void) => () => void;
	readonly subscribeReviewCodeViewItem: (itemId: string, listener: () => void) => () => void;
	readonly subscribeReviewItem: (itemId: string, listener: () => void) => () => void;
}

describe('Bridge main render snapshot store Review keyed subscriptions', () => {
	test('notifies exactly 64 keyed subscribers without cloning or publishing the root snapshot', () => {
		// Arrange
		const store = createBridgeMainRenderSnapshotStore();
		expect(isReviewKeyedSubscriptionStore(store)).toBe(true);
		if (!isReviewKeyedSubscriptionStore(store)) {
			throw new Error('Expected the Review keyed subscription store contract.');
		}
		const keyedStore = store;
		for (let batchStartIndex = 0; batchStartIndex < REVIEW_ITEM_COUNT; batchStartIndex += 64) {
			applyReviewDisplayPatchEvent(
				store,
				makeReviewItemDisplayEvent({
					items: makeReviewDisplayItems({
						count: 64,
						identityRevision: 1,
						startIndex: batchStartIndex,
					}),
					projectionRevision: batchStartIndex / 64 + 1,
					startIndex: batchStartIndex,
				}),
			);
		}
		const notificationsByItemIndex = new Uint8Array(REVIEW_ITEM_COUNT);
		const unsubscribeCallbacks = Array.from({ length: REVIEW_ITEM_COUNT }, (_, itemIndex) =>
			keyedStore.subscribeReviewItem(reviewItemId(itemIndex), (): void => {
				notificationsByItemIndex[itemIndex] = (notificationsByItemIndex[itemIndex] ?? 0) + 1;
			}),
		);
		let rootNotificationCount = 0;
		const unsubscribeRoot = store.subscribe((): void => {
			rootNotificationCount += 1;
		});
		const rootSnapshotBeforePatch = store.getSnapshot();
		const untouchedItemBeforePatch = keyedStore.getReviewItemSnapshot(reviewItemId(2_048));

		// Act
		applyReviewDisplayPatchEvent(
			store,
			makeReviewItemDisplayEvent({
				items: makeReviewDisplayItems({
					count: REVIEW_PATCH_ITEM_COUNT,
					identityRevision: 2,
					startIndex: REVIEW_PATCH_START_INDEX,
				}),
				projectionRevision: REVIEW_ITEM_COUNT / 64 + 1,
				startIndex: REVIEW_PATCH_START_INDEX,
			}),
		);

		// Assert
		const touchedNotificationCount = notificationsByItemIndex
			.slice(REVIEW_PATCH_START_INDEX, REVIEW_PATCH_START_INDEX + REVIEW_PATCH_ITEM_COUNT)
			.reduce((total, notificationCount) => total + notificationCount, 0);
		const untouchedNotificationCount =
			notificationsByItemIndex.reduce((total, notificationCount) => total + notificationCount, 0) -
			touchedNotificationCount;
		expect(touchedNotificationCount).toBe(REVIEW_PATCH_ITEM_COUNT);
		expect(untouchedNotificationCount).toBe(0);
		expect(rootNotificationCount).toBe(0);
		expect(store.getSnapshot()).toBe(rootSnapshotBeforePatch);
		expect(keyedStore.getReviewItemSnapshot(reviewItemId(2_048))).toBe(untouchedItemBeforePatch);

		unsubscribeRoot();
		for (const unsubscribe of unsubscribeCallbacks) unsubscribe();
	});

	test('publishes an immutable catalog revision for later bounded item windows', () => {
		// Arrange
		const store = createBridgeMainRenderSnapshotStore();
		expect(isReviewKeyedSubscriptionStore(store)).toBe(true);
		if (!isReviewKeyedSubscriptionStore(store)) {
			throw new Error('Expected the Review catalog subscription store contract.');
		}
		applyReviewDisplayPatchEvent(
			store,
			makeReviewItemDisplayEvent({
				includeTreeRows: true,
				items: makeReviewDisplayItems({ count: 1, identityRevision: 1, startIndex: 0 }),
				projectionRevision: 1,
				startIndex: 0,
			}),
		);
		const firstCatalogSnapshot = store.getReviewCatalogSnapshot();
		let catalogNotificationCount = 0;
		let rootNotificationCount = 0;
		const unsubscribeCatalog = store.subscribeReviewCatalog((): void => {
			catalogNotificationCount += 1;
		});
		const unsubscribeRoot = store.subscribe((): void => {
			rootNotificationCount += 1;
		});

		// Act
		applyReviewDisplayPatchEvent(
			store,
			makeReviewItemDisplayEvent({
				includeTreeRows: true,
				items: makeReviewDisplayItems({ count: 1, identityRevision: 2, startIndex: 64 }),
				projectionRevision: 2,
				startIndex: 64,
			}),
		);
		const secondCatalogSnapshot = store.getReviewCatalogSnapshot();

		// Assert
		expect(catalogNotificationCount).toBe(1);
		expect(rootNotificationCount).toBe(0);
		expect(secondCatalogSnapshot).not.toBe(firstCatalogSnapshot);
		expect(firstCatalogSnapshot).toEqual({
			changeCursor: 1,
			epoch: 1,
			itemOrderLength: 1,
			revision: 1,
			treeRowOrderLength: 1,
		});
		expect(secondCatalogSnapshot).toEqual({
			changeCursor: 2,
			epoch: 1,
			itemOrderLength: 65,
			revision: 2,
			treeRowOrderLength: 65,
		});
		expect(store.getReviewItemIdAtIndex(64)).toBe(reviewItemId(64));
		expect(store.getReviewTreeRowAtIndex(64)).toMatchObject({
			itemId: reviewItemId(64),
			path: `${reviewItemId(64)}.ts`,
		});

		unsubscribeCatalog();
		unsubscribeRoot();
	});

	test('publishes only the keyed CodeView and availability subscribers for an item', () => {
		// Arrange
		const store = createBridgeMainRenderSnapshotStore();
		expect(isReviewKeyedSubscriptionStore(store)).toBe(true);
		if (!isReviewKeyedSubscriptionStore(store)) {
			throw new Error('Expected the Review keyed render subscription store contract.');
		}
		const targetItemId = reviewItemId(1);
		const untouchedItemId = reviewItemId(2);
		let targetCodeViewNotificationCount = 0;
		let untouchedCodeViewNotificationCount = 0;
		let targetAvailabilityNotificationCount = 0;
		let untouchedAvailabilityNotificationCount = 0;
		const unsubscribers = [
			store.subscribeReviewCodeViewItem(targetItemId, (): void => {
				targetCodeViewNotificationCount += 1;
			}),
			store.subscribeReviewCodeViewItem(untouchedItemId, (): void => {
				untouchedCodeViewNotificationCount += 1;
			}),
			store.subscribeReviewAvailability(targetItemId, (): void => {
				targetAvailabilityNotificationCount += 1;
			}),
			store.subscribeReviewAvailability(untouchedItemId, (): void => {
				untouchedAvailabilityNotificationCount += 1;
			}),
		];
		const codeViewItem = makeReviewCodeViewItem(targetItemId);

		// Act
		store.setWorkerCodeViewItem({ item: codeViewItem, itemId: targetItemId });
		store.applyWorkerPatch({
			itemId: targetItemId,
			operation: 'upsert',
			payload: { state: 'ready' },
			slice: 'contentAvailability',
		});

		// Assert
		expect(targetCodeViewNotificationCount).toBe(1);
		expect(untouchedCodeViewNotificationCount).toBe(0);
		expect(targetAvailabilityNotificationCount).toBe(1);
		expect(untouchedAvailabilityNotificationCount).toBe(0);
		expect(store.getReviewCodeViewItemSnapshot(targetItemId)).toBe(codeViewItem);
		expect(store.getReviewAvailabilitySnapshot(targetItemId)).toEqual({ state: 'ready' });

		for (const unsubscribe of unsubscribers) unsubscribe();
	});

	test('publishes bounded keyed catalog changes without repeating existing catalog keys', () => {
		// Arrange
		const store = createBridgeMainRenderSnapshotStore();
		applyReviewDisplayPatchEvent(
			store,
			makeReviewItemDisplayEvent({
				includeTreeRows: true,
				items: makeReviewDisplayItems({ count: 64, identityRevision: 1, startIndex: 0 }),
				projectionRevision: 1,
				startIndex: 0,
			}),
		);
		const initialCursor = store.getReviewCatalogSnapshot().changeCursor;

		// Act
		applyReviewDisplayPatchEvent(
			store,
			makeReviewItemDisplayEvent({
				includeTreeRows: true,
				items: makeReviewDisplayItems({
					count: REVIEW_PATCH_ITEM_COUNT,
					identityRevision: 2,
					startIndex: REVIEW_PATCH_START_INDEX,
				}),
				projectionRevision: 2,
				startIndex: REVIEW_PATCH_START_INDEX,
			}),
		);
		const result = store.readReviewCatalogChangesAfter(initialCursor);

		// Assert
		expect(result.resetRequired).toBe(false);
		expect(result.changes).toHaveLength(1);
		expect(result.changes[0]).toMatchObject({
			itemIds: Array.from({ length: REVIEW_PATCH_ITEM_COUNT }, (_, itemOffset) =>
				reviewItemId(REVIEW_PATCH_START_INDEX + itemOffset),
			),
			itemOrderMutations: [
				{
					kind: 'setRange',
					length: REVIEW_PATCH_ITEM_COUNT,
					startIndex: REVIEW_PATCH_START_INDEX,
				},
			],
			reset: false,
			treeRowIds: Array.from(
				{ length: REVIEW_PATCH_ITEM_COUNT },
				(_, itemOffset) => `row-${reviewItemId(REVIEW_PATCH_START_INDEX + itemOffset)}`,
			),
			treeRowOrderMutations: [
				{
					kind: 'setRange',
					length: REVIEW_PATCH_ITEM_COUNT,
					startIndex: REVIEW_PATCH_START_INDEX,
				},
			],
		});
	});
});

function makeReviewItemDisplayEvent(props: {
	readonly includeTreeRows?: boolean;
	readonly items: readonly unknown[];
	readonly projectionRevision: number;
	readonly startIndex: number;
}): unknown {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'batch',
				payload: {
					items: props.items,
					operations: [],
					removedItemIds: [],
					replacementOrder: null,
					reset: false,
					startIndex: props.startIndex,
				},
				slice: 'reviewItem',
			},
			...(props.includeTreeRows === true
				? [
						{
							operation: 'batch',
							payload: {
								reset: false,
								windows: [
									{
										rows: props.items.map((_item, itemOffset) => {
											const itemId = reviewItemId(props.startIndex + itemOffset);
											return {
												depth: 0,
												isDirectory: false,
												itemId,
												path: `${itemId}.ts`,
												rowId: `row-${itemId}`,
											};
										}),
										startIndex: props.startIndex,
									},
								],
							},
							slice: 'reviewTree',
						},
					]
				: []),
		],
		projectionRevision: props.projectionRevision,
		sequence: props.projectionRevision,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function makeReviewDisplayItems(props: {
	readonly count: number;
	readonly identityRevision: number;
	readonly startIndex: number;
}): readonly unknown[] {
	return Array.from({ length: props.count }, (_, itemOffset) => {
		const itemIndex = props.startIndex + itemOffset;
		return {
			contentFacts: [
				{
					contentDigest: {
						algorithm: 'sha256',
						authority: 'authoritative',
						value: 'a'.repeat(64),
					},
					role: 'head',
					semanticDocumentRevision: `semantic-review-${itemIndex}`,
				},
			],
			extentFacts: [],
			metadata: { itemId: reviewItemId(itemIndex) },
			metadataWindowIdentity: `metadata-window-${itemIndex}-r${props.identityRevision}`,
		};
	});
}

function reviewItemId(itemIndex: number): string {
	return `review-item-${itemIndex.toString().padStart(4, '0')}`;
}

function makeReviewCodeViewItem(itemId: string): BridgeMainCodeViewItem {
	return {
		bridgeMetadata: {
			cacheKey: `pierre-content:${itemId}`,
			contentRoles: ['head'],
			contentState: 'hydrated',
			displayPath: `${itemId}.ts`,
			itemId,
			lineCount: 1,
		},
		file: {
			cacheKey: `pierre-content:${itemId}`,
			contents: 'export {};',
			name: `${itemId}.ts`,
		},
		id: itemId,
		type: 'file',
	};
}

function isReviewKeyedSubscriptionStore(
	value: unknown,
): value is ReviewKeyedSubscriptionStoreContract {
	return (
		isReadonlyRecord(value) &&
		typeof value['getReviewAvailabilitySnapshot'] === 'function' &&
		typeof value['getReviewCatalogSnapshot'] === 'function' &&
		typeof value['getReviewCodeViewItemSnapshot'] === 'function' &&
		typeof value['getReviewItemIdAtIndex'] === 'function' &&
		typeof value['getReviewItemSnapshot'] === 'function' &&
		typeof value['getReviewTreeRowAtIndex'] === 'function' &&
		typeof value['subscribeReviewAvailability'] === 'function' &&
		typeof value['subscribeReviewCatalog'] === 'function' &&
		typeof value['subscribeReviewCodeViewItem'] === 'function' &&
		typeof value['subscribeReviewItem'] === 'function'
	);
}

function applyReviewDisplayPatchEvent(store: unknown, event: unknown): void {
	if (!isReadonlyRecord(store) || typeof store['applyReviewDisplayPatchEvent'] !== 'function') {
		throw new Error('Expected a Review display patch store.');
	}
	store['applyReviewDisplayPatchEvent'](event);
}

function isReadonlyRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null;
}
