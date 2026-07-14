import { createHash } from 'node:crypto';

import { describe, expect, test } from 'vitest';

import { deriveBridgeProductDevFilePrefix } from '../../../scripts/dev-server/bridge-product-dev-file-prefix.js';
import { BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES } from './bridge-product-contract-primitives.js';
import { prepareBridgeWorkerFileViewContentRenderJobEvent } from './bridge-worker-file-view-content-ready.js';

const CURRENT_FILE_MAXIMUM_LINES = 10_000;
const COMPLETE_FILE_SOURCE_BYTE_COUNT = 2_097_217;
const COMPLETE_FILE_SOURCE_LINE_COUNT = 10_001;
const COMPLETE_FILE_SOURCE_SHA256 =
	'c15344b0a2aabc7a0f63ddda2d79d604bce142de7228fc3f36162db775a6cbda';
const COMPLETE_FILE_FINAL_LINE_CANARY =
	'line-10001: __BRIDGE_FILE_COMPLETE_FINAL_CANARY_8B3F27D1__ λ😀';
const REGULAR_CRLF_LINE_BYTE_COUNT = 209;
const encoder = new TextEncoder();
const strictDecoder = new TextDecoder('utf-8', { fatal: true });

describe('Bridge File complete content', () => {
	test('publishes exact complete text beyond both legacy File prefix limits', () => {
		// Arrange
		const sourceText = makeCompleteFileSourceText();
		const sourceBytes = encoder.encode(sourceText);
		const sourceSHA256 = sha256Hex(sourceBytes);
		const sourceLineCount = logicalLineCount(sourceBytes);
		expect(sourceBytes.byteLength).toBe(COMPLETE_FILE_SOURCE_BYTE_COUNT);
		expect(sourceBytes.byteLength).toBeGreaterThan(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES);
		expect(sourceLineCount).toBe(COMPLETE_FILE_SOURCE_LINE_COUNT);
		expect(sourceLineCount).toBeGreaterThan(CURRENT_FILE_MAXIMUM_LINES);
		expect(countByte(sourceBytes, 0x0d)).toBe(CURRENT_FILE_MAXIMUM_LINES);
		expect(countByte(sourceBytes, 0x0a)).toBe(CURRENT_FILE_MAXIMUM_LINES);
		expect(sourceText.endsWith(COMPLETE_FILE_FINAL_LINE_CANARY)).toBe(true);
		expect(sourceText.split(COMPLETE_FILE_FINAL_LINE_CANARY)).toHaveLength(2);
		expect(strictDecoder.decode(sourceBytes)).toBe(sourceText);
		expect(sourceSHA256).toBe(COMPLETE_FILE_SOURCE_SHA256);

		const currentPrefix = deriveBridgeProductDevFilePrefix(sourceBytes, {
			maximumBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
			maximumLines: CURRENT_FILE_MAXIMUM_LINES,
		});
		const currentPrefixText = strictDecoder.decode(currentPrefix.bytes);

		// Act
		const publication = prepareBridgeWorkerFileViewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maxWindowLines: CURRENT_FILE_MAXIMUM_LINES,
			},
			metadata: {
				metadataKind: 'fileView',
				itemId: 'complete-file-1',
				path: 'Sources/CompleteFile.txt',
				language: 'text',
				cacheKey: `complete-file:${currentPrefix.sha256}`,
				sizeBytes: sourceBytes.byteLength,
				descriptorId: 'complete-file-descriptor-1',
				contentHash: currentPrefix.sha256,
				encoding: 'utf-8',
				endsMidLine: currentPrefix.endsMidLine,
				endsWithNewline: currentPrefix.endsWithNewline,
				virtualizedExtentKind: currentPrefix.didReachEnd ? 'exactLineCount' : 'previewBounded',
				payloadByteCount: currentPrefix.bytes.byteLength,
				payloadLineCount: currentPrefix.payloadLineCount,
				totalLineCount: currentPrefix.didReachEnd ? currentPrefix.payloadLineCount : null,
				truncationKind: currentPrefix.truncationKind,
				isBinary: currentPrefix.isBinary,
				canFetchContent: true,
			},
			publicationSequence: 1,
			resource: {
				byteLength: currentPrefix.bytes.byteLength,
				contentHash: currentPrefix.sha256,
				contentHashAlgorithm: 'sha256',
				descriptorId: 'complete-file-descriptor-1',
				itemId: 'complete-file-1',
				language: 'text',
				maxBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				path: 'Sources/CompleteFile.txt',
				resourceKind: 'file.content',
				sizeBytes: sourceBytes.byteLength,
				text: currentPrefixText,
				textBytes: Uint8Array.from(currentPrefix.bytes).buffer,
			},
			workerDerivationEpoch: 1,
		});
		if (publication === null || publication.message.job.payload.kind !== 'codeViewFileItem') {
			throw new Error('Expected the current File worker seam to publish a CodeView File item.');
		}
		const assembledText = publication.message.job.payload.item.file.contents;
		const assembledBytes = encoder.encode(assembledText);

		// Assert
		expect(
			{
				byteCount: assembledBytes.byteLength,
				bytesEqualIndependentSource: bytesEqual(assembledBytes, sourceBytes),
				reachesFinalLineCanary: assembledText.endsWith(COMPLETE_FILE_FINAL_LINE_CANARY),
				sha256: sha256Hex(assembledBytes),
			},
			'complete File worker publication must reach the final-line canary and equal independent source bytes',
		).toEqual({
			byteCount: COMPLETE_FILE_SOURCE_BYTE_COUNT,
			bytesEqualIndependentSource: true,
			reachesFinalLineCanary: true,
			sha256: COMPLETE_FILE_SOURCE_SHA256,
		});
	});
});

