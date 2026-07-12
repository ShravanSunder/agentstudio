import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from './bridge-product-contract-primitives.js';
import type { BridgeProductFrameDecoderFailureCode } from './bridge-product-frame-decoder-support.js';
import { BridgeProductMetadataFrameDecoder } from './bridge-product-metadata-frame-codec.js';
import {
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductMetadataFrame,
	type BridgeProductMetadataStreamRequest,
} from './bridge-product-session-contracts.js';

export type BridgeProductMetadataStreamDecoderState = 'open' | 'terminal' | 'finished' | 'poisoned';

export type BridgeProductMetadataStreamDecoderFailureCode =
	| 'stream_acceptance_required'
	| 'duplicate_stream_acceptance'
	| 'stream_identity_mismatch'
	| 'stream_sequence_mismatch'
	| 'post_terminal_frame';

export interface BridgeProductMetadataStreamDecoderOptions {
	readonly maximumFrameBodyBytes?: number;
}

export interface BridgeProductMetadataStreamDecoderDiagnostics {
	readonly acceptedStream: boolean;
	readonly expectedNextStreamSequence: number;
	readonly failureCode:
		| BridgeProductFrameDecoderFailureCode
		| BridgeProductMetadataStreamDecoderFailureCode
		| null;
	readonly peakRetainedByteCount: number;
	readonly retainedByteCount: number;
	readonly state: BridgeProductMetadataStreamDecoderState;
}

export class BridgeProductMetadataStreamDecoderFailure extends Error {
	readonly failureCode: BridgeProductMetadataStreamDecoderFailureCode;

	constructor(failureCode: BridgeProductMetadataStreamDecoderFailureCode, message: string) {
		super(message);
		this.name = 'BridgeProductMetadataStreamDecoderFailure';
		this.failureCode = failureCode;
	}
}

export class BridgeProductMetadataStreamDecoder {
	#acceptedStream = false;
	#expectedNextStreamSequence: number;
	readonly #expectedRequest: BridgeProductMetadataStreamRequest;
	#failureCode:
		| BridgeProductFrameDecoderFailureCode
		| BridgeProductMetadataStreamDecoderFailureCode
		| null = null;
	#frameDecoder: BridgeProductMetadataFrameDecoder | null;
	#peakRetainedByteCount = 0;
	#retainedByteCount = 0;
	#state: BridgeProductMetadataStreamDecoderState = 'open';

