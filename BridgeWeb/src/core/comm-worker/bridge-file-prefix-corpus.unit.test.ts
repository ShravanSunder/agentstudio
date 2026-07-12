import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import filePrefixCorpusJSON from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-file-prefix-corpus.json' with { type: 'json' };
import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	bridgeProductSha256Schema,
} from './bridge-product-contract-primitives.js';
import {
	bridgeProductFileDescriptorReadyPayloadSchema,
	bridgeProductFileTruncationKindSchema,
} from './bridge-product-subscription-contracts.js';

const BRIDGE_PRODUCT_MAXIMUM_CONTENT_LINES = 10_000;
const FROZEN_CORPUS_SHA256 = '6e78b5ffce449348b3ff14e5913d9b46b0f72f8fdc3544ff95e68bfc7b69f274';

const bridgeFilePrefixSourceSegmentSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('hex'), value: z.string().regex(/^(?:[0-9a-f]{2})+$/u) }).strict(),
	z
		.object({
			count: z
				.number()
				.int()
				.positive()
				.max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES + 3),
			kind: z.literal('repeatHex'),
			value: z.string().regex(/^(?:[0-9a-f]{2})+$/u),
		})
		.strict(),
	z.object({ kind: z.literal('utf8'), value: z.string() }).strict(),
]);

const bridgeFilePrefixExpectedReaderSchema = z
	.object({
		didReachEnd: z.boolean(),
		endsMidLine: z.boolean(),
		endsWithNewline: z.boolean(),
		isBinary: z.boolean(),
		isValidUTF8: z.boolean(),
		payloadByteCount: z.number().int().nonnegative().max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES),
		payloadLineCount: z.number().int().nonnegative().max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_LINES),
		payloadSha256: bridgeProductSha256Schema.nullable(),
		truncationKind: bridgeProductFileTruncationKindSchema,
	})
	.strict()
	.superRefine((expectedReader, context): void => {
		if (expectedReader.endsMidLine && expectedReader.endsWithNewline) {
			context.addIssue({
				code: 'custom',
				message: 'A shared File prefix cannot end both mid-line and with LF.',
			});
		}
	});

const bridgeFilePrefixCorpusCaseSchema = z
	.object({
		expectedReader: bridgeFilePrefixExpectedReaderSchema,
		name: z.string().regex(/^[a-z0-9_]+$/u),
		productAvailability: z.enum(['available', 'binary', 'unsupported_encoding']),
		sourceSegments: z.array(bridgeFilePrefixSourceSegmentSchema).max(4).readonly(),
	})
	.strict()
	.superRefine((fixtureCase, context): void => {
		const expectsAvailablePayload = fixtureCase.productAvailability === 'available';
		if (expectsAvailablePayload !== (fixtureCase.expectedReader.payloadSha256 !== null)) {
			context.addIssue({
				code: 'custom',
				message: 'Available File cases require an independent expected payload SHA-256.',
			});
		}
		if (fixtureCase.productAvailability === 'binary' && !fixtureCase.expectedReader.isBinary) {
			context.addIssue({ code: 'custom', message: 'Binary classification requires a NUL fact.' });
		}
		if (
			fixtureCase.productAvailability === 'unsupported_encoding' &&
			fixtureCase.expectedReader.isValidUTF8
		) {
			context.addIssue({ code: 'custom', message: 'Unsupported encoding must fail strict UTF-8.' });
		}
	});

const bridgeFilePrefixCorpusSchema = z
	.object({
		cases: z.array(bridgeFilePrefixCorpusCaseSchema).min(1).readonly(),
		maximumPayloadBytes: z.literal(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES),
		maximumPayloadLines: z.literal(BRIDGE_PRODUCT_MAXIMUM_CONTENT_LINES),
		schemaVersion: z.literal(1),
	})
	.strict()
	.superRefine((corpus, context): void => {
		if (new Set(corpus.cases.map((fixtureCase) => fixtureCase.name)).size !== corpus.cases.length) {
			context.addIssue({
				code: 'custom',
				message: 'Shared File prefix case names must be unique.',
			});
		}
	});

