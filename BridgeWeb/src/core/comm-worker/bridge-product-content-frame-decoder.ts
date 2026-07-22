import {
	bridgeProductContentAcceptedBodySchema,
	bridgeProductContentAcceptedHeaderSchema,
	bridgeProductContentDataHeaderSchema,
	bridgeProductContentEndBodySchema,
	bridgeProductContentEndHeaderSchema,
	bridgeProductContentErrorBodySchema,
	bridgeProductContentErrorHeaderSchema,
	bridgeProductContentResetBodySchema,
	bridgeProductContentResetHeaderSchema,
	type BridgeProductContentFrame,
	type BridgeProductContentHeader,
} from './bridge-product-content-contracts.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_CONTROL_BODY_BYTES,
} from './bridge-product-contract-primitives.js';
import {
	BridgeProductFrameByteAccumulator,
	BridgeProductFrameDecoderDiagnosticsLedger,
	BridgeProductFrameDecoderFailure,
	type BridgeProductFrameDecoderDiagnostics,
} from './bridge-product-frame-decoder-support.js';
import { parseBridgeProductStrictJSON } from './bridge-product-strict-json.js';

const bridgeProductContentFrameLengthPrefixByteLength = 4;
const bridgeProductContentFrameTagByteLength = 1;
const bridgeProductContentFrameSequenceByteLength = 4;
const bridgeProductContentFramePrefixByteLength =
	bridgeProductContentFrameLengthPrefixByteLength +
	bridgeProductContentFrameTagByteLength +
	bridgeProductContentFrameSequenceByteLength;
const bridgeProductContentDataOffsetByteLength = 4;
const bridgeProductContentFrameMinimumBodyByteLength =
	bridgeProductContentFrameTagByteLength + bridgeProductContentFrameSequenceByteLength;

