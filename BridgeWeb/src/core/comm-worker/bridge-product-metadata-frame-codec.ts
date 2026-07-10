import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from './bridge-product-contract-primitives.js';
import {
	BridgeProductFrameByteAccumulator,
	BridgeProductFrameDecoderDiagnosticsLedger,
	BridgeProductFrameDecoderFailure,
	type BridgeProductFrameDecoderDiagnostics,
} from './bridge-product-frame-decoder-support.js';
import {
	bridgeProductMetadataFrameSchema,
	type BridgeProductMetadataFrame,
} from './bridge-product-session-contracts.js';
import { parseBridgeProductStrictJSON } from './bridge-product-strict-json.js';

const bridgeProductMetadataFramePrefixByteLength = 4;

export function encodeBridgeProductMetadataFrame(frame: BridgeProductMetadataFrame): Uint8Array {
	const validatedFrame = bridgeProductMetadataFrameSchema.parse(frame);
	const frameBytes = new TextEncoder().encode(JSON.stringify(validatedFrame));
	if (frameBytes.byteLength > BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES) {
		throw new Error('Bridge product metadata frame exceeds its byte ceiling.');
	}
	const encodedFrame = new Uint8Array(
		bridgeProductMetadataFramePrefixByteLength + frameBytes.byteLength,
	);
	new DataView(encodedFrame.buffer).setUint32(0, frameBytes.byteLength, false);
	encodedFrame.set(frameBytes, bridgeProductMetadataFramePrefixByteLength);
	return encodedFrame;
}

