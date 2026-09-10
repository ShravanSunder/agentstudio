import {
	bridgeProductContentAcceptedIdentityMatchesRequest,
	bridgeProductContentAcceptedMaximumMatchesIdentity,
	bridgeProductContentExactFactsForRequest,
	validateBridgeProductContentEndOfSource,
} from './bridge-product-content-application-registry.js';
import {
	bridgeProductContentAcceptedBodySchema,
	bridgeProductContentAcceptedHeaderSchema,
	bridgeProductContentDataHeaderSchema,
	bridgeProductContentEndBodySchema,
	bridgeProductContentEndHeaderSchema,
	bridgeProductContentErrorBodySchema,
	bridgeProductContentHeaderSchema,
	bridgeProductContentRequestSchema,
	bridgeProductContentResetBodySchema,
	type BridgeProductContentFrame,
	type BridgeProductContentHeader,
	type BridgeProductContentKind,
	type BridgeProductContentRequest,
	type BridgeProductContentRequestFor,
	type BridgeProductContentTerminal,
} from './bridge-product-content-contracts.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_CONTROL_BODY_BYTES,
} from './bridge-product-contract-primitives.js';

const bridgeProductContentFramePrefixByteLength = 9;
const bridgeProductContentFrameLengthPrefixByteLength = 4;
const bridgeProductContentFrameSequenceByteLength = 4;
const bridgeProductContentDataOffsetByteLength = 4;
const bridgeProductContentCorrelationByteLength = 32;
const bridgeProductContentCorrelationEnvelopeByteLength =
	1 + bridgeProductContentCorrelationByteLength;

const bridgeProductContentFrameTagByKind = {
	'content.accepted': 0x01,
	'content.data': 0x02,
	'content.end': 0x03,
	'content.error': 0x04,
	'content.reset': 0x05,
} as const satisfies Readonly<Record<BridgeProductContentHeader['kind'], number>>;

export class BridgeProductContentFrameEncoder {
	readonly #expectedRequest: BridgeProductContentRequest;
	#accepted = false;
	#nextOffsetBytes = 0;
	#nextSequence = 0;
	#state: 'open' | 'poisoned' | 'terminal' = 'open';

	constructor(expectedRequest: BridgeProductContentRequest) {
		this.#expectedRequest = bridgeProductContentRequestSchema.parse(expectedRequest);
	}

	encode(frame: BridgeProductContentFrame): Uint8Array {
		if (this.#state === 'terminal') {
			throw new Error('Bridge product content encoder cannot emit after terminal state.');
		}
		if (this.#state === 'poisoned') {
			throw new Error('Bridge product content encoder is poisoned.');
		}
		try {
			const encodedFrame = this.#encodeValidated(frame);
			return encodedFrame;
		} catch (error) {
			this.#state = 'poisoned';
			throw error;
		}
	}

