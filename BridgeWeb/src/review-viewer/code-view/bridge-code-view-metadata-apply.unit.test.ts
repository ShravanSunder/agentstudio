import { describe, expect, test } from 'vitest';

import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import { bridgeContentDemandExecutionPolicy } from '../../core/demand/bridge-content-demand-policy.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { createBridgeCodeViewInitialItemsForPanelSelector } from './bridge-code-view-initial-items-selector.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import { runBridgeCodeViewMetadataApplyInChunks } from './bridge-code-view-metadata-apply.js';
import {
	bridgeCodeViewInitialSeedItemIdsForPanel,
	bridgeCodeViewLoadingPlaceholderMatchesDescriptor,
	createBridgeCodeViewInitialItemsForPanel,
	makeBridgeCodeViewSourceKey,
} from './bridge-code-view-panel-support.js';
import {
	createBridgeCodeViewMetadataDeltaItemsForPanel,
	createBridgeCodeViewMetadataDeltaItemsForPanelSelector,
} from './bridge-code-view-worker-prepared-items.js';

describe('Bridge CodeView metadata apply pump', () => {
	test('seeds the complete ordered projection when continuous Review has no narrow seed', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const continuousItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});

		expect(continuousItems.map((item) => item.id)).toEqual(projection.orderedItemIds);
	});

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

	test('keeps initial CodeView reset items stable across same-source package clones', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected projection fixture item');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const sourceKey = makeBridgeCodeViewSourceKey({
			presentationPositionKey: 'metadata-apply-position',
			projection,
			reviewPackage,
		});
		const selector = createBridgeCodeViewInitialItemsForPanelSelector();
		const seedItemIds = ['source-high', 'docs-plan'];

		const firstItems = selector({
			projection,
			reviewPackage,
			seedItemIds,
			sourceKey,
		});
		const clonedReviewPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				[sourceItem.itemId]: {
					...sourceItem,
					cacheKey: `${sourceItem.cacheKey}:metadata-retouch`,
					itemVersion: sourceItem.itemVersion + 1,
				},
			},
			revision: reviewPackage.revision + 1,
		};
		const clonedProjection = { ...projection };
		const clonedSourceKey = makeBridgeCodeViewSourceKey({
			presentationPositionKey: 'metadata-apply-position',
			projection: clonedProjection,
			reviewPackage: clonedReviewPackage,
		});
		const secondItems = selector({
			projection: clonedProjection,
			reviewPackage: clonedReviewPackage,
			seedItemIds,
			sourceKey: clonedSourceKey,
		});
		const changedItems = selector({
			projection,
			reviewPackage,
			seedItemIds: ['source-high'],
			sourceKey,
		});

		expect(clonedSourceKey).toBe(sourceKey);
		expect(secondItems).toBe(firstItems);
		expect(changedItems).not.toBe(firstItems);
	});

	test('refreshes initial CodeView reset items without fabricating placeholder body geometry', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected projection fixture item');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const sourceKey = makeBridgeCodeViewSourceKey({
			presentationPositionKey: 'metadata-apply-position',
			projection,
			reviewPackage,
		});
		const selector = createBridgeCodeViewInitialItemsForPanelSelector();

		const firstItems = selector({
			projection,
			reviewPackage,
			seedItemIds: [sourceItem.itemId],
			sourceKey,
		});
		const changedReviewPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				[sourceItem.itemId]: {
					...sourceItem,
					contentLineCountsByRole: {
						...sourceItem.contentLineCountsByRole,
						head: (sourceItem.contentLineCountsByRole?.head ?? sourceItem.additions) + 7,
					},
					headPath: 'src/renamed-source.ts',
				},
			},
			revision: reviewPackage.revision + 1,
		};
		const secondItems = selector({
			projection: { ...projection },
			reviewPackage: changedReviewPackage,
			seedItemIds: [sourceItem.itemId],
			sourceKey,
		});

		expect(secondItems).not.toBe(firstItems);
		expect(secondItems[0]?.bridgeMetadata.displayPath).toBe('src/renamed-source.ts');
		expect(secondItems[0]?.bridgeMetadata.lineCount).toBe(0);
		expect(firstItems[0]?.bridgeMetadata.lineCount).toBe(0);
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

	test('invalidates the metadata selector when selected loading starts without a presentation', () => {
		// Arrange
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected fixture item');
		}
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();
		const sourceKey = makeBridgeCodeViewSourceKey({
			presentationPositionKey: 'metadata-apply-position',
			projection: buildBridgeReviewProjection({
				reviewPackage,
				request: { mode: { kind: 'normalReview' }, facets: [] },
			}),
			reviewPackage,
		});
		const beforeLoading = selector({
			reviewPackage,
			selectedCodeViewItem: null,
			selectedContentLoadingItemId: null,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey,
			visibleCodeViewItems: [],
		});

		// Act
		const afterLoading = selector({
			reviewPackage,
			selectedCodeViewItem: null,
			selectedContentLoadingItemId: sourceItem.itemId,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey,
			visibleCodeViewItems: [],
		});

		// Assert
		expect(beforeLoading).toEqual([]);
		expect(afterLoading).not.toBe(beforeLoading);
		expect(afterLoading).toHaveLength(1);
		expect(afterLoading[0]?.id).toBe(sourceItem.itemId);
		expect(afterLoading[0]?.bridgeMetadata.contentState).toBe('loading');
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

	test('preserves worker-prepared diff payload identity in visible metadata deltas', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected fixture item');
		}
		const visibleCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem),
		);
		if (visibleCodeViewItem.type !== 'diff') {
			throw new Error('expected fixture diff item');
		}

		const deltaItems = createBridgeCodeViewMetadataDeltaItemsForPanel({
			reviewPackage,
			selectedCodeViewItem: null,
			selectedItemId: null,
			selectedItemPresentation: null,
			visibleCodeViewItems: [visibleCodeViewItem],
		});
		const deltaItem = deltaItems[0];
		if (deltaItem?.type !== 'diff') {
			throw new Error('expected visible diff delta item');
		}

		expect(deltaItem).toBe(visibleCodeViewItem);
		expect(deltaItem.fileDiff.hunks).toBe(visibleCodeViewItem.fileDiff.hunks);
		expect(deltaItem.fileDiff.additionLines).toBe(visibleCodeViewItem.fileDiff.additionLines);
		expect(deltaItem.fileDiff.deletionLines).toBe(visibleCodeViewItem.fileDiff.deletionLines);
	});

	test('keeps metadata deltas stable across same-source package clones', () => {
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
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();

		const firstItems = selector({
			reviewPackage,
			selectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey: 'source-a',
			visibleCodeViewItems: [visibleCodeViewItem],
		});
		const clonedReviewPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				[sourceItem.itemId]: {
					...sourceItem,
					cacheKey: `${sourceItem.cacheKey}:metadata-retouch`,
					itemVersion: sourceItem.itemVersion + 1,
				},
			},
			revision: reviewPackage.revision + 1,
		};
		const secondItems = selector({
			reviewPackage: clonedReviewPackage,
			selectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey: 'source-a',
			visibleCodeViewItems: [visibleCodeViewItem],
		});
		const changedItems = selector({
			reviewPackage,
			selectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: { kind: 'file', version: 'current' },
			sourceKey: 'source-a',
			visibleCodeViewItems: [visibleCodeViewItem],
		});

		expect(secondItems).toBe(firstItems);
		expect(changedItems).not.toBe(firstItems);
	});

	test('refreshes selected metadata loading delta without fabricating body geometry', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected projection fixture item');
		}
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();

		const firstItems = selector({
			reviewPackage,
			selectedCodeViewItem: null,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: { kind: 'file', version: 'current' },
			sourceKey: 'source-a',
			visibleCodeViewItems: [],
		});
		const changedReviewPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				[sourceItem.itemId]: {
					...sourceItem,
					contentLineCountsByRole: {
						...sourceItem.contentLineCountsByRole,
						head: (sourceItem.contentLineCountsByRole?.head ?? sourceItem.additions) + 7,
					},
					headPath: 'src/renamed-source.ts',
				},
			},
			revision: reviewPackage.revision + 1,
		};
		const secondItems = selector({
			reviewPackage: changedReviewPackage,
			selectedCodeViewItem: null,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: { kind: 'file', version: 'current' },
			sourceKey: 'source-a',
			visibleCodeViewItems: [],
		});

		expect(secondItems).not.toBe(firstItems);
		expect(secondItems[0]?.bridgeMetadata.displayPath).toBe('src/renamed-source.ts');
		expect(secondItems[0]?.bridgeMetadata.lineCount).toBe(0);
	});

	test('keeps selected loading placeholder stable across descriptor metadata retouches', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const loadingItem = materializeBridgeCodeViewLoadingItem(sourceItem);
		const retouchedDescriptor = {
			...sourceItem,
			cacheKey: `${sourceItem.cacheKey}:metadata-retouch`,
			itemVersion: sourceItem.itemVersion + 1,
		};
		const retouchedLoadingItem = materializeBridgeCodeViewLoadingItem(retouchedDescriptor);

		expect(
			bridgeCodeViewLoadingPlaceholderMatchesDescriptor({
				existingItem: loadingItem,
				loadingItem: retouchedLoadingItem,
			}),
		).toBe(true);
	});

	test('refreshes selected loading placeholder when descriptor shape changes', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const loadingItem = materializeBridgeCodeViewLoadingItem(sourceItem);
		const shapeChangedDescriptor = {
			...sourceItem,
			contentLineCountsByRole: {
				...sourceItem.contentLineCountsByRole,
				head: (sourceItem.contentLineCountsByRole?.head ?? sourceItem.additions) + 7,
			},
			headPath: 'src/renamed-source.ts',
		};
		const shapeChangedLoadingItem = materializeBridgeCodeViewLoadingItem(shapeChangedDescriptor);

		expect(
			bridgeCodeViewLoadingPlaceholderMatchesDescriptor({
				existingItem: loadingItem,
				loadingItem: shapeChangedLoadingItem,
			}),
		).toBe(false);
	});

	test('normalizes worker-prepared diff language without rebuilding payload arrays', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected fixture item');
		}
		const visibleCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem),
		);
		if (visibleCodeViewItem.type !== 'diff') {
			throw new Error('expected fixture diff item');
		}
		const visibleCodeViewItemWithLanguageVariant = {
			...visibleCodeViewItem,
			fileDiff: {
				...visibleCodeViewItem.fileDiff,
				lang: ' TypeScript ',
			},
		};

		const deltaItems = createBridgeCodeViewMetadataDeltaItemsForPanel({
			reviewPackage,
			selectedCodeViewItem: null,
			selectedItemId: null,
			selectedItemPresentation: null,
			visibleCodeViewItems: [visibleCodeViewItemWithLanguageVariant],
		});
		const deltaItem = deltaItems[0];
		if (deltaItem?.type !== 'diff') {
			throw new Error('expected visible diff delta item');
		}

		expect(deltaItem).not.toBe(visibleCodeViewItemWithLanguageVariant);
		expect(deltaItem.fileDiff).not.toBe(visibleCodeViewItemWithLanguageVariant.fileDiff);
		expect(deltaItem.fileDiff.lang).toBe('typescript');
		expect(visibleCodeViewItemWithLanguageVariant.fileDiff.lang).toBe(' TypeScript ');
		expect(deltaItem.fileDiff.hunks).toBe(visibleCodeViewItem.fileDiff.hunks);
		expect(deltaItem.fileDiff.additionLines).toBe(visibleCodeViewItem.fileDiff.additionLines);
		expect(deltaItem.fileDiff.deletionLines).toBe(visibleCodeViewItem.fileDiff.deletionLines);
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

	test('prioritizes selected metadata without replacing the mounted manifest', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const entries = ['source-high', 'docs-plan'].map((itemId): BridgeCodeViewItem => {
			const item = reviewPackage.itemsById[itemId];
			if (item === undefined) {
				throw new Error(`expected fixture item ${itemId}`);
			}
			return materializeBridgeCodeViewLoadingItem(item);
		});
		const selectedItem = entries[0];
		const visibleItem = entries[1];
		if (selectedItem === undefined || visibleItem === undefined) {
			throw new Error('expected source-reset entries');
		}
		const appliedItemIds: string[] = [];
		const scheduledTurns: Array<() => void> = [];
		const setItemsCalls: Array<readonly BridgeCodeViewItem[]> = [];

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
				item.id === selectedItem.id ? 'selected' : 'visible',
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			setItems: (items): void => {
				setItemsCalls.push(items);
			},
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		expect(setItemsCalls).toEqual([]);
		expect(appliedItemIds).toEqual([]);
		expect(scheduledTurns).toHaveLength(1);

		scheduledTurns.shift()?.();

		expect(appliedItemIds).toEqual([selectedItem.id, visibleItem.id, 'drained']);
	});

	test('preserves the mounted continuous manifest while source-reset metadata is applied', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const entries = ['source-high', 'docs-plan'].map((itemId): BridgeCodeViewItem => {
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
				throw new Error('source-reset metadata must not replace the mounted continuous manifest');
			},
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		expect(scheduledTurns).toHaveLength(1);
		scheduledTurns.shift()?.();
		expect(appliedItemIds).toEqual([...entries.map((item) => item.id), 'drained']);
	});

	test('skips unchanged selected metadata while continuing visible metadata', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const entries = ['source-high', 'docs-plan'].map((itemId): BridgeCodeViewItem => {
			const item = reviewPackage.itemsById[itemId];
			if (item === undefined) {
				throw new Error(`expected fixture item ${itemId}`);
			}
			return materializeBridgeCodeViewLoadingItem(item);
		});
		const selectedItem = entries[0];
		const visibleItem = entries[1];
		if (selectedItem === undefined || visibleItem === undefined) {
			throw new Error('expected source-reset entries');
		}
		const appliedItemIds: string[] = [];
		const scheduledTurns: Array<() => void> = [];
		const setItemsCalls: Array<readonly BridgeCodeViewItem[]> = [];

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
				item.id === selectedItem.id ? 'selected' : 'visible',
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			setItems: (items): void => {
				setItemsCalls.push(items);
			},
			shouldSkipItem: (item): boolean => item === selectedItem,
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		expect(setItemsCalls).toEqual([]);
		expect(appliedItemIds).toEqual([]);
		expect(scheduledTurns).toHaveLength(1);

		scheduledTurns.shift()?.();

		expect(appliedItemIds).toEqual([visibleItem.id, 'drained']);
	});

	test('keeps the mounted manifest when metadata has no selected item', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const entries = ['source-high', 'docs-plan'].map((itemId): BridgeCodeViewItem => {
			const item = reviewPackage.itemsById[itemId];
			if (item === undefined) {
				throw new Error(`expected fixture item ${itemId}`);
			}
			return materializeBridgeCodeViewLoadingItem(item);
		});
		const setItemsCalls: Array<readonly BridgeCodeViewItem[]> = [];
		const scheduledTurns: Array<() => void> = [];

		runBridgeCodeViewMetadataApplyInChunks({
			applyItemUpdate: (): void => {},
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => false,
			items: entries,
			maxUnitsPerFrame: bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onComplete: (): void => {},
			rankForItem: (): 'visible' => 'visible',
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			setItems: (items): void => {
				setItemsCalls.push(items);
			},
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		expect(setItemsCalls).toEqual([]);
		expect(scheduledTurns).toHaveLength(1);
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
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		scheduledTurns.shift()?.();

		expect(appliedItemIds).toEqual([changedItem.id, 'drained']);
		expect(scheduledTurns).toHaveLength(0);
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
