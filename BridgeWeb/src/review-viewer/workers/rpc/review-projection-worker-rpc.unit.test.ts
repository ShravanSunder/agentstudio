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
	test('validates typed projection requests and rejects untyped success payloads', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
		const projectionRequest = {
			base: { kind: 'source' },
			refinements: [{ kind: 'folder', folderPath: 'Sources/App' }],
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
			base: { kind: 'guidedReview' },
			refinements: [
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
});
