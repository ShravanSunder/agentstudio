import { describe, expect, test } from 'vitest';

import {
	buildBridgeReviewProjectionFromInput,
	makeBridgeReviewProjectionInput,
} from '../../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../../test-support/review-viewer-fixtures.js';
import {
	bridgeReviewProjectionWorkerRequestSchema,
	bridgeReviewProjectionWorkerResponseSchema,
	buildBridgeReviewProjectionWorkerSuccessResponse,
	fingerprintBridgeReviewProjectionRequest,
} from './review-projection-worker-rpc.js';

describe('review projection worker RPC contract', () => {
	test('fingerprints projection requests without requiring ES2023 Array toSorted', () => {
		const projectionRequest = {
			mode: { kind: 'normalReview' },
			facets: [
				{ kind: 'fileClass', fileClasses: ['source'] },
				{ kind: 'folder', folderPath: 'Sources/App' },
			],
		} as const;
		const arrayPrototype = Array.prototype as Array<unknown> & {
			toSorted?: Array<unknown>['toSorted'];
		};
		const originalToSorted = arrayPrototype.toSorted;
		Reflect.deleteProperty(arrayPrototype, 'toSorted');

		try {
			expect(fingerprintBridgeReviewProjectionRequest(projectionRequest)).toBe(
				'review-projection:{"facets":[{"fileClasses":["source"],"kind":"fileClass"},{"folderPath":"Sources/App","kind":"folder"}],"mode":{"kind":"normalReview"}}',
			);
		} finally {
			if (originalToSorted !== undefined) {
				arrayPrototype.toSorted = originalToSorted;
			}
		}
	});

	test('validates typed projection requests and rejects untyped success payloads', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
		const projectionRequest = {
			mode: { kind: 'normalReview' },
			facets: [
				{ kind: 'fileClass', fileClasses: ['source'] },
				{ kind: 'folder', folderPath: 'Sources/App' },
			],
		} as const;
		const request = bridgeReviewProjectionWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'reviewProjection.build',
			requestId: 'request-source-folder',
			abortKey: 'package-42:projection',
			packageId: projectionInput.packageId,
			reviewGeneration: projectionInput.reviewGeneration,
			revision: projectionInput.revision,
			projectionRequestFingerprint: fingerprintBridgeReviewProjectionRequest(projectionRequest),
			projectionRequest,
			projectionInput,
			visibleItemIds: ['source-high'],
			workloadId: 'interactive',
		});

		const successResponse = buildBridgeReviewProjectionWorkerSuccessResponse({
			request,
			durationMilliseconds: 12.5,
		});

		expect(successResponse.result.orderedItemIds).toEqual([
			'source-high',
			'source-normal',
			'duplicate-display',
		]);
		expect(bridgeReviewProjectionWorkerResponseSchema.parse(successResponse).ok).toBe(true);
		expect(() =>
			bridgeReviewProjectionWorkerResponseSchema.parse({
				...successResponse,
				result: {},
			}),
		).toThrow();
	});

	test('matches the direct projection builder for the same compact input', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
		const projectionRequest = {
			mode: { kind: 'guidedReview' },
			facets: [
				{ kind: 'visibility', includeHidden: true, includeBinary: true, includeLarge: true },
			],
		} as const;
		const request = bridgeReviewProjectionWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'reviewProjection.build',
			requestId: 'request-guided',
			packageId: projectionInput.packageId,
			reviewGeneration: projectionInput.reviewGeneration,
			revision: projectionInput.revision,
			projectionRequestFingerprint: fingerprintBridgeReviewProjectionRequest(projectionRequest),
			projectionRequest,
			projectionInput,
			visibleItemIds: [],
			workloadId: 'bridge_viewer_medium_review_v1',
		});

		const directProjection = buildBridgeReviewProjectionFromInput({
			projectionInput,
			request: projectionRequest,
		});
		const workerResponse = buildBridgeReviewProjectionWorkerSuccessResponse({
			request,
			durationMilliseconds: 1,
		});

		expect(workerResponse.result).toEqual(directProjection);
	});

	test('threads the guided-order freeze hint through the RPC without touching the request fingerprint or projectionId (F5)', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projectionRequest = {
			mode: { kind: 'guidedReview' },
			facets: [
				{ kind: 'visibility', includeHidden: true, includeBinary: true, includeLarge: true },
			],
		} as const;
		const initialOrder = buildBridgeReviewProjectionFromInput({
			projectionInput: makeBridgeReviewProjectionInput(reviewPackage),
			request: projectionRequest,
		}).orderedItemIds;

		// Streaming flips a ranking key on an already-projected row.
		const sourceHigh = reviewPackage.itemsById['source-high'];
		if (sourceHigh === undefined) {
			throw new Error('expected source-high fixture item');
		}
		const streamedInput = makeBridgeReviewProjectionInput({
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': { ...sourceHigh, reviewState: 'resolved' as const },
			},
		});
		const fingerprint = fingerprintBridgeReviewProjectionRequest(projectionRequest);
		const makeRequest = (
			stableGuidedOrderHint?: readonly string[],
		): ReturnType<typeof bridgeReviewProjectionWorkerRequestSchema.parse> =>
			bridgeReviewProjectionWorkerRequestSchema.parse({
				schemaVersion: 1,
				method: 'reviewProjection.build',
				requestId: 'request-f5',
				packageId: streamedInput.packageId,
				reviewGeneration: streamedInput.reviewGeneration,
				revision: streamedInput.revision,
				projectionRequestFingerprint: fingerprint,
				projectionRequest,
				projectionInput: streamedInput,
				visibleItemIds: [],
				workloadId: 'interactive',
				...(stableGuidedOrderHint === undefined ? {} : { stableGuidedOrderHint }),
			});

		const hintedResponse = buildBridgeReviewProjectionWorkerSuccessResponse({
			request: makeRequest(initialOrder),
			durationMilliseconds: 1,
		});
		const unhintedResponse = buildBridgeReviewProjectionWorkerSuccessResponse({
			request: makeRequest(),
			durationMilliseconds: 1,
		});

		// The hint freezes the streamed order back to the initial order; without it the row moves.
		expect(hintedResponse.result.orderedItemIds).toEqual(initialOrder);
		expect(unhintedResponse.result.orderedItemIds[0]).not.toBe('source-high');
		// The hint must NOT alter the dedup fingerprint or the projectionId.
		expect(makeRequest(initialOrder).projectionRequestFingerprint).toBe(
			makeRequest().projectionRequestFingerprint,
		);
		expect(hintedResponse.result.projectionId).toBe(unhintedResponse.result.projectionId);
	});
});