	constructor(
		expectedRequest: BridgeProductMetadataStreamRequest,
		options: BridgeProductMetadataStreamDecoderOptions = {},
	) {
		this.#expectedRequest = bridgeProductMetadataStreamRequestSchema.parse(expectedRequest);
		this.#expectedNextStreamSequence =
			this.#expectedRequest.resumeFromStreamSequence === null
				? 0
				: this.#expectedRequest.resumeFromStreamSequence + 1;
		this.#frameDecoder = new BridgeProductMetadataFrameDecoder(
			options.maximumFrameBodyBytes ?? BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
		);
	}

	get diagnostics(): BridgeProductMetadataStreamDecoderDiagnostics {
		return Object.freeze({
			acceptedStream: this.#acceptedStream,
			expectedNextStreamSequence: this.#expectedNextStreamSequence,
			failureCode: this.#failureCode,
			peakRetainedByteCount: this.#peakRetainedByteCount,
			retainedByteCount: this.#retainedByteCount,
			state: this.#state,
		});
	}

	push(chunk: Uint8Array): readonly BridgeProductMetadataFrame[] {
		if (this.#state === 'terminal') {
			if (chunk.byteLength === 0) {
				return [];
			}
			throw this.#poison(
				'post_terminal_frame',
				'Bridge product metadata stream received bytes after its terminal frame.',
			);
		}
		this.#throwIfUnavailableForPush();
		const frameDecoder = this.#requiredFrameDecoder();
		let frames: readonly BridgeProductMetadataFrame[];
		try {
			frames = frameDecoder.push(chunk);
		} catch (error) {
			this.#captureFrameDecoderDiagnostics(frameDecoder);
			this.#failureCode = frameDecoder.diagnostics.failureCode;
			this.#retireAsPoisoned();
			throw error;
		}
		this.#captureFrameDecoderDiagnostics(frameDecoder);

		try {
			this.#validateAndCommitFrameBatch(frames, frameDecoder.diagnostics.retainedByteCount);
		} catch (error) {
			if (error instanceof BridgeProductMetadataStreamDecoderFailure) {
				this.#failureCode = error.failureCode;
				this.#retireAsPoisoned();
			}
			throw error;
		}
		return frames;
	}

	finish(): void {
		if (this.#state === 'poisoned') {
			throw new Error('Bridge product metadata stream decoder is poisoned.');
		}
		if (this.#state === 'finished') {
			return;
		}
		if (!this.#acceptedStream) {
			throw this.#poison(
				'stream_acceptance_required',
				'Bridge product metadata stream ended before its acceptance frame.',
			);
		}

		const frameDecoder = this.#requiredFrameDecoder();
		try {
			frameDecoder.finish();
		} catch (error) {
			this.#captureFrameDecoderDiagnostics(frameDecoder);
			this.#failureCode = frameDecoder.diagnostics.failureCode;
			this.#retireAsPoisoned();
			throw error;
		}
		this.#captureFrameDecoderDiagnostics(frameDecoder);
		this.#state = 'finished';
	}

	#validateAndCommitFrameBatch(
		frames: readonly BridgeProductMetadataFrame[],
		retainedTailByteCount: number,
	): void {
		let acceptedStream = this.#acceptedStream;
		let expectedNextStreamSequence = this.#expectedNextStreamSequence;
		let reachedTerminalFrame = this.#state === 'terminal';

		for (const frame of frames) {
			if (reachedTerminalFrame) {
				throw new BridgeProductMetadataStreamDecoderFailure(
					'post_terminal_frame',
					'Bridge product metadata stream received a frame after its terminal frame.',
				);
			}
			this.#validateFrameIdentity(frame);
			if (!acceptedStream && frame.kind !== 'metadataStream.accepted') {
				throw new BridgeProductMetadataStreamDecoderFailure(
					'stream_acceptance_required',
					'Bridge product metadata stream requires acceptance as its first frame.',
				);
			}
			if (acceptedStream && frame.kind === 'metadataStream.accepted') {
				throw new BridgeProductMetadataStreamDecoderFailure(
					'duplicate_stream_acceptance',
					'Bridge product metadata stream received a second acceptance frame.',
				);
			}
			if (frame.streamSequence !== expectedNextStreamSequence) {
				throw new BridgeProductMetadataStreamDecoderFailure(
					'stream_sequence_mismatch',
					`Bridge product metadata stream expected sequence ${expectedNextStreamSequence}.`,
				);
			}

			acceptedStream = true;
			expectedNextStreamSequence += 1;
			reachedTerminalFrame = frame.kind === 'metadataStream.error';
		}

		if (reachedTerminalFrame && retainedTailByteCount > 0) {
			throw new BridgeProductMetadataStreamDecoderFailure(
				'post_terminal_frame',
				'Bridge product metadata stream retained bytes after its terminal frame.',
			);
		}

		this.#acceptedStream = acceptedStream;
		this.#expectedNextStreamSequence = expectedNextStreamSequence;
		if (reachedTerminalFrame) {
			this.#state = 'terminal';
		}
	}

	#validateFrameIdentity(frame: BridgeProductMetadataFrame): void {
		if (
			frame.wireVersion !== this.#expectedRequest.wireVersion ||
			frame.paneSessionId !== this.#expectedRequest.paneSessionId ||
			frame.workerInstanceId !== this.#expectedRequest.workerInstanceId ||
			frame.metadataStreamId !== this.#expectedRequest.metadataStreamId
		) {
			throw new BridgeProductMetadataStreamDecoderFailure(
				'stream_identity_mismatch',
				'Bridge product metadata frame does not match its opened stream identity.',
			);
		}
	}

	#captureFrameDecoderDiagnostics(frameDecoder: BridgeProductMetadataFrameDecoder): void {
		const frameDiagnostics = frameDecoder.diagnostics;
		this.#peakRetainedByteCount = Math.max(
			this.#peakRetainedByteCount,
			frameDiagnostics.peakRetainedByteCount,
		);
		this.#retainedByteCount = frameDiagnostics.retainedByteCount;
	}

	#poison(
		failureCode: BridgeProductMetadataStreamDecoderFailureCode,
		message: string,
	): BridgeProductMetadataStreamDecoderFailure {
		this.#failureCode = failureCode;
		this.#retireAsPoisoned();
		return new BridgeProductMetadataStreamDecoderFailure(failureCode, message);
	}

	#retireAsPoisoned(): void {
		this.#frameDecoder = null;
		this.#retainedByteCount = 0;
		this.#state = 'poisoned';
	}

	#requiredFrameDecoder(): BridgeProductMetadataFrameDecoder {
		if (this.#frameDecoder === null) {
			throw new Error('Bridge product metadata stream decoder lost its frame decoder.');
		}
		return this.#frameDecoder;
	}

	#throwIfUnavailableForPush(): void {
		if (this.#state === 'poisoned') {
			throw new Error('Bridge product metadata stream decoder is poisoned.');
		}
		if (this.#state === 'finished') {
			throw new Error('Bridge product metadata stream decoder is finished.');
		}
	}
}
