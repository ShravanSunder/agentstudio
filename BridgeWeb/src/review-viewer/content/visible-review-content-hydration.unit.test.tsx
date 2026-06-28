// @vitest-environment jsdom

import type { ReactElement } from 'react';
import { useEffect } from 'react';
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, test, vi } from 'vitest';

import type { BridgeLoadedContentResource } from '../../foundation/content/content-resource-loader.js';
import { createBridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { makeBridgeViewerBrowserFixture } from '../test-support/bridge-viewer-mocked-backend.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { loadReviewItemContentResources } from './review-content-loader.js';
import type { LoadReviewItemContentResourcesProps } from './review-content-loader.js';
import type { BridgeReviewContentRegistry } from './review-content-registry.js';
import {
	type UseVisibleReviewContentHydrationResult,
	type VisibleReviewContentLoadResult,
	useVisibleReviewContentHydration,
} from './visible-review-content-hydration.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('useVisibleReviewContentHydration', () => {
	let mountedRoot: ReturnType<typeof createRoot> | null = null;

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
	});

	test('does not retry a failed visible item load for the same content key', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const load = vi.fn<BridgeReviewContentRegistry['load']>(async () => {
			throw new Error('content unavailable');
		});
		const registry = makeTestContentRegistry(load);
		const snapshots: UseVisibleReviewContentHydrationResult[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<VisibleHydrationHarness
					registry={registry}
					onSnapshot={(snapshot): void => {
						snapshots.push(snapshot);
					}}
					reviewPackage={reviewPackage}
					visibleItemIds={['hidden-binary']}
				/>,
			);
			await flushVisibleHydrationMicrotasks();
		});

		expect(load).toHaveBeenCalledTimes(1);
		expect(lastSnapshot(snapshots).visibleLoadingItemCount).toBe(0);
		expect(lastSnapshot(snapshots).visibleFailedItemIds.has('hidden-binary')).toBe(true);

		await act(async (): Promise<void> => {
			await flushVisibleHydrationMicrotasks();
		});

		expect(load).toHaveBeenCalledTimes(1);
	});

	test('exposes loaded visible resources and prunes them when the item leaves the visible window', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const visibleItem = reviewPackage.itemsById['hidden-binary'];
		const headHandle = visibleItem?.contentRoles.head;
		if (headHandle === undefined || headHandle === null) {
			throw new Error('expected hidden-binary head handle');
		}
		const visibleResource = makeLoadedContentResource({
			handle: headHandle,
			text: 'let visibleWindowHydrated = true',
		});
		const registry = makeTestContentRegistry(async () => visibleResource);
		const snapshots: UseVisibleReviewContentHydrationResult[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<VisibleHydrationHarness
					registry={registry}
					onSnapshot={(snapshot): void => {
						snapshots.push(snapshot);
					}}
					reviewPackage={reviewPackage}
					visibleItemIds={['hidden-binary']}
				/>,
			);
			await flushVisibleHydrationMicrotasks();
		});

		expect(lastSnapshot(snapshots).visibleReadyItemCount).toBe(1);
		expect(lastSnapshot(snapshots).visibleContentResourcesByItemId.get('hidden-binary')).toEqual({
			head: visibleResource,
		});

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<VisibleHydrationHarness
					registry={registry}
					onSnapshot={(snapshot): void => {
						snapshots.push(snapshot);
					}}
					reviewPackage={reviewPackage}
					visibleItemIds={[]}
				/>,
			);
			await flushVisibleHydrationMicrotasks();
		});

		expect(lastSnapshot(snapshots).visibleReadyItemCount).toBe(0);
		expect(lastSnapshot(snapshots).visibleContentResourcesByItemId.size).toBe(0);
	});

	test('hydrates a large visible CodeView window instead of stopping at the first collapsed header page', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const visibleItemIds = fixture.reviewPackage.orderedItemIds.slice(0, 72);
		const loadedItemIds: string[] = [];
		const registry = makeTestContentRegistry(async ({ handle }) => {
			loadedItemIds.push(handle.itemId);
			return makeLoadedContentResource({
				handle,
				text: `loaded ${handle.itemId}`,
			});
		});
		const snapshots: UseVisibleReviewContentHydrationResult[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<VisibleHydrationHarness
					registry={registry}
					onSnapshot={(snapshot): void => {
						snapshots.push(snapshot);
					}}
					reviewPackage={fixture.reviewPackage}
					visibleItemIds={visibleItemIds}
				/>,
			);
			await flushVisibleHydrationMicrotasks();
		});

		expect(new Set(loadedItemIds).size).toBeGreaterThan(48);
		expect(lastSnapshot(snapshots).visibleReadyItemCount).toBe(visibleItemIds.length);
	});

	test('hydrates a selected item neighborhood before CodeView publishes the rendered window', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const selectedIndex = 180;
		const selectedItemId = fixture.reviewPackage.orderedItemIds[selectedIndex];
		const nextItemId = fixture.reviewPackage.orderedItemIds[selectedIndex + 1];
		const previousItemId = fixture.reviewPackage.orderedItemIds[selectedIndex - 1];
		if (selectedItemId === undefined || nextItemId === undefined || previousItemId === undefined) {
			throw new Error('expected large fixture selection neighborhood');
		}
		const loadedItemIds: string[] = [];
		const registry = makeTestContentRegistry(async ({ handle }) => {
			loadedItemIds.push(handle.itemId);
			return makeLoadedContentResource({
				handle,
				text: `loaded ${handle.itemId}`,
			});
		});
		const snapshots: UseVisibleReviewContentHydrationResult[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<VisibleHydrationHarness
					registry={registry}
					onSnapshot={(snapshot): void => {
						snapshots.push(snapshot);
					}}
					reviewPackage={fixture.reviewPackage}
					selectedItemId={selectedItemId}
					visibleItemIds={[]}
				/>,
			);
			await flushVisibleHydrationMicrotasks();
		});

		expect(loadedItemIds).not.toContain(selectedItemId);
		expect(loadedItemIds).toContain(previousItemId);
		expect(loadedItemIds).toContain(nextItemId);
		expect(lastSnapshot(snapshots).visibleReadyItemCount).toBeGreaterThan(1);
	});

	test('aborts obsolete visible content loads when selected neighborhood changes', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const firstSelectedItemId = fixture.reviewPackage.orderedItemIds[180];
		const secondSelectedItemId = fixture.reviewPackage.orderedItemIds[280];
		const secondNeighborItemId = fixture.reviewPackage.orderedItemIds[281];
		if (
			firstSelectedItemId === undefined ||
			secondSelectedItemId === undefined ||
			secondNeighborItemId === undefined
		) {
			throw new Error('expected large fixture selection ids');
		}
		const capturedSignals: AbortSignal[] = [];
		const registry = makeTestContentRegistry(({ signal }) => {
			if (!(signal instanceof AbortSignal)) {
				throw new Error('expected visible content load abort signal');
			}
			capturedSignals.push(signal);
			return new Promise<BridgeLoadedContentResource>(() => {});
		});
		const snapshots: UseVisibleReviewContentHydrationResult[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<VisibleHydrationHarness
					registry={registry}
					onSnapshot={(snapshot): void => {
						snapshots.push(snapshot);
					}}
					reviewPackage={fixture.reviewPackage}
					selectedItemId={firstSelectedItemId}
					visibleItemIds={[]}
				/>,
			);
			await flushVisibleHydrationMicrotasks();
		});

		expect(capturedSignals.length).toBeGreaterThan(0);
		expect(capturedSignals.every((signal): boolean => !signal.aborted)).toBe(true);
		const firstSignals = [...capturedSignals];

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<VisibleHydrationHarness
					registry={registry}
					onSnapshot={(snapshot): void => {
						snapshots.push(snapshot);
					}}
					reviewPackage={fixture.reviewPackage}
					selectedItemId={secondSelectedItemId}
					visibleItemIds={[]}
				/>,
			);
			await flushVisibleHydrationMicrotasks();
		});

		expect(firstSignals.every((signal): boolean => signal.aborted)).toBe(true);
		expect(capturedSignals.length).toBeGreaterThan(firstSignals.length);
		expect(lastSnapshot(snapshots).visibleLoadingItemIds.has(secondSelectedItemId)).toBe(false);
		expect(lastSnapshot(snapshots).visibleLoadingItemIds.has(secondNeighborItemId)).toBe(true);
		expect(lastSnapshot(snapshots).visibleLoadingItemCount).toBeGreaterThan(0);
	});

	test('retries deferred visible content pressure without marking the item failed', async () => {
		const scheduledFrameCallbacks: FrameRequestCallback[] = [];
		vi.stubGlobal('requestAnimationFrame', ((callback: FrameRequestCallback): number => {
			scheduledFrameCallbacks.push(callback);
			return scheduledFrameCallbacks.length;
		}) satisfies typeof requestAnimationFrame);
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const visibleItem = reviewPackage.itemsById['hidden-binary'];
		const headHandle = visibleItem?.contentRoles.head;
		if (headHandle === undefined || headHandle === null) {
			throw new Error('expected hidden-binary head handle');
		}
		const visibleResource = makeLoadedContentResource({
			handle: headHandle,
			text: 'retried visible text',
		});
		let loadCount = 0;
		const snapshots: UseVisibleReviewContentHydrationResult[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		try {
			await act(async (): Promise<void> => {
				mountedRoot?.render(
					<VisibleHydrationHarness
						loadContentResources={async (): Promise<VisibleReviewContentLoadResult> => {
							loadCount += 1;
							return loadCount === 1
								? { status: 'deferred', reason: 'concurrency_exceeded' }
								: { status: 'ready', resources: { head: visibleResource } };
						}}
						onSnapshot={(snapshot): void => {
							snapshots.push(snapshot);
						}}
						reviewPackage={reviewPackage}
						visibleItemIds={['hidden-binary']}
					/>,
				);
				await flushVisibleHydrationMicrotasks();
			});

			expect(loadCount).toBe(1);
			expect(lastSnapshot(snapshots).visibleFailedItemIds.has('hidden-binary')).toBe(false);

			await act(async (): Promise<void> => {
				const callback = scheduledFrameCallbacks.shift();
				if (callback === undefined) {
					throw new Error('expected scheduled visible hydration retry');
				}
				callback(performance.now());
				await flushVisibleHydrationMicrotasks();
			});

			expect(loadCount).toBe(2);
			expect(lastSnapshot(snapshots).visibleFailedItemIds.has('hidden-binary')).toBe(false);
			expect(lastSnapshot(snapshots).visibleReadyItemCount).toBe(1);
			expect(lastSnapshot(snapshots).visibleContentResourcesByItemId.get('hidden-binary')).toEqual({
				head: visibleResource,
			});
		} finally {
			vi.unstubAllGlobals();
		}
	});

	test('waits for the scheduled retry token before retrying deferred visible pressure', async () => {
		const scheduledFrameCallbacks: FrameRequestCallback[] = [];
		vi.stubGlobal('requestAnimationFrame', ((callback: FrameRequestCallback): number => {
			scheduledFrameCallbacks.push(callback);
			return scheduledFrameCallbacks.length;
		}) satisfies typeof requestAnimationFrame);
		try {
			const reviewPackage = makeBridgeViewerProjectionFixture();
			let loadCount = 0;
			const snapshots: UseVisibleReviewContentHydrationResult[] = [];
			const container = document.createElement('div');
			document.body.append(container);
			mountedRoot = createRoot(container);

			await act(async (): Promise<void> => {
				mountedRoot?.render(
					<VisibleHydrationHarness
						loadContentResources={async (): Promise<VisibleReviewContentLoadResult> => {
							loadCount += 1;
							return { status: 'deferred', reason: 'concurrency_exceeded' };
						}}
						onSnapshot={(snapshot): void => {
							snapshots.push(snapshot);
						}}
						reviewPackage={reviewPackage}
						visibleItemIds={['hidden-binary']}
					/>,
				);
				await flushVisibleHydrationMicrotasks();
			});

			expect(loadCount).toBe(1);
			expect(lastSnapshot(snapshots).visibleFailedItemIds.has('hidden-binary')).toBe(false);

			await act(async (): Promise<void> => {
				await flushVisibleHydrationMicrotasks();
			});

			expect(loadCount).toBe(1);

			await act(async (): Promise<void> => {
				const callback = scheduledFrameCallbacks.shift();
				if (callback === undefined) {
					throw new Error('expected scheduled visible hydration retry');
				}
				callback(performance.now());
				await flushVisibleHydrationMicrotasks();
			});

			expect(loadCount).toBe(2);
		} finally {
			vi.unstubAllGlobals();
		}
	});

	test('coalesces visible deferred pressure retries to one scheduled frame', async () => {
		const scheduledFrameCallbacks: FrameRequestCallback[] = [];
		vi.stubGlobal('requestAnimationFrame', ((callback: FrameRequestCallback): number => {
			scheduledFrameCallbacks.push(callback);
			return scheduledFrameCallbacks.length;
		}) satisfies typeof requestAnimationFrame);
		try {
			const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
			const visibleItemIds = fixture.reviewPackage.orderedItemIds.slice(0, 2);
			const snapshots: UseVisibleReviewContentHydrationResult[] = [];
			const container = document.createElement('div');
			document.body.append(container);
			mountedRoot = createRoot(container);

			await act(async (): Promise<void> => {
				mountedRoot?.render(
					<VisibleHydrationHarness
						loadContentResources={async (): Promise<VisibleReviewContentLoadResult> => ({
							status: 'deferred',
							reason: 'concurrency_exceeded',
						})}
						onSnapshot={(snapshot): void => {
							snapshots.push(snapshot);
						}}
						reviewPackage={fixture.reviewPackage}
						visibleItemIds={visibleItemIds}
					/>,
				);
				await flushVisibleHydrationMicrotasks();
			});

			expect(visibleItemIds.length).toBe(2);
			expect(lastSnapshot(snapshots).visibleFailedItemIds.size).toBe(0);
			expect(scheduledFrameCallbacks).toHaveLength(1);
		} finally {
			vi.unstubAllGlobals();
		}
	});

	test('stops retrying deferred visible pressure after the bounded retry window', async () => {
		const scheduledFrameCallbacks: FrameRequestCallback[] = [];
		vi.stubGlobal('requestAnimationFrame', ((callback: FrameRequestCallback): number => {
			scheduledFrameCallbacks.push(callback);
			return scheduledFrameCallbacks.length;
		}) satisfies typeof requestAnimationFrame);
		try {
			const reviewPackage = makeBridgeViewerProjectionFixture();
			let loadCount = 0;
			const snapshots: UseVisibleReviewContentHydrationResult[] = [];
			const container = document.createElement('div');
			document.body.append(container);
			mountedRoot = createRoot(container);

			await act(async (): Promise<void> => {
				mountedRoot?.render(
					<VisibleHydrationHarness
						loadContentResources={async (): Promise<VisibleReviewContentLoadResult> => {
							loadCount += 1;
							return { status: 'deferred', reason: 'concurrency_exceeded' };
						}}
						onSnapshot={(snapshot): void => {
							snapshots.push(snapshot);
						}}
						reviewPackage={reviewPackage}
						visibleItemIds={['hidden-binary']}
					/>,
				);
				await flushVisibleHydrationMicrotasks();
			});

			expect(loadCount).toBe(1);
			expect(scheduledFrameCallbacks).toHaveLength(1);

			await act(async (): Promise<void> => {
				const callback = scheduledFrameCallbacks.shift();
				if (callback === undefined) {
					throw new Error('expected scheduled visible hydration retry');
				}
				callback(performance.now());
				await flushVisibleHydrationMicrotasks();
			});

			expect(loadCount).toBe(2);
			expect(lastSnapshot(snapshots).visibleFailedItemIds.has('hidden-binary')).toBe(false);
			expect(scheduledFrameCallbacks).toHaveLength(0);

			await act(async (): Promise<void> => {
				await flushVisibleHydrationMicrotasks();
			});

			expect(loadCount).toBe(2);
		} finally {
			vi.unstubAllGlobals();
		}
	});

	test('does not start visible loads while selected foreground content is loading', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const visibleItemIds = fixture.reviewPackage.orderedItemIds.slice(0, 8);
		let loadCount = 0;
		const snapshots: UseVisibleReviewContentHydrationResult[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<VisibleHydrationHarness
					loadContentResources={async (): Promise<VisibleReviewContentLoadResult> => {
						loadCount += 1;
						return { status: 'deferred', reason: 'concurrency_exceeded' };
					}}
					onSnapshot={(snapshot): void => {
						snapshots.push(snapshot);
					}}
					reviewPackage={fixture.reviewPackage}
					visibleHydrationPaused={true}
					visibleItemIds={visibleItemIds}
				/>,
			);
			await flushVisibleHydrationMicrotasks();
		});

		expect(loadCount).toBe(0);
		expect(lastSnapshot(snapshots).visibleLoadingItemCount).toBe(0);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<VisibleHydrationHarness
					loadContentResources={async (): Promise<VisibleReviewContentLoadResult> => {
						loadCount += 1;
						return { status: 'deferred', reason: 'concurrency_exceeded' };
					}}
					onSnapshot={(snapshot): void => {
						snapshots.push(snapshot);
					}}
					reviewPackage={fixture.reviewPackage}
					visibleHydrationPaused={false}
					visibleItemIds={visibleItemIds}
				/>,
			);
			await flushVisibleHydrationMicrotasks();
		});

		expect(loadCount).toBeGreaterThan(0);
	});
});

