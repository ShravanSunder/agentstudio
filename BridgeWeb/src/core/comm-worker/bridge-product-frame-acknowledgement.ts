import { BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES } from './bridge-product-contract-primitives.js';
import {
	bridgeProductFrameAcknowledgementRejectedStatusSchema,
	type BridgeProductFrameAcknowledgementRequest,
} from './bridge-product-frame-acknowledgement-contracts.js';
import type { BridgeProductRequestExecutor } from './bridge-product-request-executor.js';

export async function sendBridgeProductFrameAcknowledgement(props: {
	readonly capabilityHeader: string;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly request: BridgeProductFrameAcknowledgementRequest;
	readonly timeoutMilliseconds: number;
}): Promise<void> {
	const abortController = new AbortController();
	let timeout: ReturnType<typeof globalThis.setTimeout> | undefined;
	try {
		const response = await Promise.race([
			props.executeProductRequest('command', {
				body: encodeRequestBody(props.request),
				headers: {
					'Content-Type': 'application/json',
					'X-AgentStudio-Bridge-Product-Capability': props.capabilityHeader,
				},
				method: 'POST',
				signal: abortController.signal,
			}),
			new Promise<Response>((_, reject): void => {
				timeout = globalThis.setTimeout((): void => {
					abortController.abort();
					reject(
						new BridgeProductFrameAcknowledgementFailure(
							'request_timeout',
							null,
							'Bridge product frame acknowledgement request timed out.',
						),
					);
				}, props.timeoutMilliseconds);
			}),
		]);
		assertAccepted(response.status);
	} catch (error) {
		if (error instanceof BridgeProductFrameAcknowledgementFailure) throw error;
		throw new BridgeProductFrameAcknowledgementFailure(
			'request_failed',
			null,
			'Bridge product frame acknowledgement request failed.',
		);
	} finally {
		if (timeout !== undefined) globalThis.clearTimeout(timeout);
	}
}

function encodeRequestBody(request: BridgeProductFrameAcknowledgementRequest): ArrayBuffer {
	const body = new TextEncoder().encode(JSON.stringify(request));
	if (body.byteLength > BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES) {
		throw new Error('Bridge product request exceeds its body ceiling.');
	}
	return Uint8Array.from(body).buffer;
}

function assertAccepted(status: number): void {
	if (status === 204) return;
	const rejected = bridgeProductFrameAcknowledgementRejectedStatusSchema.safeParse(status);
	throw new BridgeProductFrameAcknowledgementFailure(
		rejected.success ? 'rejected_status' : 'unsupported_status',
		status,
		rejected.success
			? `Bridge product frame acknowledgement was rejected with status ${status}.`
			: `Bridge product frame acknowledgement returned unsupported status ${status}.`,
	);
}

type FailureCode = 'rejected_status' | 'request_failed' | 'request_timeout' | 'unsupported_status';

export class BridgeProductFrameAcknowledgementFailure extends Error {
	constructor(
		readonly failureCode: FailureCode,
		readonly status: number | null,
		message: string,
	) {
		super(message);
		this.name = 'BridgeProductFrameAcknowledgementFailure';
	}
}
