import { describe, expect, test, vi } from 'vitest';

import type { BridgeResourceDescriptor } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptorRequest,
	WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	makeWorktreeFileSurfaceRuntimeFetchedResource,
	type WorktreeFileSurfaceRuntimeFetchResourceProps,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { createBridgeFileViewerWorktreeFileSurfaceTransport } from './bridge-file-viewer-worktree-file-surface-transport-adapter.js';

describe('Bridge file viewer worktree file surface transport adapter', () => {
	test('forwards native and dev worktree-file backend methods through the typed transport boundary', async () => {
		const fetchedResource = makeWorktreeFileSurfaceRuntimeFetchedResource('adapter-content');
		const initialSurface = { frames: [makeSnapshotFrame()] };
		const fetchWorktreeFileResource = vi.fn(async () => fetchedResource);
		const loadWorktreeFileSurface = vi.fn(async () => initialSurface);
		const requestWorktreeFileDescriptor = vi.fn(async (): Promise<void> => {});
		const unsubscribeFrames = vi.fn();
		const subscribeWorktreeFileFrames = vi.fn(() => unsubscribeFrames);
		const unregisterResetCallback = vi.fn();
		const registerWorktreeFileStreamResetRequiredCallback = vi.fn(() => unregisterResetCallback);
		const transport = createBridgeFileViewerWorktreeFileSurfaceTransport({
			fetchWorktreeFileResource,
			loadWorktreeFileSurface,
			registerWorktreeFileStreamResetRequiredCallback,
			requestWorktreeFileDescriptor,
			subscribeWorktreeFileFrames,
		});
		const fetchRequest = makeFetchRequest();
		const descriptorRequest = makeDescriptorRequest();
		const frameSubscriber = vi.fn();
		const resetCallback = vi.fn();

		await expect(transport.fetchResource?.(fetchRequest)).resolves.toBe(fetchedResource);
		await expect(transport.loadInitialSurface?.()).resolves.toBe(initialSurface);
		await expect(transport.requestFileDescriptor?.(descriptorRequest)).resolves.toBeUndefined();
		expect(transport.subscribeFrames?.(frameSubscriber)).toBe(unsubscribeFrames);
		expect(transport.registerSurfaceStreamResetRequiredCallback?.(resetCallback)).toBe(
			unregisterResetCallback,
		);

		expect(fetchWorktreeFileResource).toHaveBeenCalledWith(fetchRequest);
		expect(loadWorktreeFileSurface).toHaveBeenCalledTimes(1);
		expect(requestWorktreeFileDescriptor).toHaveBeenCalledWith(descriptorRequest);
		expect(subscribeWorktreeFileFrames).toHaveBeenCalledWith(frameSubscriber);
		expect(registerWorktreeFileStreamResetRequiredCallback).toHaveBeenCalledWith(resetCallback);
	});
});

function makeFetchRequest(): WorktreeFileSurfaceRuntimeFetchResourceProps {
	return {
		descriptor: makeResourceDescriptor(),
		resourceUrl: 'agentstudio://content/worktree-file/descriptor-1',
		signal: new AbortController().signal,
	};
}

function makeResourceDescriptor(): BridgeResourceDescriptor {
	return {
		descriptorId: 'descriptor-1',
		protocol: 'worktree-file',
		resourceKind: 'worktree.fileContent',
		resourceUrl: 'agentstudio://content/worktree-file/descriptor-1',
		identity: {
			paneId: 'pane-1',
			protocol: 'worktree-file',
			sourceId: 'source-1',
			generation: 1,
			streamId: 'worktree-file:pane-1',
			cursor: 'cursor-1',
		},
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			maxBytes: 1024,
		},
	};
}

function makeDescriptorRequest(): WorktreeFileDescriptorRequest {
	return {
		sourceIdentity: {
			sourceId: 'source-1',
			repoId: 'repo-1',
			worktreeId: 'worktree-1',
			subscriptionGeneration: 1,
			sourceCursor: 'cursor-1',
			rootRevisionToken: 'root-1',
		},
		rowId: 'row-src-index',
		path: 'src/index.ts',
		fileId: 'file-src-index',
		lane: 'foreground',
	};
}

function makeSnapshotFrame(): WorktreeFileProtocolFrame {
	return {
		kind: 'snapshot',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 0,
		frameKind: 'worktree.snapshot',
		source: {
			sourceId: 'source-1',
			repoId: 'repo-1',
			worktreeId: 'worktree-1',
			subscriptionGeneration: 1,
			sourceCursor: 'cursor-1',
			rootRevisionToken: 'root-1',
		},
		metadataLineage: {
			loadedBy: 'startup_window',
			lane: 'foreground',
		},
		treeRows: [],
	};
}
