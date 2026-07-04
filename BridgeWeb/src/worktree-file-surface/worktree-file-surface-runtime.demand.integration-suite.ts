import { expect, test } from 'vitest';

import { bridgeContentDemandExecutionPolicy } from '../core/demand/bridge-content-demand-policy.js';
import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
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

export function registerWorktreeFileSurfaceRuntimeDemandTests(): void {
	test('preloads visible file demand through the unified executor without opening file sessions', async () => {
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource({
					text: `${descriptor.descriptorId}:preloaded`,
					timing: {
						firstChunkWaitMilliseconds: 2,
						responseWaitMilliseconds: 1,
						streamReadMilliseconds: 3,
					},
				});
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
						executorInFlightMilliseconds: expect.any(Number),
						executorPendingWaitMilliseconds: expect.any(Number),
						lane: 'visible',
						resourceBodyRegistryCommitMilliseconds: expect.any(Number),
						resourceFetchResponseWaitMilliseconds: 1,
						resourceFirstChunkWaitMilliseconds: 2,
						resourceStreamReadMilliseconds: 3,
						demandQueueWaitMilliseconds: expect.any(Number),
					},
				},
				{
					ok: true,
					descriptorId: 'file-content-2',
					loadTelemetry: {
						disposition: 'visible-preloaded',
						durationMilliseconds: expect.any(Number),
						estimatedBytes: 64,
						executorInFlightMilliseconds: expect.any(Number),
						executorPendingWaitMilliseconds: expect.any(Number),
						lane: 'visible',
						resourceBodyRegistryCommitMilliseconds: expect.any(Number),
						resourceFetchResponseWaitMilliseconds: 1,
						resourceFirstChunkWaitMilliseconds: 2,
						resourceStreamReadMilliseconds: 3,
						demandQueueWaitMilliseconds: expect.any(Number),
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
		expect(
			dispatchResult.loadResults.every((loadResult): boolean => {
				if (!loadResult.ok) {
					return false;
				}
				return (
					loadResult.loadTelemetry.executorInFlightMilliseconds !== null &&
					loadResult.loadTelemetry.executorInFlightMilliseconds >= 0 &&
					loadResult.loadTelemetry.executorPendingWaitMilliseconds !== null &&
					loadResult.loadTelemetry.executorPendingWaitMilliseconds >= 0 &&
					loadResult.loadTelemetry.demandQueueWaitMilliseconds !== null &&
					loadResult.loadTelemetry.demandQueueWaitMilliseconds >= 0
				);
			}),
		).toBe(true);
		expect(fetchedDescriptorIds).toEqual(['file-content-1', 'file-content-2']);
		expect(runtime.getState().openFileSessionsById).toEqual({});
		expect(runtime.getBodyRegistrySnapshot()).toEqual({
			entryCount: 2,
			totalBytes: 'file-content-1:preloaded'.length + 'file-content-2:preloaded'.length,
		});
	});

	test('settles all visible file demand without treating executor pressure as preload failure', async () => {
		const descriptors = Array.from({ length: 12 }, (_, index): WorktreeFileDescriptor => {
			const descriptorIndex = index + 1;
			return makeFileDescriptor({
				descriptorId: `file-content-${descriptorIndex}`,
				contentHandle: `handle-${descriptorIndex}`,
				expectedBytes: 4 * 1024 * 1024,
				fileId: `file-${descriptorIndex}`,
				maxBytes: 4 * 1024 * 1024,
				path: `Sources/App/File${descriptorIndex}.swift`,
			});
		});
		const fetchedDescriptorIds: string[] = [];
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ descriptor }) => {
				fetchedDescriptorIds.push(descriptor.descriptorId);
				return makeWorktreeFileSurfaceRuntimeFetchedResource(
					`${descriptor.descriptorId}:preloaded`,
				);
			},
		});
		for (const descriptor of descriptors) {
			runtime.applyFrame(makeFileDescriptorFrame(descriptor));
		}

		const dispatchResult = await runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: descriptors.map((descriptor) => descriptor.contentDescriptor.ref),
			},
		]);

		expect(dispatchResult).toMatchObject({
			stimulusCount: 1,
			intentCount: descriptors.length,
			enqueueAcceptedCount: descriptors.length,
			enqueueRejectedCount: 0,
			loadedCount: descriptors.length,
			failedCount: 0,
			executorInFlightCountAfter: 0,
			executorQueuedLoadCountAfter: 0,
		});
		expect(fetchedDescriptorIds).toHaveLength(descriptors.length);
		expect(
			dispatchResult.loadResults.every(
				(loadResult): boolean =>
					loadResult.ok && loadResult.loadTelemetry.disposition === 'visible-preloaded',
			),
		).toBe(true);
	});

	test('serializes concurrent visible demand dispatches before executor pressure can reject them', async () => {
		const firstDescriptors = Array.from({ length: 8 }, (_, index): WorktreeFileDescriptor => {
			const descriptorIndex = index + 1;
			return makeFileDescriptor({
				descriptorId: `first-visible-content-${descriptorIndex}`,
				contentHandle: `first-handle-${descriptorIndex}`,
				fileId: `first-file-${descriptorIndex}`,
				path: `Sources/App/First${descriptorIndex}.swift`,
			});
		});
		const secondDescriptors = Array.from({ length: 8 }, (_, index): WorktreeFileDescriptor => {
			const descriptorIndex = index + 1;
			return makeFileDescriptor({
				descriptorId: `second-visible-content-${descriptorIndex}`,
				contentHandle: `second-handle-${descriptorIndex}`,
				fileId: `second-file-${descriptorIndex}`,
				path: `Sources/App/Second${descriptorIndex}.swift`,
			});
		});
		const loadGate = makeDeferred<void>();
		const fetchedDescriptorIds: string[] = [];
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ descriptor }) => {
				fetchedDescriptorIds.push(descriptor.descriptorId);
				await loadGate.promise;
				return makeWorktreeFileSurfaceRuntimeFetchedResource(
					`${descriptor.descriptorId}:preloaded`,
				);
			},
		});
		for (const descriptor of [...firstDescriptors, ...secondDescriptors]) {
			runtime.applyFrame(makeFileDescriptorFrame(descriptor));
		}

		const firstDispatch = runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: firstDescriptors.map((descriptor) => descriptor.contentDescriptor.ref),
			},
		]);
		await Promise.resolve();
		const secondDispatch = runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: secondDescriptors.map((descriptor) => descriptor.contentDescriptor.ref),
			},
		]);
		await Promise.resolve();

		expect(fetchedDescriptorIds).toHaveLength(
			bridgeContentDemandExecutionPolicy.immediateStartConcurrency,
		);
		loadGate.resolve();
		const [firstDispatchResult, secondDispatchResult] = await Promise.all([
			firstDispatch,
			secondDispatch,
		]);

		expect(firstDispatchResult).toMatchObject({
			intentCount: firstDescriptors.length,
			loadedCount: firstDescriptors.length,
			failedCount: 0,
			executorInFlightCountAfter: 0,
			executorQueuedLoadCountAfter: 0,
		});
		expect(secondDispatchResult).toMatchObject({
			intentCount: secondDescriptors.length,
			loadedCount: secondDescriptors.length,
			failedCount: 0,
			executorInFlightCountAfter: 0,
			executorQueuedLoadCountAfter: 0,
		});
		expect(fetchedDescriptorIds).toHaveLength(firstDescriptors.length + secondDescriptors.length);
	});

	test('reports visible preload provenance when opening a warmed file', async () => {
		const descriptor = makeFileDescriptor({
			descriptorId: 'file-content-visible-open',
			fileId: 'file-visible-open',
			path: 'Sources/App/Warmed.swift',
		});
		const fetchedDescriptorIds: string[] = [];
		let nowMilliseconds = 900;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			now: () => nowMilliseconds,
			fetchResource: async ({ descriptor: resourceDescriptor }) => {
				fetchedDescriptorIds.push(resourceDescriptor.descriptorId);
				nowMilliseconds += 5;
				return makeWorktreeFileSurfaceRuntimeFetchedResource('let warmed = true\n');
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		await runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: [descriptor.contentDescriptor.ref],
			},
		]);
		nowMilliseconds += 3;
		const openResult = await runtime.openFile({
			descriptor,
			openFileSessionId: 'file-visible-open',
		});

		expect(openResult).toMatchObject({
			ok: true,
			loadTelemetry: {
				disposition: 'visible-preloaded',
				durationMilliseconds: 0,
				estimatedBytes: 64,
				lane: 'foreground',
			},
		});
		if (openResult.ok) {
			expect(openResult.content.readText()).toBe('let warmed = true\n');
		}
		expect(fetchedDescriptorIds).toEqual(['file-content-visible-open']);
	});

	test('reports numeric visible preload telemetry when it joins an in-flight selected load', async () => {
		const descriptor = makeFileDescriptor({
			descriptorId: 'file-content-visible-joined',
			fileId: 'file-visible-joined',
			path: 'Sources/App/JoinedVisible.swift',
		});
		const fetchStarted = makeDeferred<void>();
		const finishFetch = makeDeferred<WorktreeFileSurfaceRuntimeFetchedResource>();
		const fetchedDescriptorIds: string[] = [];
		let nowMilliseconds = 1_200;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			now: () => nowMilliseconds,
			fetchResource: async ({ descriptor: resourceDescriptor }) => {
				fetchedDescriptorIds.push(resourceDescriptor.descriptorId);
				fetchStarted.resolve();
				const fetchedResource = await finishFetch.promise;
				nowMilliseconds += 13;
				return fetchedResource;
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		const openPromise = runtime.openFile({
			descriptor,
			openFileSessionId: 'file-visible-joined',
		});
		await fetchStarted.promise;
		const visibleDispatchPromise = runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: [descriptor.contentDescriptor.ref],
			},
		]);
		finishFetch.resolve(makeWorktreeFileSurfaceRuntimeFetchedResource('let joined = true\n'));

		const [openResult, visibleDispatchResult] = await Promise.all([
			openPromise,
			visibleDispatchPromise,
		]);

		expect(openResult).toMatchObject({ ok: true });
		expect(visibleDispatchResult).toMatchObject({
			loadedCount: 1,
			failedCount: 0,
			loadResults: [
				{
					ok: true,
					loadTelemetry: {
						disposition: 'visible-preloaded',
						executorInFlightMilliseconds: expect.any(Number),
						executorPendingWaitMilliseconds: expect.any(Number),
						lane: 'visible',
						demandQueueWaitMilliseconds: expect.any(Number),
					},
				},
			],
		});
		expect(fetchedDescriptorIds).toEqual(['file-content-visible-joined']);
	});

	test('reports cached visible preload demand with its original preload provenance', async () => {
		const descriptor = makeFileDescriptor({
			descriptorId: 'file-content-visible-repeat',
			fileId: 'file-visible-repeat',
			path: 'Sources/App/RepeatedVisible.swift',
		});
		const fetchedDescriptorIds: string[] = [];
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ descriptor: resourceDescriptor }) => {
				fetchedDescriptorIds.push(resourceDescriptor.descriptorId);
				return makeWorktreeFileSurfaceRuntimeFetchedResource('let repeatedVisible = true\n');
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(descriptor));

		await runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: [descriptor.contentDescriptor.ref],
			},
		]);
		const secondDispatchResult = await runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: [descriptor.contentDescriptor.ref],
			},
		]);

		expect(secondDispatchResult).toMatchObject({
			loadedCount: 1,
			failedCount: 0,
		});
		expect(secondDispatchResult.loadResults[0]).toMatchObject({
			ok: true,
			loadTelemetry: {
				disposition: 'visible-preloaded',
				lane: 'visible',
			},
		});
		expect(fetchedDescriptorIds).toEqual(['file-content-visible-repeat']);
	});

	test('starts foreground open without waiting for visible demand dispatch to drain', async () => {
		const visibleDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-visible-blocking',
			fileId: 'file-visible-blocking',
			path: 'Sources/App/VisibleBlocking.swift',
		});
		const targetDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-click-target',
			fileId: 'file-click-target',
			path: 'Sources/App/ClickTarget.swift',
		});
		const visibleGate = makeDeferred<void>();
		const fetchedDescriptorIds: string[] = [];
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			fetchResource: async ({ descriptor }) => {
				fetchedDescriptorIds.push(descriptor.descriptorId);
				if (descriptor.descriptorId === visibleDescriptor.contentDescriptor.ref.descriptorId) {
					await visibleGate.promise;
				}
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:body`);
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(visibleDescriptor));
		runtime.applyFrame(makeFileDescriptorFrame(targetDescriptor));

		const visibleDispatch = runtime.dispatchDemandStimuli([
			{
				kind: 'treeViewportChanged',
				descriptorRefs: [visibleDescriptor.contentDescriptor.ref],
			},
		]);
		await Promise.resolve();
		const openResultPromise = runtime.openFile({
			descriptor: targetDescriptor,
			openFileSessionId: 'file-click-target',
		});
		await Promise.resolve();

		expect(fetchedDescriptorIds).toEqual([
			'file-content-visible-blocking',
			'file-content-click-target',
		]);
		visibleGate.resolve();
		await visibleDispatch;
		const openResult = await openResultPromise;

		expect(openResult).toMatchObject({
			ok: true,
			descriptorId: 'file-content-click-target',
			loadTelemetry: {
				disposition: 'cold-loaded',
				executorInFlightCountBefore: 1,
				executorInFlightCountAfter: 0,
				executorQueuedLoadCountAfter: 0,
				lane: 'foreground',
			},
		});
	});

	test('preloads recently updated files as nearby or speculative demand without opening sessions', async () => {
		const nearbyDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-updated-nearby',
			fileId: 'file-updated-nearby',
			path: 'Sources/App/Nearby.swift',
		});
		const remoteDescriptor = makeFileDescriptor({
			descriptorId: 'file-content-updated-remote',
			contentHandle: 'handle-updated-remote',
			fileId: 'file-updated-remote',
			path: 'Sources/App/Remote.swift',
		});
		const fetchedDescriptorIds: string[] = [];
		let nowMilliseconds = 1_200;
		const runtime = createWorktreeFileSurfaceRuntime({
			paneId: 'pane-1',
			now: () => nowMilliseconds,
			fetchResource: async ({ descriptor }) => {
				fetchedDescriptorIds.push(descriptor.descriptorId);
				nowMilliseconds += 4;
				return makeWorktreeFileSurfaceRuntimeFetchedResource(`${descriptor.descriptorId}:recent`);
			},
		});
		runtime.applyFrame(makeFileDescriptorFrame(nearbyDescriptor));
		runtime.applyFrame(makeFileDescriptorFrame(remoteDescriptor));

		const dispatchResult = await runtime.dispatchDemandStimuli([
			{
				kind: 'recentlyUpdatedFile',
				descriptorRef: nearbyDescriptor.contentDescriptor.ref,
				proximity: 'nearby',
				sourceIdentity: 'dev-worktree-source',
			},
			{
				kind: 'recentlyUpdatedFile',
				descriptorRef: remoteDescriptor.contentDescriptor.ref,
				proximity: 'remote',
				sourceIdentity: 'dev-worktree-source',
			},
		]);

		expect(dispatchResult).toMatchObject({
			stimulusCount: 2,
			intentCount: 2,
			enqueueAcceptedCount: 2,
			enqueueRejectedCount: 0,
			loadedCount: 2,
			failedCount: 0,
			executorInFlightCountAfter: 0,
			executorQueuedLoadCountAfter: 0,
			loadResults: [
				{
					ok: true,
					descriptorId: 'file-content-updated-nearby',
					loadTelemetry: {
						disposition: 'nearby-preloaded',
						lane: 'nearby',
					},
				},
				{
					ok: true,
					descriptorId: 'file-content-updated-remote',
					loadTelemetry: {
						disposition: 'speculative-preloaded',
						lane: 'speculative',
					},
				},
			],
		});
		expect(
			dispatchResult.loadResults
				.filter((loadResult) => loadResult.ok)
				.map((loadResult) => loadResult.loadTelemetry.lane),
		).not.toContain('foreground');
		expect(fetchedDescriptorIds).toEqual([
			'file-content-updated-nearby',
			'file-content-updated-remote',
		]);
		expect(runtime.getState().openFileSessionsById).toEqual({});
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
				return makeWorktreeFileSurfaceRuntimeFetchedResource('must-not-fetch');
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
			enqueueAcceptedCount: 1,
			enqueueRejectedCount: 0,
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
		});
		expect(fetchCount).toBe(0);
	});
}
