import { describe, expect, test } from 'vitest';

import { encodeBridgeProductMetadataFrame } from './bridge-product-metadata-frame-codec.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_DELTA_MEMBER_COUNT,
	BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_OPERATION_COUNT,
	BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT,
	bridgeProductFileMetadataEventSchema,
} from './bridge-product-subscription-contracts.js';

const source = {
	repoId: '00000000-0000-4000-8000-000000000001',
	rootRevisionToken: null,
	sourceCursor: 'source-cursor-1',
	sourceId: 'source-1',
	subscriptionGeneration: 11,
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

const row = {
	changeStatus: 'modified',
	depth: 1,
	fileId: 'file-1',
	isDirectory: false,
	lineCount: 12,
	name: 'file.ts',
	parentPath: 'src',
	path: 'src/file.ts',
	rowId: 'row-1',
	sizeBytes: 120,
} as const;

const contentDescriptor = {
	contentKind: 'file.content',
	declaredByteLength: 120,
	descriptorId: 'descriptor-1',
	encoding: 'utf-8',
	expectedSha256: 'a'.repeat(64),
	fileId: 'file-1',
	maximumBytes: 120,
	source,
	window: {
		kind: 'prefix',
		maximumBytes: 120,
		maximumLines: 10_000,
		startByte: 0,
	},
} as const;

const descriptorReadyPayload = {
	availability: { availabilityKind: 'available', contentDescriptor },
	encoding: 'utf-8',
	endsMidLine: false,
	endsWithNewline: true,
	estimatedContentHeightPixels: null,
	fileExtension: 'ts',
	fileId: 'file-1',
	language: 'typescript',
	modifiedAtUnixMilliseconds: 1_720_000_000_000,
	path: 'src/file.ts',
	payloadByteCount: 120,
	payloadLineCount: 12,
	rowId: 'row-1',
	sizeBytes: 120,
	source,
	totalLineCount: 12,
	truncationKind: 'none',
	virtualizedExtentKind: 'exactLineCount',
} as const;

const descriptorReady = {
	...descriptorReadyPayload,
	eventKind: 'file.descriptorReady',
} as const;

describe('Bridge product File metadata event contract', () => {
	test('accepts every closed File metadata event variant', () => {
		const events = [
			{ eventKind: 'file.sourceAccepted', source },
			{
				eventKind: 'file.treeWindow',
				finalWindow: true,
				lineage: { lane: 'foreground', loadedBy: 'startup_window' },
				pathScope: ['src'],
				rows: [row],
				source,
				startIndex: 0,
				totalRowCount: 1,
			},
			{
				eventKind: 'file.treeDelta',
				operations: [
					{ op: 'upsertRows', rows: [row] },
					{ op: 'removeRows', paths: ['src/old.ts'], rowIds: ['row-old'] },
				],
				source,
			},
			{
				eventKind: 'file.statusPatch',
				patch: {
					ahead: 1,
					behind: 0,
					branchName: 'main',
					patchKind: 'summary',
					staged: 1,
					unstaged: 2,
					untracked: 3,
				},
				source,
			},
			descriptorReady,
			{
				eventKind: 'file.invalidated',
				fileId: 'file-1',
				path: 'src/file.ts',
				reason: 'contentChanged',
				replacementDescriptor: descriptorReadyPayload,
				source,
			},
		] as const;

		for (const event of events) {
			expect(bridgeProductFileMetadataEventSchema.parse(event)).toEqual(event);
		}
	});

	test('keeps nullable facts explicit and closes nested status and availability unions', () => {
		const nullableRow = {
			...row,
			changeStatus: null,
			fileId: null,
			lineCount: null,
			parentPath: null,
			sizeBytes: null,
		};
		const binaryDescriptor = {
			...descriptorReady,
			availability: { availabilityKind: 'binary' },
			encoding: null,
			endsMidLine: false,
			endsWithNewline: false,
			estimatedContentHeightPixels: null,
			fileExtension: null,
			language: null,
			modifiedAtUnixMilliseconds: null,
			payloadByteCount: 0,
			payloadLineCount: 0,
			totalLineCount: null,
			truncationKind: 'none',
			virtualizedExtentKind: 'unavailable',
		};

		expect(
			bridgeProductFileMetadataEventSchema.safeParse({
				eventKind: 'file.treeWindow',
				finalWindow: false,
				lineage: { lane: 'visible', loadedBy: 'visible' },
				pathScope: [],
				rows: [nullableRow],
				source,
				startIndex: 0,
				totalRowCount: null,
			}).success,
		).toBe(true);
		expect(bridgeProductFileMetadataEventSchema.safeParse(binaryDescriptor).success).toBe(true);
		expect(
			bridgeProductFileMetadataEventSchema.safeParse({
				...binaryDescriptor,
				estimatedContentHeightPixels: 123.5,
				virtualizedExtentKind: 'estimatedHeight',
			}).success,
		).toBe(false);
		expect(
			bridgeProductFileMetadataEventSchema.safeParse({
				...descriptorReady,
				availability: {
					availabilityKind: 'unavailable',
					reason: 'unsupported_encoding',
				},
				encoding: null,
				endsMidLine: false,
				endsWithNewline: false,
				payloadByteCount: 0,
				payloadLineCount: 0,
				totalLineCount: null,
				truncationKind: 'none',
				virtualizedExtentKind: 'unavailable',
			}).success,
		).toBe(true);

		for (const invalidEvent of [
			{ ...descriptorReady, availability: { availabilityKind: 'binary', contentDescriptor } },
			{
				...descriptorReady,
				availability: {
					availabilityKind: 'unavailable',
					reason: 'too_large',
				},
				encoding: null,
				endsMidLine: false,
				endsWithNewline: false,
				payloadByteCount: 0,
				payloadLineCount: 0,
				totalLineCount: null,
				truncationKind: 'none',
				virtualizedExtentKind: 'unavailable',
			},
			{
				...descriptorReady,
				availability: {
					availabilityKind: 'available',
					contentDescriptor: {
						...contentDescriptor,
						source: { ...source, sourceCursor: 'different-source-cursor' },
					},
				},
			},
			{
				eventKind: 'file.statusPatch',
				patch: { patchKind: 'invalidated', reason: 'git_status_changed', staged: 1 },
				source,
			},
			{
				eventKind: 'file.statusPatch',
				patch: { patchKind: 'path', path: 'src/file.ts', status: 'ignored' },
				source,
			},
		]) {
			expect(bridgeProductFileMetadataEventSchema.safeParse(invalidEvent).success).toBe(false);
		}
	});

	test('enforces canonical File prefix byte, line, encoding, and truncation facts', () => {
		const byteLimitedDescriptor = {
			...descriptorReady,
			availability: {
				availabilityKind: 'available',
				contentDescriptor: {
					...contentDescriptor,
					declaredByteLength: 2 * 1024 * 1024 - 1,
					maximumBytes: 2 * 1024 * 1024 - 1,
					window: {
						...contentDescriptor.window,
						maximumBytes: 2 * 1024 * 1024 - 1,
					},
				},
			},
			endsMidLine: true,
			endsWithNewline: false,
			payloadByteCount: 2 * 1024 * 1024 - 1,
			payloadLineCount: 500,
			sizeBytes: 3 * 1024 * 1024,
			totalLineCount: null,
			truncationKind: 'byteLimit',
			virtualizedExtentKind: 'previewBounded',
		};
		const lineLimitedDescriptor = {
			...descriptorReady,
			availability: {
				availabilityKind: 'available',
				contentDescriptor: {
					...contentDescriptor,
					declaredByteLength: 100_000,
					maximumBytes: 100_000,
					window: { ...contentDescriptor.window, maximumBytes: 100_000 },
				},
			},
			endsMidLine: false,
			endsWithNewline: true,
			payloadByteCount: 100_000,
			payloadLineCount: 10_000,
			sizeBytes: 120_000,
			totalLineCount: 12_000,
			truncationKind: 'lineLimit',
			virtualizedExtentKind: 'previewBounded',
		};

		expect(bridgeProductFileMetadataEventSchema.safeParse(byteLimitedDescriptor).success).toBe(
			true,
		);
		expect(bridgeProductFileMetadataEventSchema.safeParse(lineLimitedDescriptor).success).toBe(
			true,
		);
		for (const invalidDescriptor of [
			{ ...descriptorReady, encoding: null },
			{ ...descriptorReady, payloadByteCount: 121 },
			{ ...descriptorReady, payloadLineCount: 13 },
			{ ...descriptorReady, totalLineCount: 11 },
			{ ...descriptorReady, endsMidLine: true },
			{ ...descriptorReady, endsMidLine: true, endsWithNewline: true },
			{ ...lineLimitedDescriptor, payloadLineCount: 9_999 },
			{ ...lineLimitedDescriptor, virtualizedExtentKind: 'exactLineCount' },
			{ ...descriptorReady, virtualizedExtentKind: 'previewBounded' },
			{
				...descriptorReady,
				estimatedContentHeightPixels: 240,
				virtualizedExtentKind: 'estimatedHeight',
			},
			{ ...byteLimitedDescriptor, truncationKind: 'none' },
			{ ...descriptorReady, lineCount: 12 },
		]) {
			expect(bridgeProductFileMetadataEventSchema.safeParse(invalidDescriptor).success).toBe(false);
		}
	});

	test('rejects legacy carrier fields, unknown keys, and missing required-nullable facts', () => {
		for (const invalidEvent of [
			{ ...descriptorReady, contentHandle: 'legacy-handle' },
			{ ...descriptorReady, resourceUrl: 'agentstudio://resource/legacy' },
			{ ...descriptorReady, language: undefined },
			{
				eventKind: 'file.treeWindow',
				finalWindow: true,
				generation: 11,
				lineage: { lane: 'foreground', loadedBy: 'startup_window' },
				pathScope: [],
				rows: [],
				sequence: 1,
				source,
				startIndex: 0,
				streamId: 'legacy-stream',
				totalRowCount: 0,
			},
		]) {
			expect(bridgeProductFileMetadataEventSchema.safeParse(invalidEvent).success).toBe(false);
		}
	});

	test('enforces tree-window, operation, and aggregate delta member ceilings', () => {
		expect(BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT).toBe(256);
		expect(BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_OPERATION_COUNT).toBe(256);
		expect(BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_DELTA_MEMBER_COUNT).toBe(256);

		const rows = Array.from(
			{ length: BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT + 1 },
			(_, index) => ({ ...row, fileId: `file-${index}`, rowId: `row-${index}` }),
		);
		expect(
			bridgeProductFileMetadataEventSchema.safeParse({
				eventKind: 'file.treeWindow',
				finalWindow: true,
				lineage: { lane: 'foreground', loadedBy: 'startup_window' },
				pathScope: [],
				rows,
				source,
				startIndex: 0,
				totalRowCount: rows.length,
			}).success,
		).toBe(false);

		const operations = Array.from(
			{ length: BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_OPERATION_COUNT + 1 },
			(_, index) => ({ op: 'removeRows' as const, paths: [], rowIds: [`row-${index}`] }),
		);
		expect(
			bridgeProductFileMetadataEventSchema.safeParse({
				eventKind: 'file.treeDelta',
				operations,
				source,
			}).success,
		).toBe(false);

		const aggregateRows = Array.from(
			{ length: BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_DELTA_MEMBER_COUNT + 1 },
			(_, index) => ({ ...row, fileId: `file-${index}`, rowId: `row-${index}` }),
		);
		expect(
			bridgeProductFileMetadataEventSchema.safeParse({
				eventKind: 'file.treeDelta',
				operations: [{ op: 'upsertRows', rows: aggregateRows }],
				source,
			}).success,
		).toBe(false);
	});

	test('leaves encoded-byte batching to the universal metadata frame ceiling', () => {
		const oversizedPath = String.fromCharCode(1).repeat(4096);
		const oversizedRows = Array.from({ length: 32 }, (_, index) => ({
			...row,
			fileId: `file-${index}`,
			name: oversizedPath,
			parentPath: oversizedPath,
			path: oversizedPath,
			rowId: `row-${index}`,
		}));
		const event = bridgeProductFileMetadataEventSchema.parse({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'foreground', loadedBy: 'startup_window' },
			pathScope: [],
			rows: oversizedRows,
			source,
			startIndex: 0,
			totalRowCount: oversizedRows.length,
		});

		expect(() =>
			encodeBridgeProductMetadataFrame({
				cursor: 'file-cursor-1',
				data: { event, subscriptionKind: 'file.metadata' },
				interestRevision: 0,
				interestSha256: '51ce8b03041697e18e2a24d5311e14bb1df4da119635bb84246c1b047316e46b',
				kind: 'subscription.data',
				metadataStreamId: 'metadata-stream-1',
				paneSessionId: 'pane-session-1',
				sourceGeneration: 11,
				streamSequence: 1,
				subscriptionId: 'file-subscription-1',
				subscriptionKind: 'file.metadata',
				subscriptionSequence: 1,
				wireVersion: 2,
				workerDerivationEpoch: 2,
				workerInstanceId: 'worker-instance-1',
			}),
		).toThrow('exceeds its body ceiling');
	});
});