type BridgeFilePrefixCorpus = z.infer<typeof bridgeFilePrefixCorpusSchema>;
type BridgeFilePrefixCorpusCase = BridgeFilePrefixCorpus['cases'][number];
type BridgeFilePrefixSourceSegment = BridgeFilePrefixCorpusCase['sourceSegments'][number];
type BridgeFilePrefixTruncationKind = z.infer<typeof bridgeProductFileTruncationKindSchema>;
type BridgeFileDescriptorCandidate = z.input<typeof bridgeProductFileDescriptorReadyPayloadSchema>;

interface BridgeFileDerivedPrefix {
	readonly bytes: Uint8Array;
	readonly didReachEnd: boolean;
	readonly endsMidLine: boolean;
	readonly endsWithNewline: boolean;
	readonly isBinary: boolean;
	readonly isValidUTF8: boolean;
	readonly payloadLineCount: number;
	readonly truncationKind: BridgeFilePrefixTruncationKind;
}

interface BridgeFileIncompleteUTF8Scalar {
	readonly expectedByteCount: number;
	readonly retainedByteCount: number;
}

const strictUTF8Decoder = new TextDecoder('utf-8', { fatal: true });
const filePrefixCorpus = bridgeFilePrefixCorpusSchema.parse(filePrefixCorpusJSON);

describe('Bridge File truthful-prefix shared corpus', () => {
	test('keeps mirrored corpus bytes byte-identical at one frozen hash', () => {
		const typeScriptBytes = readFileSync(
			new URL(
				'../../test-fixtures/bridge-contract-fixtures/valid/bridge-file-prefix-corpus.json',
				import.meta.url,
			),
		);
		const swiftBytes = readFileSync(
			new URL(
				'../../../../Tests/BridgeContractFixtures/valid/bridge-file-prefix-corpus.json',
				import.meta.url,
			),
		);

		expect(swiftBytes.equals(typeScriptBytes)).toBe(true);
		expect(sha256Hex(typeScriptBytes)).toBe(FROZEN_CORPUS_SHA256);
	});

	test('derives the same literal bytes, line facts, truncation, and independent hashes', () => {
		for (const fixtureCase of filePrefixCorpus.cases) {
			const sourceBytes = sourceBytesForCase(fixtureCase);
			const prefix = deriveCanonicalFilePrefix(sourceBytes, filePrefixCorpus);
			const expected = fixtureCase.expectedReader;

			expect(prefix.bytes.byteLength, fixtureCase.name).toBe(expected.payloadByteCount);
			expect(prefix.payloadLineCount, fixtureCase.name).toBe(expected.payloadLineCount);
			expect(prefix.didReachEnd, fixtureCase.name).toBe(expected.didReachEnd);
			expect(prefix.endsMidLine, fixtureCase.name).toBe(expected.endsMidLine);
			expect(prefix.endsWithNewline, fixtureCase.name).toBe(expected.endsWithNewline);
			expect(prefix.isBinary, fixtureCase.name).toBe(expected.isBinary);
			expect(prefix.isValidUTF8, fixtureCase.name).toBe(expected.isValidUTF8);
			expect(prefix.truncationKind, fixtureCase.name).toBe(expected.truncationKind);
			if (expected.payloadSha256 !== null) {
				expect(sha256Hex(prefix.bytes), fixtureCase.name).toBe(expected.payloadSha256);
			}
		}
	});

	test('admits only truthful available descriptors and bodyless terminal classifications', () => {
		for (const fixtureCase of filePrefixCorpus.cases) {
			const sourceBytes = sourceBytesForCase(fixtureCase);
			const prefix = deriveCanonicalFilePrefix(sourceBytes, filePrefixCorpus);
			const descriptor = productDescriptorForCase({ fixtureCase, prefix, sourceBytes });
			const parsedDescriptor = bridgeProductFileDescriptorReadyPayloadSchema.parse(descriptor);

			if (fixtureCase.productAvailability === 'available') {
				expect(parsedDescriptor.availability.availabilityKind, fixtureCase.name).toBe('available');
				expect(parsedDescriptor.payloadByteCount, fixtureCase.name).toBe(prefix.bytes.byteLength);
				expect(parsedDescriptor.payloadLineCount, fixtureCase.name).toBe(prefix.payloadLineCount);
				expect(prefix.bytes.byteLength, fixtureCase.name).toBeLessThanOrEqual(
					sourceBytes.byteLength,
				);
				continue;
			}
			expect(parsedDescriptor.availability.availabilityKind, fixtureCase.name).not.toBe(
				'available',
			);
			expect(parsedDescriptor.encoding, fixtureCase.name).toBeNull();
			expect(parsedDescriptor.payloadByteCount, fixtureCase.name).toBe(0);
			expect(parsedDescriptor.payloadLineCount, fixtureCase.name).toBe(0);
			expect(parsedDescriptor.totalLineCount, fixtureCase.name).toBeNull();
			expect(parsedDescriptor.truncationKind, fixtureCase.name).toBe('none');
		}
	});

	test('rejects a fabricated byte or newline appended beyond the truthful prefix', () => {
		const fixtureCase = filePrefixCorpus.cases.find(
			(candidate) => candidate.name === 'valid_scalar_split_at_byte_cap',
		);
		if (fixtureCase === undefined) {
			throw new Error('Shared File prefix corpus is missing the scalar-boundary case.');
		}
		const sourceBytes = sourceBytesForCase(fixtureCase);
		const prefix = deriveCanonicalFilePrefix(sourceBytes, filePrefixCorpus);
		const descriptor = productDescriptorForCase({ fixtureCase, prefix, sourceBytes });
		if (descriptor.availability.availabilityKind !== 'available') {
			throw new Error('Scalar-boundary corpus case must produce available File content.');
		}

		expect(
			bridgeProductFileDescriptorReadyPayloadSchema.safeParse({
				...descriptor,
				payloadByteCount: descriptor.payloadByteCount + 1,
			}).success,
		).toBe(false);
		expect(sha256Hex(Buffer.concat([Buffer.from(prefix.bytes), Buffer.from('\n')]))).not.toBe(
			descriptor.availability.contentDescriptor.expectedSha256,
		);
	});
});

