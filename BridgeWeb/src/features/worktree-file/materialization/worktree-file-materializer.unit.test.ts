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
	test('registers snapshot tree and status descriptors before publishing source facts', () => {
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
				treeDescriptorRef: frame.treeDescriptor.ref,
				statusDescriptorRef: frame.statusDescriptor?.ref,
				treeSizeFacts: frame.treeSizeFacts,
			},
		});
		expect(registry.lookup(frame.treeDescriptor.ref)?.descriptorId).toBe('tree-window-1');
		expect(
			registry.lookup(frame.statusDescriptor?.ref ?? frame.treeDescriptor.ref)?.descriptorId,
		).toBe('status-1');
	});

	test('rolls back snapshot descriptors when a later descriptor is rejected', () => {
		const registry = createWorktreeFileRegistry();
		const frame = makeSnapshotFrame();
		const statusDescriptor = frame.statusDescriptor;
		if (statusDescriptor === undefined) {
			throw new Error('Expected snapshot test fixture to include status descriptor.');
		}
		const rejectedStatusDescriptor: BridgeAttachedResourceDescriptor = {
			...statusDescriptor,
			ref: {
				...statusDescriptor.ref,
				expectedResourceKind: 'worktree.treeWindow',
			},
		};

		const result = applyWorktreeFileProtocolFrame({
			frame: {
				...frame,
				statusDescriptor: rejectedStatusDescriptor,
			},
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({ ok: false, reason: 'descriptor_rejected' });
		expect(registry.lookup(frame.treeDescriptor.ref)).toBeNull();
		expect(registry.lookup(rejectedStatusDescriptor.ref)).toBeNull();
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
		expect(registry.lookup(snapshotFrame.treeDescriptor.ref)).toBeNull();
	});
});

function createWorktreeFileRegistry(): BridgeResourceDescriptorRegistry {
	return createBridgeResourceDescriptorRegistry({
		allowedResourceKindsByProtocol: {
			'worktree-file': new Set(['worktree.treeWindow', 'worktree.status', 'worktree.fileContent']),
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
		treeDescriptor: makeAttachedDescriptor({
			descriptorId: 'tree-window-1',
			resourceKind: 'worktree.treeWindow',
		}),
		treeSizeFacts: {
			pathCount: 12_000,
			windowStartIndex: 0,
			windowRowCount: 50,
			rowHeightPixels: 24,
		},
		statusDescriptor: makeAttachedDescriptor({
			descriptorId: 'status-1',
			resourceKind: 'worktree.status',
		}),
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