export class BridgeProductMetadataFrameDecoder {
	readonly #diagnosticsLedger = new BridgeProductFrameDecoderDiagnosticsLedger(
		'awaiting_length_prefix',
	);
	readonly #maximumFrameBytes: number;
	#frameBody: BridgeProductFrameByteAccumulator | null = null;
	#lengthPrefix = new BridgeProductFrameByteAccumulator(bridgeProductMetadataFramePrefixByteLength);

	constructor(maximumFrameBytes = BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES) {
		if (
			!Number.isSafeInteger(maximumFrameBytes) ||
			maximumFrameBytes <= 0 ||
			maximumFrameBytes > BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES
		) {
			throw new Error('Bridge product metadata decoder requires a frame ceiling within contract.');
		}
		this.#maximumFrameBytes = maximumFrameBytes;
	}

	get diagnostics(): BridgeProductFrameDecoderDiagnostics {
		return this.#diagnosticsLedger.diagnostics;
	}

	push(chunk: Uint8Array): readonly BridgeProductMetadataFrame[] {
		this.#throwIfUnavailableForPush();
		this.#diagnosticsLedger.recordReceived(chunk.byteLength);
		const consumedByteCountBeforePush = this.#diagnosticsLedger.diagnostics.consumedByteCount;
		let sourceOffset = 0;
		const decodedFrames: BridgeProductMetadataFrame[] = [];
		try {
			while (sourceOffset < chunk.byteLength) {
				switch (this.#diagnosticsLedger.state) {
					case 'awaiting_length_prefix':
						sourceOffset = this.#acceptLengthPrefix(chunk, sourceOffset);
						break;
					case 'awaiting_frame_body': {
						const result = this.#acceptFrameBody(chunk, sourceOffset);
						sourceOffset = result.sourceOffset;
						if (result.frame !== null) {
							decodedFrames.push(result.frame);
						}
						break;
					}
					case 'awaiting_content_prefix':
					case 'awaiting_content_control_body':
					case 'finished':
					case 'poisoned':
						throw new Error('Bridge product metadata decoder entered an unavailable state.');
				}
			}
			this.#diagnosticsLedger.recordEmitted(decodedFrames.length);
			return decodedFrames;
		} catch (error) {
			const failure = bridgeProductMetadataDecoderFailure(error);
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
			throw new Error('Bridge product metadata frame decoder is poisoned.');
		}
		if (this.#diagnosticsLedger.state === 'finished') {
			return;
		}
		if (
			this.#diagnosticsLedger.state !== 'awaiting_length_prefix' ||
			this.#diagnosticsLedger.retainedByteCount !== 0
		) {
			const discardedTailByteCount = this.#diagnosticsLedger.retainedByteCount;
			this.#diagnosticsLedger.recordFailure('truncated_frame', discardedTailByteCount);
			this.#clearStaging();
			throw new BridgeProductFrameDecoderFailure(
				'truncated_frame',
				'Bridge product metadata response ended with a truncated frame.',
			);
		}
		this.#diagnosticsLedger.setState('finished');
	}

	#acceptLengthPrefix(chunk: Uint8Array, sourceOffset: number): number {
		const copiedByteCount = this.#lengthPrefix.appendFrom(
			chunk,
			sourceOffset,
			bridgeProductMetadataFramePrefixByteLength,
		);
		this.#diagnosticsLedger.recordCopied(copiedByteCount);
		const nextSourceOffset = sourceOffset + copiedByteCount;
		if (this.#lengthPrefix.byteLength < bridgeProductMetadataFramePrefixByteLength) {
			return nextSourceOffset;
		}
		const frameByteLength = this.#lengthPrefix.readUint32BigEndian(0);
		if (frameByteLength === 0) {
			throw new BridgeProductFrameDecoderFailure(
				'frame_length_invalid',
				'Bridge product metadata frame length is invalid.',
			);
		}
		if (frameByteLength > this.#maximumFrameBytes) {
			throw new BridgeProductFrameDecoderFailure(
				'frame_length_exceeds_ceiling',
				'Bridge product metadata frame length is invalid.',
			);
		}
		this.#frameBody = new BridgeProductFrameByteAccumulator(frameByteLength);
		this.#diagnosticsLedger.setState('awaiting_frame_body');
		return nextSourceOffset;
	}

	#acceptFrameBody(
		chunk: Uint8Array,
		sourceOffset: number,
	): { readonly frame: BridgeProductMetadataFrame | null; readonly sourceOffset: number } {
		const frameBody = this.#frameBody;
		if (frameBody === null) {
			throw new Error('Bridge product metadata decoder lost its frame body stage.');
		}
		const copiedByteCount = frameBody.appendFrom(chunk, sourceOffset, frameBody.byteCapacity);
		this.#diagnosticsLedger.recordCopied(copiedByteCount);
		const nextSourceOffset = sourceOffset + copiedByteCount;
		if (frameBody.byteLength < frameBody.byteCapacity) {
			return { frame: null, sourceOffset: nextSourceOffset };
		}

		let parsedFrame: unknown;
		try {
			parsedFrame = parseBridgeProductStrictJSON(frameBody.takeBytes());
		} catch {
			throw new BridgeProductFrameDecoderFailure(
				'frame_decode_invalid',
				'Bridge product metadata frame is not strict UTF-8 JSON.',
			);
		}
		let frame: BridgeProductMetadataFrame;
		try {
			frame = bridgeProductMetadataFrameSchema.parse(parsedFrame);
		} catch {
			throw new BridgeProductFrameDecoderFailure(
				'frame_decode_invalid',
				'Bridge product metadata frame does not match its closed contract.',
			);
		}
		this.#diagnosticsLedger.recordReleased(this.#diagnosticsLedger.retainedByteCount);
		this.#lengthPrefix = new BridgeProductFrameByteAccumulator(
			bridgeProductMetadataFramePrefixByteLength,
		);
		this.#frameBody = null;
		this.#diagnosticsLedger.setState('awaiting_length_prefix');
		return { frame, sourceOffset: nextSourceOffset };
	}

	#clearStaging(): void {
		this.#lengthPrefix = new BridgeProductFrameByteAccumulator(
			bridgeProductMetadataFramePrefixByteLength,
		);
		this.#frameBody = null;
	}

	#throwIfUnavailableForPush(): void {
		if (this.#diagnosticsLedger.state === 'poisoned') {
			throw new Error('Bridge product metadata frame decoder is poisoned.');
		}
		if (this.#diagnosticsLedger.state === 'finished') {
			throw new Error('Bridge product metadata frame decoder is finished.');
		}
	}
}

function bridgeProductMetadataDecoderFailure(error: unknown): BridgeProductFrameDecoderFailure {
	if (error instanceof BridgeProductFrameDecoderFailure) {
		return error;
	}
	return new BridgeProductFrameDecoderFailure(
		'frame_decode_invalid',
		'Bridge product metadata frame decoder rejected an invalid frame.',
	);
}
