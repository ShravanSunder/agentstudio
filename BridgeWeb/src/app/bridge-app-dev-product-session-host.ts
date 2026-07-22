import {
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_REQUEST_MEDIA_TYPE,
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE,
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE,
	decodeBridgeProductDevBootstrapDelivery,
	type BridgeProductDevBootstrapRequest,
} from '../core/comm-worker/bridge-product-dev-bootstrap.js';

type BridgeAppDevProductSessionTarget = Pick<
	EventTarget,
	'addEventListener' | 'dispatchEvent' | 'removeEventListener'
>;

export interface BridgeAppDevProductSessionHost {
	readonly dispose: () => void;
}

export interface BridgeAppDevProductSessionHostProps {
	readonly fetchBootstrap?: typeof fetch;
	readonly target?: BridgeAppDevProductSessionTarget;
}

export function installBridgeAppDevProductSessionHost(
	props: BridgeAppDevProductSessionHostProps = {},
): BridgeAppDevProductSessionHost {
	const target = props.target ?? document;
	const fetchBootstrap = props.fetchBootstrap ?? globalThis.fetch.bind(globalThis);
	let activeRequestController: AbortController | null = null;
	let isInstalled = true;
	let paneSessionId: string | null = null;
	let requestSequence = 0;

	const handleBootstrapRequest = (event: Event): void => {
		if (!isInstalled || !('detail' in event)) return;
		const request = productBootstrapRequest(event.detail);
		if (request === null) return;
		const bootstrapRequest = bridgeProductDevBootstrapRequest({
			paneSessionId,
			reason: request.reason,
		});
		if (bootstrapRequest === null) return;
		requestSequence += 1;
		const issuedRequestSequence = requestSequence;
		activeRequestController?.abort();
		const requestController = new AbortController();
		activeRequestController = requestController;
		void fetchRegisteredBootstrap({
			fetchBootstrap,
			request: bootstrapRequest,
			signal: requestController.signal,
		})
			.then(
				(delivery): void => {
					if (!isInstalled || issuedRequestSequence !== requestSequence) {
						new Uint8Array(delivery.productCapability).fill(0);
						return;
					}
					paneSessionId = delivery.bootstrap.paneSessionId;
					target.dispatchEvent(
						new CustomEvent('__bridge_product_session_bootstrap', {
							detail: {
								bootstrap: delivery.bootstrap,
								productCapability: delivery.productCapability,
								requestId: request.requestId,
							},
						}),
					);
				},
				(): void => {
					// The pane-session bootstrap timeout owns visible failure and replacement.
				},
			)
			.finally((): void => {
				if (activeRequestController === requestController) activeRequestController = null;
			});
	};

	target.addEventListener('__bridge_product_session_bootstrap_request', handleBootstrapRequest);
	return {
		dispose: (): void => {
			if (!isInstalled) return;
			isInstalled = false;
			requestSequence += 1;
			activeRequestController?.abort();
			activeRequestController = null;
			target.removeEventListener(
				'__bridge_product_session_bootstrap_request',
				handleBootstrapRequest,
			);
		},
	};
}

async function fetchRegisteredBootstrap(props: {
	readonly fetchBootstrap: typeof fetch;
	readonly request: BridgeProductDevBootstrapRequest;
	readonly signal: AbortSignal;
}): Promise<ReturnType<typeof decodeBridgeProductDevBootstrapDelivery>> {
	const response = await props.fetchBootstrap(BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE, {
		body: JSON.stringify(props.request),
		cache: 'no-store',
		credentials: 'same-origin',
		headers: { 'Content-Type': BRIDGE_PRODUCT_DEV_BOOTSTRAP_REQUEST_MEDIA_TYPE },
		method: 'POST',
		signal: props.signal,
	});
	if (
		!response.ok ||
		response.headers.get('content-type') !== BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE
	) {
		throw new Error('Bridge product dev bootstrap request was rejected.');
	}
	return decodeBridgeProductDevBootstrapDelivery(await response.arrayBuffer());
}

function bridgeProductDevBootstrapRequest(props: {
	readonly paneSessionId: string | null;
	readonly reason: 'initial' | 'workerReplacement';
}): BridgeProductDevBootstrapRequest | null {
	if (props.reason === 'initial') return { reason: props.reason };
	return props.paneSessionId === null
		? null
		: { paneSessionId: props.paneSessionId, reason: props.reason };
}

function productBootstrapRequest(detail: unknown): {
	readonly reason: BridgeProductDevBootstrapRequest['reason'];
	readonly requestId: string;
} | null {
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
	return { reason: detail.reason, requestId: detail.requestId };
}
