import { createHash } from 'node:crypto';

import { describe, expect, test } from 'vitest';

import type { BridgeProductContentFrame } from './bridge-product-content-contracts.js';
import {
	concatenateBytes,
	contentAcceptedControlBody,
	contentAcceptedFrame,
	contentAcceptedFrameForByteCount,
	contentDataFrameForPayload,
	contentEndControlBody,
	contentEndFrameForByteCount,
	contentRequest,
	contentRequestForAccepted,
	encodeMinimalControlFrame,
	encodeMinimalControlFrameBytes,
	encodeMinimalDataFrame,
} from './bridge-product-content-frame-test-support.js';
import { BridgeProductContentStreamDecoder } from './bridge-product-content-stream-decoder.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_CONTROL_BODY_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES,
} from './bridge-product-contract-primitives.js';

function sha256Hex(bytes: Uint8Array): string {
	return createHash('sha256').update(bytes).digest('hex');
}

function acceptedDataEndWire(payload: Uint8Array): Uint8Array {
	const accepted = contentAcceptedFrameForByteCount(
		payload.byteLength,
		2 * 1024 * 1024,
		sha256Hex(payload),
	);
	const end = {
		...contentEndFrameForByteCount(2, payload.byteLength),
		header: {
			...contentEndFrameForByteCount(2, payload.byteLength).header,
			observedSha256: sha256Hex(payload),
		},
	} satisfies BridgeProductContentFrame;
	return concatenateBytes(
		encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody(accepted)),
		encodeMinimalDataFrame(1, 0, payload),
		encodeMinimalControlFrame(0x03, 2, contentEndControlBody(end)),
	);
}

async function decodeByFragmentSize(
	wireBytes: Uint8Array,
	fragmentByteLength: number,
	accepted: ReturnType<typeof contentAcceptedFrameForByteCount>,
): Promise<BridgeProductContentFrame[]> {
	const decoder = new BridgeProductContentStreamDecoder(contentRequestForAccepted(accepted));
	const decodedFrames: BridgeProductContentFrame[] = [];
	for (let offset = 0; offset < wireBytes.byteLength; offset += fragmentByteLength) {
		// eslint-disable-next-line no-await-in-loop -- Fragment admission is ordered.
		const result = await decoder.push(wireBytes.subarray(offset, offset + fragmentByteLength));
		decodedFrames.push(...result.frames);
	}
	decoder.finish();
	expect(decoder.state).toBe('terminal');
	expect(decoder.retainedByteCount).toBe(0);
	return decodedFrames;
}