function makeCompleteFileSourceText(): string {
	const boundaryLineByteCount =
		BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES -
		(CURRENT_FILE_MAXIMUM_LINES - 1) * REGULAR_CRLF_LINE_BYTE_COUNT;
	const lines = Array.from({ length: CURRENT_FILE_MAXIMUM_LINES - 1 }, (_, lineOffset) =>
		makeExactCRLFLine({
			prefix: `line-${String(lineOffset + 1).padStart(5, '0')}: λ😀 `,
			totalByteCount: REGULAR_CRLF_LINE_BYTE_COUNT,
		}),
	);
	lines.push(
		makeExactCRLFLine({
			prefix: 'line-10000: boundary λ😀 ',
			totalByteCount: boundaryLineByteCount,
		}),
	);
	return `${lines.join('')}${COMPLETE_FILE_FINAL_LINE_CANARY}`;
}

function makeExactCRLFLine(props: {
	readonly prefix: string;
	readonly totalByteCount: number;
}): string {
	const fillerByteCount = props.totalByteCount - encoder.encode(props.prefix).byteLength - 2;
	if (!Number.isSafeInteger(fillerByteCount) || fillerByteCount < 0) {
		throw new Error('Complete File fixture line cannot satisfy its exact byte contract.');
	}
	const line = `${props.prefix}${'x'.repeat(fillerByteCount)}\r\n`;
	if (encoder.encode(line).byteLength !== props.totalByteCount) {
		throw new Error('Complete File fixture line violated its exact byte contract.');
	}
	return line;
}

function logicalLineCount(bytes: Uint8Array): number {
	if (bytes.byteLength === 0) return 0;
	return countByte(bytes, 0x0a) + (bytes.at(-1) === 0x0a ? 0 : 1);
}

function countByte(bytes: Uint8Array, expectedByte: number): number {
	let count = 0;
	for (const byte of bytes) {
		if (byte === expectedByte) count += 1;
	}
	return count;
}

function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
	if (left.byteLength !== right.byteLength) return false;
	return left.every((byte, index) => byte === right[index]);
}

function sha256Hex(bytes: Uint8Array): string {
	return createHash('sha256').update(bytes).digest('hex');
}
