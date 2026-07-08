import { describe, expect, test } from 'vitest';

import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import { bridgeContentDemandExecutionPolicy } from '../../core/demand/bridge-content-demand-policy.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import { runBridgeCodeViewMetadataApplyInChunks } from './bridge-code-view-metadata-apply.js';
import {
	bridgeCodeViewInitialSeedItemIdsForPanel,
	createBridgeCodeViewInitialItemsForPanel,
} from './bridge-code-view-panel-support.js';
import { createBridgeCodeViewMetadataDeltaItemsForPanel } from './bridge-code-view-worker-prepared-items.js';

describe('Bridge CodeView metadata apply pump', () => {
	test('builds non-reset metadata deltas from selected and visible worker-prepared items only', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		const visibleItem = reviewPackage.itemsById['docs-plan'];
		if (sourceItem === undefined || visibleItem === undefined) {
			throw new Error('expected projection fixture items');
		}
		const selectedCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem),
		);
		const visibleCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(visibleItem),
		);
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const deltaItems = createBridgeCodeViewMetadataDeltaItemsForPanel({
			reviewPackage,
			selectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			visibleCodeViewItems: [visibleCodeViewItem],
		});
		const sourceResetItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
			seedItemIds: deltaItems.map((item) => item.id),
		});

		expect(sourceResetItems.map((item) => item.id).toSorted()).toEqual(
			[sourceItem.itemId, visibleItem.itemId].toSorted(),
		);
		expect(deltaItems.map((item) => item.id).toSorted()).toEqual(
			[sourceItem.itemId, visibleItem.itemId].toSorted(),
		);
	});

	test('dedupes selected seed and skips visible items without matching worker metadata', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		const visibleItem = reviewPackage.itemsById['docs-plan'];
		if (sourceItem === undefined || visibleItem === undefined) {
			throw new Error('expected projection fixture items');
		}
		const visibleSelectedCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem),
		);
		const mismatchedVisibleCodeViewItem = {
			...workerPreparedCodeViewItem(materializeBridgeCodeViewLoadingItem(visibleItem)),
			bridgeMetadata: {
				...visibleSelectedCodeViewItem.bridgeMetadata,
				itemId: sourceItem.itemId,
			},
		};

		const seedItemIds = bridgeCodeViewInitialSeedItemIdsForPanel({
			selectedItemId: sourceItem.itemId,
			visibleCodeViewItems: [visibleSelectedCodeViewItem, mismatchedVisibleCodeViewItem],
		});

		expect(seedItemIds).toEqual([sourceItem.itemId]);
	});

	test('keeps selected source-reset seed first when visible items precede it in projection order', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const sourceResetItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
			seedItemIds: ['docs-plan', 'source-high'],
		});

		expect(sourceResetItems.map((item) => item.id)).toEqual(['docs-plan', 'source-high']);
		expect(sourceResetItems).toHaveLength(2);
	});

	test('does not scan projection order when source-reset seed ids are provided', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const projectionWithThrowingOrder = {
			...projection,
			get orderedItemIds(): readonly string[] {
				throw new Error('seeded source reset must not scan full projection order');
			},
		} satisfies typeof projection;

		const sourceResetItems = createBridgeCodeViewInitialItemsForPanel({
			projection: projectionWithThrowingOrder,
			reviewPackage,
			seedItemIds: ['docs-plan', 'source-high'],
		});

		expect(sourceResetItems.map((item) => item.id)).toEqual(['docs-plan', 'source-high']);
	});

	test('includes selected presentation changes in non-reset metadata deltas', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected fixture item');
		}

		const deltaItems = createBridgeCodeViewMetadataDeltaItemsForPanel({
			reviewPackage,
			selectedCodeViewItem: null,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: { kind: 'file', version: 'current' },
			visibleCodeViewItems: [],
		});

		expect(deltaItems).toHaveLength(1);
		expect(deltaItems[0]?.id).toBe(sourceItem.itemId);
		expect(deltaItems[0]?.type).toBe('file');
		expect(deltaItems[0]?.bridgeMetadata.contentState).toBe('loading');
	});

	test('replaces stale selected worker item with requested presentation loading delta', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected fixture item');
		}
		const selectedCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem, {
				kind: 'file',
				version: 'head',
			}),
		);
		const baseSelectedCodeViewItem = {
			...selectedCodeViewItem,
			bridgeMetadata: {
				...selectedCodeViewItem.bridgeMetadata,
				contentRoles: ['head' as const],
			},
		};

		const deltaItems = createBridgeCodeViewMetadataDeltaItemsForPanel({
			reviewPackage,
			selectedCodeViewItem: baseSelectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: { kind: 'file', version: 'base' },
			visibleCodeViewItems: [],
		});

		expect(deltaItems).toHaveLength(1);
		expect(deltaItems[0]?.id).toBe(sourceItem.itemId);
		expect(deltaItems[0]?.type).toBe('file');
		expect(deltaItems[0]?.bridgeMetadata.contentState).toBe('loading');
		expect(deltaItems[0]?.bridgeMetadata.contentRoles).toEqual([]);
	});

	test('keeps visible selected worker item instead of synthesizing loading presentation delta', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected fixture item');
		}
		const visibleSelectedCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem, {
				kind: 'file',
				version: 'head',
			}),
		);
		const visibleSelectedHeadCodeViewItem = {
			...visibleSelectedCodeViewItem,
			bridgeMetadata: {
				...visibleSelectedCodeViewItem.bridgeMetadata,
				contentRoles: ['head' as const],
			},
		};

		const deltaItems = createBridgeCodeViewMetadataDeltaItemsForPanel({
			reviewPackage,
			selectedCodeViewItem: null,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: { kind: 'file', version: 'head' },
			visibleCodeViewItems: [visibleSelectedHeadCodeViewItem],
		});

		expect(deltaItems).toEqual([visibleSelectedHeadCodeViewItem]);
		expect(deltaItems[0]?.bridgeMetadata.contentState).toBe('hydrated');
	});

	test('keeps one-sided diff worker item for file-targeted selected presentation', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const deletedSourceItem = reviewPackage.itemsById['deleted-source'];
		if (deletedSourceItem === undefined) {
			throw new Error('expected deleted fixture item');
		}
		const hydratedDeletedSourceItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(deletedSourceItem, {
				kind: 'file',
				version: 'base',
			}),
		);
		const selectedCodeViewItem = {
			...hydratedDeletedSourceItem,
			bridgeMetadata: {
				...hydratedDeletedSourceItem.bridgeMetadata,
				contentRoles: ['base' as const],
			},
		};

		const deltaItems = createBridgeCodeViewMetadataDeltaItemsForPanel({
			reviewPackage,
			selectedCodeViewItem,
			selectedItemId: deletedSourceItem.itemId,
			selectedItemPresentation: { kind: 'file', version: 'base' },
			visibleCodeViewItems: [],
		});

		expect(deltaItems).toEqual([selectedCodeViewItem]);
		expect(deltaItems[0]?.type).toBe('diff');
		expect(deltaItems[0]?.bridgeMetadata.contentState).toBe('hydrated');
	});

	test('schedules non-reset metadata apply across policy-bounded turns', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const entries = reviewPackage.orderedItemIds
			.slice(0, bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame + 1)
			.map((itemId): BridgeCodeViewItem => {
				const item = reviewPackage.itemsById[itemId];
				if (item === undefined) {
					throw new Error(`expected fixture item ${itemId}`);
				}
				return materializeBridgeCodeViewLoadingItem(item);
			});
		const appliedItemIds: string[] = [];
		const scheduledTurns: Array<() => void> = [];

		runBridgeCodeViewMetadataApplyInChunks({
			applyItemUpdate: (item): void => {
				appliedItemIds.push(item.id);
			},
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => false,
			items: entries,
			maxUnitsPerFrame: bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onComplete: (): void => {
				appliedItemIds.push('drained');
			},
			rankForItem: (item): 'selected' | 'visible' =>
				item.id === entries[0]?.id ? 'selected' : 'visible',
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			setItems: (): void => {
				throw new Error('source reset setItems must not run for non-reset metadata apply');
			},
			sourceReset: false,
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		expect(appliedItemIds).toEqual([]);
		expect(scheduledTurns).toHaveLength(1);
		scheduledTurns.shift()?.();
		expect(appliedItemIds).toHaveLength(
			bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
		);
		expect(appliedItemIds).not.toContain('drained');
		scheduledTurns.shift()?.();
		expect(appliedItemIds).toEqual([...entries.map((item) => item.id), 'drained']);
	});

	test('skips unchanged reconciled item references before apply work', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const entries = reviewPackage.orderedItemIds.slice(0, 2).map((itemId): BridgeCodeViewItem => {
			const item = reviewPackage.itemsById[itemId];
			if (item === undefined) {
				throw new Error(`expected fixture item ${itemId}`);
			}
			return materializeBridgeCodeViewLoadingItem(item);
		});
		const unchangedItem = entries[0];
		const changedItem = entries[1];
		if (unchangedItem === undefined || changedItem === undefined) {
			throw new Error('expected fixture apply entries');
		}
		const appliedItemIds: string[] = [];
		const scheduledTurns: Array<() => void> = [];

		runBridgeCodeViewMetadataApplyInChunks({
			applyItemUpdate: (item): void => {
				appliedItemIds.push(item.id);
			},
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => false,
			items: entries,
			maxUnitsPerFrame: bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onComplete: (): void => {
				appliedItemIds.push('drained');
			},
			rankForItem: (): 'visible' => 'visible',
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			setItems: (): void => {
				throw new Error('source reset setItems must not run for non-reset metadata apply');
			},
			shouldSkipItem: (item): boolean => item === unchangedItem,
			sourceReset: false,
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		scheduledTurns.shift()?.();

		expect(appliedItemIds).toEqual([changedItem.id, 'drained']);
	});

	test('does not spend apply slots on skipped unchanged items', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const entries = reviewPackage.orderedItemIds
			.slice(0, bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame + 1)
			.map((itemId): BridgeCodeViewItem => {
				const item = reviewPackage.itemsById[itemId];
				if (item === undefined) {
					throw new Error(`expected fixture item ${itemId}`);
				}
				return materializeBridgeCodeViewLoadingItem(item);
			});
		const changedItem = entries.at(-1);
		if (changedItem === undefined) {
			throw new Error('expected changed fixture item');
		}
		const appliedItemIds: string[] = [];
		const scheduledTurns: Array<() => void> = [];

		runBridgeCodeViewMetadataApplyInChunks({
			applyItemUpdate: (item): void => {
				appliedItemIds.push(item.id);
			},
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => false,
			items: entries,
			maxUnitsPerFrame: bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onComplete: (): void => {
				appliedItemIds.push('drained');
			},
			rankForItem: (): 'visible' => 'visible',
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			setItems: (): void => {
				throw new Error('source reset setItems must not run for non-reset metadata apply');
			},
			shouldSkipItem: (item): boolean => item !== changedItem,
			sourceReset: false,
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		scheduledTurns.shift()?.();

		expect(appliedItemIds).toEqual([changedItem.id, 'drained']);
		expect(scheduledTurns).toHaveLength(0);
	});

	test('uses setItems replacement for non-reset metadata items that cannot update in place', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const filePresentationItem = materializeBridgeCodeViewLoadingItem(sourceItem, {
			kind: 'file',
			version: 'head',
		});
		const scheduledTurns: Array<() => void> = [];
		const appliedItemIds: string[] = [];
		const setItemsCalls: Array<readonly BridgeCodeViewItem[]> = [];

		runBridgeCodeViewMetadataApplyInChunks({
			applyItemUpdate: (item): void => {
				appliedItemIds.push(item.id);
			},
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => false,
			items: [filePresentationItem],
			maxUnitsPerFrame: bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onComplete: (): void => {},
			rankForItem: (): 'selected' => 'selected',
			replacementItemsForItem: (): readonly BridgeCodeViewItem[] => [filePresentationItem],
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			setItems: (items): void => {
				setItemsCalls.push(items);
			},
			sourceReset: false,
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		expect(appliedItemIds).toEqual([]);
		expect(setItemsCalls).toEqual([]);
		scheduledTurns.shift()?.();
		expect(appliedItemIds).toEqual([]);
		expect(setItemsCalls).toEqual([[filePresentationItem]]);
	});
});

function workerPreparedCodeViewItem(item: BridgeCodeViewItem): BridgeMainCodeViewItem {
	return {
		...item,
		bridgeMetadata: {
			...item.bridgeMetadata,
			contentState: 'hydrated',
		},
		version: (item.version ?? 0) + 1,
	} satisfies BridgeMainCodeViewItem;
}
