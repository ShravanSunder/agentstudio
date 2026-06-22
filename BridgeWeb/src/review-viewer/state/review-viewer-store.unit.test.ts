import { describe, expect, test } from 'vitest';

import {
	buildBridgeReviewProjection,
	makeBridgeReviewProjectionInput,
} from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { fingerprintBridgeReviewProjectionRequest } from '../workers/projection/review-projection-worker-rpc.js';
import {
	createBridgeReviewViewerStore,
	selectBridgeReviewViewerRootSnapshot,
} from './review-viewer-store.js';

describe('Bridge review viewer Zustand store', () => {
	test('keeps root subscriptions stable for worker stats and content hydration updates', () => {
		const store = createBridgeReviewViewerStore();
		let rootRenderCount = 0;
		const unsubscribe = store.subscribe(selectBridgeReviewViewerRootSnapshot, () => {
			rootRenderCount += 1;
		});

		store.getState().actions.setWorkerStatus({
			lane: 'worker',
			pendingRequestCount: 1,
			lastCompletedRequestId: null,
		});
		store.getState().actions.setContentHydrationStatus({
			itemId: 'source-high',
			status: 'loading',
			contentHandleId: 'handle-source-high',
		});

		expect(rootRenderCount).toBe(0);

		store.getState().actions.setProjectionMode({ kind: 'normalReview' });

		expect(rootRenderCount).toBe(1);
		unsubscribe();
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
});
