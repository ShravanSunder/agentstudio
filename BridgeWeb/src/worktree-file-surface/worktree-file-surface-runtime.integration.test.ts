import { describe, expect, test } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorFrame,
	WorktreeFileInvalidatedFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeResetFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { createWorktreeFileSurfaceRuntime } from './worktree-file-surface-runtime.js';

describe('worktree file surface runtime', () => {
	test('loads selected file content through descriptor-backed demand without storing bodies in state', async () => {
		const descriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const fetches: string[] = [];
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ resourceUrl }) => {
				fetches.push(resourceUrl);
				return 'struct View {}';
			},
		});

		expect(runtime.applyFrame(makeFileDescriptorFrame(descriptor))).toEqual({
			ok: true,
			deltaKind: 'fileDescriptor',
		});
		const loadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-1',
		});

		expect(loadResult).toEqual({
			ok: true,
			body: 'struct View {}',
			descriptorId: 'file-content-1',
		});
		expect(fetches).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
		]);
		expect(JSON.stringify(runtime.getState())).not.toContain('struct View');
		expect(runtime.getBodyRegistrySnapshot()).toEqual({ entryCount: 1, totalBytes: 14 });
	});

	test('marks open files stale without auto-fetching and refreshes only the latest descriptor', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const latestDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-2',
			contentHandle: 'handle-2',
		});
		const fetchedDescriptorIds: string[] = [];
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ descriptor }) => {
				fetchedDescriptorIds.push(descriptor.descriptorId);
				return `${descriptor.descriptorId}:body`;
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(firstDescriptor));
		await runtime.openFile({
			descriptor: firstDescriptor,
			openFileSessionId: 'session-1',
		});

		const invalidationResult = runtime.applyFrame(
			makeInvalidationFrame({ firstDescriptor, latestDescriptor }),
		);

		expect(invalidationResult).toEqual({
			ok: true,
			deltaKind: 'fileInvalidated',
			autoDemandCount: 0,
		});
		expect(fetchedDescriptorIds).toEqual(['file-content-1']);
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'stale',
			latestDescriptorRef: latestDescriptor.contentDescriptor.ref,
		});

		const refreshResult = await runtime.refreshOpenFile({ openFileSessionId: 'session-1' });

		expect(refreshResult).toEqual({
			ok: true,
			body: 'file-content-2:body',
			descriptorId: 'file-content-2',
		});
		expect(fetchedDescriptorIds).toEqual(['file-content-1', 'file-content-2']);
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'fresh',
			descriptorRef: latestDescriptor.contentDescriptor.ref,
		});
	});

	test('keeps failed explicit refresh sessions stale and retryable', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const latestDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-2',
			contentHandle: 'handle-2',
		});
		let latestFetchCount = 0;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ descriptor }) => {
				if (descriptor.descriptorId !== 'file-content-2') {
					return `${descriptor.descriptorId}:body`;
				}
				latestFetchCount += 1;
				if (latestFetchCount === 1) {
					throw new Error('transient refresh failure');
				}
				return 'file-content-2:body';
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(firstDescriptor));
		await runtime.openFile({
			descriptor: firstDescriptor,
			openFileSessionId: 'session-1',
		});
		runtime.applyFrame(makeInvalidationFrame({ firstDescriptor, latestDescriptor }));

		const failedRefreshResult = await runtime.refreshOpenFile({ openFileSessionId: 'session-1' });

		expect(failedRefreshResult).toEqual({ ok: false, reason: 'load_failed' });
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'stale',
			latestDescriptorRef: latestDescriptor.contentDescriptor.ref,
		});

		const retryRefreshResult = await runtime.refreshOpenFile({ openFileSessionId: 'session-1' });

		expect(retryRefreshResult).toEqual({
			ok: true,
			body: 'file-content-2:body',
			descriptorId: 'file-content-2',
		});
		expect(latestFetchCount).toBe(2);
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'fresh',
			descriptorRef: latestDescriptor.contentDescriptor.ref,
		});
	});

	test('rejects a refresh completion superseded by a newer invalidation', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const refreshDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-2',
			contentHandle: 'handle-2',
		});
		const supersedingDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-3',
			contentHandle: 'handle-3',
		});
		const refreshGate = makeDeferred<void>();
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ descriptor }) => {
				if (descriptor.descriptorId === 'file-content-2') {
					await refreshGate.promise;
				}
				return `${descriptor.descriptorId}:body`;
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(firstDescriptor));
		await runtime.openFile({
			descriptor: firstDescriptor,
			openFileSessionId: 'session-1',
		});
		runtime.applyFrame(
			makeInvalidationFrame({ firstDescriptor, latestDescriptor: refreshDescriptor }),
		);

		const refreshResultPromise = runtime.refreshOpenFile({ openFileSessionId: 'session-1' });
		runtime.applyFrame(
			makeInvalidationFrame({ firstDescriptor, latestDescriptor: supersedingDescriptor }),
		);
		refreshGate.resolve();
		const refreshResult = await refreshResultPromise;

		expect(refreshResult).toEqual({ ok: false, reason: 'stale_completion' });
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'stale',
			descriptorRef: refreshDescriptor.contentDescriptor.ref,
			latestDescriptorRef: supersedingDescriptor.contentDescriptor.ref,
		});
	});

	test('fails closed when file selection references a descriptor that was never materialized', async () => {
		const descriptor = makeFileDescriptor({ descriptorId: 'forged-content' });
		let fetchCount = 0;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async () => {
				fetchCount += 1;
				return 'must-not-fetch';
			},
		});

		const loadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-1',
		});

		expect(loadResult).toEqual({ ok: false, reason: 'descriptor_missing' });
		expect(fetchCount).toBe(0);
	});

	test('keeps binary unavailable descriptors metadata-only without fetching bodies', async () => {
		const descriptor = makeFileDescriptor({
			descriptorId: 'binary-content',
			isBinary: true,
			virtualizedExtentKind: 'unavailable',
		});
		let fetchCount = 0;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async () => {
				fetchCount += 1;
				return 'must-not-fetch';
			},
		});

		expect(runtime.applyFrame(makeFileDescriptorFrame(descriptor))).toEqual({
			ok: true,
			deltaKind: 'fileDescriptor',
		});
		const loadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-1',
		});

		expect(loadResult).toEqual({ ok: false, reason: 'content_unavailable' });
		expect(fetchCount).toBe(0);
		expect(runtime.getBodyRegistrySnapshot()).toEqual({ entryCount: 0, totalBytes: 0 });
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'failed',
			descriptorRef: descriptor.contentDescriptor.ref,
		});
	});

	test('source reset cancels queued source work and rejects stale refresh commits', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const latestDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-2',
			contentHandle: 'handle-2',
		});
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ descriptor }) => `${descriptor.descriptorId}:body`,
		});
		runtime.applyFrame(makeFileDescriptorFrame(firstDescriptor));
		await runtime.openFile({
			descriptor: firstDescriptor,
			openFileSessionId: 'session-1',
		});
		runtime.applyFrame(makeInvalidationFrame({ firstDescriptor, latestDescriptor }));

		expect(runtime.applyFrame(makeResetFrame())).toEqual({
			ok: true,
			deltaKind: 'reset',
			cancelledDemandCount: 0,
		});
		const refreshResult = await runtime.refreshOpenFile({ openFileSessionId: 'session-1' });

		expect(refreshResult).toEqual({ ok: false, reason: 'source_reset' });
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'stale',
			staleReason: 'sourceReset',
		});
	});
});