function sourceBytesForCase(fixtureCase: BridgeFilePrefixCorpusCase): Uint8Array {
	return Buffer.concat(fixtureCase.sourceSegments.map(sourceBytesForSegment));
}

function sourceBytesForSegment(segment: BridgeFilePrefixSourceSegment): Uint8Array {
	switch (segment.kind) {
		case 'hex':
			return Buffer.from(segment.value, 'hex');
		case 'repeatHex': {
			const pattern = Buffer.from(segment.value, 'hex');
			if (pattern.byteLength === 1) {
				return Buffer.alloc(segment.count, pattern[0]);
			}
			const bytes = Buffer.alloc(pattern.byteLength * segment.count);
			for (let offset = 0; offset < bytes.byteLength; offset += pattern.byteLength) {
				pattern.copy(bytes, offset);
			}
			return bytes;
		}
		case 'utf8':
			return Buffer.from(segment.value, 'utf8');
	}
}

function deriveCanonicalFilePrefix(
	sourceBytes: Uint8Array,
	corpus: BridgeFilePrefixCorpus,
): BridgeFileDerivedPrefix {
	let boundaryOffset = 0;
	let isBinary = false;
	let newlineCount = 0;
	let reachedByteLimit = false;
	let reachedLineLimit = false;
	while (boundaryOffset < sourceBytes.byteLength && !reachedByteLimit && !reachedLineLimit) {
		const byte = sourceBytes[boundaryOffset];
		if (byte === undefined) {
			throw new Error('Bridge File prefix source ended before its checked boundary.');
		}
		boundaryOffset += 1;
		isBinary ||= byte === 0;
		if (byte === 0x0a) {
			newlineCount += 1;
		}
		reachedByteLimit = boundaryOffset === corpus.maximumPayloadBytes;
		reachedLineLimit = newlineCount === corpus.maximumPayloadLines;
	}
	const sourceHasMoreBytes = boundaryOffset < sourceBytes.byteLength;
	let payloadBytes: Uint8Array = sourceBytes.slice(0, boundaryOffset);
	let isValidUTF8 = isValidUTF8Bytes(payloadBytes);
	if (!isValidUTF8 && reachedByteLimit && sourceHasMoreBytes) {
		const canonicalBytes = canonicalizeSplitUTF8Scalar(payloadBytes, sourceBytes, boundaryOffset);
		if (canonicalBytes !== null) {
			payloadBytes = canonicalBytes;
			isValidUTF8 = true;
		}
	}
	const endsWithNewline = payloadBytes.at(-1) === 0x0a;
	const payloadLineCount =
		payloadBytes.byteLength === 0 ? 0 : newlineCount + (endsWithNewline ? 0 : 1);
	return {
		bytes: payloadBytes,
		didReachEnd: !sourceHasMoreBytes,
		endsMidLine: sourceHasMoreBytes && !endsWithNewline,
		endsWithNewline,
		isBinary,
		isValidUTF8,
		payloadLineCount,
		truncationKind: truncationKindForPrefix({
			payloadLineCount,
			reachedByteLimit,
			reachedLineLimit,
			sourceHasMoreBytes,
		}),
	};
}