interface VisibleHydrationHarnessProps {
	readonly registry?: BridgeReviewContentRegistry;
	readonly loadContentResources?: (
		props: LoadReviewItemContentResourcesProps,
	) => Promise<VisibleReviewContentLoadResult>;
	readonly reviewPackage: ReturnType<typeof makeBridgeViewerProjectionFixture>;
	readonly selectedItemId?: string | null;
	readonly contentInvalidationVersion?: number;
	readonly visibleHydrationPaused?: boolean;
	readonly visibleItemIds: readonly string[];
	readonly onSnapshot: (snapshot: UseVisibleReviewContentHydrationResult) => void;
}

function VisibleHydrationHarness(props: VisibleHydrationHarnessProps): ReactElement {
	const hydration = useVisibleReviewContentHydration({
		contentRegistry:
			props.registry ??
			makeTestContentRegistry(async () => {
				throw new Error('unexpected content registry load');
			}),
		loadContentResources:
			props.loadContentResources ??
			(async (loadProps) => await loadReviewItemContentResources(loadProps)),
		reviewPackage: props.reviewPackage,
		selectedItemId: props.selectedItemId ?? null,
		telemetryParentTraceContext: null,
		telemetryRecorder: createBridgeTelemetryRecorder(null),
		contentInvalidationVersion: props.contentInvalidationVersion ?? 0,
		visibleHydrationPaused: props.visibleHydrationPaused ?? false,
	});
	useEffect((): void => {
		hydration.setVisibleItemIds(props.visibleItemIds);
	}, [hydration, props.visibleItemIds]);
	useEffect((): void => {
		props.onSnapshot(hydration);
	}, [hydration, props]);
	return <div data-testid="visible-hydration-harness" />;
}

function makeTestContentRegistry(
	load: BridgeReviewContentRegistry['load'],
): BridgeReviewContentRegistry {
	return {
		clear: (): void => {},
		load,
		setActiveIdentity: (): void => {},
		snapshot: () => ({
			activeIdentity: null,
			cachedResourceCount: 0,
			cachedResourceKeys: [],
			inFlightRequestCount: 0,
		}),
	};
}

function makeLoadedContentResource(props: {
	readonly handle: BridgeLoadedContentResource['handle'];
	readonly text: string;
}): BridgeLoadedContentResource {
	return {
		authoritative: true,
		byteLength: new TextEncoder().encode(props.text).byteLength,
		handle: props.handle,
		readText: (): string => props.text,
	};
}

async function flushVisibleHydrationMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}

function lastSnapshot(
	snapshots: readonly UseVisibleReviewContentHydrationResult[],
): UseVisibleReviewContentHydrationResult {
	const snapshot = snapshots.at(-1);
	if (snapshot === undefined) {
		throw new Error('expected visible hydration snapshot');
	}
	return snapshot;
}
