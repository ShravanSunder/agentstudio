import { createHash } from 'node:crypto';

import {
	bridgeProductContentAcceptedHeaderSchema,
	bridgeProductContentIdentityFromDescriptor,
	type BridgeProductContentDescriptor,
	type BridgeProductContentKind,
	type BridgeProductContentRequest,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import { BridgeProductContentFrameEncoder } from '../../src/core/comm-worker/bridge-product-content-frame-codec.js';
import { BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import type { BridgeProductFrameAcknowledgementRequest } from '../../src/core/comm-worker/bridge-product-frame-acknowledgement-contracts.js';
import {
	writeBridgeProductDevResponseChunk,
	type BridgeProductDevWritableResponse,
} from './bridge-product-dev-http.js';
import {
	BridgeProductDevObservationGate,
	type BridgeProductDevObservationDisposition,
} from './bridge-product-dev-observation-gate.js';

type BridgeProductDevContentObservation = Extract<
	BridgeProductFrameAcknowledgementRequest,
	{ readonly streamKind: 'content' }
>;

export interface BridgeProductDevContentPayload {
	readonly bytes: Uint8Array;
	readonly descriptor: BridgeProductContentDescriptor<BridgeProductContentKind>;
	readonly endOfSource: boolean;
}

export interface BridgeProductDevContentProducerSnapshot {
	readonly responseCount: number;
	readonly waiterCount: number;
}

export class BridgeProductDevContentProducer {
	readonly #gate = new BridgeProductDevObservationGate<BridgeProductDevContentObservation>();
	readonly #request: BridgeProductContentRequest;
	readonly #response: BridgeProductDevWritableResponse;
	#settled = false;

	constructor(props: {
		readonly request: BridgeProductContentRequest;
		readonly response: BridgeProductDevWritableResponse;
	}) {
		this.#request = props.request;
		this.#response = props.response;
	}

	get request(): BridgeProductContentRequest {
		return this.#request;
	}

	observe(observation: BridgeProductDevContentObservation): BridgeProductDevObservationDisposition {
		return this.#gate.observe(observation);
	}

	async start(content: BridgeProductDevContentPayload): Promise<void> {
		if (JSON.stringify(content.descriptor) !== JSON.stringify(this.#request.descriptor)) {
			throw new Error('Bridge product dev content descriptor does not match its request.');
		}
		const encoder = new BridgeProductContentFrameEncoder(this.#request);
		try {
			await this.#writeObservedFrame({
				bytes: encoder.encode({
					header: bridgeProductContentAcceptedHeaderSchema.parse({
						contentRequestId: this.#request.contentRequestId,
						contentSequence: 0,
						declaredByteLength: this.#request.descriptor.declaredByteLength,
						expectedSha256: this.#request.descriptor.expectedSha256,
						identity: bridgeProductContentIdentityFromDescriptor(this.#request.descriptor),
						kind: 'content.accepted',
						leaseId: this.#request.leaseId,
						maximumBytes: this.#request.descriptor.maximumBytes,
						paneSessionId: this.#request.paneSessionId,
						wireVersion: this.#request.wireVersion,
						workerDerivationEpoch: this.#request.workerDerivationEpoch,
						workerInstanceId: this.#request.workerInstanceId,
					}),
					payload: new Uint8Array(),
				}),
				contentSequence: 0,
			});
			let contentSequence = 1;
			for (
				let offsetBytes = 0;
				offsetBytes < content.bytes.byteLength;
				offsetBytes += BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES
			) {
				const payload = content.bytes.slice(
					offsetBytes,
					offsetBytes + BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
				);
				// oxlint-disable-next-line no-await-in-loop -- Each content frame waits for its own observation.
				await this.#writeObservedFrame({
					bytes: encoder.encode({
						header: { contentSequence, kind: 'content.data', offsetBytes },
						payload,
					}),
					contentSequence,
				});
				contentSequence += 1;
			}
			await this.#writeObservedFrame({
				bytes: encoder.encode({
					header: {
						contentSequence,
						endOfSource: content.endOfSource,
						kind: 'content.end',
						observedByteLength: content.bytes.byteLength,
						observedSha256: createHash('sha256').update(content.bytes).digest('hex'),
					},
					payload: new Uint8Array(),
				}),
				contentSequence,
			});
			encoder.finish();
			this.#settled = true;
			this.#response.end();
		} catch (error) {
			this.cancel();
			throw error;
		}
	}

	cancel(): void {
		if (this.#settled) return;
		this.#settled = true;
		this.#gate.cancel('Bridge product dev content observation was cancelled.');
	}

	snapshot(): BridgeProductDevContentProducerSnapshot {
		return {
			responseCount: this.#settled ? 0 : 1,
			waiterCount: this.#gate.snapshot().waiterCount,
		};
	}

	async #writeObservedFrame(props: {
		readonly bytes: Uint8Array;
		readonly contentSequence: number;
	}): Promise<void> {
		const observation = contentObservationForRequest(this.#request, props.contentSequence);
		const waitForObservation = this.#gate.register({ observation });
		try {
			await writeBridgeProductDevResponseChunk(this.#response, props.bytes);
			await waitForObservation;
		} catch (error) {
			this.#gate.cancel('Bridge product dev content frame write was cancelled.');
			await waitForObservation.catch((): void => {});
			throw error;
		}
	}
}

function contentObservationForRequest(
	request: BridgeProductContentRequest,
	contentSequence: number,
): BridgeProductDevContentObservation {
	return {
		contentRequestId: request.contentRequestId,
		contentSequence,
		kind: 'stream.frameObserved',
		leaseId: request.leaseId,
		paneSessionId: request.paneSessionId,
		streamKind: 'content',
		wireVersion: request.wireVersion,
		workerInstanceId: request.workerInstanceId,
	};
}