function canonicalizeSplitUTF8Scalar(
	payloadBytes: Uint8Array,
	sourceBytes: Uint8Array,
	boundaryOffset: number,
): Uint8Array | null {
	const incompleteScalar = incompleteUTF8Scalar(payloadBytes);
	if (incompleteScalar === null) {
		return null;
	}
	const requiredContinuationByteCount =
		incompleteScalar.expectedByteCount - incompleteScalar.retainedByteCount;
	const boundaryScalar = Buffer.concat([
		Buffer.from(payloadBytes.slice(-incompleteScalar.retainedByteCount)),
		Buffer.from(sourceBytes.slice(boundaryOffset, boundaryOffset + requiredContinuationByteCount)),
	]);
	const candidate = payloadBytes.slice(0, -incompleteScalar.retainedByteCount);
	return isValidUTF8Bytes(boundaryScalar) && isValidUTF8Bytes(candidate) ? candidate : null;
}

function incompleteUTF8Scalar(payloadBytes: Uint8Array): BridgeFileIncompleteUTF8Scalar | null {
	const finalByte = payloadBytes.at(-1);
	if (finalByte === undefined || finalByte < 0x80) {
		return null;
	}
	let scalarStart = payloadBytes.byteLength - 1;
	while (scalarStart > 0 && payloadBytes.byteLength - scalarStart < 4) {
		const scalarByte = payloadBytes[scalarStart];
		if (scalarByte === undefined || !isUTF8ContinuationByte(scalarByte)) {
			break;
		}
		scalarStart -= 1;
	}
	const leadingByte = payloadBytes[scalarStart];
	if (leadingByte === undefined) {
		return null;
	}
	const expectedByteCount = expectedUTF8ScalarByteCount(leadingByte);
	if (expectedByteCount === null) {
		return null;
	}
	const availableByteCount = payloadBytes.byteLength - scalarStart;
	const continuationBytes = payloadBytes.slice(scalarStart + 1);
	if (
		availableByteCount >= expectedByteCount ||
		!continuationBytes.every(isUTF8ContinuationByte) ||
		!isValidPartialUTF8ScalarPrefix(leadingByte, continuationBytes)
	) {
		return null;
	}
	return { expectedByteCount, retainedByteCount: availableByteCount };
}

function expectedUTF8ScalarByteCount(leadingByte: number): number | null {
	if (leadingByte >= 0xc2 && leadingByte <= 0xdf) return 2;
	if (leadingByte >= 0xe0 && leadingByte <= 0xef) return 3;
	if (leadingByte >= 0xf0 && leadingByte <= 0xf4) return 4;
	return null;
}

function isUTF8ContinuationByte(byte: number): boolean {
	return byte >= 0x80 && byte <= 0xbf;
}

function isValidPartialUTF8ScalarPrefix(
	leadingByte: number,
	continuationBytes: Uint8Array,
): boolean {
	const secondByte = continuationBytes[0];
	if (secondByte === undefined) return true;
	if (leadingByte === 0xe0) return secondByte >= 0xa0 && secondByte <= 0xbf;
	if (leadingByte === 0xed) return secondByte >= 0x80 && secondByte <= 0x9f;
	if (leadingByte === 0xf0) return secondByte >= 0x90 && secondByte <= 0xbf;
	if (leadingByte === 0xf4) return secondByte >= 0x80 && secondByte <= 0x8f;
	return true;
}

