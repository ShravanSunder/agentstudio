import { describe, expect, test } from 'vitest';

import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { VisibleContentResourcesState } from './visible-review-content-hydration-support.js';
import { deriveVisibleHydrationStateProbe } from './visible-review-content-hydration-support.js';
import {
	createVisibleReviewContentHydrationResult,
	deriveVisibleReviewContentLoadPlans,
	makeReviewItemContentResourcesKey,
	normalizeVisibleReviewItemIds,
	pruneVisibleReviewContentHydrationCaches,
	recoverAbortedVisibleContentLoadState,
	selectedAdjacentReviewItemIds,
	shouldAcceptVisibleReviewContentReadyResult,
	shouldAbortVisibleContentLoadsForPause,
	shouldApplyVisibleContentStateImmediately,
	shouldRearmAbortedVisibleContentLoad,
	shouldRetryVisibleContentAfterDeferredLoad,
	visibleContentStateForAcceptedReadyResult,
	visibleContentHydrationDispatchDelayMilliseconds,
	visibleContentHydrationConcurrentLoadLimit,
	visibleReviewContentLoadPlanCount,
} from './visible-review-content-hydration.js';

describe('visible hydration state probe derivation', () => {
	test('reports membership truncation between reported and tracked visible sets', () => {
		const trackedVisibleItemIds = Array.from(
			{ length: 12 },
			(_, index): string => `item-${String(index).padStart(3, '0')}`,
		);
		const contentStateByItemId = new Map<string, VisibleContentResourcesState>([
			['item-000', { contentKey: 'k0', itemId: 'item-000', status: 'ready' }],
			['item-001', { contentKey: 'k1', itemId: 'item-001', status: 'loading' }],
			['item-002', { contentKey: 'k2', itemId: 'item-002', status: 'failed' }],
			['item-003', { contentKey: 'k3', itemId: 'item-003', status: 'deferred' }],
			['off-screen', { contentKey: 'k9', itemId: 'off-screen', status: 'ready' }],
		]);

		const probe = deriveVisibleHydrationStateProbe({
			contentStateByItemId,
			pausedNow: true,
			reportedVisibleItemCount: 20,
			trackedVisibleItemIds,
		});

		expect(probe.reportedVisibleItemCount).toBe(20);
		expect(probe.trackedVisibleItemCount).toBe(12);
		expect(probe.truncatedVisibleItemCount).toBe(8);
		expect(probe.readyItemCount).toBe(1);
		expect(probe.loadingItemCount).toBe(1);
		expect(probe.failedItemCount).toBe(1);
		expect(probe.deferredItemCount).toBe(1);
		expect(probe.untrackedItemCount).toBe(8);
		expect(probe.pausedNow).toBe(true);
	});

	test('reports zero truncation when the tracked set covers the report', () => {
		const probe = deriveVisibleHydrationStateProbe({
			contentStateByItemId: new Map<string, VisibleContentResourcesState>(),
			pausedNow: false,
			reportedVisibleItemCount: 3,
			trackedVisibleItemIds: ['a', 'b', 'c'],
		});

		expect(probe.truncatedVisibleItemCount).toBe(0);
		expect(probe.untrackedItemCount).toBe(3);
		expect(probe.readyItemCount).toBe(0);
	});
});

