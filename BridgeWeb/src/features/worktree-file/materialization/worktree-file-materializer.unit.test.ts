import { describe, expect, test } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../../core/models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../../../core/resources/bridge-resource-registry.js';
import { createBridgeResourceDescriptorRegistry } from '../../../core/resources/bridge-resource-registry.js';
import type {
	WorktreeFileDescriptorFrame,
	WorktreeFileInvalidatedFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeSnapshotFrame,
	WorktreeResetFrame,
} from '../models/worktree-file-protocol-models.js';
import { applyWorktreeFileProtocolFrame } from './worktree-file-materializer.js';

describe('worktree file materializer', () => {
	test('applies snapshot metadata without registering tree or status resources', () => {
		const registry = createWorktreeFileRegistry();
		const frame = makeSnapshotFrame();

		const result = applyWorktreeFileProtocolFrame({
			frame,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'snapshot',
				source: frame.source,
				treeSizeFacts: frame.treeSizeFacts,
			},
		});
		expect(JSON.stringify(result)).not.toContain('treeDescriptorRef');
		expect(JSON.stringify(result)).not.toContain('statusDescriptorRef');
	});

	test('registers file descriptor content authority without storing body content', () => {
		const registry = createWorktreeFileRegistry();
		const frame = makeFileDescriptorFrame();

		const result = applyWorktreeFileProtocolFrame({
			frame,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'fileDescriptor',
				descriptor: frame.descriptor,
				contentDescriptorRef: frame.descriptor.contentDescriptor.ref,
			},
		});
		expect(registry.lookup(frame.descriptor.contentDescriptor.ref)?.descriptorId).toBe(
			'file-content-1',
		);
		expect(JSON.stringify(result)).not.toContain('struct View');
	});

	test('materializes invalidation frames as stale metadata without registering descriptors first', () => {
		const registry = createWorktreeFileRegistry();
		const frame = makeInvalidationFrame();

		const result = applyWorktreeFileProtocolFrame({
			frame,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'fileInvalidated',
				invalidation: frame.invalidation,
			},
		});
		expect(
			registry.lookup(
				frame.invalidation.latestDescriptor?.contentDescriptor.ref ??
					makeFileContentDescriptor().ref,
			),
		).toBeNull();
	});

	test('resets Worktree/File source identity and revokes stale descriptors', () => {
		const registry = createWorktreeFileRegistry();
		const snapshotFrame = makeSnapshotFrame();
		applyWorktreeFileProtocolFrame({
			frame: snapshotFrame,
			paneId: 'pane-1',
			registry,
		});
		const resetFrame: WorktreeResetFrame = {
			kind: 'reset',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 1,
			frameKind: 'worktree.reset',
			reason: 'authorityChanged',
			source: snapshotFrame.source,
		};

		const result = applyWorktreeFileProtocolFrame({
			frame: resetFrame,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'reset',
				reason: 'authorityChanged',
				source: snapshotFrame.source,
			},
		});
		expect(JSON.stringify(result)).not.toContain('treeDescriptorRef');
	});
});

function createWorktreeFileRegistry(): BridgeResourceDescriptorRegistry {
	return createBridgeResourceDescriptorRegistry({
		allowedResourceKindsByProtocol: {
			'worktree-file': new Set(['worktree.fileContent', 'worktree.fileRange']),
		},
	});
}

function makeSnapshotFrame(): WorktreeSnapshotFrame {
	return {
		kind: 'snapshot',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 0,
		frameKind: 'worktree.snapshot',
		source: makeSourceIdentity(),
		treeRows: [
			{
				rowId: 'row-1',
				path: 'Sources/App/View.swift',
				name: 'View.swift',
				parentPath: 'Sources/App',
				depth: 2,
				isDirectory: false,
				fileId: 'file-1',
			},
		],
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: 12_000,
			windowStartIndex: 0,
			windowRowCount: 50,
			rowHeightPixels: 24,
		},
		statusPatch: {
			staged: 0,
			unstaged: 1,
			untracked: 0,
		},
	};
}

function makeFileDescriptorFrame(): WorktreeFileDescriptorFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 1,
		frameKind: 'worktree.fileDescriptor',
		descriptor: {
			path: 'Sources/App/View.swift',
			fileId: 'file-1',
			contentHandle: 'handle-1',
			contentDescriptor: makeFileContentDescriptor(),
			sourceIdentity: makeSourceIdentity(),
			sizeBytes: 64,
			virtualizedExtentKind: 'exactLineCount',
			lineCount: 4,
			isBinary: false,
			language: 'swift',
			fileExtension: 'swift',
		},
	};
}

function makeInvalidationFrame(): WorktreeFileInvalidatedFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 2,
		frameKind: 'worktree.fileInvalidated',
		invalidation: {
			path: 'Sources/App/View.swift',
			fileId: 'file-1',
			reason: 'filesystemEvent',
			contentHandleIds: ['handle-2'],
			latestDescriptor: {
				...makeFileDescriptorFrame().descriptor,
				contentHandle: 'handle-2',
				contentDescriptor: makeAttachedDescriptor({
					descriptorId: 'file-content-2',
					resourceKind: 'worktree.fileContent',
				}),
			},
		},
	};
}

function makeSourceIdentity(): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-1',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		subscriptionGeneration: 1,
		sourceCursor: 'cursor-1',
	};
}

function makeFileContentDescriptor(): BridgeAttachedResourceDescriptor {
	return makeAttachedDescriptor({
		descriptorId: 'file-content-1',
		resourceKind: 'worktree.fileContent',
	});
}

interface MakeAttachedDescriptorProps {
	readonly descriptorId: string;
	readonly resourceKind: string;
}

function makeAttachedDescriptor(
	props: MakeAttachedDescriptorProps,
): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'source-1',
		generation: 1,
		streamId: 'worktree-file:pane-1',
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'worktree-file',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/worktree-file/${props.resourceKind}/${props.descriptorId}?generation=1`,
		identity,
		content: {
			mediaType: 'application/json',
			encoding: 'utf-8',
			expectedBytes: 128,
			maxBytes: 1024,
		},
	} satisfies BridgeResourceDescriptor;
	return {
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: identity,
		},
		descriptor,
	};
}
