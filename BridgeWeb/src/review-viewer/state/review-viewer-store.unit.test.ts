import { describe, expect, test } from 'vitest';

import {
	buildBridgeReviewProjection,
	makeBridgeReviewProjectionInput,
} from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { fingerprintBridgeReviewProjectionRequest } from '../workers/projection/review-projection-worker-rpc.js';
import {
	type BridgeReviewViewerStoreState,
	createBridgeReviewViewerStore,
	readBridgeReviewViewerStoreSelectorSnapshot,
	selectBridgeReviewPanelChromeSlice,
	selectBridgeReviewRowPaintSlice,
	selectBridgeReviewSelectionSlice,
	selectBridgeReviewViewerRootSnapshot,
} from './review-viewer-store.js';

describe('Bridge review viewer render store', () => {
	test('selection subscribers observe only selection slice and selected row paint slice', () => {
		const store = createBridgeReviewViewerStore();
		const selectionUpdates: string[] = [];
		const firstRowPaintUpdates: string[] = [];
		const secondRowPaintUpdates: string[] = [];
		const panelChromeUpdates: string[] = [];

		const unsubscribeSelection = store.subscribeSelector(
			selectBridgeReviewSelectionSlice,
			(slice) => {
				selectionUpdates.push(slice.selectedItemId ?? 'none');
			},
		);
		const unsubscribeFirstRow = store.subscribeSelector(
			selectBridgeReviewRowPaintSlice('source-high'),
			(slice) => {
				firstRowPaintUpdates.push(`${slice.itemId}:${slice.isSelected ? 'selected' : 'idle'}`);
			},
		);
		const unsubscribeSecondRow = store.subscribeSelector(
			selectBridgeReviewRowPaintSlice('docs-plan'),
			(slice) => {
				secondRowPaintUpdates.push(`${slice.itemId}:${slice.isSelected ? 'selected' : 'idle'}`);
			},
		);
		const unsubscribePanelChrome = store.subscribeSelector(
			selectBridgeReviewPanelChromeSlice,
			(slice) => {
				panelChromeUpdates.push(slice.renderMode.kind);
			},
		);

		store.getState().actions.setSelectedItemId('source-high');
		store.getState().actions.setSelectedItemId('docs-plan');

		expect(selectionUpdates).toEqual(['source-high', 'docs-plan']);
		expect(firstRowPaintUpdates).toEqual(['source-high:selected', 'source-high:idle']);
		expect(secondRowPaintUpdates).toEqual(['docs-plan:selected']);
		expect(panelChromeUpdates).toEqual([]);

		unsubscribeSelection();
		unsubscribeFirstRow();
		unsubscribeSecondRow();
		unsubscribePanelChrome();
	});

	test('keeps root subscriptions stable for worker stats and viewport updates', () => {
		const store = createBridgeReviewViewerStore();
		let rootRenderCount = 0;
		const unsubscribe = store.subscribeSelector(selectBridgeReviewViewerRootSnapshot, () => {
			rootRenderCount += 1;
		});

		store.getState().actions.setWorkerStatus({
			lane: 'worker',
			pendingRequestCount: 1,
			lastCompletedRequestId: null,
		});
		store.getState().actions.setMountedItemIds(['source-high']);

		expect(rootRenderCount).toBe(0);

		store.getState().actions.setProjectionMode({ kind: 'guidedReview' });

		expect(rootRenderCount).toBe(1);
		unsubscribe();
	});

	test('does not notify stable selector subscriptions for unrelated store updates', () => {
		const store = createBridgeReviewViewerStore();
		const initialActions = store.getState().actions;
		const updates: string[] = [];
		const unsubscribe = store.subscribeSelector(selectBridgeReviewSelectionSlice, (slice) => {
			updates.push(slice.selectedItemId ?? 'none');
		});

		store.getState().actions.setWorkerStatus({
			lane: 'worker',
			pendingRequestCount: 1,
			lastCompletedRequestId: null,
		});
		store.getState().actions.setMountedItemIds(['source-high']);

		expect(updates).toEqual([]);

		store.getState().actions.setSelectedItemId('source-high');

		expect(updates).toEqual(['source-high']);
		expect(store.getState().actions).toBe(initialActions);
		unsubscribe();
	});

	test('caches hook selector snapshots while store state and selector are unchanged', () => {
		const store = createBridgeReviewViewerStore();
		const cache = { current: null };

		const firstSnapshot = readBridgeReviewViewerStoreSelectorSnapshot(
			cache,
			store,
			selectAllocatingReviewStoreSnapshot,
		);
		const secondSnapshot = readBridgeReviewViewerStoreSelectorSnapshot(
			cache,
			store,
			selectAllocatingReviewStoreSnapshot,
		);

		expect(secondSnapshot).toBe(firstSnapshot);
		expect(firstSnapshot.actions).toBe(store.getState().actions);

		store.getState().actions.setWorkerStatus({
			lane: 'worker',
			pendingRequestCount: 1,
			lastCompletedRequestId: null,
		});
		const afterStoreChange = readBridgeReviewViewerStoreSelectorSnapshot(
			cache,
			store,
			selectAllocatingReviewStoreSnapshot,
		);
		const repeatedAfterStoreChange = readBridgeReviewViewerStoreSelectorSnapshot(
			cache,
			store,
			selectAllocatingReviewStoreSnapshot,
		);

		expect(afterStoreChange).not.toBe(firstSnapshot);
		expect(afterStoreChange.actions).toBe(firstSnapshot.actions);
		expect(repeatedAfterStoreChange).toBe(afterStoreChange);
	});

	test('owns viewer search filter and render-mode state as pure state transitions', () => {
		const store = createBridgeReviewViewerStore();

		store.getState().actions.setTreeSearchText('docs');
		store.getState().actions.setTreeSearchMode({ kind: 'regex' });
		store.getState().actions.setGitStatusFilter('modified');
		store.getState().actions.setFileClassFilter('docs');
		store.getState().actions.setRenderMode({ kind: 'markdownPreview' });

		expect(store.getState().rootSnapshot).toMatchObject({
			treeSearchText: 'docs',
			treeSearchMode: { kind: 'regex' },
			gitStatusFilter: 'modified',
			fileClassFilter: 'docs',
			renderMode: { kind: 'markdownPreview' },
		});
	});

	test('keeps review mode separate from file-filter facets', () => {
		const store = createBridgeReviewViewerStore();

		store.getState().actions.setProjectionFacets([{ kind: 'fileClass', fileClasses: ['docs'] }]);
		store.getState().actions.setProjectionMode({ kind: 'guidedReview' });

		expect(store.getState().rootSnapshot.projectionMode).toEqual({ kind: 'guidedReview' });
		expect(store.getState().rootSnapshot.facets).toEqual([
			{ kind: 'fileClass', fileClasses: ['docs'] },
		]);
	});

	test('discards stale worker projection results before mutating projection state', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
		const sourceRequest = {
			mode: { kind: 'normalReview' },
			facets: [{ kind: 'fileClass', fileClasses: ['source'] }],
		} as const;
		const docsRequest = { mode: { kind: 'plansAndSpecs' }, facets: [] } as const;
		const sourceIdentity = {
			requestId: 'request-source',
			packageId: projectionInput.packageId,
			reviewGeneration: projectionInput.reviewGeneration,
			revision: projectionInput.revision,
			projectionRequestFingerprint: fingerprintBridgeReviewProjectionRequest(sourceRequest),
			abortKey: 'projection',
		};
		const docsIdentity = {
			requestId: 'request-docs',
			packageId: projectionInput.packageId,
			reviewGeneration: projectionInput.reviewGeneration,
			revision: projectionInput.revision,
			projectionRequestFingerprint: fingerprintBridgeReviewProjectionRequest(docsRequest),
			abortKey: 'projection',
		};
		const sourceProjection = buildBridgeReviewProjection({
			reviewPackage,
			request: sourceRequest,
		});
		const docsProjection = buildBridgeReviewProjection({
			reviewPackage,
			request: docsRequest,
		});
		const store = createBridgeReviewViewerStore();

		store.getState().actions.startProjectionRequest(sourceIdentity);
		store.getState().actions.startProjectionRequest(docsIdentity);

		expect(
			store.getState().actions.applyProjectionWorkerResult({
				identity: sourceIdentity,
				result: sourceProjection,
			}),
		).toBe(false);
		expect(store.getState().projection).toBeNull();

		expect(
			store.getState().actions.applyProjectionWorkerResult({
				identity: docsIdentity,
				result: docsProjection,
			}),
		).toBe(true);
		expect(store.getState().projection?.orderedItemIds).toEqual(['docs-plan']);
	});

	test('keeps the last completed projection visible while a newer stream revision is projecting', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
		const projectionRequest = {
			mode: { kind: 'normalReview' },
			facets: [],
		} as const;
		const completedIdentity = {
			requestId: 'request-revision-1',
			packageId: projectionInput.packageId,
			reviewGeneration: projectionInput.reviewGeneration,
			revision: projectionInput.revision,
			projectionRequestFingerprint: fingerprintBridgeReviewProjectionRequest(projectionRequest),
			abortKey: 'projection',
		};
		const nextRevisionIdentity = {
			...completedIdentity,
			requestId: 'request-revision-2',
			revision: projectionInput.revision + 1,
		};
		const completedProjection = buildBridgeReviewProjection({
			reviewPackage,
			request: projectionRequest,
		});
		const store = createBridgeReviewViewerStore();

		store.getState().actions.startProjectionRequest(completedIdentity);
		store.getState().actions.applyProjectionWorkerResult({
			identity: completedIdentity,
			result: completedProjection,
		});
		store.getState().actions.setSelectedItemId('source-high');
		store.getState().actions.startProjectionRequest(nextRevisionIdentity);

		expect(store.getState().rootSnapshot.projectionStatus).toBe('running');
		expect(store.getState().rootSnapshot.selectedItemId).toBe('source-high');
		expect(store.getState().projection).toBe(completedProjection);
		expect(store.getState().projectionIdentity).toEqual(completedIdentity);
	});

	test('keeps runtime controls out of the Zustand snapshot', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
		const projectionRequest = {
			mode: { kind: 'normalReview' },
			facets: [],
		} as const;
		const projectionIdentity = {
			requestId: 'request-normal',
			packageId: projectionInput.packageId,
			reviewGeneration: projectionInput.reviewGeneration,
			revision: projectionInput.revision,
			projectionRequestFingerprint: fingerprintBridgeReviewProjectionRequest(projectionRequest),
			abortKey: 'projection',
		};
		const store = createBridgeReviewViewerStore();

		store.getState().actions.startProjectionRequest(projectionIdentity);
		store.getState().actions.applyProjectionWorkerResult({
			identity: projectionIdentity,
			result: buildBridgeReviewProjection({ reviewPackage, request: projectionRequest }),
		});
		store.getState().actions.setSelectedItemId('source-high');

		const snapshot = serializableViewerStateForBodyBoundary(store.getState());
		const snapshotJSON = JSON.stringify(snapshot);

		expect(snapshotJSON).not.toContain('large base text');
		expect(snapshotJSON).not.toContain('large head text');
		expect(snapshotJSON).not.toContain('agentstudio://resource');
		expect(containsRuntimeControlObject(snapshot)).toBe(false);
	});
});

function serializableViewerStateForBodyBoundary(
	state: BridgeReviewViewerStoreState,
): Omit<BridgeReviewViewerStoreState, 'actions'> {
	const { actions, ...snapshot } = state;
	void actions;
	return snapshot;
}

function selectAllocatingReviewStoreSnapshot(state: BridgeReviewViewerStoreState): {
	readonly actions: unknown;
	readonly selectedItemId: string | null;
} {
	return {
		actions: state.actions,
		selectedItemId: state.selectionSlice.selectedItemId,
	};
}

function containsRuntimeControlObject(value: unknown): boolean {
	if (value instanceof Promise || value instanceof AbortController) {
		return true;
	}
	if (typeof Worker !== 'undefined' && value instanceof Worker) {
		return true;
	}
	if (Array.isArray(value)) {
		return value.some(containsRuntimeControlObject);
	}
	if (typeof value !== 'object' || value === null) {
		return false;
	}
	return Object.values(value).some(containsRuntimeControlObject);
}
