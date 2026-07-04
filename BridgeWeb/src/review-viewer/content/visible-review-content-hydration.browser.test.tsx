import { act, useEffect, useState, type ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import {
	createDeferred,
	makeNoopTelemetryRecorder,
} from '../../app/bridge-app.unit.test-support.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import {
	createBridgeReviewContentRegistry,
	type BridgeReviewContentRegistry,
} from './review-content-registry.js';
import {
	useVisibleReviewContentHydration,
	visibleContentHydrationDispatchDelayMilliseconds,
	type VisibleReviewContentLoadProps,
	type VisibleReviewContentLoadResult,
} from './visible-review-content-hydration.js';

describe('visible review content hydration Browser Mode', () => {
	test('demands and paints every reported visible item beyond the legacy membership cap', async () => {
		vi.useFakeTimers();
		try {
			const reportedVisibleItemIds = Array.from(
				{ length: 16 },
				(_, index): string => `item-${String(index).padStart(3, '0')}`,
			);
			const reviewPackage = makeReviewPackageWithItemCount(reportedVisibleItemIds.length);
			const loadAttempts: VisibleReviewContentLoadProps[] = [];
			let setVisibleItemIds: ((itemIds: readonly string[]) => void) | null = null;
			resetVisibleHydrationStateProbe();

			function HydrationProbe(): ReactElement {
				const [reportedItemIds, setReportedItemIds] = useState<readonly string[]>([]);
				const hydration = useVisibleReviewContentHydration({
					contentRegistry: createBridgeReviewContentRegistry(),
					contentInvalidationVersion: 0,
					loadContentResources: (props): Promise<VisibleReviewContentLoadResult> => {
						loadAttempts.push(props);
						return Promise.resolve(makeLoadedResources(props.itemId));
					},
					reviewPackage,
					resolveDescriptorRef: resolveDescriptorRefForTest,
					selectedItemId: null,
					telemetryParentTraceContext: null,
					telemetryRecorder: makeNoopTelemetryRecorder(),
					visibleHydrationPaused: false,
				});
				useEffect((): void => {
					setVisibleItemIds = setReportedItemIds;
				}, []);
				useEffect((): void => {
					hydration.setVisibleItemIds(reportedItemIds);
				}, [hydration, reportedItemIds]);
				return (
					<div
						data-ready-count={String(hydration.visibleReadyItemCount)}
						data-resource-item-ids={[...hydration.visibleContentResourcesByItemId.keys()].join(',')}
						data-testid="visible-hydration-probe"
					/>
				);
			}

			render(<HydrationProbe />);
			await flushReactWork();

			await reportVisibleItemIds(setVisibleItemIds, reportedVisibleItemIds);
			for (let index = 0; index < reportedVisibleItemIds.length; index += 1) {
				// oxlint-disable-next-line no-await-in-loop -- Hydration batches are timer-driven and must drain sequentially.
				await dispatchVisibleHydrationTimers();
			}

			expect(visibleHydrationStateProbe()?.reportedVisibleItemCount).toBe(
				reportedVisibleItemIds.length,
			);
			expect(visibleHydrationStateProbe()?.truncatedVisibleItemCount).toBe(0);
			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual(
				reportedVisibleItemIds,
			);
			expect(probeReadyCount()).toBe(String(reportedVisibleItemIds.length));
			expect(probeResourceItemIds()).toBe(reportedVisibleItemIds.join(','));
		} finally {
			vi.useRealTimers();
		}
	});

	test('lands multi-item ready results while momentum pause remains active', async () => {
		vi.useFakeTimers();
		try {
			const reviewPackage = makeReviewPackageWithItemCount(4);
			const contentRegistry = createBridgeReviewContentRegistry();
			const loadDeferredsByItemId = makeDeferredLoadResults(['item-000', 'item-001']);
			const loadAttempts: VisibleReviewContentLoadProps[] = [];
			let setVisibleItemIds: ((itemIds: readonly string[]) => void) | null = null;
			let setHydrationPaused: ((paused: boolean) => void) | null = null;
			resetVisibleHydrationDiscardProbe();

			function HydrationProbe(): ReactElement {
				const [reportedVisibleItemIds, setReportedVisibleItemIds] = useState<readonly string[]>([]);
				const [visibleHydrationPaused, setVisibleHydrationPaused] = useState(false);
				const hydration = useVisibleReviewContentHydration({
					contentRegistry,
					contentInvalidationVersion: 0,
					loadContentResources: (props): Promise<VisibleReviewContentLoadResult> => {
						loadAttempts.push(props);
						const deferredLoad = loadDeferredsByItemId.get(props.itemId);
						const loadResult = deferredLoad?.promise ?? Promise.resolve(null);
						return loadResult.then(
							(result): VisibleReviewContentLoadResult =>
								storeReadyLoadResultInRegistry({ contentRegistry, loadResult: result }),
						);
					},
					reviewPackage,
					resolveDescriptorRef: resolveDescriptorRefForTest,
					selectedItemId: null,
					telemetryParentTraceContext: null,
					telemetryRecorder: makeNoopTelemetryRecorder(),
					visibleHydrationPaused,
				});
				useEffect((): void => {
					setVisibleItemIds = setReportedVisibleItemIds;
					setHydrationPaused = setVisibleHydrationPaused;
				}, []);
				useEffect((): void => {
					hydration.setVisibleItemIds(reportedVisibleItemIds);
				}, [hydration, reportedVisibleItemIds]);
				return (
					<div
						data-loading-count={String(hydration.visibleLoadingItemCount)}
						data-ready-count={String(hydration.visibleReadyItemCount)}
						data-resource-item-ids={[...hydration.visibleContentResourcesByItemId.keys()].join(',')}
						data-testid="visible-hydration-probe"
					/>
				);
			}

			render(<HydrationProbe />);
			await flushReactWork();

			await reportVisibleItemIds(setVisibleItemIds, ['item-000', 'item-001']);
			await dispatchVisibleHydrationTimers();
			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual([
				'item-000',
				'item-001',
			]);
			expect(probeLoadingCount()).toBe('2');

			await setVisibleHydrationPausedState(setHydrationPaused, true);
			resolveDeferredLoads(loadDeferredsByItemId, ['item-000', 'item-001']);
			await flushReactWork();
			await dispatchVisibleHydrationTimers();

			expect(contentRegistry.snapshot().cachedResourceCount).toBe(2);
			expect(visibleHydrationStateProbe()?.deferredItemCount).toBe(2);
			expect(probeReadyCount()).toBe('0');
			expect(probeResourceItemIds()).toBe('');
			expect(visibleHydrationDiscardProbeReadyDiscardCount()).toBe(0);

			await setVisibleHydrationPausedState(setHydrationPaused, false);
			await flushReactWork();
			expect(probeReadyCount()).toBe('2');
			expect(probeResourceItemIds()).toBe('item-000,item-001');
			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual([
				'item-000',
				'item-001',
			]);

			await setVisibleHydrationPausedState(setHydrationPaused, true);
			await reportVisibleItemIds(setVisibleItemIds, ['item-002', 'item-003']);
			await dispatchVisibleHydrationTimers();
			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual([
				'item-000',
				'item-001',
			]);
		} finally {
			vi.useRealTimers();
		}
	});

	test('sweeps every final visible item when several fast-scroll aborts settle after demand passes', async () => {
		vi.useFakeTimers();
		try {
			const revealedItemCount = 8;
			const reviewPackage = makeReviewPackageWithItemCount(revealedItemCount);
			const firstLoadDeferredsByItemId = makeDeferredLoadResults([
				'item-000',
				'item-001',
				'item-002',
				'item-003',
				'item-004',
				'item-005',
			]);
			const fastScrollWindows: readonly (readonly string[])[] = [
				['item-000', 'item-001'],
				['item-002', 'item-003'],
				['item-004', 'item-005'],
				['item-005', 'item-006', 'item-007', 'item-000'],
			];
			const finalVisibleItemIds = fastScrollWindows[fastScrollWindows.length - 1] ?? [];
			const finalMissingItemIds = ['item-006', 'item-007'];
			const finalCachedReentryItemId = 'item-000';
			const finalExecutorBackoffItemId = 'item-005';
			const loadAttempts: VisibleReviewContentLoadProps[] = [];
			let setVisibleItemIds: ((itemIds: readonly string[]) => void) | null = null;

			expect(revealedItemCount).toBe(8);
			expect(finalVisibleItemIds).toEqual([
				finalExecutorBackoffItemId,
				...finalMissingItemIds,
				finalCachedReentryItemId,
			]);

			function HydrationProbe(): ReactElement {
				const [reportedVisibleItemIds, setReportedVisibleItemIds] = useState<readonly string[]>([]);
				const hydration = useVisibleReviewContentHydration({
					contentRegistry: createBridgeReviewContentRegistry(),
					contentInvalidationVersion: 0,
					loadContentResources: (props): Promise<VisibleReviewContentLoadResult> => {
						loadAttempts.push(props);
						const firstLoadDeferred = firstLoadDeferredsByItemId.get(props.itemId);
						if (
							firstLoadDeferred !== undefined &&
							itemLoadAttemptCount(loadAttempts, props.itemId) === 1
						) {
							return firstLoadDeferred.promise;
						}
						return Promise.resolve(makeLoadedResources(props.itemId));
					},
					reviewPackage,
					resolveDescriptorRef: resolveDescriptorRefForTest,
					selectedItemId: null,
					telemetryParentTraceContext: null,
					telemetryRecorder: makeNoopTelemetryRecorder(),
					visibleHydrationPaused: false,
				});
				useEffect((): void => {
					setVisibleItemIds = setReportedVisibleItemIds;
				}, []);
				useEffect((): void => {
					hydration.setVisibleItemIds(reportedVisibleItemIds);
				}, [hydration, reportedVisibleItemIds]);
				return (
					<div
						data-ready-count={String(hydration.visibleReadyItemCount)}
						data-resource-item-ids={[...hydration.visibleContentResourcesByItemId.keys()].join(',')}
						data-testid="visible-hydration-probe"
					/>
				);
			}

			render(<HydrationProbe />);
			await flushReactWork();

			await reportVisibleItemIds(setVisibleItemIds, fastScrollWindows[0] ?? []);
			await dispatchVisibleHydrationTimers();
			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual([
				'item-000',
				'item-001',
			]);

			await reportVisibleItemIds(setVisibleItemIds, fastScrollWindows[1] ?? []);
			await dispatchVisibleHydrationTimers();
			resolveDeferredLoads(firstLoadDeferredsByItemId, ['item-000', 'item-001']);
			await dispatchVisibleHydrationTimers();
			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual([
				'item-000',
				'item-001',
				'item-002',
				'item-003',
			]);

			await reportVisibleItemIds(setVisibleItemIds, fastScrollWindows[2] ?? []);
			await dispatchVisibleHydrationTimers();
			resolveDeferredLoads(firstLoadDeferredsByItemId, ['item-002', 'item-003']);
			await dispatchVisibleHydrationTimers();
			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual([
				'item-000',
				'item-001',
				'item-002',
				'item-003',
				'item-004',
				'item-005',
			]);

			await reportVisibleItemIds(setVisibleItemIds, finalVisibleItemIds);
			await dispatchVisibleHydrationTimers();
			resolveDeferredLoads(firstLoadDeferredsByItemId, ['item-004']);
			// item-004 is still tracked (not aborted; retention keys off `visibleItemIds`
			// keep every reviewed item, not just currently visible ones) so this resolve
			// drives a real `setContentStateByItemId` update. Unlike the earlier
			// `resolveDeferredLoads` calls above, this one feeds into
			// `dispatchVisibleHydrationTimersUntil`, whose first loop iteration reads
			// `isSatisfied()` synchronously before any `act()` is re-entered. Flush the
			// resulting update here, inside a plain act-wrapped microtask drain, so it
			// never lands in that pre-loop gap outside any act() scope.
			await flushReactWork();
			await dispatchVisibleHydrationTimersUntil((): boolean => {
				const demandedItemIds = new Set(
					loadAttempts.map((loadAttempt): string => loadAttempt.itemId),
				);
				return finalMissingItemIds.every((itemId): boolean => demandedItemIds.has(itemId));
			});

			expect(itemLoadAttemptCount(loadAttempts, finalCachedReentryItemId)).toBe(1);
			expect(itemLoadAttemptCount(loadAttempts, finalExecutorBackoffItemId)).toBe(1);
			expect(probeReadyCount()).toBe('3');
			expect(visibleHydrationStateProbe()).toMatchObject({
				loadingItemCount: 1,
				readyItemCount: 3,
				reportedVisibleItemCount: finalVisibleItemIds.length,
				trackedVisibleItemCount: finalVisibleItemIds.length,
				truncatedVisibleItemCount: 0,
				untrackedItemCount: 0,
			});
		} finally {
			vi.useRealTimers();
		}
	});

	test('keeps a final deferred visible item in membership until executor-paced retry paints', async () => {
		vi.useFakeTimers();
		try {
			const reviewPackage = makeReviewPackageWithItemCount(8);
			const firstItem003Load = createDeferred<VisibleReviewContentLoadResult>();
			const loadAttempts: VisibleReviewContentLoadProps[] = [];
			let setVisibleItemIds: ((itemIds: readonly string[]) => void) | null = null;

			function HydrationProbe(): ReactElement {
				const [reportedVisibleItemIds, setReportedVisibleItemIds] = useState<readonly string[]>([]);
				const hydration = useVisibleReviewContentHydration({
					contentRegistry: createBridgeReviewContentRegistry(),
					contentInvalidationVersion: 0,
					loadContentResources: (props): Promise<VisibleReviewContentLoadResult> => {
						loadAttempts.push(props);
						if (
							props.itemId === 'item-003' &&
							itemLoadAttemptCount(loadAttempts, 'item-003') === 1
						) {
							return firstItem003Load.promise;
						}
						return Promise.resolve(makeLoadedResources(props.itemId));
					},
					reviewPackage,
					resolveDescriptorRef: resolveDescriptorRefForTest,
					selectedItemId: null,
					telemetryParentTraceContext: null,
					telemetryRecorder: makeNoopTelemetryRecorder(),
					visibleHydrationPaused: false,
				});
				useEffect((): void => {
					setVisibleItemIds = setReportedVisibleItemIds;
				}, []);
				useEffect((): void => {
					hydration.setVisibleItemIds(reportedVisibleItemIds);
				}, [hydration, reportedVisibleItemIds]);
				return (
					<div
						data-ready-count={String(hydration.visibleReadyItemCount)}
						data-resource-item-ids={[...hydration.visibleContentResourcesByItemId.keys()].join(',')}
						data-testid="visible-hydration-probe"
					/>
				);
			}

			render(<HydrationProbe />);
			await flushReactWork();

			await reportVisibleItemIds(setVisibleItemIds, ['item-003']);
			await dispatchVisibleHydrationTimers();
			expect(itemLoadAttemptCount(loadAttempts, 'item-003')).toBe(1);
			expect(loadAttempts[0]?.interest).toBe('visible');

			await reportVisibleItemIds(setVisibleItemIds, ['item-004']);
			await flushReactWork();
			await reportVisibleItemIds(setVisibleItemIds, ['item-003']);
			await flushReactWork();

			firstItem003Load.resolve({ status: 'deferred', reason: 'aborted' });
			await flushReactWork();
			expect(visibleHydrationStateProbe()).toMatchObject({
				reportedVisibleItemCount: 1,
				trackedVisibleItemCount: 1,
				truncatedVisibleItemCount: 0,
			});

			await dispatchVisibleHydrationTimersUntil((): boolean => probeReadyCount() === '1');
			expect(probeReadyCount()).toBe('1');
			expect(probeResourceItemIds()).toBe('item-003');
		} finally {
			vi.useRealTimers();
		}
	});
});

