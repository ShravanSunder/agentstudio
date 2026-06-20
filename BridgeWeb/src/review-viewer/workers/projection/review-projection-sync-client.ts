import {
	createBridgeReviewProjectionWorkerClient,
	type BridgeReviewProjectionWorkerClient,
} from './review-projection-worker-client.js';
import {
	buildBridgeReviewProjectionWorkerSuccessResponse,
	type BridgeReviewProjectionWorkerRequest,
	type BridgeReviewProjectionWorkerResponse,
} from './review-projection-worker-rpc.js';

export interface CreateBridgeReviewProjectionSyncClientProps {
	readonly createRequestId?: () => string;
	readonly now?: () => number;
}

export function createBridgeReviewProjectionSyncClient(
	props: CreateBridgeReviewProjectionSyncClientProps = {},
): BridgeReviewProjectionWorkerClient {
	const now = props.now ?? defaultNow;
	return createBridgeReviewProjectionWorkerClient({
		...(props.createRequestId === undefined ? {} : { createRequestId: props.createRequestId }),
		transport: {
			send: async (
				request: BridgeReviewProjectionWorkerRequest,
			): Promise<BridgeReviewProjectionWorkerResponse> => {
				const start = now();
				await Promise.resolve();
				return buildBridgeReviewProjectionWorkerSuccessResponse({
					request,
					durationMilliseconds: now() - start,
				});
			},
		},
	});
}

function defaultNow(): number {
	return performance.now();
}
