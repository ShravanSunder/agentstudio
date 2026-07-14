import {
	bridgeProductControlResponseSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import {
	bridgeProductDevControlIdentity,
	type BridgeProductDevSession,
} from './bridge-product-dev-session.js';

type BridgeProductDevCallRequest = Extract<
	BridgeProductControlRequest,
	{ readonly kind: 'product.call' }
>;

export async function handleBridgeProductDevCall(
	session: BridgeProductDevSession,
	request: BridgeProductDevCallRequest,
): Promise<BridgeProductControlResponse> {
	switch (request.call.method) {
		case 'file.source.current':
			session.fileSource ??= await (await session.loadFileAdapter()).loadSource();
			return bridgeProductControlResponseSchema.parse({
				...bridgeProductDevControlIdentity(request),
				call: {
					method: request.call.method,
					result: { source: session.fileSource.configuration, status: 'available' },
				},
				kind: 'call.completed',
			});
		case 'file.activeViewerMode.update':
		case 'review.activeViewerMode.update':
		case 'review.intake.ready':
		case 'review.markFileViewed':
			return bridgeProductControlResponseSchema.parse({
				...bridgeProductDevControlIdentity(request),
				call: { method: request.call.method, result: null },
				kind: 'call.completed',
			});
	}
	throw new Error('Bridge product dev call method is unsupported.');
}