async function reportVisibleItemIds(
	setVisibleItemIds: ((itemIds: readonly string[]) => void) | null,
	itemIds: readonly string[],
): Promise<void> {
	if (setVisibleItemIds === null) {
		throw new Error('Expected visible hydration probe setter to be installed.');
	}
	await act(async (): Promise<void> => {
		setVisibleItemIds(itemIds);
	});
}

async function setVisibleHydrationPausedState(
	setHydrationPaused: ((paused: boolean) => void) | null,
	paused: boolean,
): Promise<void> {
	if (setHydrationPaused === null) {
		throw new Error('Expected visible hydration pause setter to be installed.');
	}
	await act(async (): Promise<void> => {
		setHydrationPaused(paused);
	});
}

async function flushReactWork(): Promise<void> {
	await act(async (): Promise<void> => {
		await Promise.resolve();
	});
}

async function dispatchVisibleHydrationTimers(): Promise<void> {
	await act(async (): Promise<void> => {
		await vi.advanceTimersByTimeAsync(visibleContentHydrationDispatchDelayMilliseconds);
	});
	await flushReactWork();
}

// The executor's abort-and-sweep retry (`scheduleVisibleHydrationRetry`) is scheduled via
// `requestAnimationFrame`. Vitest's fake clock only fires a faked `requestAnimationFrame`
// callback once simulated time crosses the next ~16ms frame boundary, so the 0ms
// `visibleContentHydrationDispatchDelayMilliseconds` advance in `dispatchVisibleHydrationTimers`
// never reaches it. Advancing by a full frame lets a pending sweep retry fire.
const animationFrameAdvanceMilliseconds = 16;