	finish(): void {
		if (this.#state === 'terminal') return;
		if (this.#state === 'poisoned') {
			throw new Error('Bridge product content encoder cannot finish a poisoned stream.');
		}
		this.#state = 'poisoned';
		throw new Error('Bridge product content encoder finished without a terminal frame.');
	}

	#encodeValidated(frame: BridgeProductContentFrame): Uint8Array {
		const header = bridgeProductContentHeaderSchema.parse(frame.header);
		validateBridgeProductContentFramePayload(header, frame.payload);
		validateBridgeProductContentFrameCorrelation(header, this.#expectedRequest);
		const payload = Uint8Array.from(frame.payload);

		if (!this.#accepted) {
			if (header.kind !== 'content.accepted') {
				throw new Error('Bridge product content encoder must begin with content.accepted.');
			}
			validateBridgeProductAcceptedHeaderAgainstRequest(header, this.#expectedRequest);
			this.#accepted = true;
			this.#nextSequence = 1;
			return encodeBridgeProductContentFrameBytes(header, payload);
		}

		if (header.kind === 'content.accepted') {
			throw new Error('Bridge product content encoder cannot emit duplicate acceptance.');
		}
		if (header.contentSequence !== this.#nextSequence) {
			throw new Error('Bridge product content encoder sequence is not contiguous.');
		}
		this.#nextSequence += 1;

		if (header.kind === 'content.data') {
			if (header.offsetBytes !== this.#nextOffsetBytes) {
				throw new Error('Bridge product content encoder offset is not contiguous.');
			}
			const nextOffsetBytes = this.#nextOffsetBytes + payload.byteLength;
			const declaredByteLength = bridgeProductDeclaredByteLengthForRequest(this.#expectedRequest);
			if (
				nextOffsetBytes > this.#expectedRequest.descriptor.maximumBytes ||
				(declaredByteLength !== null && nextOffsetBytes > declaredByteLength)
			) {
				throw new Error('Bridge product content encoder exceeded its admitted byte bounds.');
			}
			this.#nextOffsetBytes = nextOffsetBytes;
		} else {
			if (header.kind === 'content.end' && header.observedByteLength !== this.#nextOffsetBytes) {
				throw new Error('Bridge product content encoder end length does not match emitted bytes.');
			}
			this.#state = 'terminal';
		}
		return encodeBridgeProductContentFrameBytes(header, payload);
	}
}

function encodeBridgeProductContentFrameBytes(
	header: BridgeProductContentHeader,
	payload: Uint8Array,
): Uint8Array {
	const bodyBytes = encodeBridgeProductContentTagBody(header);
	const frameByteLength =
		1 +
		bridgeProductContentFrameSequenceByteLength +
		(header.kind === 'content.data' ? bridgeProductContentDataOffsetByteLength : 0) +
		(header.kind === 'content.data' ? bridgeProductContentCorrelationEnvelopeByteLength : 0) +
		bodyBytes.byteLength +
		payload.byteLength;
	if (frameByteLength > BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES) {
		throw new Error('Bridge product content frame exceeds its byte ceiling.');
	}
	const encodedFrame = new Uint8Array(
		bridgeProductContentFrameLengthPrefixByteLength + frameByteLength,
	);
	const frameView = new DataView(encodedFrame.buffer);
	frameView.setUint32(0, frameByteLength, false);
	encodedFrame[4] = bridgeProductContentFrameTagByKind[header.kind];
	frameView.setUint32(5, header.contentSequence, false);
	let bodyOffset = bridgeProductContentFramePrefixByteLength;
	if (header.kind === 'content.data') {
		frameView.setUint32(bodyOffset, header.offsetBytes, false);
		bodyOffset += bridgeProductContentDataOffsetByteLength;
		encodedFrame.set(
			encodeBridgeProductContentCorrelation(header.operationCorrelationId),
			bodyOffset,
		);
		bodyOffset += bridgeProductContentCorrelationEnvelopeByteLength;
	} else {
		encodedFrame.set(bodyBytes, bodyOffset);
		bodyOffset += bodyBytes.byteLength;
	}
	encodedFrame.set(payload, bodyOffset);
	return encodedFrame;
}

function encodeBridgeProductContentTagBody(header: BridgeProductContentHeader): Uint8Array {
	if (header.kind === 'content.data') {
		return new Uint8Array();
	}
	const body = (() => {
		switch (header.kind) {
			case 'content.accepted':
				return bridgeProductContentAcceptedBodySchema.parse({
					contentRequestId: header.contentRequestId,
					declaredByteLength: header.declaredByteLength,
					expectedSha256: header.expectedSha256,
					identity: header.identity,
					leaseId: header.leaseId,
					operationCorrelationId: header.operationCorrelationId,
					maximumBytes: header.maximumBytes,
					paneSessionId: header.paneSessionId,
					wireVersion: header.wireVersion,
					workerDerivationEpoch: header.workerDerivationEpoch,
					workerInstanceId: header.workerInstanceId,
				});
			case 'content.end':
				return bridgeProductContentEndBodySchema.parse({
					endOfSource: header.endOfSource,
					operationCorrelationId: header.operationCorrelationId,
					observedByteLength: header.observedByteLength,
					observedSha256: header.observedSha256,
				});
			case 'content.error':
				return bridgeProductContentErrorBodySchema.parse({
					code: header.code,
					operationCorrelationId: header.operationCorrelationId,
					retryable: header.retryable,
					safeMessage: header.safeMessage,
				});
			case 'content.reset':
				return bridgeProductContentResetBodySchema.parse({
					operationCorrelationId: header.operationCorrelationId,
					reason: header.reason,
				});
		}
		throw new Error('Bridge product data frames do not carry JSON control bodies.');
	})();
	const bodyBytes = new TextEncoder().encode(JSON.stringify(body));
	if (
		bodyBytes.byteLength === 0 ||
		bodyBytes.byteLength > BRIDGE_PRODUCT_MAXIMUM_CONTENT_CONTROL_BODY_BYTES
	) {
		throw new Error('Bridge product content control body exceeds its byte ceiling.');
	}
	return bodyBytes;
}

export class BridgeProductContentStreamValidator<
	TContentKind extends BridgeProductContentKind = BridgeProductContentKind,
> {
	readonly #expectedRequest: BridgeProductContentRequest;
	#acceptedHeader: ReturnType<typeof bridgeProductContentAcceptedHeaderSchema.parse> | null = null;
	#chunks: Uint8Array[] = [];
	#nextSequence = 0;
	#observedByteLength = 0;
	#state: 'open' | 'poisoned' | 'terminal' = 'open';

	constructor(expectedRequest: BridgeProductContentRequestFor<TContentKind>) {
		this.#expectedRequest = bridgeProductContentRequestSchema.parse(expectedRequest);
	}

	async accept(
		frame: BridgeProductContentFrame,
	): Promise<BridgeProductContentTerminal<TContentKind> | null> {
		if (this.#state === 'terminal') {
			throw new Error('Bridge product content stream received a post-terminal frame.');
		}
		if (this.#state === 'poisoned') {
			throw new Error('Bridge product content stream is poisoned.');
		}
		try {
			return await this.#acceptFrame(frame);
		} catch (error) {
			this.#state = 'poisoned';
			this.#chunks = [];
			throw error;
		}
	}

	finish(): void {
		if (this.#state === 'terminal') return;
		if (this.#state === 'poisoned') {
			throw new Error('Bridge product content stream cannot finish after validation failure.');
		}
		this.#state = 'poisoned';
		this.#chunks = [];
		throw new Error('Bridge product content response ended without a terminal frame.');
	}

	async #acceptFrame(
		frame: BridgeProductContentFrame,
	): Promise<BridgeProductContentTerminal<TContentKind> | null> {
		const header = bridgeProductContentHeaderSchema.parse(frame.header);
		validateBridgeProductContentFramePayload(header, frame.payload);
		validateBridgeProductContentFrameCorrelation(header, this.#expectedRequest);
		const payload = Uint8Array.from(frame.payload);
		if (this.#acceptedHeader === null) {
			if (header.kind !== 'content.accepted') {
				throw new Error('Bridge product content stream must begin with content.accepted.');
			}
			this.#validateAcceptedFrame(header);
			this.#acceptedHeader = header;
			this.#nextSequence = 1;
			return null;
		}

		if (header.contentSequence !== this.#nextSequence) {
			throw new Error('Bridge product content sequence is not contiguous.');
		}
		this.#nextSequence += 1;

		switch (header.kind) {
			case 'content.accepted':
				throw new Error('Bridge product content stream received duplicate content.accepted.');
			case 'content.data':
				this.#acceptDataFrame(header, payload);
				return null;
			case 'content.end':
				return await this.#acceptEndFrame(header);
			case 'content.error':
				this.#state = 'terminal';
				this.#chunks = [];
				return {
					code: header.code,
					contentKind: this.#acceptedHeader.identity.contentKind,
					descriptorId: this.#acceptedHeader.identity.descriptorId,
					kind: 'error',
					retryable: header.retryable,
					safeMessage: header.safeMessage,
				};
			case 'content.reset':
				this.#state = 'terminal';
				this.#chunks = [];
				return {
					contentKind: this.#acceptedHeader.identity.contentKind,
					descriptorId: this.#acceptedHeader.identity.descriptorId,
					kind: 'reset',
					reason: header.reason,
					retryable: true,
				};
		}
		throw new Error('Bridge product content stream received an unsupported frame kind.');
	}

	#validateAcceptedFrame(
		header: ReturnType<typeof bridgeProductContentAcceptedHeaderSchema.parse>,
	): void {
		validateBridgeProductAcceptedHeaderAgainstRequest(header, this.#expectedRequest);
	}

	#acceptDataFrame(
		header: ReturnType<typeof bridgeProductContentDataHeaderSchema.parse>,
		payload: Uint8Array,
	): void {
		if (header.offsetBytes !== this.#observedByteLength) {
			throw new Error('Bridge product content data offset is not contiguous.');
		}
		const nextObservedByteLength = this.#observedByteLength + payload.byteLength;
		const acceptedHeader = this.#acceptedHeader;
		if (acceptedHeader === null) {
			throw new Error('Bridge product content data arrived before acceptance.');
		}
		if (nextObservedByteLength > acceptedHeader.maximumBytes) {
			throw new Error('Bridge product content bytes exceed their maximum.');
		}
		if (
			acceptedHeader.declaredByteLength !== null &&
			nextObservedByteLength > acceptedHeader.declaredByteLength
		) {
			throw new Error('Bridge product content bytes exceed their declared length.');
		}
		this.#chunks.push(payload);
		this.#observedByteLength = nextObservedByteLength;
	}

	async #acceptEndFrame(
		header: ReturnType<typeof bridgeProductContentEndHeaderSchema.parse>,
	): Promise<BridgeProductContentTerminal<TContentKind>> {
		const acceptedHeader = this.#acceptedHeader;
		if (acceptedHeader === null) {
			throw new Error('Bridge product content end arrived before acceptance.');
		}
		validateBridgeProductContentEndOfSource({
			endOfSource: header.endOfSource,
			identity: acceptedHeader.identity,
		});
		if (header.observedByteLength !== this.#observedByteLength) {
			throw new Error('Bridge product content end length does not match received bytes.');
		}
		if (
			acceptedHeader.declaredByteLength !== null &&
			header.observedByteLength !== acceptedHeader.declaredByteLength
		) {
			throw new Error('Bridge product content end length does not match its declaration.');
		}
		const bytes = concatenateBridgeProductContentBytes(...this.#chunks);
		const observedSha256 = await sha256Hex(bytes);
		if (observedSha256 !== header.observedSha256) {
			throw new Error('Bridge product content end digest does not match received bytes.');
		}
		if (
			acceptedHeader.expectedSha256 !== null &&
			observedSha256 !== acceptedHeader.expectedSha256
		) {
			throw new Error(
				'Bridge product content digest conflicts with its authoritative expectation.',
			);
		}
		this.#state = 'terminal';
		this.#chunks = [];
		return {
			bytes: bytes.buffer,
			contentKind: acceptedHeader.identity.contentKind,
			descriptorId: acceptedHeader.identity.descriptorId,
			endOfSource: header.endOfSource,
			kind: 'complete',
			observedByteLength: header.observedByteLength,
			observedSha256,
		};
	}
}

export function validateBridgeProductContentFramePayload(
	header: BridgeProductContentHeader,
	payload: Uint8Array,
): void {
	if (header.kind === 'content.data') {
		if (
			payload.byteLength === 0 ||
			payload.byteLength > BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES
		) {
			throw new Error('Bridge product content data payload is outside its byte bounds.');
		}
		return;
	}
	if (payload.byteLength !== 0) {
		throw new Error('Bridge product non-data content frame cannot carry a raw payload.');
	}
}

function validateBridgeProductAcceptedHeaderAgainstRequest(
	header: ReturnType<typeof bridgeProductContentAcceptedHeaderSchema.parse>,
	expectedRequest: BridgeProductContentRequest,
): void {
	const expectedExactFacts = bridgeProductContentExactFactsForRequest(expectedRequest);
	if (
		header.contentRequestId !== expectedRequest.contentRequestId ||
		header.leaseId !== expectedRequest.leaseId ||
		header.operationCorrelationId !== expectedRequest.operationCorrelationId ||
		header.paneSessionId !== expectedRequest.paneSessionId ||
		header.workerDerivationEpoch !== expectedRequest.workerDerivationEpoch ||
		header.workerInstanceId !== expectedRequest.workerInstanceId ||
		header.maximumBytes !== expectedRequest.descriptor.maximumBytes ||
		header.declaredByteLength !== expectedExactFacts.declaredByteLength ||
		header.expectedSha256 !== expectedExactFacts.expectedSha256 ||
		!bridgeProductContentAcceptedIdentityMatchesRequest({
			identity: header.identity,
			request: expectedRequest,
		})
	) {
		throw new Error('Bridge product content acceptance does not match its issued request.');
	}
	if (
		!bridgeProductContentAcceptedMaximumMatchesIdentity({
			identity: header.identity,
			maximumBytes: header.maximumBytes,
		})
	) {
		throw new Error('Bridge product content accepted maximum does not match its identity.');
	}
	if (header.declaredByteLength !== null && header.declaredByteLength > header.maximumBytes) {
		throw new Error('Bridge product content declared length exceeds its maximum.');
	}
}

function validateBridgeProductContentFrameCorrelation(
	header: BridgeProductContentHeader,
	expectedRequest: BridgeProductContentRequest,
): void {
	if (header.operationCorrelationId !== expectedRequest.operationCorrelationId) {
		throw new Error('Bridge product content frame correlation does not match its issued request.');
	}
}

function encodeBridgeProductContentCorrelation(operationCorrelationId: string | null): Uint8Array {
	const encoded = new Uint8Array(bridgeProductContentCorrelationEnvelopeByteLength);
	if (operationCorrelationId === null) return encoded;
	encoded[0] = 1;
	for (let index = 0; index < bridgeProductContentCorrelationByteLength; index += 1) {
		encoded[index + 1] = Number.parseInt(
			operationCorrelationId.slice(index * 2, index * 2 + 2),
			16,
		);
	}
	return encoded;
}

function bridgeProductDeclaredByteLengthForRequest(
	expectedRequest: BridgeProductContentRequest,
): number | null {
	return bridgeProductContentExactFactsForRequest(expectedRequest).declaredByteLength;
}

function concatenateBridgeProductContentBytes(
	...parts: readonly Uint8Array[]
): Uint8Array<ArrayBuffer> {
	const byteLength = parts.reduce((total, part) => total + part.byteLength, 0);
	const bytes = new Uint8Array(byteLength);
	let offset = 0;
	for (const part of parts) {
		bytes.set(part, offset);
		offset += part.byteLength;
	}
	return bytes;
}

async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
	const digestBytes = new Uint8Array(await globalThis.crypto.subtle.digest('SHA-256', bytes));
	return [...digestBytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
