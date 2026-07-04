import { describe, expect, test } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import {
	createVisibleReviewContentHydrationResult,
	makeReviewItemContentResourcesKey,
	normalizeVisibleReviewItemIds,
	recoverAbortedVisibleContentLoadState,
	selectedAdjacentReviewItemIds,
	shouldAbortVisibleContentLoadsForPause,
	shouldRearmAbortedVisibleContentLoad,
	visibleContentHydrationDispatchDelayMilliseconds,
	visibleContentHydrationConcurrentLoadLimit,
	visibleContentHydrationItemLimit,
	visibleReviewContentLoadPlanCount,
} from './visible-review-content-hydration.js';

describe('visible review content hydration', () => {
	test('bounds opportunistic visible content warming around the selected item', () => {
		const reviewPackage = makeReviewPackageWithItemCount(40);
		const selectedItemId = 'item-020';

		const normalizedItemIds = normalizeVisibleReviewItemIds({
			itemIds: reviewPackage.orderedItemIds,
			reviewPackage,
			selectedItemId,
		});

		expect(normalizedItemIds).toHaveLength(visibleContentHydrationItemLimit);
		expect(normalizedItemIds).not.toContain(selectedItemId);
		expect(normalizedItemIds.slice(0, 4)).toEqual(['item-018', 'item-019', 'item-021', 'item-022']);
		expect(
			selectedAdjacentReviewItemIds({
				reviewPackage,
				selectedItemId,
			}),
		).toEqual(['item-018', 'item-019', 'item-021', 'item-022']);
	});

	test('keeps visible content warming opportunistic under active visible loads', () => {
		expect(visibleContentHydrationDispatchDelayMilliseconds).toBeGreaterThanOrEqual(32);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: 0,
				requestedLoadCount: visibleContentHydrationItemLimit,
				scheduledCount: 0,
			}),
		).toBe(visibleContentHydrationConcurrentLoadLimit);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: 1,
				requestedLoadCount: visibleContentHydrationItemLimit,
				scheduledCount: 0,
			}),
		).toBe(1);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: visibleContentHydrationConcurrentLoadLimit,
				requestedLoadCount: visibleContentHydrationItemLimit,
				scheduledCount: 0,
			}),
		).toBe(0);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: 0,
				requestedLoadCount: visibleContentHydrationItemLimit,
				scheduledCount: visibleContentHydrationConcurrentLoadLimit,
			}),
		).toBe(0);
	});

	test('keeps a sweep slot open when one retained final-window item is already loading', () => {
		const retainedLoadingItemIds = ['item-005'];
		const finalUnhydratedItemIds = ['item-006', 'item-007', 'item-000'];

		expect(finalUnhydratedItemIds).toHaveLength(3);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: retainedLoadingItemIds.length,
				requestedLoadCount: finalUnhydratedItemIds.length,
				scheduledCount: retainedLoadingItemIds.length,
			}),
		).toBe(1);
	});

	test('publishes no visible lane content while hydration is paused for active scroll', () => {
		const loadedResource: BridgeContentResource = {
			handle: makeBridgeContentHandle('item-001', 'head'),
			readText: (): string => 'ready content\n',
		};

		const result = createVisibleReviewContentHydrationResult({
			contentStateByItemId: new Map([
				[
					'item-001',
					{
						contentKey: 'content:item-001',
						itemId: 'item-001',
						status: 'ready',
					},
				],
				[
					'item-002',
					{
						contentKey: 'content:item-002',
						itemId: 'item-002',
						status: 'loading',
					},
				],
			]),
			resourcesByItemId: new Map([['item-001', { head: loadedResource }]]),
			setVisibleItemIds: (): void => {},
			visibleHydrationPaused: true,
			visibleItemIds: ['item-001', 'item-002'],
		});

		expect(result.visibleContentResourcesByItemId.size).toBe(0);
		expect(result.visibleLoadingItemIds.size).toBe(0);
		expect(result.visibleReadyItemCount).toBe(0);
		expect(result.visibleLoadingItemCount).toBe(0);
	});

	test('keeps paused visible loads alive so completed bodies are not refetched after selection churn', () => {
		expect(shouldAbortVisibleContentLoadsForPause()).toBe(false);
	});

	test('publishes scheduled visible item ids before they become loading or ready', () => {
		const result = createVisibleReviewContentHydrationResult({
			contentStateByItemId: new Map(),
			resourcesByItemId: new Map(),
			setVisibleItemIds: (): void => {},
			visibleHydrationPaused: false,
			visibleItemIds: ['item-001', 'item-002'],
		});

		expect(result.visibleItemIds).toEqual(['item-001', 'item-002']);
		expect(result.visibleLoadingItemCount).toBe(0);
		expect(result.visibleContentResourcesByItemId.size).toBe(0);
	});

	test('recovers aborted visible loads so re-entered items can reschedule', () => {
		const recoveredStateByItemId = recoverAbortedVisibleContentLoadState({
			contentKey: 'content:item-001',
			currentStateByItemId: new Map([
				[
					'item-001',
					{
						contentKey: 'content:item-001',
						itemId: 'item-001',
						status: 'loading',
					},
				],
			]),
			itemId: 'item-001',
		});

		const result = createVisibleReviewContentHydrationResult({
			contentStateByItemId: recoveredStateByItemId,
			resourcesByItemId: new Map(),
			setVisibleItemIds: (): void => {},
			visibleHydrationPaused: false,
			visibleItemIds: ['item-001'],
		});

		expect(recoveredStateByItemId.get('item-001')?.status).toBe('aborted');
		expect(result.visibleLoadingItemCount).toBe(0);
		expect(result.visibleLoadingItemIds.has('item-001')).toBe(false);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: result.visibleLoadingItemCount,
				requestedLoadCount: 1,
				scheduledCount: 0,
			}),
		).toBe(1);
	});

	test('aborted visible loads release their concurrency slot for the next visible item', () => {
		const recoveredStateByItemId = recoverAbortedVisibleContentLoadState({
			contentKey: 'content:item-001',
			currentStateByItemId: new Map([
				[
					'item-001',
					{
						contentKey: 'content:item-001',
						itemId: 'item-001',
						status: 'loading',
					},
				],
				[
					'item-002',
					{
						contentKey: 'content:item-002',
						itemId: 'item-002',
						status: 'loading',
					},
				],
			]),
			itemId: 'item-001',
		});
		const result = createVisibleReviewContentHydrationResult({
			contentStateByItemId: recoveredStateByItemId,
			resourcesByItemId: new Map(),
			setVisibleItemIds: (): void => {},
			visibleHydrationPaused: false,
			visibleItemIds: ['item-001', 'item-002', 'item-003'],
		});

		expect(result.visibleLoadingItemCount).toBe(1);
		expect(result.visibleLoadingItemIds.has('item-002')).toBe(true);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: result.visibleLoadingItemCount,
				requestedLoadCount: 1,
				scheduledCount: 0,
			}),
		).toBe(1);
	});

	test('re-arms an aborted visible item after the final demand pass clears in-flight bookkeeping', () => {
		const fixture = makeVisibleContentKeyFixture('item-003');

		expect(
			shouldRearmAbortedVisibleContentLoad({
				contentInvalidationVersion: 0,
				contentKey: fixture.contentKey,
				itemId: 'item-003',
				reviewPackage: fixture.reviewPackage,
				visibleHydrationPaused: false,
				visibleItemIds: ['item-003'],
			}),
		).toBe(true);
	});

	test('does not re-arm aborted visible content for superseded or inactive windows', () => {
		const fixture = makeVisibleContentKeyFixture('item-003');

		expect(
			shouldRearmAbortedVisibleContentLoad({
				contentInvalidationVersion: 0,
				contentKey: fixture.contentKey,
				itemId: 'item-003',
				reviewPackage: fixture.reviewPackage,
				visibleHydrationPaused: false,
				visibleItemIds: ['item-004'],
			}),
		).toBe(false);
		expect(
			shouldRearmAbortedVisibleContentLoad({
				contentInvalidationVersion: 0,
				contentKey: fixture.contentKey,
				itemId: 'item-003',
				reviewPackage: fixture.reviewPackage,
				visibleHydrationPaused: true,
				visibleItemIds: ['item-003'],
			}),
		).toBe(false);
		expect(
			shouldRearmAbortedVisibleContentLoad({
				contentInvalidationVersion: 1,
				contentKey: fixture.contentKey,
				itemId: 'item-003',
				reviewPackage: fixture.reviewPackage,
				visibleHydrationPaused: false,
				visibleItemIds: ['item-003'],
			}),
		).toBe(false);
	});
});

