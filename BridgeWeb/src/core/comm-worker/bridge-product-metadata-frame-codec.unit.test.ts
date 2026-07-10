import { describe, expect, test } from 'vitest';

import validProductSessionCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-session-corpus.json' with { type: 'json' };
import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from './bridge-product-contract-primitives.js';
import {
	BridgeProductMetadataFrameDecoder,
	encodeBridgeProductMetadataFrame,
} from './bridge-product-metadata-frame-codec.js';
import { bridgeProductMetadataFrameSchema } from './bridge-product-session-contracts.js';

describe('Bridge product metadata frame decoder', () => {
	test('rejects a configured ceiling above the locked logical-frame maximum', () => {
		expect(
			() => new BridgeProductMetadataFrameDecoder(BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES + 1),
		).toThrow(/frame ceiling/iu);
	});

	test('admits only the length prefix from a hostile multi-megabyte chunk', () => {
		const hostileTailByteCount = 8 * 1024 * 1024;
		const hostileChunk = new Uint8Array(4 + hostileTailByteCount);
		new DataView(hostileChunk.buffer).setUint32(
			0,
			BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES + 1,
			false,
		);
		hostileChunk.fill(0xa5, 4);
		const decoder = new BridgeProductMetadataFrameDecoder();

		expect(() => decoder.push(hostileChunk)).toThrow(/length/iu);
		expect(decoder.diagnostics).toEqual({
			consumedByteCount: 4,
			copiedByteCount: 4,
			discardedTailByteCount: hostileChunk.byteLength - 4,
			emittedFrameCount: 0,
			failureCode: 'frame_length_exceeds_ceiling',
			peakRetainedByteCount: 4,
			receivedByteCount: hostileChunk.byteLength,
			retainedByteCount: 0,
			state: 'poisoned',
		});
	});

	test('decodes fragmented and concatenated frames with bounded owned storage', () => {
		const frame = bridgeProductMetadataFrameSchema.parse(
			validProductSessionCorpus.metadataFrames[0],
		);
		const encodedFrame = encodeBridgeProductMetadataFrame(frame);
		const concatenatedFrames = concatenateBytes(encodedFrame, encodedFrame);
		const concatenatedDecoder = new BridgeProductMetadataFrameDecoder();

		expect(concatenatedDecoder.push(concatenatedFrames)).toEqual([frame, frame]);
		concatenatedDecoder.finish();
		expect(concatenatedDecoder.diagnostics.emittedFrameCount).toBe(2);
		expect(concatenatedDecoder.diagnostics.peakRetainedByteCount).toBe(encodedFrame.byteLength);

		const fragmentedDecoder = new BridgeProductMetadataFrameDecoder();
		let decodedFrames = 0;
		for (let offset = 0; offset < encodedFrame.byteLength; offset += 1) {
			decodedFrames += fragmentedDecoder.push(encodedFrame.subarray(offset, offset + 1)).length;
		}
		fragmentedDecoder.finish();

		expect(decodedFrames).toBe(1);
		expect(fragmentedDecoder.diagnostics).toMatchObject({
			consumedByteCount: encodedFrame.byteLength,
			copiedByteCount: encodedFrame.byteLength,
			discardedTailByteCount: 0,
			emittedFrameCount: 1,
			failureCode: null,
			peakRetainedByteCount: encodedFrame.byteLength,
			receivedByteCount: encodedFrame.byteLength,
			retainedByteCount: 0,
			state: 'finished',
		});
		const finishedDiagnostics = fragmentedDecoder.diagnostics;
		fragmentedDecoder.finish();
		expect(Object.isFrozen(finishedDiagnostics)).toBe(true);
		expect(fragmentedDecoder.diagnostics).toEqual(finishedDiagnostics);
		expect(() => fragmentedDecoder.push(encodedFrame)).toThrow(/finished/iu);
		expect(fragmentedDecoder.diagnostics).toEqual(finishedDiagnostics);
	});

	test('interleaves independent Review and File epochs on one contiguous physical stream', () => {
		const reviewInterestSha256 = '1a71797cab8ed23c72233b7706b166a33049e4e87dfbc55b9e252f9c1843eca6';
		const fileInterestSha256 = '51ce8b03041697e18e2a24d5311e14bb1df4da119635bb84246c1b047316e46b';
		const frameIdentity = {
			metadataStreamId: 'metadata-stream-independent-epochs',
			paneSessionId: 'pane-session-1',
			wireVersion: 2,
			workerInstanceId: 'worker-instance-1',
		} as const;
		const fileSource = {
			repoId: '00000000-0000-4000-8000-000000000001',
			rootRevisionToken: null,
			sourceCursor: 'source-cursor-1',
			sourceId: 'source-1',
			subscriptionGeneration: 11,
			worktreeId: '00000000-0000-4000-8000-000000000002',
		} as const;
		const frames = [
			{
				...frameIdentity,
				kind: 'metadataStream.accepted',
				resumeDisposition: 'snapshot_required',
				streamSequence: 0,
			},
			{
				...frameIdentity,
				cursor: null,
				interestRevision: 0,
				interestSha256: reviewInterestSha256,
				kind: 'subscription.accepted',
				sourceGeneration: 7,
				streamSequence: 1,
				subscriptionId: 'review-subscription-epoch-7',
				subscriptionKind: 'review.metadata',
				subscriptionSequence: 0,
				workerDerivationEpoch: 7,
			},
			{
				...frameIdentity,
				cursor: null,
				interestRevision: 0,
				interestSha256: fileInterestSha256,
				kind: 'subscription.accepted',
				sourceGeneration: 11,
				streamSequence: 2,
				subscriptionId: 'file-subscription-epoch-2',
				subscriptionKind: 'file.metadata',
				subscriptionSequence: 0,
				workerDerivationEpoch: 2,
			},
			{
				...frameIdentity,
				cursor: null,
				interestRevision: 0,
				interestSha256: fileInterestSha256,
				kind: 'subscription.accepted',
				sourceGeneration: 12,
				streamSequence: 3,
				subscriptionId: 'file-subscription-epoch-3',
				subscriptionKind: 'file.metadata',
				subscriptionSequence: 0,
				workerDerivationEpoch: 3,
			},
			{
				...frameIdentity,
				cursor: 'file-cursor-old-epoch',
				data: {
					event: { eventKind: 'file.sourceAccepted', source: fileSource },
					subscriptionKind: 'file.metadata',
				},
				interestRevision: 0,
				interestSha256: fileInterestSha256,
				kind: 'subscription.data',
				sourceGeneration: 11,
				streamSequence: 4,
				subscriptionId: 'file-subscription-epoch-2',
				subscriptionKind: 'file.metadata',
				subscriptionSequence: 1,
				workerDerivationEpoch: 2,
			},
			{
				...frameIdentity,
				cursor: 'review-cursor-epoch-7',
				data: {
					event: {
						eventKind: 'review.sourceAccepted',
						generation: 7,
						packageId: 'review-package-1',
						revision: 1,
						sourceIdentity: 'review-source-1',
					},
					subscriptionKind: 'review.metadata',
				},
				interestRevision: 0,
				interestSha256: reviewInterestSha256,
				kind: 'subscription.data',
				sourceGeneration: 7,
				streamSequence: 5,
				subscriptionId: 'review-subscription-epoch-7',
				subscriptionKind: 'review.metadata',
				subscriptionSequence: 1,
				workerDerivationEpoch: 7,
			},
			{
				...frameIdentity,
				cursor: 'file-cursor-old-epoch-terminal',
				interestRevision: 0,
				interestSha256: fileInterestSha256,
				kind: 'subscription.end',
				sourceGeneration: 11,
				streamSequence: 6,
				subscriptionId: 'file-subscription-epoch-2',
				subscriptionKind: 'file.metadata',
				subscriptionSequence: 2,
				workerDerivationEpoch: 2,
			},
		] as const;
		const encodedFrames = frames.map((frame) =>
			encodeBridgeProductMetadataFrame(bridgeProductMetadataFrameSchema.parse(frame)),
		);
		const decoder = new BridgeProductMetadataFrameDecoder();

		const decodedFrames = decoder.push(concatenateBytes(...encodedFrames));
		decoder.finish();

		expect(decodedFrames).toEqual(frames);
		expect(decodedFrames.map((frame) => frame.streamSequence)).toEqual([0, 1, 2, 3, 4, 5, 6]);
		expect(
			decodedFrames
				.slice(1)
				.map((frame) => ('workerDerivationEpoch' in frame ? frame.workerDerivationEpoch : null)),
		).toEqual([7, 2, 3, 2, 7, 2]);
		expect(frames.every((frame) => !('surface' in frame))).toBe(true);
	});

	test('poisons atomically on a bad tail and clears truncated storage at finish', () => {
		const frame = bridgeProductMetadataFrameSchema.parse(
			validProductSessionCorpus.metadataFrames[0],
		);
		const encodedFrame = encodeBridgeProductMetadataFrame(frame);
		const hostileTail = new Uint8Array(4 + 8 * 1024 * 1024);
		new DataView(hostileTail.buffer).setUint32(
			0,
			BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES + 1,
			false,
		);
		const atomicChunk = concatenateBytes(encodedFrame, hostileTail);
		const atomicDecoder = new BridgeProductMetadataFrameDecoder();

		expect(() => atomicDecoder.push(atomicChunk)).toThrow(/length/iu);
		expect(atomicDecoder.diagnostics).toMatchObject({
			discardedTailByteCount: hostileTail.byteLength - 4,
			emittedFrameCount: 0,
			failureCode: 'frame_length_exceeds_ceiling',
			retainedByteCount: 0,
			state: 'poisoned',
		});

		const truncatedDecoder = new BridgeProductMetadataFrameDecoder();
		expect(truncatedDecoder.push(encodedFrame.subarray(0, encodedFrame.byteLength - 1))).toEqual(
			[],
		);
		expect(() => truncatedDecoder.finish()).toThrow(/truncated/iu);
		expect(truncatedDecoder.diagnostics).toMatchObject({
			discardedTailByteCount: encodedFrame.byteLength - 1,
			failureCode: 'truncated_frame',
			retainedByteCount: 0,
			state: 'poisoned',
		});
		expect(() => truncatedDecoder.push(encodedFrame)).toThrow(/poisoned/iu);
	});

	test('owns staged bytes across caller mutation and detachment', () => {
		const frame = bridgeProductMetadataFrameSchema.parse(
			validProductSessionCorpus.metadataFrames[0],
		);
		const encodedFrame = encodeBridgeProductMetadataFrame(frame);
		const stagedBytes = encodedFrame.slice(0, encodedFrame.byteLength - 1);
		const finalByte = encodedFrame.slice(-1);
		const decoder = new BridgeProductMetadataFrameDecoder();

		expect(decoder.push(stagedBytes)).toEqual([]);
		stagedBytes.fill(0xff);
		structuredClone(stagedBytes, { transfer: [stagedBytes.buffer] });
		expect(decoder.push(finalByte)).toEqual([frame]);
		decoder.finish();

		expect(stagedBytes.byteLength).toBe(0);
	});

	test('rejects duplicate discriminant and worker derivation epoch members before schema decoding', () => {
		const frame = {
			cursor: null,
			interestRevision: 0,
			interestSha256: '1a71797cab8ed23c72233b7706b166a33049e4e87dfbc55b9e252f9c1843eca6',
			kind: 'subscription.accepted',
			metadataStreamId: 'metadata-stream-1',
			paneSessionId: 'pane-session-1',
			sourceGeneration: 7,
			streamSequence: 1,
			subscriptionId: 'review-subscription-1',
			subscriptionKind: 'review.metadata',
			subscriptionSequence: 0,
			wireVersion: 2,
			workerDerivationEpoch: 7,
			workerInstanceId: 'worker-instance-1',
		} as const;
		const canonicalJSON = JSON.stringify(frame);
		const duplicateBodies = [
			canonicalJSON.replace(
				'"kind":"subscription.accepted"',
				'"kind":"subscription.end","kind":"subscription.accepted"',
			),
			canonicalJSON.replace(
				'"workerDerivationEpoch":7',
				'"workerDerivationEpoch":999,"workerDerivationEpoch":7',
			),
			canonicalJSON.replace(
				'"kind":"subscription.accepted"',
				'"kind":"subscription.end","\\u006bind":"subscription.accepted"',
			),
		];

		for (const duplicateBody of duplicateBodies) {
			const decoder = new BridgeProductMetadataFrameDecoder();
			expect(() => decoder.push(encodeRawMetadataFrame(duplicateBody))).toThrow(/invalid|strict/iu);
			expect(decoder.diagnostics).toMatchObject({
				emittedFrameCount: 0,
				failureCode: 'frame_decode_invalid',
				retainedByteCount: 0,
				state: 'poisoned',
			});
		}
	});
});

function encodeRawMetadataFrame(rawJSON: string): Uint8Array<ArrayBuffer> {
	const body = new TextEncoder().encode(rawJSON);
	const frame = new Uint8Array(4 + body.byteLength);
	new DataView(frame.buffer).setUint32(0, body.byteLength, false);
	frame.set(body, 4);
	return frame;
}

function concatenateBytes(...parts: readonly Uint8Array[]): Uint8Array<ArrayBuffer> {
	const result = new Uint8Array(parts.reduce((total, part) => total + part.byteLength, 0));
	let offset = 0;
	for (const part of parts) {
		result.set(part, offset);
		offset += part.byteLength;
	}
	return result;
}