async function dispatchVisibleHydrationAnimationFrame(): Promise<void> {
	await act(async (): Promise<void> => {
		await vi.advanceTimersByTimeAsync(animationFrameAdvanceMilliseconds);
	});
	await flushReactWork();
}

async function dispatchVisibleHydrationTimersUntil(
	isSatisfied: () => boolean,
	maxDispatchCount = 10,
): Promise<void> {
	for (let dispatchIndex = 0; dispatchIndex < maxDispatchCount; dispatchIndex += 1) {
		if (isSatisfied()) {
			return;
		}
		// oxlint-disable-next-line no-await-in-loop -- Demand re-derivation is timer/effect driven.
		await dispatchVisibleHydrationTimers();
		if (isSatisfied()) {
			return;
		}
		// oxlint-disable-next-line no-await-in-loop -- Frame-driven retry dispatch must drain sequentially.
		await dispatchVisibleHydrationAnimationFrame();
	}
	if (!isSatisfied()) {
		throw new Error('Expected visible hydration condition to settle after timer dispatches.');
	}
}

function itemLoadAttemptCount(
	loadAttempts: readonly VisibleReviewContentLoadProps[],
	itemId: string,
): number {
	return loadAttempts.filter((loadAttempt): boolean => loadAttempt.itemId === itemId).length;
}