export class BridgeProductContentFrameDecoder {
	readonly #diagnosticsLedger = new BridgeProductFrameDecoderDiagnosticsLedger(
		'awaiting_length_prefix',
	);
	readonly #maximumFrameBytes: number;
	#accepted = false;
	#contentSequence: number | null = null;
	#controlBodyBytes: BridgeProductFrameByteAccumulator | null = null;
	#dataOffsetBytes: BridgeProductFrameByteAccumulator | null = null;
	#dataOffsetValue: number | null = null;
	#dataPayloadBytes: BridgeProductFrameByteAccumulator | null = null;
	#fixedPrefix = new BridgeProductFrameByteAccumulator(bridgeProductContentFramePrefixByteLength);
	#frameByteLength: number | null = null;
	#frameTag: number | null = null;
	#nextContentSequence = 0;
	#nextOffsetBytes = 0;
	#terminalSeen = false;

	constructor(maximumFrameBytes = BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES) {
		if (
			!Number.isSafeInteger(maximumFrameBytes) ||
			maximumFrameBytes <= 0 ||
			maximumFrameBytes > BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES
		) {
			throw new Error('Bridge product content decoder requires a frame ceiling within contract.');
		}
		this.#maximumFrameBytes = maximumFrameBytes;
	}

	get diagnostics(): BridgeProductFrameDecoderDiagnostics {
		return this.#diagnosticsLedger.diagnostics;
	}

	push(chunk: Uint8Array): readonly BridgeProductContentFrame[] {
		this.#throwIfUnavailableForPush();
		this.#diagnosticsLedger.recordReceived(chunk.byteLength);
		const consumedByteCountBeforePush = this.#diagnosticsLedger.diagnostics.consumedByteCount;
		let sourceOffset = 0;
		const decodedFrames: BridgeProductContentFrame[] = [];
		try {
			while (sourceOffset < chunk.byteLength) {
				if (this.#terminalSeen) {
					throw new BridgeProductFrameDecoderFailure(
						'frame_decode_invalid',
						'Bridge product content response carried bytes after terminal state.',
					);
				}
				switch (this.#diagnosticsLedger.state) {
					case 'awaiting_length_prefix':
						sourceOffset = this.#acceptLengthPrefix(chunk, sourceOffset);
						break;
					case 'awaiting_content_prefix':
						sourceOffset = this.#acceptContentPrefix(chunk, sourceOffset);
						break;
					case 'awaiting_content_control_body': {
						const result = this.#acceptTagBodyPrefix(chunk, sourceOffset);
						sourceOffset = result.sourceOffset;
						if (result.frame !== null) decodedFrames.push(result.frame);
						break;
					}
					case 'awaiting_frame_body': {
						const result = this.#acceptDataPayload(chunk, sourceOffset);
						sourceOffset = result.sourceOffset;
						if (result.frame !== null) decodedFrames.push(result.frame);
						break;
					}
					case 'finished':
					case 'poisoned':
						throw new Error('Bridge product content decoder entered an unavailable state.');
				}
			}
			this.#diagnosticsLedger.recordEmitted(decodedFrames.length);
			return decodedFrames;
		} catch (error) {
			const failure = bridgeProductContentDecoderFailure(error);
			const consumedByteCountFromChunk =
				this.#diagnosticsLedger.diagnostics.consumedByteCount - consumedByteCountBeforePush;
			this.#diagnosticsLedger.recordFailure(
				failure.failureCode,
				chunk.byteLength - consumedByteCountFromChunk,
			);
			this.#clearStaging();
			throw failure;
		}
	}

	finish(): void {
		if (this.#diagnosticsLedger.state === 'poisoned') {
			throw new Error('Bridge product content frame decoder is poisoned.');
		}
		if (this.#diagnosticsLedger.state === 'finished') return;
		if (
			this.#diagnosticsLedger.state !== 'awaiting_length_prefix' ||
			this.#diagnosticsLedger.retainedByteCount !== 0
		) {
			const discardedTailByteCount = this.#diagnosticsLedger.retainedByteCount;
			this.#diagnosticsLedger.recordFailure('truncated_frame', discardedTailByteCount);
			this.#clearStaging();
			throw new BridgeProductFrameDecoderFailure(
				'truncated_frame',
				'Bridge product content response ended with a truncated frame.',
			);
		}
		if (!this.#accepted || !this.#terminalSeen) {
			this.#diagnosticsLedger.recordFailure('truncated_frame', 0);
			this.#clearStaging();
			throw new BridgeProductFrameDecoderFailure(
				'truncated_frame',
				'Bridge product content response ended without a complete terminal lifecycle.',
			);
		}
		this.#diagnosticsLedger.setState('finished');
	}

	#acceptLengthPrefix(chunk: Uint8Array, sourceOffset: number): number {
		const nextSourceOffset = this.#copyInto(
			this.#fixedPrefix,
			chunk,
			sourceOffset,
			bridgeProductContentFrameLengthPrefixByteLength,
		);
		if (this.#fixedPrefix.byteLength < bridgeProductContentFrameLengthPrefixByteLength) {
			return nextSourceOffset;
		}
		const frameByteLength = this.#fixedPrefix.readUint32BigEndian(0);
		if (frameByteLength < bridgeProductContentFrameMinimumBodyByteLength) {
			throw new BridgeProductFrameDecoderFailure(
				'frame_length_invalid',
				'Bridge product content frame length is smaller than its fixed prefix.',
			);
		}
		if (frameByteLength > this.#maximumFrameBytes) {
			throw new BridgeProductFrameDecoderFailure(
				'frame_length_exceeds_ceiling',
				'Bridge product content frame exceeds its byte ceiling.',
			);
		}
		this.#frameByteLength = frameByteLength;
		this.#diagnosticsLedger.setState('awaiting_content_prefix');
		return nextSourceOffset;
	}

	#acceptContentPrefix(chunk: Uint8Array, sourceOffset: number): number {
		const nextSourceOffset = this.#copyInto(
			this.#fixedPrefix,
			chunk,
			sourceOffset,
			bridgeProductContentFramePrefixByteLength,
		);
		if (this.#fixedPrefix.byteLength < bridgeProductContentFramePrefixByteLength) {
			return nextSourceOffset;
		}

		const frameByteLength = requireBridgeProductContentNumber(
			this.#frameByteLength,
			'frame byte length',
		);
		const frameTag = this.#fixedPrefix.readByte(4);
		if (frameTag < 0x01 || frameTag > 0x05) {
			throw new BridgeProductFrameDecoderFailure(
				'content_frame_tag_invalid',
				'Bridge product response used an unknown content frame tag.',
			);
		}
		const contentSequence = this.#fixedPrefix.readUint32BigEndian(5);
		if (
			(frameTag === 0x01 && contentSequence !== 0) ||
			(frameTag !== 0x01 && contentSequence === 0)
		) {
			throw new BridgeProductFrameDecoderFailure(
				'frame_decode_invalid',
				'Bridge product content frame sequence does not match its tag.',
			);
		}
		this.#frameTag = frameTag;
		this.#contentSequence = contentSequence;

		const tagBodyByteLength = frameByteLength - bridgeProductContentFrameMinimumBodyByteLength;
		if (frameTag === 0x02) {
			const payloadByteLength = tagBodyByteLength - bridgeProductContentDataOffsetByteLength;
			if (
				payloadByteLength <= 0 ||
				payloadByteLength > BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES
			) {
				throw new BridgeProductFrameDecoderFailure(
					'frame_payload_invalid',
					'Bridge product content data payload is outside its byte bounds.',
				);
			}
			this.#dataOffsetBytes = new BridgeProductFrameByteAccumulator(
				bridgeProductContentDataOffsetByteLength,
			);
			this.#dataPayloadBytes = new BridgeProductFrameByteAccumulator(payloadByteLength);
		} else {
			if (tagBodyByteLength <= 0) {
				throw new BridgeProductFrameDecoderFailure(
					'content_control_body_length_invalid',
					'Bridge product content control body is empty.',
				);
			}
			if (tagBodyByteLength > BRIDGE_PRODUCT_MAXIMUM_CONTENT_CONTROL_BODY_BYTES) {
				throw new BridgeProductFrameDecoderFailure(
					'content_control_body_exceeds_ceiling',
					'Bridge product content control body exceeds its byte ceiling.',
				);
			}
			this.#controlBodyBytes = new BridgeProductFrameByteAccumulator(tagBodyByteLength);
		}
		this.#diagnosticsLedger.setState('awaiting_content_control_body');
		return nextSourceOffset;
	}

	#acceptTagBodyPrefix(
		chunk: Uint8Array,
		sourceOffset: number,
	): { readonly frame: BridgeProductContentFrame | null; readonly sourceOffset: number } {
		const frameTag = requireBridgeProductContentNumber(this.#frameTag, 'frame tag');
		if (frameTag === 0x02) {
			return this.#acceptDataOffset(chunk, sourceOffset);
		}
		return this.#acceptControlBody(chunk, sourceOffset);
	}

	#acceptDataOffset(
		chunk: Uint8Array,
		sourceOffset: number,
	): { readonly frame: null; readonly sourceOffset: number } {
		const offsetBytes = requireBridgeProductContentAccumulator(
			this.#dataOffsetBytes,
			'data offset bytes',
		);
		const nextSourceOffset = this.#copyInto(
			offsetBytes,
			chunk,
			sourceOffset,
			bridgeProductContentDataOffsetByteLength,
		);
		if (offsetBytes.byteLength < bridgeProductContentDataOffsetByteLength) {
			return { frame: null, sourceOffset: nextSourceOffset };
		}
		this.#dataOffsetValue = offsetBytes.readUint32BigEndian(0);
		this.#dataOffsetBytes = null;
		this.#fixedPrefix = new BridgeProductFrameByteAccumulator(
			bridgeProductContentFramePrefixByteLength,
		);
		this.#diagnosticsLedger.recordReleased(
			bridgeProductContentFramePrefixByteLength + bridgeProductContentDataOffsetByteLength,
		);
		this.#diagnosticsLedger.setState('awaiting_frame_body');
		return { frame: null, sourceOffset: nextSourceOffset };
	}

	#acceptControlBody(
		chunk: Uint8Array,
		sourceOffset: number,
	): { readonly frame: BridgeProductContentFrame | null; readonly sourceOffset: number } {
		const controlBodyBytes = requireBridgeProductContentAccumulator(
			this.#controlBodyBytes,
			'control body bytes',
		);
		const nextSourceOffset = this.#copyInto(
			controlBodyBytes,
			chunk,
			sourceOffset,
			controlBodyBytes.byteCapacity,
		);
		if (controlBodyBytes.byteLength < controlBodyBytes.byteCapacity) {
			return { frame: null, sourceOffset: nextSourceOffset };
		}

		const frameTag = requireBridgeProductContentNumber(this.#frameTag, 'frame tag');
		const contentSequence = requireBridgeProductContentNumber(
			this.#contentSequence,
			'content sequence',
		);
		const controlBodyByteLength = controlBodyBytes.byteLength;
		let header: BridgeProductContentHeader;
		try {
			header = decodeBridgeProductContentControlBody(
				frameTag,
				contentSequence,
				controlBodyBytes.takeBytes(),
			);
		} catch {
			throw new BridgeProductFrameDecoderFailure(
				'frame_decode_invalid',
				'Bridge product content control body does not match its closed contract.',
			);
		}
		this.#validateLifecycle({ header, payload: new Uint8Array() });
		this.#diagnosticsLedger.recordReleased(
			bridgeProductContentFramePrefixByteLength + controlBodyByteLength,
		);
		const frame = { header, payload: new Uint8Array() };
		this.#resetAfterFrame();
		return { frame, sourceOffset: nextSourceOffset };
	}

	#acceptDataPayload(
		chunk: Uint8Array,
		sourceOffset: number,
	): { readonly frame: BridgeProductContentFrame | null; readonly sourceOffset: number } {
		const payloadBytes = requireBridgeProductContentAccumulator(
			this.#dataPayloadBytes,
			'data payload bytes',
		);
		const nextSourceOffset = this.#copyInto(
			payloadBytes,
			chunk,
			sourceOffset,
			payloadBytes.byteCapacity,
		);
		if (payloadBytes.byteLength < payloadBytes.byteCapacity) {
			return { frame: null, sourceOffset: nextSourceOffset };
		}

		const offsetBytes = requireBridgeProductContentNumber(
			this.#dataOffsetValue,
			'data offset value',
		);
		const header = bridgeProductContentDataHeaderSchema.parse({
			contentSequence: requireBridgeProductContentNumber(this.#contentSequence, 'content sequence'),
			kind: 'content.data',
			offsetBytes,
		});
		const payload = payloadBytes.takeBytes();
		this.#validateLifecycle({ header, payload });
		this.#diagnosticsLedger.recordReleased(payload.byteLength);
		const frame = { header, payload };
		this.#resetAfterFrame();
		return { frame, sourceOffset: nextSourceOffset };
	}

	#copyInto(
		accumulator: BridgeProductFrameByteAccumulator,
		chunk: Uint8Array,
		sourceOffset: number,
		targetByteLength: number,
	): number {
		const copiedByteCount = accumulator.appendFrom(chunk, sourceOffset, targetByteLength);
		this.#diagnosticsLedger.recordCopied(copiedByteCount);
		return sourceOffset + copiedByteCount;
	}

	#resetAfterFrame(): void {
		if (this.#fixedPrefix.byteLength !== 0) {
			this.#fixedPrefix = new BridgeProductFrameByteAccumulator(
				bridgeProductContentFramePrefixByteLength,
			);
		}
		this.#frameByteLength = null;
		this.#frameTag = null;
		this.#contentSequence = null;
		this.#controlBodyBytes = null;
		this.#dataOffsetBytes = null;
		this.#dataOffsetValue = null;
		this.#dataPayloadBytes = null;
		this.#diagnosticsLedger.setState('awaiting_length_prefix');
	}

	#clearStaging(): void {
		this.#fixedPrefix = new BridgeProductFrameByteAccumulator(
			bridgeProductContentFramePrefixByteLength,
		);
		this.#frameByteLength = null;
		this.#frameTag = null;
		this.#contentSequence = null;
		this.#controlBodyBytes = null;
		this.#dataOffsetBytes = null;
		this.#dataOffsetValue = null;
		this.#dataPayloadBytes = null;
	}

	#validateLifecycle(frame: BridgeProductContentFrame): void {
		const { header, payload } = frame;
		if (this.#terminalSeen) {
			throw new BridgeProductFrameDecoderFailure(
				'frame_decode_invalid',
				'Bridge product content frame arrived after terminal state.',
			);
		}
		if (!this.#accepted) {
			if (header.kind !== 'content.accepted') {
				throw new BridgeProductFrameDecoderFailure(
					'frame_decode_invalid',
					'Bridge product content response must begin with content.accepted.',
				);
			}
			this.#accepted = true;
			this.#nextContentSequence = 1;
			return;
		}
		if (header.kind === 'content.accepted') {
			throw new BridgeProductFrameDecoderFailure(
				'frame_decode_invalid',
				'Bridge product content response cannot accept twice.',
			);
		}
		if (header.contentSequence !== this.#nextContentSequence) {
			throw new BridgeProductFrameDecoderFailure(
				'frame_decode_invalid',
				'Bridge product content response sequence is not contiguous.',
			);
		}
		this.#nextContentSequence += 1;
		if (header.kind === 'content.data') {
			if (header.offsetBytes !== this.#nextOffsetBytes) {
				throw new BridgeProductFrameDecoderFailure(
					'frame_decode_invalid',
					'Bridge product content response offset is not contiguous.',
				);
			}
			this.#nextOffsetBytes += payload.byteLength;
			return;
		}
		this.#terminalSeen = true;
	}

	#throwIfUnavailableForPush(): void {
		if (this.#diagnosticsLedger.state === 'poisoned') {
			throw new Error('Bridge product content frame decoder is poisoned.');
		}
		if (this.#diagnosticsLedger.state === 'finished') {
			throw new Error('Bridge product content frame decoder is finished.');
		}
	}
}

