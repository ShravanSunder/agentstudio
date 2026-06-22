import { describe, expect, test } from 'vitest';

import { makeBridgeReviewProjectionInput } from '../../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../../test-support/review-viewer-fixtures.js';
import {
	createBridgeReviewProjectionWorkerClient,
	type BridgeReviewProjectionWorkerTransport,
} from './review-projection-worker-client.js';
import {
	buildBridgeReviewProjectionWorkerSuccessResponse,
	type BridgeReviewProjectionWorkerRequest,
	type BridgeReviewProjectionWorkerResponse,
} from './review-projection-worker-rpc.js';

describe('Bridge review projection worker client', () => {
	test('supersedes an older request with the same abort key before completion reaches state', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
		const deferredResponses = new Map<
			string,
			ReturnType<typeof createDeferred<BridgeReviewProjectionWorkerResponse>>
		>();
		const abortedKeys: string[] = [];
		const transport: BridgeReviewProjectionWorkerTransport = {
			abort: (abortKey: string): void => {
				abortedKeys.push(abortKey);
			},
			send: (
				request: BridgeReviewProjectionWorkerRequest,
			): Promise<BridgeReviewProjectionWorkerResponse> => {
				const deferred = createDeferred<BridgeReviewProjectionWorkerResponse>();
				deferredResponses.set(request.requestId, deferred);
				return deferred.promise;
			},
		};
		let requestCount = 0;
		const client = createBridgeReviewProjectionWorkerClient({
			transport,
			createRequestId: (): string => {
				requestCount += 1;
				return `request-${requestCount}`;
			},
		});

		const firstTask = client.startProjection({
			abortKey: 'projection',
			projectionInput,
			projectionRequest: {
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'fileClass', fileClasses: ['source'] }],
			},
			visibleItemIds: [],
			workloadId: 'bridge_viewer_medium_review_v1',
		});
		const secondTask = client.startProjection({
			abortKey: 'projection',
			projectionInput,
			projectionRequest: { mode: { kind: 'plansAndSpecs' }, facets: [] },
			visibleItemIds: [],
			workloadId: 'bridge_viewer_medium_review_v1',
		});

		expect(abortedKeys).toEqual(['projection']);

		deferredResponses.get(secondTask.identity.requestId)?.resolve(
			buildBridgeReviewProjectionWorkerSuccessResponse({
				request: secondTask.request,
				durationMilliseconds: 3,
			}),
		);
		deferredResponses.get(firstTask.identity.requestId)?.resolve(
			buildBridgeReviewProjectionWorkerSuccessResponse({
				request: firstTask.request,
				durationMilliseconds: 12,
			}),
		);

		await expect(secondTask.completed).resolves.toMatchObject({
			status: 'success',
			identity: secondTask.identity,
		});
		await expect(firstTask.completed).resolves.toEqual({
			status: 'stale',
			reason: 'superseded',
			identity: firstTask.identity,
		});
	});

	test('rejects out-of-order completions with stale request identity fields', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
		const transport: BridgeReviewProjectionWorkerTransport = {
			send: async (
				request: BridgeReviewProjectionWorkerRequest,
			): Promise<BridgeReviewProjectionWorkerResponse> => ({
				...buildBridgeReviewProjectionWorkerSuccessResponse({
					request,
					durationMilliseconds: 1,
				}),
				reviewGeneration: request.reviewGeneration + 1,
			}),
		};
		const client = createBridgeReviewProjectionWorkerClient({
			transport,
			createRequestId: (): string => 'request-stale-generation',
		});
		const task = client.startProjection({
			projectionInput,
			projectionRequest: {
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'fileClass', fileClasses: ['source'] }],
			},
			visibleItemIds: [],
			workloadId: 'interactive',
		});

		await expect(task.completed).resolves.toEqual({
			status: 'stale',
			reason: 'identityMismatch',
			identity: task.identity,
		});
	});
});

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
	readonly reject: (error: Error) => void;
}

function createDeferred<TValue>(): Deferred<TValue> {
	let resolveValue: ((value: TValue) => void) | null = null;
	let rejectValue: ((error: Error) => void) | null = null;
	const promise = new Promise<TValue>((resolve, reject): void => {
		resolveValue = resolve;
		rejectValue = reject;
	});
	if (resolveValue === null || rejectValue === null) {
		throw new Error('Deferred promise handlers were not initialized.');
	}

	return {
		promise,
		resolve: resolveValue,
		reject: rejectValue,
	};
}
