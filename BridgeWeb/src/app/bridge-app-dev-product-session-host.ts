import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from '../core/comm-worker/bridge-product-contract-primitives.js';
import { bridgeProductSessionBootstrapSchema } from '../core/comm-worker/bridge-product-session-contracts.js';

type BridgeAppDevProductSessionTarget = Pick<
	EventTarget,
	'addEventListener' | 'dispatchEvent' | 'removeEventListener'
>;

export interface BridgeAppDevProductSessionHost {
	readonly dispose: () => void;
}

let bridgeAppDevProductWorkerSequence = 0;

export function installBridgeAppDevProductSessionHost(
	target: BridgeAppDevProductSessionTarget = document,
): BridgeAppDevProductSessionHost {
	let isInstalled = true;
	const handleBootstrapRequest = (event: Event): void => {
		if (!isInstalled || !('detail' in event)) return;
		const requestId = productBootstrapRequestId(event.detail);
		if (requestId === null) return;
		bridgeAppDevProductWorkerSequence =
			(bridgeAppDevProductWorkerSequence + 1) % Number.MAX_SAFE_INTEGER;
		const workerSequence = bridgeAppDevProductWorkerSequence.toString(36);
		const capabilityBytes = new Uint8Array(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		crypto.getRandomValues(capabilityBytes);
		const bootstrap = bridgeProductSessionBootstrapSchema.parse({
			kind: 'productSession.bootstrap',
			paneSessionId: 'vite-dev-pane-session',
			policy: {
				maximumContentBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maximumMetadataFrameBytes: BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
				maximumQueuedStreamBytes: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
				maximumQueuedStreamFrames: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
				maximumRequestBodyBytes: BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
				terminalFrameReserve: BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
			},
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId: `vite-dev-worker-${workerSequence}`,
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_product_session_bootstrap', {
				detail: {
					bootstrap,
					productCapability: capabilityBytes.buffer,
					requestId,
				},
			}),
		);
	};

	target.addEventListener('__bridge_product_session_bootstrap_request', handleBootstrapRequest);
	return {
		dispose: (): void => {
			if (!isInstalled) return;
			isInstalled = false;
			target.removeEventListener(
				'__bridge_product_session_bootstrap_request',
				handleBootstrapRequest,
			);
		},
	};
}

function productBootstrapRequestId(detail: unknown): string | null {
	if (
		typeof detail !== 'object' ||
		detail === null ||
		!('requestId' in detail) ||
		!('reason' in detail) ||
		typeof detail.requestId !== 'string' ||
		detail.requestId.length === 0 ||
		(detail.reason !== 'initial' && detail.reason !== 'workerReplacement')
	) {
		return null;
	}
	return detail.requestId;
}