function decodeBridgeProductContentControlBody(
	frameTag: number,
	contentSequence: number,
	bodyBytes: Uint8Array,
): BridgeProductContentHeader {
	const parsedBody = parseBridgeProductStrictJSON(bodyBytes);
	switch (frameTag) {
		case 0x01:
			return bridgeProductContentAcceptedHeaderSchema.parse({
				...bridgeProductContentAcceptedBodySchema.parse(parsedBody),
				contentSequence,
				kind: 'content.accepted',
			});
		case 0x03:
			return bridgeProductContentEndHeaderSchema.parse({
				...bridgeProductContentEndBodySchema.parse(parsedBody),
				contentSequence,
				kind: 'content.end',
			});
		case 0x04:
			return bridgeProductContentErrorHeaderSchema.parse({
				...bridgeProductContentErrorBodySchema.parse(parsedBody),
				contentSequence,
				kind: 'content.error',
			});
		case 0x05:
			return bridgeProductContentResetHeaderSchema.parse({
				...bridgeProductContentResetBodySchema.parse(parsedBody),
				contentSequence,
				kind: 'content.reset',
			});
		default:
			throw new Error('Bridge product data frames do not carry JSON control bodies.');
	}
}

function bridgeProductContentDecoderFailure(error: unknown): BridgeProductFrameDecoderFailure {
	if (error instanceof BridgeProductFrameDecoderFailure) return error;
	return new BridgeProductFrameDecoderFailure(
		'frame_decode_invalid',
		'Bridge product content frame decoder rejected an invalid frame.',
	);
}

function requireBridgeProductContentNumber(value: number | null, description: string): number {
	if (value === null) {
		throw new Error(`Bridge product content decoder lost its ${description}.`);
	}
	return value;
}

function requireBridgeProductContentAccumulator(
	accumulator: BridgeProductFrameByteAccumulator | null,
	description: string,
): BridgeProductFrameByteAccumulator {
	if (accumulator === null) {
		throw new Error(`Bridge product content decoder lost its ${description}.`);
	}
	return accumulator;
}
