export type BridgeProductFrameDecoderState =
	| 'awaiting_length_prefix'
	| 'awaiting_content_prefix'
	| 'awaiting_content_control_body'
	| 'awaiting_frame_body'
	| 'finished'
	| 'poisoned';

export type BridgeProductFrameDecoderFailureCode =
	| 'frame_length_invalid'
	| 'frame_length_exceeds_ceiling'
	| 'content_frame_tag_invalid'
	| 'content_control_body_length_invalid'
	| 'content_control_body_exceeds_ceiling'
	| 'frame_decode_invalid'
	| 'frame_payload_invalid'
	| 'truncated_frame';

export interface BridgeProductFrameDecoderDiagnostics {
	readonly consumedByteCount: number;
	readonly copiedByteCount: number;
	readonly discardedTailByteCount: number;
	readonly emittedFrameCount: number;
	readonly failureCode: BridgeProductFrameDecoderFailureCode | null;
	readonly peakRetainedByteCount: number;
	readonly receivedByteCount: number;
	readonly retainedByteCount: number;
	readonly state: BridgeProductFrameDecoderState;
}

export class BridgeProductFrameDecoderFailure extends Error {
	readonly failureCode: BridgeProductFrameDecoderFailureCode;

	constructor(failureCode: BridgeProductFrameDecoderFailureCode, message: string) {
		super(message);
		this.name = 'BridgeProductFrameDecoderFailure';
		this.failureCode = failureCode;
	}
}

export class BridgeProductFrameDecoderDiagnosticsLedger {
	#consumedByteCount = 0;
	#copiedByteCount = 0;
	#discardedTailByteCount = 0;
	#emittedFrameCount = 0;
	#failureCode: BridgeProductFrameDecoderFailureCode | null = null;
	#peakRetainedByteCount = 0;
	#receivedByteCount = 0;
	#retainedByteCount = 0;
	#state: BridgeProductFrameDecoderState;

	constructor(initialState: BridgeProductFrameDecoderState) {
		this.#state = initialState;
	}

	get diagnostics(): BridgeProductFrameDecoderDiagnostics {
		return Object.freeze({
			consumedByteCount: this.#consumedByteCount,
			copiedByteCount: this.#copiedByteCount,
			discardedTailByteCount: this.#discardedTailByteCount,
			emittedFrameCount: this.#emittedFrameCount,
			failureCode: this.#failureCode,
			peakRetainedByteCount: this.#peakRetainedByteCount,
			receivedByteCount: this.#receivedByteCount,
			retainedByteCount: this.#retainedByteCount,
			state: this.#state,
		});
	}

	get retainedByteCount(): number {
		return this.#retainedByteCount;
	}

	get state(): BridgeProductFrameDecoderState {
		return this.#state;
	}

	recordReceived(byteCount: number): void {
		this.#receivedByteCount += byteCount;
	}

	recordCopied(byteCount: number): void {
		this.#consumedByteCount += byteCount;
		this.#copiedByteCount += byteCount;
		this.#retainedByteCount += byteCount;
		this.#peakRetainedByteCount = Math.max(this.#peakRetainedByteCount, this.#retainedByteCount);
	}

	recordReleased(byteCount: number): void {
		if (byteCount < 0 || byteCount > this.#retainedByteCount) {
			throw new Error('Bridge product frame diagnostics release is out of bounds.');
		}
		this.#retainedByteCount -= byteCount;
	}

	recordEmitted(frameCount: number): void {
		this.#emittedFrameCount += frameCount;
	}

	setState(state: BridgeProductFrameDecoderState): void {
		this.#state = state;
	}

	recordFailure(
		failureCode: BridgeProductFrameDecoderFailureCode,
		discardedTailByteCount: number,
	): void {
		if (discardedTailByteCount < 0) {
			throw new Error('Bridge product frame diagnostics tail discard is out of bounds.');
		}
		this.#discardedTailByteCount += discardedTailByteCount;
		this.#failureCode = failureCode;
		this.#retainedByteCount = 0;
		this.#state = 'poisoned';
	}
}

export class BridgeProductFrameByteAccumulator {
	#byteLength = 0;
	#bytes: Uint8Array<ArrayBuffer>;

	constructor(byteCapacity: number) {
		if (!Number.isSafeInteger(byteCapacity) || byteCapacity < 0) {
			throw new Error('Bridge product frame byte accumulator requires a nonnegative capacity.');
		}
		this.#bytes = new Uint8Array(byteCapacity);
	}

	get byteCapacity(): number {
		return this.#bytes.byteLength;
	}

	get byteLength(): number {
		return this.#byteLength;
	}

	appendFrom(chunk: Uint8Array, sourceOffset: number, targetByteLength: number): number {
		if (
			!Number.isSafeInteger(sourceOffset) ||
			sourceOffset < 0 ||
			sourceOffset > chunk.byteLength
		) {
			throw new Error('Bridge product frame byte accumulator source offset is out of bounds.');
		}
		if (
			!Number.isSafeInteger(targetByteLength) ||
			targetByteLength < this.#byteLength ||
			targetByteLength > this.#bytes.byteLength
		) {
			throw new Error('Bridge product frame byte accumulator target is out of bounds.');
		}

		const copiedByteCount = Math.min(
			targetByteLength - this.#byteLength,
			chunk.byteLength - sourceOffset,
		);
		if (copiedByteCount === 0) {
			return 0;
		}
		this.#bytes.set(chunk.subarray(sourceOffset, sourceOffset + copiedByteCount), this.#byteLength);
		this.#byteLength += copiedByteCount;
		return copiedByteCount;
	}

	readByte(offset: number): number {
		if (!Number.isSafeInteger(offset) || offset < 0 || offset >= this.#byteLength) {
			throw new Error('Bridge product frame byte accumulator read is out of bounds.');
		}
		const value = this.#bytes[offset];
		if (value === undefined) {
			throw new Error('Bridge product frame byte accumulator lost an admitted byte.');
		}
		return value;
	}

	readUint32BigEndian(offset: number): number {
		if (offset + 4 > this.#byteLength) {
			throw new Error('Bridge product frame byte accumulator lacks a complete u32 prefix.');
		}
		return (
			this.readByte(offset) * 0x1_00_00_00 +
			this.readByte(offset + 1) * 0x1_00_00 +
			this.readByte(offset + 2) * 0x1_00 +
			this.readByte(offset + 3)
		);
	}

	takeBytes(): Uint8Array<ArrayBuffer> {
		if (this.#byteLength !== this.#bytes.byteLength) {
			throw new Error('Bridge product frame byte accumulator cannot release an incomplete stage.');
		}
		const bytes = this.#bytes;
		this.#bytes = new Uint8Array(0);
		this.#byteLength = 0;
		return bytes;
	}
}
