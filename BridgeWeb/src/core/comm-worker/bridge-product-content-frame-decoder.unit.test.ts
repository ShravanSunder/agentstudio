import { describe, expect, test } from 'vitest';

import { BridgeProductContentFrameEncoder } from './bridge-product-content-frame-codec.js';
import { BridgeProductContentFrameDecoder } from './bridge-product-content-frame-decoder.js';
import {
	concatenateBytes,
	contentAcceptedControlBody,
	contentAcceptedFrame,
	contentAcceptedFrameForByteCount,
	contentDataFrame,
	contentDataFrameForPayload,
	contentEndControlBody,
	contentEndFrame,
	contentEndFrameForByteCount,
	contentRequestForAccepted,
	encodeMinimalControlFrame,
	encodeMinimalControlFrameBytes,
	encodeMinimalDataFrame,
} from './bridge-product-content-frame-test-support.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_CONTROL_BODY_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
} from './bridge-product-contract-primitives.js';

describe('Bridge product content frame decoder', () => {
	test('bounds every Swift response logical frame at 256 KiB', () => {
		expect(BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES).toBe(256 * 1024);
		expect(BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES).toBe(256 * 1024);
		expect(BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES).toBe(128 * 1024);
		expect(
			() => new BridgeProductContentFrameDecoder(BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES + 1),
		).toThrow(/frame ceiling/iu);
	});

	test('decodes independently constructed accepted, data, and terminal wire bytes', () => {
		const accepted = encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody());
		const data = encodeMinimalDataFrame(1, 0, Uint8Array.from([97, 98, 99]));
		const end = encodeMinimalControlFrame(0x03, 2, contentEndControlBody());
		const wireBytes = concatenateBytes(accepted, data, end);
		const decoder = new BridgeProductContentFrameDecoder();

		const firstFrames = decoder.push(wireBytes.subarray(0, 3));
		const secondFrames = decoder.push(wireBytes.subarray(3, accepted.byteLength + 2));
		const finalFrames = decoder.push(wireBytes.subarray(accepted.byteLength + 2));
		decoder.finish();

		expect(firstFrames).toEqual([]);
		expect(secondFrames).toEqual([contentAcceptedFrame()]);
		expect(finalFrames).toEqual([contentDataFrame(), contentEndFrame()]);
	});

	test('continues an admitted old-epoch lifecycle after the File derivation floor advances', () => {
		const acceptedFixture = contentAcceptedFrame();
		const admittedAcceptedFrame = {
			header: {
				contentRequestId: acceptedFixture.header.contentRequestId,
				contentSequence: 0,
				declaredByteLength: acceptedFixture.header.declaredByteLength,
				expectedSha256: acceptedFixture.header.expectedSha256,
				identity: acceptedFixture.header.identity,
				kind: 'content.accepted',
				leaseId: acceptedFixture.header.leaseId,
				maximumBytes: acceptedFixture.header.maximumBytes,
				paneSessionId: acceptedFixture.header.paneSessionId,
				wireVersion: 2,
				workerDerivationEpoch: 2,
				workerInstanceId: acceptedFixture.header.workerInstanceId,
			},
			payload: new Uint8Array(),
		} as const;
		const {
			contentSequence: _contentSequence,
			kind: _kind,
			...acceptedControlBody
		} = admittedAcceptedFrame.header;
		const currentFileDerivationEpoch = 3;
		const decoder = new BridgeProductContentFrameDecoder();

		const decodedFrames = decoder.push(
			concatenateBytes(
				encodeMinimalControlFrame(0x01, 0, acceptedControlBody),
				encodeMinimalDataFrame(1, 0, contentDataFrame().payload),
				encodeMinimalControlFrame(0x03, 2, contentEndControlBody()),
			),
		);
		decoder.finish();

		expect(admittedAcceptedFrame.header.workerDerivationEpoch).toBeLessThan(
			currentFileDerivationEpoch,
		);
		expect(decodedFrames).toEqual([admittedAcceptedFrame, contentDataFrame(), contentEndFrame()]);
	});

	test('admits only fixed prefixes from hostile multi-megabyte chunks', () => {
		const hostileTailByteCount = 8 * 1024 * 1024;
		const oversizedFrameChunk = new Uint8Array(4 + hostileTailByteCount);
		new DataView(oversizedFrameChunk.buffer).setUint32(
			0,
			BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES + 1,
			false,
		);
		oversizedFrameChunk.fill(0xa5, 4);
		const oversizedFrameDecoder = new BridgeProductContentFrameDecoder();

		expect(() => oversizedFrameDecoder.push(oversizedFrameChunk)).toThrow(/byte ceiling/iu);
		expect(oversizedFrameDecoder.diagnostics).toEqual({
			consumedByteCount: 4,
			copiedByteCount: 4,
			discardedTailByteCount: oversizedFrameChunk.byteLength - 4,
			emittedFrameCount: 0,
			failureCode: 'frame_length_exceeds_ceiling',
			peakRetainedByteCount: 4,
			receivedByteCount: oversizedFrameChunk.byteLength,
			retainedByteCount: 0,
			state: 'poisoned',
		});

		const hostileControlBytes = new Uint8Array(
			BRIDGE_PRODUCT_MAXIMUM_CONTENT_CONTROL_BODY_BYTES + 1,
		).fill(0x5a);
		const oversizedControlChunk = concatenateBytes(
			encodeMinimalControlFrameBytes(0x01, 0, hostileControlBytes),
			new Uint8Array(hostileTailByteCount).fill(0x5a),
		);
		const oversizedControlDecoder = new BridgeProductContentFrameDecoder();

		expect(() => oversizedControlDecoder.push(oversizedControlChunk)).toThrow(
			/header|control|JSON/iu,
		);
		expect(oversizedControlDecoder.diagnostics).toMatchObject({
			consumedByteCount: 9,
			copiedByteCount: 9,
			discardedTailByteCount: oversizedControlChunk.byteLength - 9,
			emittedFrameCount: 0,
			failureCode: 'content_control_body_exceeds_ceiling',
			peakRetainedByteCount: 9,
			receivedByteCount: oversizedControlChunk.byteLength,
			retainedByteCount: 0,
			state: 'poisoned',
		});
	});

	test('treats data bytes as raw payload rather than JSON or a header length', () => {
		const payload = Uint8Array.from([
			0x00, 0x00, 0x40, 0x01, 0x7b, 0x22, 0x78, 0x22, 0x3a, 0x31, 0x7d,
		]);
		const acceptedFrame = contentAcceptedFrameForByteCount(payload.byteLength, 1024);
		const dataFrame = contentDataFrameForPayload(1, 0, payload);
		const decoder = new BridgeProductContentFrameDecoder();

		expect(
			decoder.push(
				concatenateBytes(
					encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody(acceptedFrame)),
					encodeMinimalDataFrame(1, 0, payload),
				),
			),
		).toEqual([acceptedFrame, dataFrame]);
	});

	test('rejects the retired header-length frame grammar without a compatibility decoder', () => {
		const accepted = encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody());
		const retiredHeaderLengthDataFrame = Uint8Array.of(
			0x00,
			0x00,
			0x00,
			0x0a,
			0x02,
			0x00,
			0x00,
			0x00,
			0x02,
			0x7b,
			0x7d,
			0x61,
			0x62,
			0x63,
		);
		const decoder = new BridgeProductContentFrameDecoder();

		expect(() => decoder.push(concatenateBytes(accepted, retiredHeaderLengthDataFrame))).toThrow(
			/sequence|offset|invalid/iu,
		);
		expect(decoder.diagnostics).toMatchObject({ emittedFrameCount: 0, state: 'poisoned' });
	});

	test('copies one-byte and 4 KiB fragmentation once with bounded retention', () => {
		const oneByteFrame = concatenateBytes(
			encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody()),
			encodeMinimalDataFrame(1, 0, contentDataFrame().payload),
			encodeMinimalControlFrame(0x03, 2, contentEndControlBody()),
		);
		const oneByteDecoder = new BridgeProductContentFrameDecoder();
		let oneByteDecodedFrameCount = 0;
		for (let offset = 0; offset < oneByteFrame.byteLength; offset += 1) {
			oneByteDecodedFrameCount += oneByteDecoder.push(
				oneByteFrame.subarray(offset, offset + 1),
			).length;
		}
		oneByteDecoder.finish();

		const maximumPayload = new Uint8Array(128 * 1024).fill(0xa5);
		const maximumAccepted = contentAcceptedFrameForByteCount(
			maximumPayload.byteLength,
			2 * 1024 * 1024,
		);
		const maximumEnd = contentEndFrameForByteCount(2, maximumPayload.byteLength);
		const maximumWireBytes = concatenateBytes(
			encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody(maximumAccepted)),
			encodeMinimalDataFrame(1, 0, maximumPayload),
			encodeMinimalControlFrame(0x03, 2, contentEndControlBody(maximumEnd)),
		);
		const maximumDecoder = new BridgeProductContentFrameDecoder();
		let maximumDecodedFrameCount = 0;
		for (let offset = 0; offset < maximumWireBytes.byteLength; offset += 4096) {
			maximumDecodedFrameCount += maximumDecoder.push(
				maximumWireBytes.subarray(offset, offset + 4096),
			).length;
		}
		maximumDecoder.finish();

		expect(oneByteDecodedFrameCount).toBe(3);
		expect(oneByteDecoder.diagnostics).toMatchObject({
			consumedByteCount: oneByteFrame.byteLength,
			copiedByteCount: oneByteFrame.byteLength,
			discardedTailByteCount: 0,
			emittedFrameCount: 3,
			failureCode: null,
			retainedByteCount: 0,
			state: 'finished',
		});
		expect(maximumDecodedFrameCount).toBe(3);
		expect(maximumDecoder.diagnostics).toMatchObject({
			consumedByteCount: maximumWireBytes.byteLength,
			copiedByteCount: maximumWireBytes.byteLength,
			discardedTailByteCount: 0,
			emittedFrameCount: 3,
			failureCode: null,
			retainedByteCount: 0,
			state: 'finished',
		});
	});

	test('accepts exactly 128 KiB of raw data and rejects one byte more', () => {
		const maximumPayload = new Uint8Array(128 * 1024).fill(0x61);
		const oversizedPayload = new Uint8Array(maximumPayload.byteLength + 1).fill(0x62);
		const accepted = contentAcceptedFrameForByteCount(null, 2 * 1024 * 1024);
		const maximumFrame = contentDataFrameForPayload(1, 0, maximumPayload);
		const oversizedFrame = contentDataFrameForPayload(1, 0, oversizedPayload);

		const maximumEncoder = new BridgeProductContentFrameEncoder(
			contentRequestForAccepted(accepted),
		);
		maximumEncoder.encode(accepted);
		expect(() => maximumEncoder.encode(maximumFrame)).not.toThrow();
		const oversizedEncoder = new BridgeProductContentFrameEncoder(
			contentRequestForAccepted(accepted),
		);
		oversizedEncoder.encode(accepted);
		expect(() => oversizedEncoder.encode(oversizedFrame)).toThrow(/128|data|payload|ceiling/iu);

		const maximumDecoder = new BridgeProductContentFrameDecoder();
		expect(
			maximumDecoder.push(
				concatenateBytes(
					encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody(accepted)),
					encodeMinimalDataFrame(1, 0, maximumPayload),
				),
			),
		).toHaveLength(2);

		const oversizedDecoder = new BridgeProductContentFrameDecoder();
		expect(() =>
			oversizedDecoder.push(
				concatenateBytes(
					encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody(accepted)),
					encodeMinimalDataFrame(1, 0, oversizedPayload),
				),
			),
		).toThrow(/128|data|payload|ceiling/iu);
		expect(oversizedDecoder.diagnostics).toMatchObject({
			emittedFrameCount: 0,
			retainedByteCount: 0,
			state: 'poisoned',
		});
	});

	test('accepts a partial final data frame', () => {
		const maximumPayload = new Uint8Array(128 * 1024).fill(0x61);
		const finalPayload = Uint8Array.from([97, 98, 99]);
		const totalByteCount = maximumPayload.byteLength + finalPayload.byteLength;
		const accepted = contentAcceptedFrameForByteCount(totalByteCount, 2 * 1024 * 1024);
		const end = contentEndFrameForByteCount(3, totalByteCount);
		const decoder = new BridgeProductContentFrameDecoder();

		const frames = decoder.push(
			concatenateBytes(
				encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody(accepted)),
				encodeMinimalDataFrame(1, 0, maximumPayload),
				encodeMinimalDataFrame(2, maximumPayload.byteLength, finalPayload),
				encodeMinimalControlFrame(0x03, 3, contentEndControlBody(end)),
			),
		);
		decoder.finish();

		expect(frames).toHaveLength(4);
		expect(frames[2]?.payload).toEqual(finalPayload);
	});

	test('owns staged and emitted raw data bytes across caller mutation and detachment', () => {
		const accepted = encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody());
		const encodedFrame = encodeMinimalDataFrame(1, 0, contentDataFrame().payload);
		const stagedPrefix = encodedFrame.slice(0, encodedFrame.byteLength - 1);
		const finalByte = encodedFrame.slice(-1);
		const decoder = new BridgeProductContentFrameDecoder();

		expect(decoder.push(accepted)).toEqual([contentAcceptedFrame()]);
		expect(decoder.push(stagedPrefix)).toEqual([]);
		stagedPrefix.fill(0xff);
		structuredClone(stagedPrefix, { transfer: [stagedPrefix.buffer] });
		const [decodedFrame] = decoder.push(finalByte);
		decoder.push(encodeMinimalControlFrame(0x03, 2, contentEndControlBody()));
		decoder.finish();
		encodedFrame.fill(0);

		expect(stagedPrefix.byteLength).toBe(0);
		expect(decodedFrame).toEqual(contentDataFrame());
		expect(decodedFrame?.payload.buffer).not.toBe(encodedFrame.buffer);
	});

	test('rejects duplicate accepted and terminal JSON members before schemas', () => {
		const acceptedJSON = JSON.stringify(contentAcceptedControlBody());
		const endJSON = JSON.stringify(contentEndControlBody());
		const duplicateControlBodies = [
			{
				bytes: new TextEncoder().encode(
					acceptedJSON.replace(
						'"workerDerivationEpoch":2',
						'"workerDerivationEpoch":999,"workerDerivationEpoch":2',
					),
				),
				sequence: 0,
				tag: 0x01,
			},
			{
				bytes: new TextEncoder().encode(
					endJSON.replace(
						'"observedByteLength":3',
						'"observedByteLength":999,"observedByteLength":3',
					),
				),
				sequence: 2,
				tag: 0x03,
			},
		];

		for (const duplicateControlBody of duplicateControlBodies) {
			const decoder = new BridgeProductContentFrameDecoder();
			const acceptedPrefix =
				duplicateControlBody.tag === 0x01
					? new Uint8Array()
					: encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody());
			expect(() =>
				decoder.push(
					concatenateBytes(
						acceptedPrefix,
						encodeMinimalControlFrameBytes(
							duplicateControlBody.tag,
							duplicateControlBody.sequence,
							duplicateControlBody.bytes,
						),
					),
				),
			).toThrow(/closed contract|invalid|strict|duplicate/iu);
			expect(decoder.diagnostics).toMatchObject({
				emittedFrameCount: 0,
				failureCode: 'frame_decode_invalid',
				retainedByteCount: 0,
				state: 'poisoned',
			});
		}
	});

	test('rejects unknown tags, invalid sequences, and truncation', () => {
		const accepted = encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody());
		const unknownTag = accepted.slice();
		unknownTag[4] = 0xff;
		const nonzeroAccepted = encodeMinimalControlFrame(0x01, 1, contentAcceptedControlBody());
		const zeroData = encodeMinimalDataFrame(0, 0, contentDataFrame().payload);

		expect(() => new BridgeProductContentFrameDecoder().push(unknownTag)).toThrow(
			/unknown content frame tag/iu,
		);
		expect(() => new BridgeProductContentFrameDecoder().push(nonzeroAccepted)).toThrow(
			/sequence/iu,
		);
		expect(() => new BridgeProductContentFrameDecoder().push(zeroData)).toThrow(
			/accepted|sequence/iu,
		);
		const poisonedDecoder = new BridgeProductContentFrameDecoder();
		expect(() => poisonedDecoder.push(unknownTag)).toThrow(/unknown content frame tag/iu);
		expect(() => poisonedDecoder.push(accepted)).toThrow(/poisoned/iu);
		const truncatedDecoder = new BridgeProductContentFrameDecoder();
		truncatedDecoder.push(accepted.subarray(0, accepted.byteLength - 1));
		expect(truncatedDecoder.diagnostics.retainedByteCount).toBe(accepted.byteLength - 1);
		expect(() => truncatedDecoder.finish()).toThrow(/truncated/iu);
		expect(truncatedDecoder.diagnostics).toMatchObject({
			discardedTailByteCount: accepted.byteLength - 1,
			failureCode: 'truncated_frame',
			retainedByteCount: 0,
			state: 'poisoned',
		});
		expect(() => truncatedDecoder.push(accepted)).toThrow(/poisoned/iu);
	});

	test('poisons one push atomically on sequence, offset, or post-terminal misuse', () => {
		const accepted = encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody());
		const misuseChunks = [
			concatenateBytes(accepted, encodeMinimalDataFrame(2, 0, contentDataFrame().payload)),
			concatenateBytes(accepted, encodeMinimalDataFrame(1, 1, contentDataFrame().payload)),
			concatenateBytes(
				accepted,
				encodeMinimalControlFrame(0x03, 1, contentEndControlBody()),
				encodeMinimalDataFrame(2, 0, contentDataFrame().payload),
			),
		];

		for (const atomicChunk of misuseChunks) {
			const decoder = new BridgeProductContentFrameDecoder();

			expect(() => decoder.push(atomicChunk)).toThrow(/sequence|offset|terminal/iu);
			expect(decoder.diagnostics).toMatchObject({
				emittedFrameCount: 0,
				receivedByteCount: atomicChunk.byteLength,
				retainedByteCount: 0,
				state: 'poisoned',
			});
		}
	});

	test('finishes terminally without mutating diagnostics on repeated terminal calls', () => {
		const decoder = new BridgeProductContentFrameDecoder();
		const encodedFrames = concatenateBytes(
			encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody()),
			encodeMinimalControlFrame(0x03, 1, contentEndControlBody()),
		);

		expect(decoder.push(encodedFrames)).toEqual([
			contentAcceptedFrame(),
			{ ...contentEndFrame(), header: { ...contentEndFrame().header, contentSequence: 1 } },
		]);
		decoder.finish();
		const finishedDiagnostics = decoder.diagnostics;
		decoder.finish();

		expect(Object.isFrozen(finishedDiagnostics)).toBe(true);
		expect(decoder.diagnostics).toEqual(finishedDiagnostics);
		expect(() => decoder.push(encodedFrames)).toThrow(/finished/iu);
		expect(decoder.diagnostics).toEqual(finishedDiagnostics);
	});

	test('rejects incomplete lifecycles and any first byte after terminal state', () => {
		const accepted = encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody());
		const data = encodeMinimalDataFrame(1, 0, contentDataFrame().payload);
		const end = encodeMinimalControlFrame(0x03, 2, contentEndControlBody());
		for (const incompleteBytes of [new Uint8Array(), accepted, concatenateBytes(accepted, data)]) {
			const incompleteDecoder = new BridgeProductContentFrameDecoder();
			incompleteDecoder.push(incompleteBytes);
			expect(() => incompleteDecoder.finish()).toThrow(/terminal lifecycle|truncated/iu);
			expect(incompleteDecoder.diagnostics.state).toBe('poisoned');
		}

		const coalescedTailDecoder = new BridgeProductContentFrameDecoder();
		expect(() =>
			coalescedTailDecoder.push(concatenateBytes(accepted, data, end, Uint8Array.of(0))),
		).toThrow(/after terminal/iu);
		expect(coalescedTailDecoder.diagnostics.emittedFrameCount).toBe(0);

		const laterTailDecoder = new BridgeProductContentFrameDecoder();
		laterTailDecoder.push(concatenateBytes(accepted, data, end));
		expect(() => laterTailDecoder.push(Uint8Array.of(0))).toThrow(/after terminal/iu);
		expect(laterTailDecoder.diagnostics.state).toBe('poisoned');
	});
});
