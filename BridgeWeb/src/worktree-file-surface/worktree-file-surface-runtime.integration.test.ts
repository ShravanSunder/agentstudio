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
	WorktreeSnapshotFrame,
	WorktreeResetFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { createWorktreeFileSurfaceRuntime } from './worktree-file-surface-runtime.js';

describe('worktree file surface runtime', () => {
	test('loads selected file content through descriptor-backed demand without storing bodies in state', async () => {
		const descriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const fetches: string[] = [];
		let nowMilliseconds = 100;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			now: () => nowMilliseconds,
			fetchResource: async ({ resourceUrl }) => {
				fetches.push(resourceUrl);
				nowMilliseconds = 128;
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

		expect(loadResult).toMatchObject({
			ok: true,
			body: 'struct View {}',
			descriptorId: 'file-content-1',
		});
		expect(fetches).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1&cursor=cursor-1',
		]);
		expect(JSON.stringify(runtime.getState())).not.toContain('struct View');
		expect(runtime.getBodyRegistrySnapshot()).toEqual({ entryCount: 1, totalBytes: 14 });
	});

	test('reports selected file load disposition and queue pressure for cold and cached opens', async () => {
		const descriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const fetches: string[] = [];
		let nowMilliseconds = 200;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			now: () => nowMilliseconds,
			fetchResource: async ({ resourceUrl }) => {
				fetches.push(resourceUrl);
				nowMilliseconds += 9;
				return `body from ${resourceUrl}`;
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		const coldLoadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-1',
		});
		nowMilliseconds += 7;
		const cachedLoadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-1',
		});

		expect(coldLoadResult).toMatchObject({
			ok: true,
			loadTelemetry: {
				disposition: 'cold-loaded',
				durationMilliseconds: 9,
				estimatedBytes: 64,
				executorInFlightBytesAfter: 0,
				executorInFlightBytesBefore: 0,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'foreground',
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			},
		});
		expect(cachedLoadResult).toMatchObject({
			ok: true,
			loadTelemetry: {
				disposition: 'cache-hit',
				durationMilliseconds: 0,
				estimatedBytes: 64,
				lane: 'foreground',
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			},
		});
		expect(fetches).toHaveLength(1);
	});

	test('reports scheduler byte pressure before fetching oversized selected files', async () => {
		const descriptor = makeFileDescriptor({
			descriptorId: 'oversized-content',
			expectedBytes: 9 * 1024 * 1024,
			maxBytes: 10 * 1024 * 1024,
		});
		let fetchCount = 0;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async () => {
				fetchCount += 1;
				return 'must-not-fetch';
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		const loadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-1',
		});

		expect(loadResult).toEqual({ ok: false, reason: 'byte_budget_exceeded' });
		expect(fetchCount).toBe(0);
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'failed',
			descriptorRef: descriptor.contentDescriptor.ref,
		});
	});

	test('preloads visible file demand through scheduler without opening file sessions', async () => {
		const firstDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-1',
			fileId: 'file-1',
			path: 'Sources/App/First.swift',
		});
		const secondDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-2',
			contentHandle: 'handle-2',
			fileId: 'file-2',
			path: 'Sources/App/Second.swift',
		});
		const fetchedDescriptorIds: string[] = [];
		let nowMilliseconds = 400;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			now: () => nowMilliseconds,
			fetchResource: async ({ descriptor }) => {
				fetchedDescriptorIds.push(descriptor.descriptorId);
				nowMilliseconds += 6;
				return `${descriptor.descriptorId}:preloaded`;
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(firstDescriptor));
		runtime.applyFrame(makeFileDescriptorFrame(secondDescriptor));

		const dispatchResult = await runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: [
					firstDescriptor.contentDescriptor.ref,
					secondDescriptor.contentDescriptor.ref,
				],
			},
		]);

		expect(dispatchResult).toMatchObject({
			stimulusCount: 1,
			intentCount: 2,
			enqueueAcceptedCount: 2,
			enqueueRejectedCount: 0,
			loadedCount: 2,
			failedCount: 0,
			schedulerQueuedIntentCountAfter: 0,
			executorInFlightCountAfter: 0,
			executorQueuedLoadCountAfter: 0,
			loadResults: [
				{
					ok: true,
					descriptorId: 'file-content-1',
					loadTelemetry: {
						disposition: 'visible-preloaded',
						durationMilliseconds: expect.any(Number),
						estimatedBytes: 64,
						lane: 'visible',
					},
				},
				{
					ok: true,
					descriptorId: 'file-content-2',
					loadTelemetry: {
						disposition: 'visible-preloaded',
						durationMilliseconds: expect.any(Number),
						estimatedBytes: 64,
						lane: 'visible',
					},
				},
			],
		});
		expect(
			dispatchResult.loadResults.every((loadResult): boolean => {
				if (!loadResult.ok) {
					return false;
				}
				return loadResult.loadTelemetry.durationMilliseconds > 0;
			}),
		).toBe(true);
		expect(fetchedDescriptorIds).toEqual(['file-content-1', 'file-content-2']);
		expect(runtime.getState().openFileSessionsById).toEqual({});
		expect(runtime.getBodyRegistrySnapshot()).toEqual({
			entryCount: 2,
			totalBytes: 'file-content-1:preloaded'.length + 'file-content-2:preloaded'.length,
		});
	});

	test('reports descriptor and lane when visible preload demand is rejected by byte pressure', async () => {
		const descriptor = makeFileDescriptor({
			descriptorId: 'oversized-visible-content',
			expectedBytes: 9 * 1024 * 1024,
			maxBytes: 10 * 1024 * 1024,
		});
		let fetchCount = 0;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async () => {
				fetchCount += 1;
				return 'must-not-fetch';
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		const dispatchResult = await runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: [descriptor.contentDescriptor.ref],
			},
		]);

		expect(dispatchResult).toMatchObject({
			stimulusCount: 1,
			intentCount: 1,
			enqueueAcceptedCount: 0,
			enqueueRejectedCount: 1,
			loadedCount: 0,
			failedCount: 1,
			loadResults: [
				{
					ok: false,
					descriptorId: 'oversized-visible-content',
					lane: 'visible',
					reason: 'byte_budget_exceeded',
				},
			],
			schedulerQueuedEstimatedBytesAfter: 0,
			schedulerQueuedIntentCountAfter: 0,
		});
		expect(fetchCount).toBe(0);
	});

	test('marks open files stale without auto-fetching and refreshes only the latest descriptor', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const latestDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-2',
			contentHandle: 'handle-2',
		});
		const fetchedDescriptorIds: string[] = [];
		let nowMilliseconds = 300;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			now: () => nowMilliseconds,
			fetchResource: async ({ descriptor }) => {
				fetchedDescriptorIds.push(descriptor.descriptorId);
				nowMilliseconds += descriptor.descriptorId === 'file-content-2' ? 17 : 5;
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

		expect(refreshResult).toMatchObject({
			ok: true,
			body: 'file-content-2:body',
			descriptorId: 'file-content-2',
			loadTelemetry: {
				disposition: 'refreshed',
				durationMilliseconds: 17,
				estimatedBytes: 64,
				executorInFlightBytesAfter: 0,
				executorInFlightBytesBefore: 0,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'foreground',
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			},
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

		expect(retryRefreshResult).toMatchObject({
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

	test('source reset replacement descriptors keep open sessions refreshable', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const replacementDescriptor = makeFileDescriptor({
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

		runtime.applyFrame(makeResetFrame());
		runtime.applyFrame(makeFileDescriptorFrame(replacementDescriptor));

		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'stale',
			staleReason: 'sourceReset',
			latestDescriptorRef: replacementDescriptor.contentDescriptor.ref,
		});

		const refreshResult = await runtime.refreshOpenFile({ openFileSessionId: 'session-1' });

		expect(refreshResult).toMatchObject({
			ok: true,
			body: 'file-content-2:body',
			descriptorId: 'file-content-2',
		});
		expect(fetchedDescriptorIds).toEqual(['file-content-1', 'file-content-2']);
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'fresh',
			descriptorRef: replacementDescriptor.contentDescriptor.ref,
		});
	});

	test('source reset replacement descriptors do not unblock stale descriptors for other files', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const staleLatestDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-2',
			contentHandle: 'handle-2',
		});
		const unrelatedReplacementDescriptor = makeFileDescriptor({
			descriptorId: 'unrelated-content-1',
			contentHandle: 'unrelated-handle-1',
			fileId: 'file-2',
			path: 'Sources/App/OtherView.swift',
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
		runtime.applyFrame(
			makeInvalidationFrame({ firstDescriptor, latestDescriptor: staleLatestDescriptor }),
		);

		runtime.applyFrame(makeResetFrame());
		runtime.applyFrame(makeFileDescriptorFrame(unrelatedReplacementDescriptor));
		const refreshResult = await runtime.refreshOpenFile({ openFileSessionId: 'session-1' });

		expect(refreshResult).toEqual({ ok: false, reason: 'source_reset' });
		expect(fetchedDescriptorIds).toEqual(['file-content-1']);
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'stale',
			staleReason: 'sourceReset',
			latestDescriptorRef: staleLatestDescriptor.contentDescriptor.ref,
		});
	});

	test('source-less reset blocks unanchored old-stream descriptors', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const oldStreamReplacementDescriptor = makeFileDescriptor({
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

		runtime.applyFrame(makeResetFrame({ source: null }));
		runtime.applyFrame(makeFileDescriptorFrame(oldStreamReplacementDescriptor));
		const refreshResult = await runtime.refreshOpenFile({ openFileSessionId: 'session-1' });

		expect(refreshResult).toEqual({ ok: false, reason: 'source_reset' });
		expect(fetchedDescriptorIds).toEqual(['file-content-1']);
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'stale',
			staleReason: 'sourceReset',
		});
		expect(
			runtime.getState().openFileSessionsById['session-1']?.latestDescriptorRef,
		).toBeUndefined();
	});

	test('source-less reset replacement descriptors require a post-reset snapshot anchor', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const replacementSource = makeSourceIdentity({
			sourceId: 'source-2',
			sourceCursor: 'cursor-2',
			subscriptionGeneration: 2,
		});
		const replacementDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-2',
			contentHandle: 'handle-2',
			sourceIdentity: replacementSource,
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

		runtime.applyFrame(makeResetFrame({ source: null }));
		runtime.applyFrame(makeSnapshotFrame(replacementSource));
		runtime.applyFrame(makeFileDescriptorFrame(replacementDescriptor));

		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'stale',
			staleReason: 'sourceReset',
			latestDescriptorRef: replacementDescriptor.contentDescriptor.ref,
		});

		const refreshResult = await runtime.refreshOpenFile({ openFileSessionId: 'session-1' });

		expect(refreshResult).toMatchObject({
			ok: true,
			body: 'file-content-2:body',
			descriptorId: 'file-content-2',
		});
		expect(fetchedDescriptorIds).toEqual(['file-content-1', 'file-content-2']);
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'fresh',
			descriptorRef: replacementDescriptor.contentDescriptor.ref,
		});
	});

	test('source-less reset anchored descriptors can open files that were not open during reset', async () => {
		const firstDescriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const replacementSource = makeSourceIdentity({
			sourceId: 'source-2',
			sourceCursor: 'cursor-2',
			subscriptionGeneration: 2,
		});
		const secondDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-2',
			contentHandle: 'handle-2',
			fileId: 'file-2',
			path: 'Sources/App/OtherView.swift',
			sourceIdentity: replacementSource,
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

		runtime.applyFrame(makeResetFrame({ source: null }));
		runtime.applyFrame(makeSnapshotFrame(replacementSource));
		runtime.applyFrame(makeFileDescriptorFrame(secondDescriptor));
		const openSecondResult = await runtime.openFile({
			descriptor: secondDescriptor,
			openFileSessionId: 'session-2',
		});

		expect(openSecondResult).toMatchObject({
			ok: true,
			body: 'file-content-2:body',
			descriptorId: 'file-content-2',
		});
		expect(fetchedDescriptorIds).toEqual(['file-content-1', 'file-content-2']);
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

function makeResetFrame(props?: {
	readonly source?: WorktreeFileSurfaceSourceIdentity | null;
}): WorktreeResetFrame {
	const source = props?.source === undefined ? makeSourceIdentity() : props.source;
	return {
		kind: 'reset',
		streamId: 'worktree-file:pane-1',
		generation: 2,
		sequence: 3,
		frameKind: 'worktree.reset',
		reason: 'sourceChanged',
		...(source === null ? {} : { source }),
	};
}

function makeSnapshotFrame(source: WorktreeFileSurfaceSourceIdentity): WorktreeSnapshotFrame {
	return {
		kind: 'snapshot',
		streamId: 'worktree-file:pane-1',
		generation: source.subscriptionGeneration,
		sequence: 4,
		frameKind: 'worktree.snapshot',
		source,
		treeDescriptor: makeAttachedDescriptor({
			descriptorId: `tree-window-${source.sourceCursor}`,
			resourceKind: 'worktree.treeWindow',
			sourceIdentity: source,
		}),
		treeSizeFacts: {
			pathCount: 1,
			rowHeightPixels: 24,
		},
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
	readonly expectedBytes?: number;
	readonly fileId?: string;
	readonly isBinary?: boolean;
	readonly maxBytes?: number;
	readonly path?: string;
	readonly sourceIdentity?: WorktreeFileSurfaceSourceIdentity;
	readonly virtualizedExtentKind?: WorktreeFileDescriptor['virtualizedExtentKind'];
}

function makeFileDescriptor(props: MakeFileDescriptorProps): WorktreeFileDescriptor {
	const virtualizedExtentKind = props.virtualizedExtentKind ?? 'exactLineCount';
	const sourceIdentity = props.sourceIdentity ?? makeSourceIdentity();
	return {
		path: props.path ?? 'Sources/App/View.swift',
		fileId: props.fileId ?? 'file-1',
		contentHandle: props.contentHandle ?? 'handle-1',
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: props.descriptorId,
			...(props.expectedBytes === undefined ? {} : { expectedBytes: props.expectedBytes }),
			...(props.maxBytes === undefined ? {} : { maxBytes: props.maxBytes }),
			resourceKind: 'worktree.fileContent',
			sourceIdentity,
		}),
		sourceIdentity,
		sizeBytes: 64,
		virtualizedExtentKind,
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: 4 } : {}),
		isBinary: props.isBinary ?? false,
		language: 'swift',
		fileExtension: 'swift',
	};
}

