// oxlint-disable unicorn/require-post-message-target-origin -- Dedicated worker postMessage does not accept a targetOrigin argument.
import {
	bridgeReviewProjectionWorkerResponseSchema,
	bridgeReviewProjectionWorkerRequestSchema,
	buildBridgeReviewProjectionWorkerSuccessResponse,
	identityFromWorkerRequest,
	type BridgeReviewProjectionWorkerFailureResponse,
	type BridgeReviewProjectionWorkerRequest,
} from './review-projection-worker-rpc.js';

self.addEventListener('message', (event: MessageEvent<unknown>): void => {
	const parsedRequest = bridgeReviewProjectionWorkerRequestSchema.safeParse(event.data);
	if (!parsedRequest.success) {
		return;
	}

	const request = parsedRequest.data;
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
