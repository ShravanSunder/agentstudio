import { expect, test } from 'vitest';

import {
	makeDeferred,
	makeFileDescriptor,
	makeFileDescriptorFrame,
	makeInvalidationFrame,
	makeResetFrame,
	makeSnapshotFrame,
	makeSourceIdentity,
} from './worktree-file-surface-runtime.integration.test-support.js';
import {
	createWorktreeFileSurfaceRuntime,
	makeWorktreeFileSurfaceRuntimeFetchedResource,
} from './worktree-file-surface-runtime.js';

export function registerWorktreeFileSurfaceRuntimeResetTests(): void {
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
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
					return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
				}
				latestFetchCount += 1;
				if (latestFetchCount === 1) {
					throw new Error('transient refresh failure');
				}
				return makeWorktreeFileSurfaceRuntimeFetchedResource('file-content-2:body');
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
			descriptorId: 'file-content-2',
		});
		if (retryRefreshResult.ok) {
			expect(retryRefreshResult.content.readText()).toBe('file-content-2:body');
		}
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource('must-not-fetch');
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource('must-not-fetch');
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
			fetchResource: async ({ descriptor }) =>
				makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`),
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
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
			descriptorId: 'file-content-2',
		});
		if (refreshResult.ok) {
			expect(refreshResult.content.readText()).toBe('file-content-2:body');
		}
		expect(fetchedDescriptorIds).toEqual(['file-content-1', 'file-content-2']);
		expect(runtime.getState().openFileSessionsById['session-1']).toMatchObject({
			status: 'fresh',
			descriptorRef: replacementDescriptor.contentDescriptor.ref,
		});
	});

	test('replacement source snapshots keep same-path open sessions refreshable', async () => {
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(firstDescriptor));
		await runtime.openFile({
			descriptor: firstDescriptor,
			openFileSessionId: 'session-1',
		});

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
			descriptorId: 'file-content-2',
		});
		if (refreshResult.ok) {
			expect(refreshResult.content.readText()).toBe('file-content-2:body');
		}
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
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
			descriptorId: 'file-content-2',
		});
		if (refreshResult.ok) {
			expect(refreshResult.content.readText()).toBe('file-content-2:body');
		}
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
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
			descriptorId: 'file-content-2',
		});
		if (openSecondResult.ok) {
			expect(openSecondResult.content.readText()).toBe('file-content-2:body');
		}
		expect(fetchedDescriptorIds).toEqual(['file-content-1', 'file-content-2']);
	});
}