function makeReviewPackageWithItemCount(itemCount: number): BridgeReviewPackage {
	const reviewPackage = makeBridgeReviewPackage();
	const orderedItemIds = Array.from(
		{ length: itemCount },
		(_, index): string => `item-${String(index).padStart(3, '0')}`,
	);
	const itemsById = Object.fromEntries(
		orderedItemIds.map((itemId): readonly [string, ReturnType<typeof makeBridgeReviewItem>] => [
			itemId,
			makeBridgeReviewItem({
				itemId,
				path: `Sources/App/File${itemId}.swift`,
			}),
		]),
	);
	return {
		...reviewPackage,
		orderedItemIds,
		itemsById,
		summary: {
			...reviewPackage.summary,
			filesChanged: itemCount,
			visibleFileCount: itemCount,
		},
	};
}

function makeVisibleContentKeyFixture(itemId: string): {
	readonly contentKey: string;
	readonly reviewPackage: BridgeReviewPackage;
} {
	const reviewPackage = makeReviewPackageWithItemCount(8);
	const item = reviewPackage.itemsById[itemId];
	if (item === undefined) {
		throw new Error(`Expected ${itemId} fixture item to exist.`);
	}
	return {
		contentKey: [
			makeReviewItemContentResourcesKey({
				item,
				reviewPackage,
			}),
			'visibleInvalidation',
			'0',
		].join(':'),
		reviewPackage,
	};
}
