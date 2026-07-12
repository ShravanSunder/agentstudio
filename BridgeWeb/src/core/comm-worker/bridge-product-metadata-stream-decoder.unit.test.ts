import { describe, expect, test } from 'vitest';

import validProductSessionCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-session-corpus.json' with { type: 'json' };
import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from './bridge-product-contract-primitives.js';
import { encodeBridgeProductMetadataFrame } from './bridge-product-metadata-frame-codec.js';
import {
	BridgeProductMetadataStreamDecoder,
	BridgeProductMetadataStreamDecoderFailure,
} from './bridge-product-metadata-stream-decoder.js';
import {
	bridgeProductMetadataFrameSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductMetadataFrame,
	type BridgeProductMetadataStreamRequest,
} from './bridge-product-session-contracts.js';

const validMetadataFrames = validProductSessionCorpus.metadataFrames.map((frame) =>
	bridgeProductMetadataFrameSchema.parse(frame),
);
const validMetadataStreamRequests = validProductSessionCorpus.metadataStreamRequests.map(
	(request) => bridgeProductMetadataStreamRequestSchema.parse(request),
);

describe('Bridge product metadata stream decoder', () => {
	test('decodes one-byte and 4 KiB fragmentation without retaining unbounded residue', () => {
		const frames = validMetadataFrames.slice(0, 13);
		const encodedStream = concatenateBytes(...frames.map(encodeBridgeProductMetadataFrame));

		for (const fragmentByteLength of [1, 4 * 1024]) {
			const decoder = createMetadataStreamDecoder();
			const decodedFrames: BridgeProductMetadataFrame[] = [];
			for (let offset = 0; offset < encodedStream.byteLength; offset += fragmentByteLength) {
				decodedFrames.push(
					...decoder.push(encodedStream.subarray(offset, offset + fragmentByteLength)),
				);
			}
			decoder.finish();

			expect(decodedFrames).toEqual(frames);
			expect(decoder.diagnostics).toMatchObject({
				expectedNextStreamSequence: 13,
				retainedByteCount: 0,
				state: 'finished',
			});
			expect(decoder.diagnostics.peakRetainedByteCount).toBeLessThanOrEqual(
				BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES + 4,
			);
		}
	});

	test('admits an exact-cap body and rejects cap + 1 from only its prefix', () => {
		const acceptedFrame = validMetadataFrames[0];
		if (acceptedFrame === undefined) {
			throw new Error('Bridge product metadata fixture lost its accepted frame.');
		}
		const acceptedJSON = JSON.stringify(acceptedFrame);
		const exactCapBody = new TextEncoder().encode(
			acceptedJSON.padEnd(BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES, ' '),
		);
		const exactCapDecoder = createMetadataStreamDecoder();

		expect(exactCapDecoder.push(encodeRawBody(exactCapBody))).toEqual([acceptedFrame]);
		exactCapDecoder.finish();
		expect(exactCapDecoder.diagnostics.peakRetainedByteCount).toBe(
			BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES + 4,
		);

		const hostileTailByteCount = 2 * 1024 * 1024;
		const hostileChunk = new Uint8Array(4 + hostileTailByteCount);
		new DataView(hostileChunk.buffer).setUint32(
			0,
			BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES + 1,
			false,
		);
		const capPlusOneDecoder = createMetadataStreamDecoder();

		expect(() => capPlusOneDecoder.push(hostileChunk)).toThrow(/length/iu);
		expect(capPlusOneDecoder.diagnostics).toMatchObject({
			retainedByteCount: 0,
			state: 'poisoned',
		});
		expect(capPlusOneDecoder.diagnostics.peakRetainedByteCount).toBe(4);
	});

	test('rejects invalid UTF-8 and frames outside the strict typed schema', () => {
		const invalidUtf8Decoder = createMetadataStreamDecoder();
		expect(() => invalidUtf8Decoder.push(encodeRawBody(Uint8Array.of(0xff)))).toThrow(
			/UTF-8|invalid/iu,
		);
		expect(invalidUtf8Decoder.diagnostics.state).toBe('poisoned');

		const invalidSchemaDecoder = createMetadataStreamDecoder();
		expect(() =>
			invalidSchemaDecoder.push(
				encodeRawBody(new TextEncoder().encode('{"kind":"metadataStream.accepted"}')),
			),
		).toThrow(/contract|invalid/iu);
		expect(invalidSchemaDecoder.diagnostics.state).toBe('poisoned');
	});

	test('rejects a pane-wide stream sequence gap and duplicate', () => {
		const acceptedFrame = requiredFrame(0);
		const reviewAcceptedFrame = requiredFrame(1);
		const fileAcceptedFrame = requiredFrame(4);
		const gapFrame = bridgeProductMetadataFrameSchema.parse({
			...reviewAcceptedFrame,
			streamSequence: 2,
		});
		const duplicateFrame = bridgeProductMetadataFrameSchema.parse({
			...fileAcceptedFrame,
			streamSequence: 1,
		});

		for (const hostileFrames of [
			[acceptedFrame, gapFrame],
			[acceptedFrame, reviewAcceptedFrame, duplicateFrame],
		]) {
			const decoder = createMetadataStreamDecoder();
			expect(() =>
				decoder.push(concatenateBytes(...hostileFrames.map(encodeBridgeProductMetadataFrame))),
			).toThrow(BridgeProductMetadataStreamDecoderFailure);
			expect(decoder.diagnostics).toMatchObject({
				failureCode: 'stream_sequence_mismatch',
				retainedByteCount: 0,
				state: 'poisoned',
			});
		}
	});

	test('keeps mixed Review and File frames in one contiguous physical order', () => {
		const frames = validMetadataFrames.slice(0, 13);
		const decoder = createMetadataStreamDecoder();

		const decodedFrames = decoder.push(
			concatenateBytes(...frames.map(encodeBridgeProductMetadataFrame)),
		);
		decoder.finish();

		expect(decodedFrames).toEqual(frames);
		expect(decodedFrames.map((frame) => frame.streamSequence)).toEqual([
			0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
		]);
		expect(
			decodedFrames
				.filter((frame) => 'subscriptionKind' in frame)
				.map((frame) => frame.subscriptionKind),
		).toContain('review.metadata');
		expect(
			decodedFrames
				.filter((frame) => 'subscriptionKind' in frame)
				.map((frame) => frame.subscriptionKind),
		).toContain('file.metadata');
	});

	test('accepts the resumed first sequence supplied by metadataStream.open', () => {
		const resumedAcceptedFrame = requiredFrame(14);
		const decoder = new BridgeProductMetadataStreamDecoder(requiredMetadataStreamRequest(1));

		expect(decoder.push(encodeBridgeProductMetadataFrame(resumedAcceptedFrame))).toEqual([
			resumedAcceptedFrame,
		]);
		decoder.finish();
		expect(decoder.diagnostics.expectedNextStreamSequence).toBe(8);
	});

	test('requires stream acceptance as the first frame and rejects a second acceptance', () => {
		const acceptedFrame = requiredFrame(0);
		const reviewAcceptedFrame = requiredFrame(1);
		const duplicateStreamAcceptance = bridgeProductMetadataFrameSchema.parse({
			...acceptedFrame,
			streamSequence: 1,
		});

		const missingAcceptanceDecoder = createMetadataStreamDecoder();
		expect(() =>
			missingAcceptanceDecoder.push(encodeBridgeProductMetadataFrame(reviewAcceptedFrame)),
		).toThrow(/acceptance/iu);

		const duplicateAcceptanceDecoder = createMetadataStreamDecoder();
		expect(() =>
			duplicateAcceptanceDecoder.push(
				concatenateBytes(
					encodeBridgeProductMetadataFrame(acceptedFrame),
					encodeBridgeProductMetadataFrame(duplicateStreamAcceptance),
				),
			),
		).toThrow(/acceptance/iu);
	});

	test('treats metadataStream.error as terminal and rejects all post-terminal bytes', () => {
		const acceptedFrame = requiredFrame(0);
		const streamErrorFrame = bridgeProductMetadataFrameSchema.parse({
			...requiredFrame(13),
			streamSequence: 1,
		});
		const postTerminalFrame = bridgeProductMetadataFrameSchema.parse({
			...requiredFrame(10),
			streamSequence: 2,
		});
		const acceptedAndTerminal = concatenateBytes(
			encodeBridgeProductMetadataFrame(acceptedFrame),
			encodeBridgeProductMetadataFrame(streamErrorFrame),
		);

		const laterPushDecoder = createMetadataStreamDecoder();
		expect(laterPushDecoder.push(acceptedAndTerminal)).toEqual([acceptedFrame, streamErrorFrame]);
		expect(laterPushDecoder.diagnostics.state).toBe('terminal');
		expect(() =>
			laterPushDecoder.push(encodeBridgeProductMetadataFrame(postTerminalFrame)),
		).toThrow(/terminal/iu);
		expect(laterPushDecoder.diagnostics.state).toBe('poisoned');

		const samePushDecoder = createMetadataStreamDecoder();
		expect(() =>
			samePushDecoder.push(
				concatenateBytes(acceptedAndTerminal, encodeBridgeProductMetadataFrame(postTerminalFrame)),
			),
		).toThrow(/terminal/iu);
		expect(samePushDecoder.diagnostics).toMatchObject({
			failureCode: 'post_terminal_frame',
			retainedByteCount: 0,
			state: 'poisoned',
		});

		const partialTailDecoder = createMetadataStreamDecoder();
		expect(() =>
			partialTailDecoder.push(concatenateBytes(acceptedAndTerminal, Uint8Array.of(0))),
		).toThrow(/terminal/iu);
		expect(partialTailDecoder.diagnostics.retainedByteCount).toBe(0);
	});

	test('correlates every frame to the exact metadata stream request before returning a batch', () => {
		const acceptedFrame = requiredFrame(0);
		const laterFrame = requiredFrame(1);
		const wrongIdentityFrames = [
			{ ...acceptedFrame, metadataStreamId: 'metadata-stream-other' },
			{ ...acceptedFrame, paneSessionId: 'pane-session-other' },
			{ ...acceptedFrame, workerInstanceId: 'worker-instance-other' },
		] as const;

		for (const wrongIdentityFrame of wrongIdentityFrames) {
			const decoder = createMetadataStreamDecoder();
			expect(() =>
				decoder.push(
					encodeBridgeProductMetadataFrame(
						bridgeProductMetadataFrameSchema.parse(wrongIdentityFrame),
					),
				),
			).toThrow(/identity|stream|pane|worker/iu);
			expect(decoder.diagnostics).toMatchObject({
				failureCode: 'stream_identity_mismatch',
				retainedByteCount: 0,
				state: 'poisoned',
			});
		}

		const wrongLaterFrame = bridgeProductMetadataFrameSchema.parse({
			...laterFrame,
			metadataStreamId: 'metadata-stream-other',
		});
		const transactionalDecoder = createMetadataStreamDecoder();
		expect(() =>
			transactionalDecoder.push(
				concatenateBytes(
					encodeBridgeProductMetadataFrame(acceptedFrame),
					encodeBridgeProductMetadataFrame(wrongLaterFrame),
				),
			),
		).toThrow(/identity|stream/iu);
		expect(transactionalDecoder.diagnostics).toMatchObject({
			acceptedStream: false,
			failureCode: 'stream_identity_mismatch',
			retainedByteCount: 0,
			state: 'poisoned',
		});

		const wrongWireVersionBody = new TextEncoder().encode(
			JSON.stringify({ ...acceptedFrame, wireVersion: 1 }),
		);
		const wrongWireVersionDecoder = createMetadataStreamDecoder();
		expect(() => wrongWireVersionDecoder.push(encodeRawBody(wrongWireVersionBody))).toThrow(
			/wire|contract|invalid/iu,
		);
		expect(wrongWireVersionDecoder.diagnostics).toMatchObject({
			retainedByteCount: 0,
			state: 'poisoned',
		});
	});
});

