import { createHash } from 'node:crypto';

import { describe, expect, test } from 'vitest';

import { deriveBridgeProductDevFilePrefix } from '../../../scripts/dev-server/bridge-product-dev-file-prefix.js';
import {
	bridgeProductContentIdentityFromDescriptor,
	bridgeProductContentRequestSchema,
	type BridgeProductContentFrameFor,
	type BridgeProductContentTerminal,
	type BridgeProductFileContentDescriptor,
} from './bridge-product-content-contracts.js';
import {
	concatenateBytes,
	encodeMinimalControlFrame,
	encodeMinimalDataFrame,
} from './bridge-product-content-frame-test-support.js';
import { BridgeProductContentStreamDecoder } from './bridge-product-content-stream-decoder.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from './bridge-product-contract-primitives.js';
import {
	fetchBridgeWorkerFileViewContentResource,
	type BridgeWorkerFileViewContentOpen,
} from './bridge-worker-file-view-content-fetch.js';
import { prepareBridgeWorkerFileViewContentRenderJobEvent } from './bridge-worker-file-view-content-ready.js';
import { makeBridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.test-support.js';

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
	test('assembles fragmented complete text and publishes beyond both legacy File prefix limits', async () => {
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
		expect(currentPrefix.didReachEnd).toBe(false);
		expect(currentPrefix.bytes.byteLength).toBe(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES);
		expect(currentPrefix.sha256).not.toBe(sourceSHA256);
		const contentDescriptor = makeCompleteFileContentDescriptor({
			byteLength: sourceBytes.byteLength,
			lineCount: sourceLineCount,
			sha256: sourceSHA256,
		});
		const resource = await fetchBridgeWorkerFileViewContentResource({
			contentRequest: {
				contentDescriptor,
				itemId: 'complete-file-1',
				language: 'text',
				path: 'Sources/CompleteFile.txt',
				sizeBytes: sourceBytes.byteLength,
			},
			openContent: fragmentedCompleteContentOpen(sourceBytes),
		});

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
				cacheKey: `complete-file:${sourceSHA256}`,
				sizeBytes: sourceBytes.byteLength,
				descriptorId: 'complete-file-descriptor-1',
				contentHash: sourceSHA256,
				encoding: 'utf-8',
				endsMidLine: false,
				endsWithNewline: false,
				virtualizedExtentKind: 'exactLineCount',
				payloadByteCount: sourceBytes.byteLength,
				payloadLineCount: sourceLineCount,
				totalLineCount: sourceLineCount,
				truncationKind: 'none',
				isBinary: false,
				canFetchContent: true,
			},
			publicationSequence: 1,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({ itemId: 'file-1', publicationSequence: 1, surface: 'file', workerDerivationEpoch: 1 }),
			resource,
			workerDerivationEpoch: 1,
		});
		if (publication === null || publication.message.job.payload.kind !== 'codeViewFileItem') {
			throw new Error('Expected the current File worker seam to publish a CodeView File item.');
		}
		const assembledText = publication.message.job.payload.item.file.contents;
		const assembledBytes = encoder.encode(assembledText);

		// Assert
		expect(publication.message.job.window).toEqual({
			startLine: 1,
			endLine: COMPLETE_FILE_SOURCE_LINE_COUNT,
			totalLineCount: COMPLETE_FILE_SOURCE_LINE_COUNT,
		});
		expect(publication.message.job.budget).toEqual({
			className: 'interactive',
			maxBytes: COMPLETE_FILE_SOURCE_BYTE_COUNT,
			maxWindowLines: COMPLETE_FILE_SOURCE_LINE_COUNT,
		});
		expect(publication.message.job.payload.item.bridgeMetadata.contentState).toBe('hydrated');
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

function makeCompleteFileContentDescriptor(props: {
	readonly byteLength: number;
	readonly lineCount: number;
	readonly sha256: string;
}): BridgeProductFileContentDescriptor {
	return {
		contentKind: 'file.content',
		declaredByteLength: props.byteLength,
		descriptorId: 'complete-file-descriptor-1',
		encoding: 'utf-8',
		expectedSha256: props.sha256,
		fileId: 'complete-file-1',
		maximumBytes: props.byteLength,
		source: {
			repoId: '00000000-0000-4000-8000-000000000001',
			rootRevisionToken: 'complete-file-root-revision',
			sourceCursor: 'complete-file-source-cursor',
			sourceId: 'complete-file-source',
			subscriptionGeneration: 1,
			worktreeId: '00000000-0000-4000-8000-000000000002',
		},
		window: {
			kind: 'prefix',
			maximumBytes: props.byteLength,
			maximumLines: props.lineCount,
			startByte: 0,
		},
	};
}