function makeFileDescriptorFrame(descriptor: WorktreeFileDescriptor): WorktreeFileDescriptorFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 1,
		frameKind: 'worktree.fileDescriptor',
		descriptor,
	};
}

function makeInvalidationFrame(props: {
	readonly firstDescriptor: WorktreeFileDescriptor;
	readonly latestDescriptor: WorktreeFileDescriptor;
}): WorktreeFileInvalidatedFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 2,
		frameKind: 'worktree.fileInvalidated',
		invalidation: {
			path: props.firstDescriptor.path,
			fileId: props.firstDescriptor.fileId,
			reason: 'filesystemEvent',
			latestDescriptor: props.latestDescriptor,
		},
	};
}

function makeResetFrame(): WorktreeResetFrame {
	return {
		kind: 'reset',
		streamId: 'worktree-file:pane-1',
		generation: 2,
		sequence: 3,
		frameKind: 'worktree.reset',
		reason: 'sourceChanged',
		source: makeSourceIdentity(),
	};
}

function makeDeferred<TValue>(): {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue | PromiseLike<TValue>) => void;
	readonly reject: (reason?: unknown) => void;
} {
	let resolvePromise: ((value: TValue | PromiseLike<TValue>) => void) | undefined;
	let rejectPromise: ((reason?: unknown) => void) | undefined;
	const promise = new Promise<TValue>((resolve, reject) => {
		resolvePromise = resolve;
		rejectPromise = reject;
	});
	if (resolvePromise === undefined || rejectPromise === undefined) {
		throw new Error('Expected deferred callbacks to initialize synchronously');
	}
	return {
		promise,
		resolve: resolvePromise,
		reject: rejectPromise,
	};
}

interface MakeFileDescriptorProps {
	readonly descriptorId: string;
	readonly contentHandle?: string;
	readonly isBinary?: boolean;
	readonly virtualizedExtentKind?: WorktreeFileDescriptor['virtualizedExtentKind'];
}

function makeFileDescriptor(props: MakeFileDescriptorProps): WorktreeFileDescriptor {
	const virtualizedExtentKind = props.virtualizedExtentKind ?? 'exactLineCount';
	return {
		path: 'Sources/App/View.swift',
		fileId: 'file-1',
		contentHandle: props.contentHandle ?? 'handle-1',
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: props.descriptorId,
			resourceKind: 'worktree.fileContent',
		}),
		sourceIdentity: makeSourceIdentity(),
		sizeBytes: 64,
		virtualizedExtentKind,
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: 4 } : {}),
		isBinary: props.isBinary ?? false,
		language: 'swift',
		fileExtension: 'swift',
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
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: 64,
			maxBytes: 1024,
		},
	} satisfies BridgeResourceDescriptor;
	return bridgeAttachedResourceDescriptorSchema.parse({
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: descriptor.identity,
		},
		descriptor,
	});
}