function createMetadataStreamDecoder(): BridgeProductMetadataStreamDecoder {
	return new BridgeProductMetadataStreamDecoder(requiredMetadataStreamRequest(0));
}

function requiredMetadataStreamRequest(index: number): BridgeProductMetadataStreamRequest {
	const request = validMetadataStreamRequests[index];
	if (request === undefined) {
		throw new Error(`Bridge product metadata fixture lost stream request ${index}.`);
	}
	return request;
}

function requiredFrame(index: number): BridgeProductMetadataFrame {
	const frame = validMetadataFrames[index];
	if (frame === undefined) {
		throw new Error(`Bridge product metadata fixture lost frame ${index}.`);
	}
	return frame;
}

function encodeRawBody(body: Uint8Array): Uint8Array<ArrayBuffer> {
	const encodedFrame = new Uint8Array(4 + body.byteLength);
	new DataView(encodedFrame.buffer).setUint32(0, body.byteLength, false);
	encodedFrame.set(body, 4);
	return encodedFrame;
}

function concatenateBytes(...parts: readonly Uint8Array[]): Uint8Array<ArrayBuffer> {
	const concatenatedBytes = new Uint8Array(
		parts.reduce((totalByteLength, part) => totalByteLength + part.byteLength, 0),
	);
	let targetOffset = 0;
	for (const part of parts) {
		concatenatedBytes.set(part, targetOffset);
		targetOffset += part.byteLength;
	}
	return concatenatedBytes;
}