function isValidUTF8Bytes(bytes: Uint8Array): boolean {
	try {
		strictUTF8Decoder.decode(bytes);
		return true;
	} catch {
		return false;
	}
}

function truncationKindForPrefix(props: {
	readonly payloadLineCount: number;
	readonly reachedByteLimit: boolean;
	readonly reachedLineLimit: boolean;
	readonly sourceHasMoreBytes: boolean;
}): BridgeFilePrefixTruncationKind {
	if (!props.sourceHasMoreBytes) return 'none';
	if (props.reachedByteLimit && props.payloadLineCount === BRIDGE_PRODUCT_MAXIMUM_CONTENT_LINES) {
		return 'both';
	}
	return props.reachedLineLimit ? 'lineLimit' : 'byteLimit';
}

function productDescriptorForCase(props: {
	readonly fixtureCase: BridgeFilePrefixCorpusCase;
	readonly prefix: BridgeFileDerivedPrefix;
	readonly sourceBytes: Uint8Array;
}): BridgeFileDescriptorCandidate {
	const common = {
		estimatedContentHeightPixels: null,
		fileExtension: 'txt',
		fileId: `file-${props.fixtureCase.name.replaceAll('_', '-')}`,
		language: 'text',
		modifiedAtUnixMilliseconds: null,
		path: `${props.fixtureCase.name}.txt`,
		rowId: `row-${props.fixtureCase.name.replaceAll('_', '-')}`,
		sizeBytes: props.sourceBytes.byteLength,
		source: {
			repoId: '00000000-0000-4000-8000-000000000001',
			rootRevisionToken: 'root-revision-1',
			sourceCursor: 'source-cursor-1',
			sourceId: 'file-source-1',
			subscriptionGeneration: 1,
			worktreeId: '00000000-0000-4000-8000-000000000002',
		},
	} as const;
	if (props.fixtureCase.productAvailability !== 'available') {
		return {
			...common,
			availability:
				props.fixtureCase.productAvailability === 'binary'
					? { availabilityKind: 'binary' as const }
					: {
							availabilityKind: 'unavailable' as const,
							reason: 'unsupported_encoding' as const,
						},
			encoding: null,
			endsMidLine: false,
			endsWithNewline: false,
			payloadByteCount: 0,
			payloadLineCount: 0,
			totalLineCount: null,
			truncationKind: 'none',
			virtualizedExtentKind: 'unavailable',
		};
	}
	const payloadSha256 = props.fixtureCase.expectedReader.payloadSha256;
	if (payloadSha256 === null) {
		throw new Error('Available shared File prefix case is missing its expected SHA-256.');
	}
	return {
		...common,
		availability: {
			availabilityKind: 'available',
			contentDescriptor: {
				contentKind: 'file.content',
				declaredByteLength: props.prefix.bytes.byteLength,
				descriptorId: `descriptor-${props.fixtureCase.name.replaceAll('_', '-')}`,
				encoding: 'utf-8',
				expectedSha256: payloadSha256,
				fileId: common.fileId,
				maximumBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				source: common.source,
				window: {
					kind: 'prefix',
					maximumBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
					maximumLines: BRIDGE_PRODUCT_MAXIMUM_CONTENT_LINES,
					startByte: 0,
				},
			},
		},
		encoding: 'utf-8',
		endsMidLine: props.prefix.endsMidLine,
		endsWithNewline: props.prefix.endsWithNewline,
		payloadByteCount: props.prefix.bytes.byteLength,
		payloadLineCount: props.prefix.payloadLineCount,
		totalLineCount: props.prefix.truncationKind === 'none' ? props.prefix.payloadLineCount : null,
		truncationKind: props.prefix.truncationKind,
		virtualizedExtentKind:
			props.prefix.truncationKind === 'none' ? 'exactLineCount' : 'previewBounded',
	};
}

function sha256Hex(bytes: Uint8Array): string {
	return createHash('sha256').update(bytes).digest('hex');
}