describe('Bridge product content stream decoder', () => {
	test('decodes accepted, raw data, and end across one-byte and 4 KiB fragmentation', async () => {
		const payload = new Uint8Array(8 * 1024 + 17).fill(0xa5);
		const request = contentRequest();
		const accepted = contentAcceptedFrameForByteCount(
			payload.byteLength,
			2 * 1024 * 1024,
			sha256Hex(payload),
		);
		const wireBytes = acceptedDataEndWire(payload);

		const oneByteFrames = await decodeByFragmentSize(wireBytes, 1, accepted);
		const fourKiBFrames = await decodeByFragmentSize(wireBytes, 4 * 1024, accepted);

		expect(oneByteFrames.map((frame) => frame.header.kind)).toEqual([
			'content.accepted',
			'content.data',
			'content.end',
		]);
		expect(fourKiBFrames).toEqual(oneByteFrames);
		expect(oneByteFrames[0]).toEqual(accepted);
		expect(oneByteFrames[1]).toEqual(contentDataFrameForPayload(1, 0, payload));
		expect(request.contentRequestId).toBe(accepted.header.contentRequestId);
	});

	test('accepts exactly 128 KiB of raw data and rejects one byte more', async () => {
		const exactPayload = new Uint8Array(BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES).fill(
			0x61,
		);
		const accepted = contentAcceptedFrameForByteCount(exactPayload.byteLength, 2 * 1024 * 1024);
		const acceptedWire = encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody(accepted));
		const exactDecoder = new BridgeProductContentStreamDecoder(contentRequestForAccepted(accepted));

		const exactResult = await exactDecoder.push(
			concatenateBytes(acceptedWire, encodeMinimalDataFrame(1, 0, exactPayload)),
		);

		expect(exactResult.frames[1]?.payload.byteLength).toBe(
			BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
		);

		const oversizedDecoder = new BridgeProductContentStreamDecoder(
			contentRequestForAccepted(accepted),
		);
		await expect(
			oversizedDecoder.push(
				concatenateBytes(
					acceptedWire,
					encodeMinimalDataFrame(1, 0, new Uint8Array(exactPayload.byteLength + 1)),
				),
			),
		).rejects.toThrow(/payload|128|bounds/iu);
		expect(oversizedDecoder.state).toBe('poisoned');
		expect(oversizedDecoder.retainedByteCount).toBe(0);
	});

	test('enforces the 256 KiB universal body and 16 KiB JSON control ceilings', async () => {
		const exactFrameBody = new Uint8Array(4 + BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES);
		new DataView(exactFrameBody.buffer).setUint32(
			0,
			BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES,
			false,
		);
		exactFrameBody[4] = 0x02;
		new DataView(exactFrameBody.buffer).setUint32(5, 1, false);
		const exactFrameDecoder = new BridgeProductContentStreamDecoder(contentRequest());
		await expect(exactFrameDecoder.push(exactFrameBody)).rejects.toThrow(/payload|bounds/iu);

		const oversizedFrameBody = exactFrameBody.slice();
		new DataView(oversizedFrameBody.buffer).setUint32(
			0,
			BRIDGE_PRODUCT_MAXIMUM_CONTENT_FRAME_BYTES + 1,
			false,
		);
		const oversizedFrameDecoder = new BridgeProductContentStreamDecoder(contentRequest());
		await expect(oversizedFrameDecoder.push(oversizedFrameBody)).rejects.toThrow(/ceiling/iu);

		const acceptedJSONBytes = new TextEncoder().encode(
			JSON.stringify(contentAcceptedControlBody()),
		);
		const exactControlBody = new Uint8Array(BRIDGE_PRODUCT_MAXIMUM_CONTENT_CONTROL_BODY_BYTES).fill(
			0x20,
		);
		exactControlBody.set(acceptedJSONBytes);
		const exactControlDecoder = new BridgeProductContentStreamDecoder(contentRequest());
		const exactControlResult = await exactControlDecoder.push(
			encodeMinimalControlFrameBytes(0x01, 0, exactControlBody),
		);
		expect(exactControlResult.frames).toEqual([contentAcceptedFrame()]);

		const oversizedControlBody = new Uint8Array(exactControlBody.byteLength + 1).fill(0x20);
		oversizedControlBody.set(acceptedJSONBytes);
		const oversizedControlDecoder = new BridgeProductContentStreamDecoder(contentRequest());
		await expect(
			oversizedControlDecoder.push(encodeMinimalControlFrameBytes(0x01, 0, oversizedControlBody)),
		).rejects.toThrow(/control|ceiling/iu);
		expect(oversizedControlDecoder.retainedByteCount).toBe(0);
	});

	test('rejects pre-acceptance, gap, duplicate, and offset-mismatch frames', async () => {
		const acceptedWire = encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody());
		const hostileStreams = [
			encodeMinimalDataFrame(1, 0, Uint8Array.of(0x61)),
			concatenateBytes(acceptedWire, encodeMinimalDataFrame(2, 0, Uint8Array.of(0x61))),
			concatenateBytes(
				acceptedWire,
				encodeMinimalDataFrame(1, 0, Uint8Array.of(0x61)),
				encodeMinimalDataFrame(1, 1, Uint8Array.of(0x62)),
			),
			concatenateBytes(acceptedWire, encodeMinimalDataFrame(1, 9, Uint8Array.of(0x61))),
		] as const;

		await Promise.all(
			hostileStreams.map(async (hostileStream): Promise<void> => {
				const decoder = new BridgeProductContentStreamDecoder(contentRequest());
				await expect(decoder.push(hostileStream)).rejects.toThrow(/accepted|sequence|offset/iu);
				expect(decoder.state).toBe('poisoned');
				expect(decoder.retainedByteCount).toBe(0);
			}),
		);
	});

	test('rejects mismatched accepted identity and post-terminal bytes without retained state', async () => {
		const request = contentRequest();
		const accepted = contentAcceptedFrame();
		const mismatchedAccepted = {
			...accepted,
			header: { ...accepted.header, workerInstanceId: 'worker-instance-other' },
		} satisfies BridgeProductContentFrame;
		const mismatchDecoder = new BridgeProductContentStreamDecoder(request);
		await expect(
			mismatchDecoder.push(
				encodeMinimalControlFrame(0x01, 0, contentAcceptedControlBody(mismatchedAccepted)),
			),
		).rejects.toThrow(/issued request|match|correlation/iu);
		expect(mismatchDecoder.retainedByteCount).toBe(0);

		const terminalAccepted = contentAcceptedFrameForByteCount(3, 2 * 1024 * 1024);
		const terminalDecoder = new BridgeProductContentStreamDecoder(
			contentRequestForAccepted(terminalAccepted),
		);
		await terminalDecoder.push(acceptedDataEndWire(Uint8Array.from([97, 98, 99])));
		expect(terminalDecoder.state).toBe('terminal');
		expect(terminalDecoder.retainedByteCount).toBe(0);
		await expect(terminalDecoder.push(Uint8Array.of(0))).rejects.toThrow(/terminal/iu);
		expect(terminalDecoder.retainedByteCount).toBe(0);
	});
});