function makeSourceIdentity(
	props: Partial<WorktreeFileSurfaceSourceIdentity> = {},
): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: props.sourceId ?? 'source-1',
		repoId: props.repoId ?? 'repo-1',
		worktreeId: props.worktreeId ?? 'worktree-1',
		subscriptionGeneration: props.subscriptionGeneration ?? 1,
		sourceCursor: props.sourceCursor ?? 'cursor-1',
		...(props.rootRevisionToken === undefined
			? {}
			: { rootRevisionToken: props.rootRevisionToken }),
	};
}

interface MakeAttachedDescriptorProps {
	readonly descriptorId: string;
	readonly expectedBytes?: number;
	readonly maxBytes?: number;
	readonly resourceKind: string;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}

function makeAttachedDescriptor(
	props: MakeAttachedDescriptorProps,
): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: props.sourceIdentity.sourceId,
		generation: props.sourceIdentity.subscriptionGeneration,
		cursor: props.sourceIdentity.sourceCursor,
		streamId: 'worktree-file:pane-1',
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'worktree-file',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/worktree-file/${props.resourceKind}/${props.descriptorId}?generation=${props.sourceIdentity.subscriptionGeneration}&cursor=${encodeURIComponent(props.sourceIdentity.sourceCursor)}`,
		identity,
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: props.expectedBytes ?? 64,
			maxBytes: props.maxBytes ?? 1024,
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