function fragmentedCompleteContentOpen(sourceBytes: Uint8Array): BridgeWorkerFileViewContentOpen {
	return (descriptor) => {
		const decodedStream = decodeFragmentedCompleteContent({ descriptor, sourceBytes });
		return {
			contentKind: 'file.content',
			contentRequestId: 'complete-file-content-request',
			frames: decodedCompleteContentFrames(decodedStream),
			terminal: decodedStream.then(({ terminal }) => terminal),
		};
	};
}

interface DecodedCompleteContent {
	readonly frames: readonly BridgeProductContentFrameFor<'file.content'>[];
	readonly terminal: BridgeProductContentTerminal<'file.content'>;
}

async function decodeFragmentedCompleteContent(props: {
	readonly descriptor: BridgeProductFileContentDescriptor;
	readonly sourceBytes: Uint8Array;
}): Promise<DecodedCompleteContent> {
	const request = bridgeProductContentRequestSchema.parse({
		contentKind: 'file.content',
		contentRequestId: 'complete-file-content-request',
		descriptor: props.descriptor,
		kind: 'content.open',
		leaseId: 'complete-file-lease',
		paneSessionId: 'complete-file-pane-session',
		wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
		workerDerivationEpoch: 1,
		workerInstanceId: 'complete-file-worker-instance',
	});
	if (request.contentKind !== 'file.content') {
		throw new Error('Complete File fixture decoded a non-File content request.');
	}
	const acceptedBody = {
		contentRequestId: request.contentRequestId,
		declaredByteLength: props.descriptor.declaredByteLength,
		expectedSha256: props.descriptor.expectedSha256,
		identity: bridgeProductContentIdentityFromDescriptor(props.descriptor),
		leaseId: request.leaseId,
		maximumBytes: props.descriptor.maximumBytes,
		paneSessionId: request.paneSessionId,
		wireVersion: request.wireVersion,
		workerDerivationEpoch: request.workerDerivationEpoch,
		workerInstanceId: request.workerInstanceId,
	};
	const encodedFrames: Uint8Array[] = [encodeMinimalControlFrame(0x01, 0, acceptedBody)];
	let contentSequence = 1;
	for (
		let offsetBytes = 0;
		offsetBytes < props.sourceBytes.byteLength;
		offsetBytes += BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES
	) {
		encodedFrames.push(
			encodeMinimalDataFrame(
				contentSequence,
				offsetBytes,
				props.sourceBytes.subarray(
					offsetBytes,
					offsetBytes + BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
				),
			),
		);
		contentSequence += 1;
	}
	encodedFrames.push(
		encodeMinimalControlFrame(0x03, contentSequence, {
			endOfSource: true,
			observedByteLength: props.sourceBytes.byteLength,
			observedSha256: props.descriptor.expectedSha256,
		}),
	);

	const wireBytes = concatenateBytes(...encodedFrames);
	const decoder = new BridgeProductContentStreamDecoder(request);
	const decodedFrames: BridgeProductContentFrameFor<'file.content'>[] = [];
	let terminal: BridgeProductContentTerminal<'file.content'> | null = null;
	const fragmentByteLengths = [4093, 8191, 257, 32_768] as const;
	let fragmentIndex = 0;
	let wireOffset = 0;
	while (wireOffset < wireBytes.byteLength) {
		const fragmentByteLength = fragmentByteLengths[fragmentIndex % fragmentByteLengths.length];
		if (fragmentByteLength === undefined) {
			throw new Error('Complete File fragmentation fixture lost its fragment length.');
		}
		// eslint-disable-next-line no-await-in-loop -- Fragment decoding is intentionally ordered.
		const result = await decoder.push(
			wireBytes.subarray(wireOffset, wireOffset + fragmentByteLength),
		);
		decodedFrames.push(...result.frames);
		terminal = result.terminal ?? terminal;
		wireOffset += fragmentByteLength;
		fragmentIndex += 1;
	}
	decoder.finish();
	if (terminal === null) {
		throw new Error('Complete File fragmentation fixture produced no terminal.');
	}
	return { frames: decodedFrames, terminal };
}

async function* decodedCompleteContentFrames(
	decodedStream: Promise<DecodedCompleteContent>,
): AsyncIterable<BridgeProductContentFrameFor<'file.content'>> {
	const decoded = await decodedStream;
	for (const frame of decoded.frames) {
		yield frame;
	}
}

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