function probeReadyCount(): string | null {
	return (
		document
			.querySelector('[data-testid="visible-hydration-probe"]')
			?.getAttribute('data-ready-count') ?? null
	);
}

function probeLoadingCount(): string | null {
	return (
		document
			.querySelector('[data-testid="visible-hydration-probe"]')
			?.getAttribute('data-loading-count') ?? null
	);
}

function probeResourceItemIds(): string | null {
	return (
		document
			.querySelector('[data-testid="visible-hydration-probe"]')
			?.getAttribute('data-resource-item-ids') ?? null
	);
}

function resetVisibleHydrationDiscardProbe(): void {
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	delete window.__bridgeVisibleHydrationDiscardProbe;
}

function resetVisibleHydrationStateProbe(): void {
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	delete window.__bridgeVisibleHydrationStateProbe;
}

function visibleHydrationStateProbe(): Window['__bridgeVisibleHydrationStateProbe'] {
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	return window.__bridgeVisibleHydrationStateProbe;
}

function visibleHydrationDiscardProbeReadyDiscardCount(): number {
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	return window.__bridgeVisibleHydrationDiscardProbe?.readyResultDiscardCount ?? 0;
}

function makeLoadedResources(itemId: string): { readonly head: BridgeContentResource } {
	return {
		head: {
			authoritative: true,
			byteLength: 64,
			handle: makeBridgeContentHandle(itemId, 'head'),
			readText: (): string => `loaded ${itemId}`,
		},
	};
}

