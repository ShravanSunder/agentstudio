import { act, useEffect, useState, type ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import {
	createDeferred,
	makeNoopTelemetryRecorder,
} from '../../app/bridge-app.unit.test-support.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import { createBridgeReviewContentRegistry } from './review-content-registry.js';
import {
	useVisibleReviewContentHydration,
	visibleContentHydrationDispatchDelayMilliseconds,
	type VisibleReviewContentLoadProps,
	type VisibleReviewContentLoadResult,
} from './visible-review-content-hydration.js';

describe('visible review content hydration Browser Mode', () => {
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
			const finalUnhydratedItemIds = ['item-006', 'item-007', 'item-000'];
			const loadAttempts: VisibleReviewContentLoadProps[] = [];
			let setVisibleItemIds: ((itemIds: readonly string[]) => void) | null = null;

			expect(revealedItemCount).toBe(8);
			expect(finalVisibleItemIds.filter((itemId): boolean => itemId !== 'item-005')).toEqual(
				finalUnhydratedItemIds,
			);
			expect(finalUnhydratedItemIds.length).toBeGreaterThanOrEqual(3);

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
			await dispatchVisibleHydrationTimers();

			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual([
				'item-000',
				'item-001',
				'item-002',
				'item-003',
				'item-004',
				'item-005',
				'item-006',
			]);

			await dispatchVisibleHydrationTimers();

			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual([
				'item-000',
				'item-001',
				'item-002',
				'item-003',
				'item-004',
				'item-005',
				'item-006',
				'item-007',
			]);

			await dispatchVisibleHydrationTimers();

			expect(loadAttempts.map((loadAttempt): string => loadAttempt.itemId)).toEqual([
				'item-000',
				'item-001',
				'item-002',
				'item-003',
				'item-004',
				'item-005',
				'item-006',
				'item-007',
				'item-000',
			]);
			expect(probeReadyCount()).toBe(String(finalUnhydratedItemIds.length));
		} finally {
			vi.useRealTimers();
		}
	});

	test('re-arms a final visible item when its aborted load completes after the last demand pass', async () => {
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
			await dispatchVisibleHydrationTimers();

			expect(itemLoadAttemptCount(loadAttempts, 'item-003')).toBe(2);
			expect(probeReadyCount()).toBe('1');
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

function makeLoadedResources(itemId: string): { readonly head: BridgeContentResource } {
	return {
		head: {
			handle: makeBridgeContentHandle(itemId, 'head'),
			readText: (): string => `loaded ${itemId}`,
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