describe('visible review content hydration', () => {
	test('tracks all visible content warming candidates around the selected item', () => {
		const reviewPackage = makeReviewPackageWithItemCount(40);
		const selectedItemId = 'item-020';

		const normalizedItemIds = normalizeVisibleReviewItemIds({
			itemIds: reviewPackage.orderedItemIds,
			reviewPackage,
			selectedItemId,
		});

		expect(normalizedItemIds).toHaveLength(reviewPackage.orderedItemIds.length - 1);
		expect(normalizedItemIds).not.toContain(selectedItemId);
		expect(normalizedItemIds.slice(0, 4)).toEqual(['item-018', 'item-019', 'item-021', 'item-022']);
		expect(
			selectedAdjacentReviewItemIds({
				reviewPackage,
				selectedItemId,
			}),
		).toEqual(['item-018', 'item-019', 'item-021', 'item-022']);
	});

	test('starts visible content warming immediately with bounded scroll-tail concurrency', () => {
		expect(visibleContentHydrationDispatchDelayMilliseconds).toBe(0);
		expect(visibleContentHydrationConcurrentLoadLimit).toBe(4);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: 0,
				requestedLoadCount: 40,
				scheduledCount: 0,
			}),
		).toBe(visibleContentHydrationConcurrentLoadLimit);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: 1,
				requestedLoadCount: 40,
				scheduledCount: 0,
			}),
		).toBe(3);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: visibleContentHydrationConcurrentLoadLimit,
				requestedLoadCount: 40,
				scheduledCount: 0,
			}),
		).toBe(0);
		expect(
			visibleReviewContentLoadPlanCount({
				loadingCount: 0,
				requestedLoadCount: 40,
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
		).toBe(3);
	});

	test('continues publishing existing ready and loading visible content while paused', () => {
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
			visibleItemIds: ['item-001', 'item-002'],
		});

		expect(result.visibleItemIds).toEqual(['item-001', 'item-002']);
		expect(result.visibleContentResourcesByItemId.get('item-001')).toEqual({
			head: loadedResource,
		});
		expect(result.visibleLoadingItemIds.has('item-002')).toBe(true);
		expect(result.visibleReadyItemCount).toBe(1);
		expect(result.visibleLoadingItemCount).toBe(1);
	});

	test('keeps visible resource map identity when unrelated visible state churns', () => {
		const readyResource: BridgeContentResource = {
			handle: makeBridgeContentHandle('item-ready', 'head'),
			readText: (): string => 'ready content\n',
		};
		const readyResources = { head: readyResource };
		const readyState: VisibleContentResourcesState = {
			contentKey: 'content:item-ready',
			itemId: 'item-ready',
			status: 'ready',
		};
		const failedState: VisibleContentResourcesState = {
			contentKey: 'content:item-failed',
			itemId: 'item-failed',
			status: 'failed',
		};
		const previousResult = createVisibleReviewContentHydrationResult({
			contentStateByItemId: new Map([
				['item-ready', readyState],
				['item-failed', failedState],
			]),
			resourcesByItemId: new Map([['item-ready', readyResources]]),
			setVisibleItemIds: noopVisibleItemIdsSetter,
			visibleItemIds: ['item-ready', 'item-failed'],
		});

		const nextResult = createVisibleReviewContentHydrationResult({
			contentStateByItemId: new Map([
				['item-ready', readyState],
				[
					'item-failed',
					{
						...failedState,
						contentKey: 'content:item-failed:retry',
					},
				],
			]),
			previousResult,
			resourcesByItemId: new Map([['item-ready', readyResources]]),
			setVisibleItemIds: noopVisibleItemIdsSetter,
			visibleItemIds: ['item-ready', 'item-failed'],
		});

		expect(nextResult.visibleContentResourcesByItemId).toBe(
			previousResult.visibleContentResourcesByItemId,
		);
		expect(nextResult.visibleLoadingItemIds).toBe(previousResult.visibleLoadingItemIds);
	});

	test('keeps paused visible loads alive so completed bodies are not refetched after selection churn', () => {
		expect(shouldAbortVisibleContentLoadsForPause()).toBe(false);
	});

	test('keeps cache landing immediate while deferring non-selected DOM apply during scroll momentum', () => {
		const readyState = visibleContentStateForAcceptedReadyResult({
			contentKey: 'content:item-visible',
			itemId: 'item-visible',
			pausedNow: true,
			selectedItemId: 'item-selected',
		});
		const readyResource: BridgeContentResource = {
			handle: makeBridgeContentHandle('item-visible', 'head'),
			readText: (): string => 'ready during scroll\n',
		};

		const result = createVisibleReviewContentHydrationResult({
			contentStateByItemId: new Map([['item-visible', readyState]]),
			resourcesByItemId: new Map([['item-visible', { head: readyResource }]]),
			setVisibleItemIds: noopVisibleItemIdsSetter,
			visibleItemIds: ['item-visible'],
		});

		expect(readyState.status).toBe('deferred');
		expect(result.visibleReadyItemCount).toBe(0);
		expect(result.visibleContentResourcesByItemId.has('item-visible')).toBe(false);
	});

	test('delegates scroll apply decisions through extracted hydration helpers', () => {
		expect(
			shouldApplyVisibleContentStateImmediately({
				itemId: 'item-selected',
				pausedNow: true,
				selectedItemId: 'item-selected',
			}),
		).toBe(true);
		expect(
			shouldApplyVisibleContentStateImmediately({
				itemId: 'item-visible',
				pausedNow: true,
				selectedItemId: 'item-selected',
			}),
		).toBe(false);
		expect(
			shouldApplyVisibleContentStateImmediately({
				itemId: 'item-visible',
				pausedNow: false,
				selectedItemId: 'item-selected',
			}),
		).toBe(true);
	});

	test('accepts ready results when only transient loading state is absent', () => {
		expect(
			shouldAcceptVisibleReviewContentReadyResult({
				contentKey: 'content:item-001',
				currentState: undefined,
			}),
		).toBe(true);
		expect(
			shouldAcceptVisibleReviewContentReadyResult({
				contentKey: 'content:item-001',
				currentState: {
					contentKey: 'content:item-001',
					itemId: 'item-001',
					status: 'loading',
				},
			}),
		).toBe(true);
		expect(
			shouldAcceptVisibleReviewContentReadyResult({
				contentKey: 'content:item-001',
				currentState: {
					contentKey: 'content:item-002',
					itemId: 'item-001',
					status: 'loading',
				},
			}),
		).toBe(false);
	});

	test('prunes stale resources while keeping retained ready-unapplied content', () => {
		const oldResource: BridgeContentResource = {
			handle: makeBridgeContentHandle('item-old-ready', 'head'),
			readText: (): string => 'old ready\n',
		};
		const recentResource: BridgeContentResource = {
			handle: makeBridgeContentHandle('item-recent-ready', 'head'),
			readText: (): string => 'recent ready\n',
		};
		const visibleResource: BridgeContentResource = {
			handle: makeBridgeContentHandle('item-visible-ready', 'head'),
			readText: (): string => 'visible ready\n',
		};

		const pruned = pruneVisibleReviewContentHydrationCaches({
			contentStateByItemId: new Map([
				[
					'item-old-ready',
					{
						contentKey: 'content:item-old-ready',
						itemId: 'item-old-ready',
						status: 'ready',
					},
				],
				[
					'item-recent-ready',
					{
						contentKey: 'content:item-recent-ready',
						itemId: 'item-recent-ready',
						status: 'ready',
					},
				],
				[
					'item-visible-ready',
					{
						contentKey: 'content:item-visible-ready',
						itemId: 'item-visible-ready',
						status: 'ready',
					},
				],
				[
					'item-visible-loading',
					{
						contentKey: 'content:item-visible-loading',
						itemId: 'item-visible-loading',
						status: 'loading',
					},
				],
			]),
			resourcesByItemId: new Map([
				['item-old-ready', { head: oldResource }],
				['item-recent-ready', { head: recentResource }],
				['item-visible-ready', { head: visibleResource }],
			]),
			retainedContentKeys: new Set([
				'content:item-old-ready',
				'content:item-recent-ready',
				'content:item-visible-ready',
				'content:item-visible-loading',
			]),
			visibleItemIds: ['item-visible-ready', 'item-visible-loading'],
		});

		expect([...pruned.resourcesByItemId.keys()]).toEqual([
			'item-visible-ready',
			'item-recent-ready',
			'item-old-ready',
		]);
		expect(pruned.contentStateByItemId.has('item-old-ready')).toBe(true);
		expect(pruned.contentStateByItemId.get('item-visible-loading')?.status).toBe('loading');
	});

	test('publishes scheduled visible item ids before they become loading or ready', () => {
		const result = createVisibleReviewContentHydrationResult({
			contentStateByItemId: new Map(),
			resourcesByItemId: new Map(),
			setVisibleItemIds: (): void => {},
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

	test('keeps failed visible items in reconciler membership for later executor-paced retry', () => {
		const fixture = makeVisibleContentKeyFixture('item-003');

		const derivedDemand = deriveVisibleReviewContentLoadPlans({
			contentInvalidationVersion: 0,
			contentRegistry: { peekResource: () => null },
			contentStateByItemId: new Map([
				[
					'item-003',
					{
						contentKey: fixture.contentKey,
						itemId: 'item-003',
						status: 'failed',
					},
				],
			]),
			generation: fixture.reviewPackage.reviewGeneration,
			paused: false,
			previousEntries: [],
			reviewPackage: fixture.reviewPackage,
			resolveDescriptorRef: () => makeDescriptorRef('item-003-head'),
			scheduledContentKeys: new Set<string>(),
			selectedItemId: null,
			visibleItemIds: ['item-003'],
		});

		expect(derivedDemand.loadPlans.map((plan) => plan.itemId)).toEqual(['item-003']);
		expect(derivedDemand.loadPlans.map((plan) => plan.interest)).toEqual(['visible']);
	});

	test('schedules executor-paced retry for deferred visible loads while unpaused', () => {
		const fixture = makeVisibleContentKeyFixture('item-003');

		expect(
			shouldRetryVisibleContentAfterDeferredLoad({
				loadResult: { status: 'deferred', reason: 'aborted' },
				snapshot: {
					contentInvalidationVersion: 0,
					reviewPackage: fixture.reviewPackage,
					selectedItemId: null,
					visibleHydrationPaused: false,
					visibleItemIds: ['item-003'],
				},
			}),
		).toBe(true);
		expect(
			shouldRetryVisibleContentAfterDeferredLoad({
				loadResult: { status: 'deferred', reason: 'aborted' },
				snapshot: {
					contentInvalidationVersion: 0,
					reviewPackage: fixture.reviewPackage,
					selectedItemId: null,
					visibleHydrationPaused: true,
					visibleItemIds: ['item-003'],
				},
			}),
		).toBe(false);
	});

	test('delegates visible membership to the reconciler with selected dedupe and cache hits', () => {
		const reviewPackage = makeReviewPackageWithItemCount(8);
		const selectedItem = reviewPackage.itemsById['item-003'];
		if (selectedItem === undefined) {
			throw new Error('Expected selected fixture item.');
		}
		const selectedContentKey = [
			makeReviewItemContentResourcesKey({ item: selectedItem, reviewPackage }),
			'visibleInvalidation',
			'0',
		].join(':');

		const derivedDemand = deriveVisibleReviewContentLoadPlans({
			contentInvalidationVersion: 0,
			contentRegistry: {
				peekResource: (handle) =>
					handle.itemId === 'item-004'
						? {
								authoritative: true,
								byteLength: 11,
								handle,
								readText: (): string => 'cached\n',
							}
						: null,
			},
			contentStateByItemId: new Map(),
			generation: reviewPackage.reviewGeneration,
			paused: false,
			previousEntries: [],
			reviewPackage,
			resolveDescriptorRef: (handle) => makeDescriptorRef(`${handle.itemId}-${handle.role}`),
			scheduledContentKeys: new Set<string>([selectedContentKey]),
			selectedItemId: 'item-003',
			visibleItemIds: ['item-003', 'item-004', 'item-005'],
		});

		expect(derivedDemand.loadPlans.map((plan) => plan.itemId)).toEqual(['item-005']);
		expect(derivedDemand.loadPlans.map((plan) => plan.interest)).toEqual(['nearby']);
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

function noopVisibleItemIdsSetter(): void {}

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

function makeDescriptorRef(descriptorId: string): BridgeDescriptorRef {
	return {
		descriptorId,
		expectedProtocol: 'review',
		expectedResourceKind: 'content',
		expectedIdentity: {
			paneId: 'pane-1',
			protocol: 'review',
			sourceId: 'source-1',
			packageId: 'package-1',
			generation: 1,
			revision: 1,
		},
	};
}
