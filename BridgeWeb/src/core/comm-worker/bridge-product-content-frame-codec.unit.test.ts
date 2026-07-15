import { createHash } from 'node:crypto';

import { describe, expect, test, vi } from 'vitest';

import type { BridgeProductContentFrame } from './bridge-product-content-contracts.js';
import {
	BridgeProductContentFrameEncoder,
	BridgeProductContentStreamValidator,
} from './bridge-product-content-frame-codec.js';
import {
	abcSha256,
	countByteSubsequence,
	contentAcceptedControlBody,
	contentAcceptedFrame,
	contentAcceptedFrameForByteCount,
	contentDataFrame,
	contentDataFrameForPayload,
	contentEndControlBody,
	contentEndFrame,
	contentEndFrameForByteCount,
	contentErrorFrame,
	contentRequest,
	contentRequestForAccepted,
	contentResetFrame,
	encodeMinimalDataFrame,
	parseMinimalControlBody,
	readUint32BigEndian,
	reviewContentAcceptedFrame,
	reviewContentRequest,
} from './bridge-product-content-frame-test-support.js';
import { BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES } from './bridge-product-contract-primitives.js';

describe('Bridge product content frame encoder and validator', () => {
	test('encodes sequence once and repeats full binding identity only in accepted', () => {
		const encoder = new BridgeProductContentFrameEncoder(contentRequest());
		const accepted = encoder.encode(contentAcceptedFrame());
		const data = encoder.encode(contentDataFrame());
		const end = encoder.encode(contentEndFrame());

		expect(readUint32BigEndian(accepted, 0)).toBe(accepted.byteLength - 4);
		expect(accepted[4]).toBe(0x01);
		expect(readUint32BigEndian(accepted, 5)).toBe(0);
		expect(parseMinimalControlBody(accepted)).toEqual(contentAcceptedControlBody());
		expect(data).toEqual(
			encodeMinimalDataFrame(
				contentDataFrame().header.contentSequence,
				contentDataFrame().header.offsetBytes,
				contentDataFrame().payload,
			),
		);
		expect(end[4]).toBe(0x03);
		expect(readUint32BigEndian(end, 5)).toBe(2);
		expect(parseMinimalControlBody(end)).toEqual(contentEndControlBody());
		expect(contentEndFrame().header.endOfSource).toBe(true);

		const identityMarker = new TextEncoder().encode('file-descriptor-1');
		expect(countByteSubsequence(accepted, identityMarker)).toBe(1);
		expect(countByteSubsequence(data, identityMarker)).toBe(0);
		expect(countByteSubsequence(end, identityMarker)).toBe(0);
		expect(new TextDecoder().decode(data)).not.toMatch(
			/identity|contentRequestId|workerInstanceId|rawByteLength/iu,
		);
	});

	test('represents exactly 2 MiB with sixteen full data frames plus accepted and end', () => {
		const payloadByteCount = 128 * 1024;
		const totalByteCount = 2 * 1024 * 1024;
		const accepted = contentAcceptedFrameForByteCount(totalByteCount, totalByteCount);
		const encoder = new BridgeProductContentFrameEncoder(contentRequestForAccepted(accepted));
		const encodedFrames = [
			encoder.encode(accepted),
			...Array.from({ length: 16 }, (_, index) => {
				const payload = new Uint8Array(payloadByteCount).fill(index);
				return encoder.encode(
					contentDataFrameForPayload(index + 1, index * payloadByteCount, payload),
				);
			}),
			encoder.encode(contentEndFrameForByteCount(17, totalByteCount)),
		];

		expect(encodedFrames).toHaveLength(18);
		for (const [index, dataFrame] of encodedFrames.slice(1, -1).entries()) {
			expect(readUint32BigEndian(dataFrame, 0)).toBe(1 + 4 + 4 + payloadByteCount);
			expect(dataFrame[4]).toBe(0x02);
			expect(readUint32BigEndian(dataFrame, 5)).toBe(index + 1);
			expect(readUint32BigEndian(dataFrame, 9)).toBe(index * payloadByteCount);
			expect(dataFrame.byteLength).toBe(4 + 1 + 4 + 4 + payloadByteCount);
		}
	});

	test('admits empty File content with an exact zero-byte maximum and terminal', async () => {
		const emptyBytes = new Uint8Array();
		const emptySha256 = createHash('sha256').update(emptyBytes).digest('hex');
		const accepted = contentAcceptedFrameForByteCount(0, 0, emptySha256);
		const request = contentRequestForAccepted(accepted);
		const validator = new BridgeProductContentStreamValidator(request);

		expect(await validator.accept(accepted)).toBeNull();
		const endFrame = {
			...contentEndFrameForByteCount(1, 0),
			header: {
				...contentEndFrameForByteCount(1, 0).header,
				observedSha256: emptySha256,
			},
		} satisfies BridgeProductContentFrame;
		const terminal = await validator.accept(endFrame);
		validator.finish();

		expect(terminal).toEqual({
			bytes: emptyBytes.buffer,
			contentKind: 'file.content',
			descriptorId: 'file-descriptor-1',
			endOfSource: true,
			kind: 'complete',
			observedSha256: emptySha256,
		});
	});

	test('admits complete File content beyond the legacy prefix through seventeen data frames', async () => {
		const dataFrameByteCount = BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES;
		const legacyPrefixByteCount = 2 * 1024 * 1024;
		const finalDataFrameByteCount = 65;
		const sourceBytes = new Uint8Array(legacyPrefixByteCount + finalDataFrameByteCount);
		sourceBytes.fill(0x61, 0, legacyPrefixByteCount);
		sourceBytes.fill(0x62, legacyPrefixByteCount);
		const sourceSha256 = createHash('sha256').update(sourceBytes).digest('hex');
		const accepted = contentAcceptedFrameForByteCount(
			sourceBytes.byteLength,
			sourceBytes.byteLength,
			sourceSha256,
		);
		const request = contentRequestForAccepted(accepted);
		const encoder = new BridgeProductContentFrameEncoder(request);
		const validator = new BridgeProductContentStreamValidator(request);
		const encodedFrames = [encoder.encode(accepted)];
		expect(await validator.accept(accepted)).toBeNull();

		for (let dataFrameIndex = 0; dataFrameIndex < 17; dataFrameIndex += 1) {
			const offsetBytes = dataFrameIndex * dataFrameByteCount;
			const payload = sourceBytes.slice(
				offsetBytes,
				Math.min(offsetBytes + dataFrameByteCount, sourceBytes.byteLength),
			);
			const frame = contentDataFrameForPayload(dataFrameIndex + 1, offsetBytes, payload);
			encodedFrames.push(encoder.encode(frame));
			// oxlint-disable-next-line no-await-in-loop -- Stream validation is sequence-ordered.
			expect(await validator.accept(frame)).toBeNull();
		}

		const endFrame = {
			...contentEndFrameForByteCount(18, sourceBytes.byteLength),
			header: {
				...contentEndFrameForByteCount(18, sourceBytes.byteLength).header,
				observedSha256: sourceSha256,
			},
		} satisfies BridgeProductContentFrame;
		encodedFrames.push(encoder.encode(endFrame));
		const terminal = await validator.accept(endFrame);
		encoder.finish();
		validator.finish();

		expect(sourceBytes.byteLength).toBe(2_097_217);
		expect(encodedFrames).toHaveLength(19);
		const finalDataFrame = encodedFrames[17];
		if (finalDataFrame === undefined) {
			throw new Error('Complete File contract omitted its seventeenth data frame.');
		}
		expect(readUint32BigEndian(finalDataFrame, 5)).toBe(17);
		expect(readUint32BigEndian(finalDataFrame, 9)).toBe(legacyPrefixByteCount);
		expect(finalDataFrame).toHaveLength(4 + 1 + 4 + 4 + finalDataFrameByteCount);
		expect(terminal).toEqual({
			bytes: sourceBytes.buffer,
			contentKind: 'file.content',
			descriptorId: 'file-descriptor-1',
			endOfSource: true,
			kind: 'complete',
			observedSha256: sourceSha256,
		});
	});

	test('stateful producer binds one response and poisons atomically on misuse', () => {
		const foreignAcceptedFrame = {
			...contentAcceptedFrame(),
			header: {
				...contentAcceptedFrame().header,
				contentRequestId: 'content-request-foreign',
			},
		};
		const foreignEncoder = new BridgeProductContentFrameEncoder(contentRequest());
		const foreignEmissions: Uint8Array[] = [];
		expect(() => foreignEmissions.push(foreignEncoder.encode(foreignAcceptedFrame))).toThrow(
			/issued request|acceptance|match/iu,
		);
		expect(foreignEmissions).toEqual([]);
		expect(() => foreignEncoder.encode(contentAcceptedFrame())).toThrow(/terminal|poison/iu);

		const preAcceptedEncoder = new BridgeProductContentFrameEncoder(contentRequest());
		expect(() => preAcceptedEncoder.encode(contentDataFrame())).toThrow(/begin|accepted/iu);
		expect(() => preAcceptedEncoder.encode(contentAcceptedFrame())).toThrow(/terminal|poison/iu);

		const duplicateAcceptedEncoder = new BridgeProductContentFrameEncoder(contentRequest());
		duplicateAcceptedEncoder.encode(contentAcceptedFrame());
		expect(() => duplicateAcceptedEncoder.encode(contentAcceptedFrame())).toThrow(/duplicate/iu);
		expect(() => duplicateAcceptedEncoder.encode(contentDataFrame())).toThrow(/terminal|poison/iu);

		const sequenceEncoder = new BridgeProductContentFrameEncoder(contentRequest());
		sequenceEncoder.encode(contentAcceptedFrame());
		expect(() =>
			sequenceEncoder.encode({
				...contentDataFrame(),
				header: { ...contentDataFrame().header, contentSequence: 2 },
			}),
		).toThrow(/sequence/iu);
		expect(() => sequenceEncoder.encode(contentDataFrame())).toThrow(/terminal|poison/iu);

		const offsetEncoder = new BridgeProductContentFrameEncoder(contentRequest());
		offsetEncoder.encode(contentAcceptedFrame());
		expect(() =>
			offsetEncoder.encode({
				...contentDataFrame(),
				header: { ...contentDataFrame().header, offsetBytes: 1 },
			}),
		).toThrow(/offset/iu);
		expect(() => offsetEncoder.encode(contentDataFrame())).toThrow(/terminal|poison/iu);

		const postTerminalEncoder = new BridgeProductContentFrameEncoder(contentRequest());
		postTerminalEncoder.encode(contentAcceptedFrame());
		postTerminalEncoder.encode(contentDataFrame());
		postTerminalEncoder.encode(contentEndFrame());
		expect(() => postTerminalEncoder.encode(contentDataFrame())).toThrow(/terminal/iu);
	});

	test('encoder and validator reject finish before a terminal frame', async () => {
		const encoder = new BridgeProductContentFrameEncoder(contentRequest());
		encoder.encode(contentAcceptedFrame());
		expect(() => encoder.finish()).toThrow(/without a terminal frame/iu);

		const validator = new BridgeProductContentStreamValidator(contentRequest());
		await validator.accept(contentAcceptedFrame());
		expect(() => validator.finish()).toThrow(/without a terminal frame/iu);
	});

	test('rejects hostile raw payload before taking an owned copy', async () => {
		const oversizedPayload = new Uint8Array(BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES + 1);
		const encoder = new BridgeProductContentFrameEncoder(contentRequest());
		encoder.encode(contentAcceptedFrame());
		const validator = new BridgeProductContentStreamValidator(contentRequest());
		await validator.accept(contentAcceptedFrame());
		const dataFrame = contentDataFrame();
		const copySpy = vi.spyOn(Uint8Array, 'from');

		expect(() => encoder.encode({ ...dataFrame, payload: oversizedPayload })).toThrow(
			/payload|byte bounds/iu,
		);
		expect(() => encoder.finish()).toThrow(/poison/iu);
		await expect(validator.accept({ ...dataFrame, payload: oversizedPayload })).rejects.toThrow(
			/payload|byte bounds/iu,
		);
		expect(copySpy).not.toHaveBeenCalled();
		copySpy.mockRestore();
	});

	test('validates sequence, offset, length, digest, and one terminal frame', async () => {
		const validator = new BridgeProductContentStreamValidator(contentRequest());

		expect(await validator.accept(contentAcceptedFrame())).toBeNull();
		expect(await validator.accept(contentDataFrame())).toBeNull();
		const completion = await validator.accept(contentEndFrame());

		expect(completion).toEqual({
			bytes: Uint8Array.from([97, 98, 99]).buffer,
			contentKind: 'file.content',
			descriptorId: 'file-descriptor-1',
			endOfSource: true,
			kind: 'complete',
			observedSha256: abcSha256,
		});
		await expect(validator.accept(contentDataFrame())).rejects.toThrow(/terminal/iu);
	});

	test('rejects a non-final terminal for complete File content', async () => {
		const validator = new BridgeProductContentStreamValidator(contentRequest());
		await validator.accept(contentAcceptedFrame());
		await validator.accept(contentDataFrame());

		await expect(
			validator.accept({
				...contentEndFrame(),
				header: { ...contentEndFrame().header, endOfSource: false },
			}),
		).rejects.toThrow(/end of source|final/iu);
	});

	test('preserves a non-final terminal for an exact-sized Review range', async () => {
		const validator = new BridgeProductContentStreamValidator(reviewContentRequest());
		await validator.accept(reviewContentAcceptedFrame());
		await validator.accept(contentDataFrame());

		const completion = await validator.accept({
			...contentEndFrame(),
			header: { ...contentEndFrame().header, endOfSource: false },
		});

		expect(completion).toMatchObject({
			contentKind: 'review.content',
			endOfSource: false,
			kind: 'complete',
		});
	});

	test('rejects gaps, wrong offsets, declared-length overruns, and digest conflicts', async () => {
		const gapValidator = new BridgeProductContentStreamValidator(contentRequest());
		await gapValidator.accept(contentAcceptedFrame());
		await expect(
			gapValidator.accept({
				...contentDataFrame(),
				header: { ...contentDataFrame().header, contentSequence: 2 },
			}),
		).rejects.toThrow(/sequence/iu);

		const offsetValidator = new BridgeProductContentStreamValidator(contentRequest());
		await offsetValidator.accept(contentAcceptedFrame());
		await expect(
			offsetValidator.accept({
				...contentDataFrame(),
				header: { ...contentDataFrame().header, offsetBytes: 1 },
			}),
		).rejects.toThrow(/offset/iu);

		const lengthRequest = contentRequest();
		const lengthValidator = new BridgeProductContentStreamValidator({
			...lengthRequest,
			descriptor: {
				...lengthRequest.descriptor,
				declaredByteLength: 2,
				maximumBytes: 2,
				window: { ...lengthRequest.descriptor.window, maximumBytes: 2 },
			},
		});
		await lengthValidator.accept({
			...contentAcceptedFrame(),
			header: {
				...contentAcceptedFrame().header,
				declaredByteLength: 2,
				identity: {
					...contentAcceptedFrame().header.identity,
					window: { ...contentAcceptedFrame().header.identity.window, maximumBytes: 2 },
				},
				maximumBytes: 2,
			},
		});
		await expect(lengthValidator.accept(contentDataFrame())).rejects.toThrow(/declared|maximum/iu);

		const digestRequest = contentRequest();
		const digestValidator = new BridgeProductContentStreamValidator({
			...digestRequest,
			descriptor: { ...digestRequest.descriptor, expectedSha256: '0'.repeat(64) },
		});
		await digestValidator.accept({
			...contentAcceptedFrame(),
			header: { ...contentAcceptedFrame().header, expectedSha256: '0'.repeat(64) },
		});
		await digestValidator.accept(contentDataFrame());
		await expect(digestValidator.accept(contentEndFrame())).rejects.toThrow(/digest/iu);
	});

	test('binds the accepted frame to the issued request identity', async () => {
		const validator = new BridgeProductContentStreamValidator(contentRequest());
		const acceptedFrame = contentAcceptedFrame();
		const wrongIdentityFrame: BridgeProductContentFrame = {
			...acceptedFrame,
			header: {
				...acceptedFrame.header,
				identity: {
					...acceptedFrame.header.identity,
					descriptorId: 'wrong-file-descriptor',
				},
			},
		};

		await expect(validator.accept(wrongIdentityFrame)).rejects.toThrow(/issued request/iu);
	});

	test('poisons the stream after a validation failure', async () => {
		const validator = new BridgeProductContentStreamValidator(contentRequest());
		await validator.accept(contentAcceptedFrame());
		await expect(
			validator.accept({
				...contentDataFrame(),
				header: { ...contentDataFrame().header, offsetBytes: 1 },
			}),
		).rejects.toThrow(/offset/iu);

		await expect(
			validator.accept({
				...contentDataFrame(),
				header: { ...contentDataFrame().header, contentSequence: 2 },
			}),
		).rejects.toThrow(/poison/iu);
		expect(() => validator.finish()).toThrow(/validation failure|poison/iu);
	});

	test('returns the shared typed error and reset terminals', async () => {
		const errorValidator = new BridgeProductContentStreamValidator(contentRequest());
		await errorValidator.accept(contentAcceptedFrame());
		await errorValidator.accept(contentDataFrame());
		expect(await errorValidator.accept(contentErrorFrame())).toEqual({
			code: 'internal',
			contentKind: 'file.content',
			descriptorId: 'file-descriptor-1',
			kind: 'error',
			retryable: false,
			safeMessage: null,
		});
		expect(() => errorValidator.finish()).not.toThrow();

		const resetValidator = new BridgeProductContentStreamValidator(contentRequest());
		await resetValidator.accept(contentAcceptedFrame());
		expect(await resetValidator.accept(contentResetFrame())).toEqual({
			contentKind: 'file.content',
			descriptorId: 'file-descriptor-1',
			kind: 'reset',
			reason: 'stale_source',
			retryable: true,
		});
		expect(() => resetValidator.finish()).not.toThrow();
	});
});
