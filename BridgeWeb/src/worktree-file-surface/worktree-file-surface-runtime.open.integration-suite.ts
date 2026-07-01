import { expect, test } from 'vitest';

import {
	makeDeferred,
	makeFileDescriptor,
	makeFileDescriptorFrame,
} from './worktree-file-surface-runtime.integration.test-support.js';
import type { WorktreeFileSurfaceRuntimeFetchedResource } from './worktree-file-surface-runtime.js';
import {
	createWorktreeFileSurfaceRuntime,
	makeWorktreeFileSurfaceRuntimeFetchedResource,
} from './worktree-file-surface-runtime.js';

export function registerWorktreeFileSurfaceRuntimeOpenTests(): void {
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource('struct View {}');
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
			descriptorId: 'file-content-1',
		});
		if (loadResult.ok) {
			expect(loadResult.content.readText()).toBe('struct View {}');
		}
		expect(fetches).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1&cursor=cursor-1',
		]);
		expect(JSON.stringify(runtime.getState())).not.toContain('struct View');
		expect(runtime.getBodyRegistrySnapshot()).toEqual({ entryCount: 1, totalBytes: 14 });
	});

	test('surfaces streamed selected-file chunks before final body materialization', async () => {
		const descriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const streamedChunks: string[] = [];
		let loadSettled = false;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			onResourceTextChunk: (chunk) => {
				streamedChunks.push(chunk.text);
				expect(loadSettled).toBe(false);
			},
			fetchResource: async ({ onTextChunk }) => {
				onTextChunk?.({ byteLength: 9, text: 'streamed ', totalBytesRead: 9 });
				await Promise.resolve();
				onTextChunk?.({ byteLength: 4, text: 'body', totalBytesRead: 13 });
				return makeWorktreeFileSurfaceRuntimeFetchedResource('streamed body');
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		const loadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-1',
		});
		loadSettled = true;

		expect(streamedChunks).toEqual(['streamed ', 'body']);
		expect(loadResult).toMatchObject({
			ok: true,
		});
		if (loadResult.ok) {
			expect(loadResult.content.readText()).toBe('streamed body');
		}
	});

	test('routes selected-file provisional chunks before authoritative cache commit', async () => {
		const descriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const provisionalChunks: string[] = [];
		const fetchStarted = makeDeferred<void>();
		const finishFetch = makeDeferred<WorktreeFileSurfaceRuntimeFetchedResource>();
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ onTextChunk }) => {
				onTextChunk?.({ byteLength: 8, text: 'partial ', totalBytesRead: 8 });
				fetchStarted.resolve();
				return await finishFetch.promise;
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		const loadPromise = runtime.openFile({
			descriptor,
			onProvisionalTextChunk: (chunk) => {
				provisionalChunks.push(chunk.text);
			},
			openFileSessionId: 'session-1',
		});
		await fetchStarted.promise;

		expect(provisionalChunks).toEqual(['partial ']);
		expect(runtime.getBodyRegistrySnapshot()).toEqual({ entryCount: 0, totalBytes: 0 });

		finishFetch.resolve(makeWorktreeFileSurfaceRuntimeFetchedResource('partial final\n'));
		const loadResult = await loadPromise;

		expect(loadResult).toMatchObject({ ok: true });
		if (loadResult.ok) {
			expect(loadResult.content.readText()).toBe('partial final\n');
		}
		expect(runtime.getBodyRegistrySnapshot()).toEqual({
			entryCount: 1,
			totalBytes: 'partial final\n'.length,
		});
	});

	test('does not finalize or cache preview-only selected-file materialization', async () => {
		const descriptor = makeFileDescriptor({
			descriptorId: 'preview-content-1',
			integrity: { kind: 'previewOnly' },
		});
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async () =>
				makeWorktreeFileSurfaceRuntimeFetchedResource({
					authoritative: false,
					text: 'preview window body',
				}),
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		const loadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-preview',
		});

		expect(loadResult).toMatchObject({
			ok: false,
			reason: 'preview_only',
		});
		expect(runtime.getBodyRegistrySnapshot()).toEqual({ entryCount: 0, totalBytes: 0 });
		expect(runtime.getState().openFileSessionsById['session-preview']?.status).toBe('failed');
	});

	test('reports selected file load disposition and queue pressure for cold and cached opens', async () => {
		const descriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const fetches: string[] = [];
		const resourceLoadSamples: unknown[] = [];
		let nowMilliseconds = 200;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			now: () => nowMilliseconds,
			resourceLoadProbe: {
				isEnabled: () => true,
				now: () => nowMilliseconds,
				record: (sample): void => {
					resourceLoadSamples.push(sample);
				},
			},
			fetchResource: async ({ resourceUrl }) => {
				fetches.push(resourceUrl);
				nowMilliseconds += 9;
				return makeWorktreeFileSurfaceRuntimeFetchedResource({
					text: `body from ${resourceUrl}`,
					timing: {
						firstChunkWaitMilliseconds: 3,
						responseWaitMilliseconds: 2,
						streamReadMilliseconds: 4,
					},
				});
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
				executorInFlightMilliseconds: 9,
				executorPendingWaitMilliseconds: 0,
				lane: 'foreground',
				resourceBodyRegistryCommitMilliseconds: expect.any(Number),
				resourceFetchResponseWaitMilliseconds: 2,
				resourceFirstChunkWaitMilliseconds: 3,
				resourceStreamReadMilliseconds: 4,
				schedulerQueueWaitMilliseconds: 0,
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
				resourceBodyRegistryCommitMilliseconds: expect.any(Number),
				resourceFetchResponseWaitMilliseconds: 2,
				resourceFirstChunkWaitMilliseconds: 3,
				resourceStreamReadMilliseconds: 4,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			},
		});
		expect(fetches).toHaveLength(1);
		expect(resourceLoadSamples).toEqual([
			expect.objectContaining({
				byteLength: expect.any(Number),
				estimatedBytes: 64,
				firstChunkWaitMilliseconds: 3,
				lane: 'foreground',
				responseWaitMilliseconds: 2,
				result: 'success',
				resultReason: null,
				streamReadMilliseconds: 4,
				totalDurationMilliseconds: 9,
			}),
		]);
	});

	test('does not emit resource load samples when the resource probe is disabled', async () => {
		const descriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const resourceLoadSamples: unknown[] = [];
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			resourceLoadProbe: {
				isEnabled: () => false,
				now: () => {
					throw new Error('disabled probe must not read timing');
				},
				record: (sample): void => {
					resourceLoadSamples.push(sample);
				},
			},
			fetchResource: async () =>
				makeWorktreeFileSurfaceRuntimeFetchedResource({
					text: 'body',
					timing: {
						firstChunkWaitMilliseconds: 1,
						responseWaitMilliseconds: 1,
						streamReadMilliseconds: 1,
					},
				}),
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		const loadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-1',
		});

		expect(loadResult).toMatchObject({ ok: true });
		expect(resourceLoadSamples).toEqual([]);
	});

	test('reports failed selected file content loads to the resource probe', async () => {
		const descriptor = makeFileDescriptor({ descriptorId: 'file-content-1' });
		const resourceLoadSamples: unknown[] = [];
		let nowMilliseconds = 300;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			now: () => nowMilliseconds,
			resourceLoadProbe: {
				isEnabled: () => true,
				now: () => nowMilliseconds,
				record: (sample): void => {
					resourceLoadSamples.push(sample);
				},
			},
			fetchResource: async () => {
				nowMilliseconds += 11;
				throw new Error('fixture load failed');
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		const loadResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'session-1',
		});

		expect(loadResult).toEqual({ ok: false, reason: 'load_failed' });
		expect(resourceLoadSamples).toEqual([
			{
				byteLength: 0,
				estimatedBytes: 64,
				firstChunkWaitMilliseconds: null,
				lane: 'foreground',
				responseWaitMilliseconds: null,
				result: 'failed',
				resultReason: 'load_failed',
				streamReadMilliseconds: null,
				totalDurationMilliseconds: 11,
			},
		]);
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource('must-not-fetch');
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
}
