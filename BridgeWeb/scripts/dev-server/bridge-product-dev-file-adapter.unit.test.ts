import { createHash } from 'node:crypto';

import { describe, expect, test } from 'vitest';

import { BridgeProductDevFileAdapter } from './bridge-product-dev-file-adapter.js';
import {
	worktreeFileProtocolFrameSchema,
	type WorktreeFileDescriptor,
	type WorktreeFileSurfaceSourceIdentity,
} from './bridge-worktree-dev-file-fixture-contracts.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

const filePath = 'fixtures/complete-file.txt';
const sourceIdentity: WorktreeFileSurfaceSourceIdentity = {
	repoId: 'fixture-repo',
	rootRevisionToken: 'fixture-revision-1',
	sourceCursor: 'fixture-cursor-1',
	sourceId: 'fixture-source-1',
	subscriptionGeneration: 1,
	worktreeId: 'fixture-worktree',
};

const completeFileCases = [
	{ name: 'empty', text: '' },
	{ name: 'LF-terminated', text: 'alpha\nbeta\n' },
	{ name: 'CRLF-terminated', text: 'alpha\r\nbeta\r\n' },
	{ name: 'multibyte without final newline', text: '🙂 alpha\n尾 beta' },
	{
		name: 'beyond the deleted byte and line caps',
		text: `${`${'x'.repeat(256)}\r\n`.repeat(10_001)}FINAL_COMPLETE_FILE_CANARY`,
	},
] as const;

describe('BridgeProductDevFileAdapter complete File contract', () => {
	test.each(completeFileCases)(
		'publishes exact complete bytes for $name text',
		async ({ text }) => {
			// Arrange
			const sourceBytes = new TextEncoder().encode(text);
			const expectedSha256 = createHash('sha256').update(sourceBytes).digest('hex');
			const expectedLineCount = exactLogicalLineCount(sourceBytes);
			const adapter = new BridgeProductDevFileAdapter(fakeFileProvider(text));

			// Act
			const descriptorEvent = await adapter.loadDescriptor(filePath);
			if (descriptorEvent.availability.availabilityKind !== 'available') {
				throw new Error('Expected an available complete File descriptor.');
			}
			const contentDescriptor = descriptorEvent.availability.contentDescriptor;
			const content = await adapter.loadContent(contentDescriptor);

			// Assert
			expect(contentDescriptor).toMatchObject({
				declaredByteLength: sourceBytes.byteLength,
				expectedSha256,
				maximumBytes: sourceBytes.byteLength,
				window: {
					kind: 'prefix',
					maximumBytes: sourceBytes.byteLength,
					maximumLines: expectedLineCount,
					startByte: 0,
				},
			});
			expect(descriptorEvent).toMatchObject({
				endsMidLine: false,
				endsWithNewline: sourceBytes.at(-1) === 0x0a,
				payloadByteCount: sourceBytes.byteLength,
				payloadLineCount: expectedLineCount,
				sizeBytes: sourceBytes.byteLength,
				totalLineCount: expectedLineCount,
				truncationKind: 'none',
				virtualizedExtentKind: 'exactLineCount',
			});
			expect(content?.endOfSource).toBe(true);
			expect(content?.bytes.byteLength).toBe(sourceBytes.byteLength);
			expect(Buffer.compare(Buffer.from(content?.bytes ?? []), Buffer.from(sourceBytes))).toBe(0);
		},
	);
});

function fakeFileProvider(text: string): BridgeWorktreeDevProvider {
	const sourceBytes = new TextEncoder().encode(text);
	const descriptor = fakeDescriptor(sourceBytes);
	return {
		loadWorktreeFileContent: async () => text,
		loadWorktreeFileDescriptor: async () => {
			const frame = worktreeFileProtocolFrameSchema.parse({
				descriptor,
				frameKind: 'worktree.fileDescriptor',
				generation: 1,
				kind: 'delta',
				sequence: 2,
				streamId: 'worktree-file:fixture-pane',
			});
			if (frame.frameKind !== 'worktree.fileDescriptor') {
				throw new Error('Fixture produced the wrong frame kind.');
			}
			return frame;
		},
		loadWorktreeFileSurface: async () => ({
			frames: [
				worktreeFileProtocolFrameSchema.parse({
					frameKind: 'worktree.snapshot',
					generation: 1,
					kind: 'snapshot',
					metadataLineage: { lane: 'foreground', loadedBy: 'startup_window' },
					sequence: 0,
					source: sourceIdentity,
					streamId: 'worktree-file:fixture-pane',
					treeRows: [
						{
							changeStatus: 'modified',
							depth: 0,
							fileId: descriptor.fileId,
							isDirectory: false,
							lineCount: exactLogicalLineCount(sourceBytes),
							name: 'complete-file.txt',
							parentPath: null,
							path: filePath,
							rowId: 'fixture-row-complete-file',
							sizeBytes: sourceBytes.byteLength,
						},
					],
					treeSizeFacts: { extentKind: 'exactPathCount', pathCount: 1, rowHeightPixels: 24 },
				}),
			],
			provenance: {
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'fixture-root-token',
			},
			source: sourceIdentity,
			treeSizeFacts: { extentKind: 'exactPathCount', pathCount: 1, rowHeightPixels: 24 },
		}),
	};
}

function fakeDescriptor(sourceBytes: Uint8Array): WorktreeFileDescriptor {
	const expectedSha256 = createHash('sha256').update(sourceBytes).digest('hex');
	const descriptorId = 'fixture-complete-file-descriptor';
	const attachedIdentity = {
		cursor: sourceIdentity.sourceCursor,
		generation: sourceIdentity.subscriptionGeneration,
		paneId: 'fixture-pane',
		protocol: 'worktree-file' as const,
		sourceId: sourceIdentity.sourceId,
		streamId: 'worktree-file:fixture-pane',
	};
	return {
		contentDescriptor: {
			descriptor: {
				content: {
					encoding: 'utf-8',
					expectedBytes: sourceBytes.byteLength,
					maxBytes: Math.max(1, sourceBytes.byteLength),
					mediaType: 'text/plain',
				},
				descriptorId,
				identity: attachedIdentity,
				protocol: 'worktree-file',
				resourceKind: 'worktree.fileContent',
				resourceUrl:
					'agentstudio://resource/worktree-file/worktree.fileContent/fixture-complete-file-descriptor',
			},
			ref: {
				descriptorId,
				expectedIdentity: attachedIdentity,
				expectedProtocol: 'worktree-file',
				expectedResourceKind: 'worktree.fileContent',
			},
		},
		contentHandle: descriptorId,
		contentHash: `sha256:${expectedSha256}`,
		fileExtension: 'txt',
		fileId: 'fixture-complete-file-id',
		isBinary: false,
		language: 'text',
		lineCount: exactLogicalLineCount(sourceBytes),
		modifiedAtUnixMilliseconds: 1,
		path: filePath,
		sizeBytes: sourceBytes.byteLength,
		sourceIdentity,
		unavailableReason: null,
		virtualizedExtentKind: 'exactLineCount',
	};
}

function exactLogicalLineCount(sourceBytes: Uint8Array): number {
	let lineFeedCount = 0;
	for (const byte of sourceBytes) {
		if (byte === 0x0a) lineFeedCount += 1;
	}
	return lineFeedCount + (sourceBytes.byteLength > 0 && sourceBytes.at(-1) !== 0x0a ? 1 : 0);
}
