// @vitest-environment jsdom

import type { ReactElement } from 'react';
import { useEffect } from 'react';
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, test, vi } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import { createBridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import type { BridgeReviewContentRegistry } from './review-content-registry.js';
import {
	type UseVisibleReviewContentHydrationResult,
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
		const visibleResource: BridgeContentResource = {
			handle: headHandle,
			text: 'let visibleWindowHydrated = true',
		};
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
});

interface VisibleHydrationHarnessProps {
	readonly registry: BridgeReviewContentRegistry;
	readonly reviewPackage: ReturnType<typeof makeBridgeViewerProjectionFixture>;
	readonly visibleItemIds: readonly string[];
	readonly onSnapshot: (snapshot: UseVisibleReviewContentHydrationResult) => void;
}

function VisibleHydrationHarness(props: VisibleHydrationHarnessProps): ReactElement {
	const hydration = useVisibleReviewContentHydration({
		contentRegistry: props.registry,
		reviewPackage: props.reviewPackage,
		selectedItemId: null,
		telemetryParentTraceContext: null,
		telemetryRecorder: createBridgeTelemetryRecorder(null),
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