function storeReadyLoadResultInRegistry(props: {
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly loadResult: VisibleReviewContentLoadResult;
}): VisibleReviewContentLoadResult {
	if (props.loadResult === null || 'status' in props.loadResult) {
		return props.loadResult;
	}
	for (const resource of Object.values(props.loadResult)) {
		if (resource !== undefined) {
			props.contentRegistry.storeResource({ resource });
		}
	}
	return props.loadResult;
}

function resolveDescriptorRefForTest(handle: { readonly handleId: string }): BridgeDescriptorRef {
	return {
		descriptorId: handle.handleId,
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

function makeDeferredLoadResults(
	itemIds: readonly string[],
): Map<string, ReturnType<typeof createDeferred<VisibleReviewContentLoadResult>>> {
	return new Map(
		itemIds.map(
			(
				itemId,
			): readonly [string, ReturnType<typeof createDeferred<VisibleReviewContentLoadResult>>] => [
				itemId,
				createDeferred<VisibleReviewContentLoadResult>(),
			],
		),
	);
}

function resolveDeferredLoads(
	deferredLoadResultsByItemId: ReadonlyMap<
		string,
		ReturnType<typeof createDeferred<VisibleReviewContentLoadResult>>
	>,
	itemIds: readonly string[],
): void {
	for (const itemId of itemIds) {
		deferredLoadResultsByItemId.get(itemId)?.resolve(makeLoadedResources(itemId));
	}
}

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
