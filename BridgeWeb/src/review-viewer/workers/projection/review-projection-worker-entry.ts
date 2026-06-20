// oxlint-disable unicorn/require-post-message-target-origin -- Dedicated worker postMessage does not accept a targetOrigin argument.
import {
	bridgeReviewProjectionWorkerResponseSchema,
	bridgeReviewProjectionWorkerRequestSchema,
	buildBridgeReviewProjectionWorkerSuccessResponse,
	identityFromWorkerRequest,
	type BridgeReviewProjectionWorkerFailureResponse,
	type BridgeReviewProjectionWorkerRequest,
} from './review-projection-worker-rpc.js';

const abortedRequestKeys = new Set<string>();

self.addEventListener('message', (event: MessageEvent<unknown>): void => {
	const abortKey = parseAbortMessage(event.data);
	if (abortKey !== null) {
		abortedRequestKeys.add(abortKey);
		return;
	}

	const parsedRequest = bridgeReviewProjectionWorkerRequestSchema.safeParse(event.data);
	if (!parsedRequest.success) {
		return;
	}

	const request = parsedRequest.data;
	if (request.abortKey !== undefined && abortedRequestKeys.has(request.abortKey)) {
		abortedRequestKeys.delete(request.abortKey);
		postProjectionFailure(request, 'aborted', 'Projection request was aborted');
		return;
	}

	const start = performance.now();
	try {
		self.postMessage(
			buildBridgeReviewProjectionWorkerSuccessResponse({
				request,
				durationMilliseconds: performance.now() - start,
			}),
		);
	} catch {
		postProjectionFailure(request, 'projectionFailed', 'Projection worker failed');
	}
});

function parseAbortMessage(value: unknown): string | null {
	if (typeof value !== 'object' || value === null) {
		return null;
	}
	if (!('schemaVersion' in value) || value.schemaVersion !== 1) {
		return null;
	}
	if (!('method' in value) || value.method !== 'reviewProjection.abort') {
		return null;
	}
	if (!('abortKey' in value) || typeof value.abortKey !== 'string' || value.abortKey.length === 0) {
		return null;
	}
	return value.abortKey;
}

function postProjectionFailure(
	request: BridgeReviewProjectionWorkerRequest,
	code: BridgeReviewProjectionWorkerFailureResponse['error']['code'],
	message: string,
): void {
	const response = {
		schemaVersion: 1,
		method: request.method,
		ok: false,
		...identityFromWorkerRequest(request),
		error: { code, message },
	} satisfies BridgeReviewProjectionWorkerFailureResponse;

	self.postMessage(bridgeReviewProjectionWorkerResponseSchema.parse(response));
}
