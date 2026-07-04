import { describe, expect, test } from 'vitest';

import type { BridgeDemandIntent } from '../models/bridge-demand-models.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
	BridgeResourceDescriptor,
} from '../models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../resources/bridge-resource-registry.js';
import {
	createBridgeResourceExecutor,
	type BridgeResourceExecutorContent,
} from './bridge-resource-executor.js';

describe('bridge resource executor', () => {
	test('rejects unknown descriptor refs before fetch', async () => {
		const registry = createRegistry();
		const executor = createBridgeResourceExecutor({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async () => ({ content: 'unreachable', byteLength: 11 }),
		});

		const result = await executor.load(makeIntent(makeAttachedDescriptor().ref));

		expect(result).toEqual({ ok: false, reason: 'descriptor_missing' });
	});

	test('coalesces concurrent work by dedupe key', async () => {
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);
		let fetchCount = 0;
		const executor = createBridgeResourceExecutor({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async () => {
				fetchCount += 1;
				return { content: 'materialized', byteLength: 4 };
			},
		});
		const intent = makeIntent(attachedDescriptor.ref);

		const [firstResult, secondResult] = await Promise.all([
			executor.load(intent),
			executor.load(intent),
		]);

		expect(fetchCount).toBe(1);
		expect(firstResult).toEqual({
			ok: true,
			authoritative: true,
			content: 'materialized',
			byteLength: 4,
			descriptor: attachedDescriptor.descriptor,
			freshnessKey: intent.freshnessKey,
		});
		expect(secondResult).toEqual(firstResult);
	});

	test('forwards streamed chunks before the final materialized resource resolves', async () => {
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);
		const chunkEvents: string[] = [];
		const finalMaterialization = createDeferred<BridgeResourceExecutorContent<string>>();
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			onChunk: ({ chunk, descriptor, intent }): void => {
				expect(descriptor.descriptorId).toBe(attachedDescriptor.descriptor.descriptorId);
				expect(intent.descriptorRef.descriptorId).toBe(attachedDescriptor.ref.descriptorId);
				chunkEvents.push(String(chunk.chunk));
			},
			loadResource: async ({ onChunk }) => {
				onChunk({ byteLength: 7, chunk: 'partial', totalBytesRead: 7 });
				onChunk({ byteLength: 6, chunk: '-chunk', totalBytesRead: 13 });
				return await finalMaterialization.promise;
			},
		});
		const loadPromise = executor.load(makeIntent(attachedDescriptor.ref));
		await Promise.resolve();

		expect(chunkEvents).toEqual(['partial', '-chunk']);
		finalMaterialization.resolve({ content: 'partial-chunk', byteLength: 13 });

		await expect(loadPromise).resolves.toMatchObject({
			ok: true,
			authoritative: true,
			content: 'partial-chunk',
			byteLength: 13,
		});
	});

	test('forwards streamed chunks to a single load observer', async () => {
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);
		const globalChunkEvents: string[] = [];
		const loadChunkEvents: string[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			onChunk: ({ chunk }): void => {
				globalChunkEvents.push(String(chunk.chunk));
			},
			loadResource: async ({ onChunk }) => {
				onChunk({ byteLength: 5, chunk: 'first', totalBytesRead: 5 });
				onChunk({ byteLength: 6, chunk: 'second', totalBytesRead: 11 });
				return { content: 'firstsecond', byteLength: 11 };
			},
		});

		const result = await executor.load(makeIntent(attachedDescriptor.ref), {
			onChunk: ({ chunk }): void => {
				loadChunkEvents.push(String(chunk.chunk));
			},
		});

		expect(result).toMatchObject({
			ok: true,
			content: 'firstsecond',
			byteLength: 11,
		});
		expect(globalChunkEvents).toEqual(['first', 'second']);
		expect(loadChunkEvents).toEqual(['first', 'second']);
	});

	test('preserves preview-only authority on successful materialization', async () => {
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async () => ({
				authoritative: false,
				content: 'preview materialized',
				byteLength: 20,
			}),
		});
		const intent = makeIntent(attachedDescriptor.ref);

		await expect(executor.load(intent)).resolves.toEqual({
			ok: true,
			authoritative: false,
			content: 'preview materialized',
			byteLength: 20,
			descriptor: attachedDescriptor.descriptor,
			freshnessKey: intent.freshnessKey,
		});
	});

	test('does not coalesce in-flight work when freshness differs', async () => {
		const registry = createRegistry();
		const firstDescriptor = makeAttachedDescriptor();
		const secondDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=2',
				identity: {
					paneId: 'pane-1',
					protocol: 'review',
					sourceId: 'source-1',
					packageId: 'package-1',
					generation: 1,
					revision: 2,
				},
			},
		});
		registry.register(firstDescriptor);
		registry.register(secondDescriptor);
		const requestedDescriptorIds: string[] = [];
		const firstDeferred = createDeferred<BridgeResourceExecutorContent<string>>();
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor }) => {
				requestedDescriptorIds.push(descriptor.descriptorId);
				if (descriptor.descriptorId === firstDescriptor.descriptor.descriptorId) {
					return await firstDeferred.promise;
				}
				return { content: 'fresh-materialized', byteLength: 10 };
			},
		});
		const firstIntent = makeIntent(firstDescriptor.ref, {
			dedupeKey: 'item-source:head',
			freshnessKey: 'item-source:head:revision-1',
		});
		const secondIntent = makeIntent(secondDescriptor.ref, {
			dedupeKey: 'item-source:head',
			freshnessKey: 'item-source:head:revision-2',
		});

		const firstLoad = executor.load(firstIntent);
		const secondResult = await executor.load(secondIntent);
		firstDeferred.resolve({ content: 'stale-materialized', byteLength: 10 });

		expect(secondResult).toEqual({
			ok: true,
			authoritative: true,
			content: 'fresh-materialized',
			byteLength: 10,
			descriptor: secondDescriptor.descriptor,
			freshnessKey: secondIntent.freshnessKey,
		});
		expect(await firstLoad).toEqual({
			ok: true,
			authoritative: true,
			content: 'stale-materialized',
			byteLength: 10,
			descriptor: firstDescriptor.descriptor,
			freshnessKey: firstIntent.freshnessKey,
		});
		expect(requestedDescriptorIds).toEqual(['descriptor-1', 'descriptor-2']);
	});

	test('queues foreground pressure behind active work instead of returning terminal concurrency failure', async () => {
		const registry = createRegistry();
		const firstDescriptor = makeAttachedDescriptor();
		const secondDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		registry.register(firstDescriptor);
		registry.register(secondDescriptor);
		const firstDeferred = createDeferred<BridgeResourceExecutorContent<string>>();
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId === firstDescriptor.descriptor.descriptorId) {
					return await firstDeferred.promise;
				}
				return { content: 'queued-materialized', byteLength: 11 };
			},
		});

		const firstLoad = executor.load(makeIntent(firstDescriptor.ref));
		const queuedLoad = executor.load(makeIntent(secondDescriptor.ref, { lane: 'foreground' }));
		await Promise.resolve();
		firstDeferred.resolve({ content: 'first-materialized', byteLength: 10 });

		expect(await firstLoad).toMatchObject({ ok: true, content: 'first-materialized' });
		expect(await queuedLoad).toMatchObject({ ok: true, content: 'queued-materialized' });
		expect(executor.inFlightCount).toBe(0);
	});

	test('emits pending wait and in-flight lifecycle timing for queued foreground work', async () => {
		let nowMilliseconds = 2_000;
		const lifecycleEvents: unknown[] = [];
		const registry = createRegistry();
		const firstDescriptor = makeAttachedDescriptor();
		const secondDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		registry.register(firstDescriptor);
		registry.register(secondDescriptor);
		const firstDeferred = createDeferred<BridgeResourceExecutorContent<string>>();
		const secondDeferred = createDeferred<BridgeResourceExecutorContent<string>>();
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			now: () => nowMilliseconds,
			onLifecycleEvent: (event): void => {
				lifecycleEvents.push(event);
			},
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId === firstDescriptor.descriptor.descriptorId) {
					return await firstDeferred.promise;
				}
				return await secondDeferred.promise;
			},
		});
		const firstIntent = makeIntent(firstDescriptor.ref);
		const secondIntent = makeIntent(secondDescriptor.ref, { lane: 'foreground' });

		const firstLoad = executor.load(firstIntent);
		await Promise.resolve();
		nowMilliseconds = 2_010;
		const queuedLoad = executor.load(secondIntent);
		await Promise.resolve();
		nowMilliseconds = 2_040;
		firstDeferred.resolve({ content: 'first-materialized', byteLength: 10 });

		expect(await firstLoad).toMatchObject({ ok: true, content: 'first-materialized' });
		nowMilliseconds = 2_055;
		secondDeferred.resolve({ content: 'queued-materialized', byteLength: 11 });
		expect(await queuedLoad).toMatchObject({ ok: true, content: 'queued-materialized' });
		expect(lifecycleEvents).toEqual([
			expect.objectContaining({
				kind: 'started',
				intent: firstIntent,
				pendingWaitMilliseconds: 0,
				startedAtMilliseconds: 2_000,
			}),
			expect.objectContaining({
				kind: 'queued',
				intent: secondIntent,
				pendingEnteredAtMilliseconds: 2_010,
				queuedLoadCountAfter: 1,
			}),
			expect.objectContaining({
				kind: 'completed',
				intent: firstIntent,
				inFlightMilliseconds: 40,
				result: 'success',
			}),
			expect.objectContaining({
				kind: 'started',
				intent: secondIntent,
				pendingWaitMilliseconds: 30,
				startedAtMilliseconds: 2_040,
			}),
			expect.objectContaining({
				kind: 'completed',
				intent: secondIntent,
				inFlightMilliseconds: 15,
				result: 'success',
			}),
		]);
	});

	test('admits queued members beyond legacy pending queue caps', async () => {
		const registry = createRegistry();
		const blockingDescriptor = makeAttachedDescriptor();
		const queuedDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		const rejectedDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-3',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-3?generation=1&revision=1',
			},
		});
		registry.register(blockingDescriptor);
		registry.register(queuedDescriptor);
		registry.register(rejectedDescriptor);
		const blockingDeferred = createDeferred<BridgeResourceExecutorContent<string>>();
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 1,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId === blockingDescriptor.descriptor.descriptorId) {
					return await blockingDeferred.promise;
				}
				return { content: `${descriptor.descriptorId}-materialized`, byteLength: 17 };
			},
		});

		const blockingLoad = executor.load(
			makeIntent(blockingDescriptor.ref, {
				demandRank: 0,
				orderingKey: '000-blocking-selected-rank',
			}),
		);
		const queuedLoad = executor.load(makeIntent(queuedDescriptor.ref, { lane: 'foreground' }));
		const admittedLoad = executor.load(makeIntent(rejectedDescriptor.ref, { lane: 'foreground' }));
		blockingDeferred.resolve({ content: 'blocking-materialized', byteLength: 13 });

		expect(await blockingLoad).toMatchObject({ ok: true, content: 'blocking-materialized' });
		expect(await queuedLoad).toMatchObject({ ok: true, content: 'descriptor-2-materialized' });
		expect(await admittedLoad).toMatchObject({ ok: true, content: 'descriptor-3-materialized' });
		expect(executor.queuedLoadCount).toBe(0);
		expect(executor.queuedBytes).toBe(0);
	});

	test('does not evict lower-priority pending members when foreground joins', async () => {
		const registry = createRegistry();
		const blockingDescriptor = makeAttachedDescriptor();
		const activeDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		const foregroundDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-3',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-3?generation=1&revision=1',
			},
		});
		registry.register(blockingDescriptor);
		registry.register(activeDescriptor);
		registry.register(foregroundDescriptor);
		const blockingDeferred = createDeferred<BridgeResourceExecutorContent<string>>();
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 1,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId === blockingDescriptor.descriptor.descriptorId) {
					return await blockingDeferred.promise;
				}
				return { content: `${descriptor.descriptorId}-materialized`, byteLength: 17 };
			},
		});

		const blockingLoad = executor.load(
			makeIntent(blockingDescriptor.ref, {
				demandRank: 0,
				orderingKey: '000-blocking-selected-rank',
			}),
		);
		const activeLoad = executor.load(makeIntent(activeDescriptor.ref, { lane: 'active' }));
		const foregroundLoad = executor.load(
			makeIntent(foregroundDescriptor.ref, { lane: 'foreground' }),
		);
		blockingDeferred.resolve({ content: 'blocking-materialized', byteLength: 13 });

		expect(await blockingLoad).toMatchObject({ ok: true, content: 'blocking-materialized' });
		expect(await foregroundLoad).toMatchObject({
			ok: true,
			content: 'descriptor-3-materialized',
		});
		expect(await activeLoad).toMatchObject({
			ok: true,
			content: 'descriptor-2-materialized',
		});
		expect(executor.queuedLoadCount).toBe(0);
		expect(executor.queuedBytes).toBe(0);
	});

	test('admits foreground pressure by preempting lower-priority in-flight work', async () => {
		const registry = createRegistry();
		const visibleDescriptor = makeAttachedDescriptor();
		const foregroundDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		registry.register(visibleDescriptor);
		registry.register(foregroundDescriptor);
		const visibleLoadStarted = createDeferred<void>();
		const capturedVisibleSignals: AbortSignal[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor, signal }) => {
				if (descriptor.descriptorId === visibleDescriptor.descriptor.descriptorId) {
					capturedVisibleSignals.push(signal);
					visibleLoadStarted.resolve();
					return await new Promise<BridgeResourceExecutorContent<string>>(() => {});
				}
				return { content: 'foreground-materialized', byteLength: 15 };
			},
		});

		const visibleLoad = executor.load(makeIntent(visibleDescriptor.ref, { lane: 'visible' }));
		await visibleLoadStarted.promise;
		const foregroundLoad = executor.load(
			makeIntent(foregroundDescriptor.ref, { lane: 'foreground' }),
		);

		await expect(visibleLoad).resolves.toEqual({ ok: false, reason: 'aborted' });
		await expect(foregroundLoad).resolves.toMatchObject({
			ok: true,
			content: 'foreground-materialized',
		});
		expect(capturedVisibleSignals.every((signal): boolean => signal.aborted)).toBe(true);
		expect(executor.inFlightCount).toBe(0);
		expect(executor.queuedLoadCount).toBe(0);
	});

	test('classifies abort-shaped resource failures as aborted instead of load failed', async () => {
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async () => {
				throw new DOMException('Bridge descriptor fetch aborted by context switch', 'AbortError');
			},
		});

		const result = await executor.load(makeIntent(attachedDescriptor.ref));

		expect(result).toEqual({ ok: false, reason: 'aborted' });
	});

	test('starts foreground work in the same turn after preempting lower-priority in-flight work', async () => {
		const registry = createRegistry();
		const visibleDescriptor = makeAttachedDescriptor();
		const foregroundDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		registry.register(visibleDescriptor);
		registry.register(foregroundDescriptor);
		const visibleLoadStarted = createDeferred<void>();
		const visibleLoadCanFinish = createDeferred<BridgeResourceExecutorContent<string>>();
		const startedDescriptorIds: string[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor }) => {
				startedDescriptorIds.push(descriptor.descriptorId);
				if (descriptor.descriptorId === visibleDescriptor.descriptor.descriptorId) {
					visibleLoadStarted.resolve();
					return await visibleLoadCanFinish.promise;
				}
				return { content: 'foreground-materialized', byteLength: 15 };
			},
		});

		const visibleLoad = executor.load(makeIntent(visibleDescriptor.ref, { lane: 'visible' }));
		await visibleLoadStarted.promise;
		const foregroundLoad = executor.load(
			makeIntent(foregroundDescriptor.ref, { lane: 'foreground' }),
		);

		expect(startedDescriptorIds).toEqual(['descriptor-1', 'descriptor-2']);
		expect(executor.inFlightCount).toBe(1);
		expect(executor.queuedLoadCount).toBe(0);
		visibleLoadCanFinish.resolve({ content: 'visible-too-late', byteLength: 16 });
		await expect(visibleLoad).resolves.toEqual({ ok: false, reason: 'aborted' });
		await expect(foregroundLoad).resolves.toMatchObject({
			ok: true,
			content: 'foreground-materialized',
		});
	});

	test('orders pending same-lane work by demand rank before ordering key', async () => {
		const registry = createRegistry();
		const blockingDescriptor = makeAttachedDescriptor();
		const visibleForegroundDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		const selectedForegroundDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-3',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-3?generation=1&revision=1',
			},
		});
		registry.register(blockingDescriptor);
		registry.register(visibleForegroundDescriptor);
		registry.register(selectedForegroundDescriptor);
		const blockingDeferred = createDeferred<BridgeResourceExecutorContent<string>>();
		const startedDescriptorIds: string[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor }) => {
				startedDescriptorIds.push(descriptor.descriptorId);
				if (descriptor.descriptorId === blockingDescriptor.descriptor.descriptorId) {
					return await blockingDeferred.promise;
				}
				return { content: `${descriptor.descriptorId}-materialized`, byteLength: 17 };
			},
		});

		const blockingLoad = executor.load(
			makeIntent(blockingDescriptor.ref, {
				demandRank: 0,
				orderingKey: '000-blocking-selected-rank',
			}),
		);
		const visibleSameLaneLoad = executor.load(
			makeIntent(visibleForegroundDescriptor.ref, {
				lane: 'foreground',
				demandRank: 1,
				orderingKey: '000-visible-before-selected',
			}),
		);
		const selectedSameLaneLoad = executor.load(
			makeIntent(selectedForegroundDescriptor.ref, {
				lane: 'foreground',
				demandRank: 0,
				orderingKey: '999-selected-after-visible',
			}),
		);
		blockingDeferred.resolve({ content: 'blocking-materialized', byteLength: 13 });

		expect(await blockingLoad).toMatchObject({ ok: true, content: 'blocking-materialized' });
		expect(await selectedSameLaneLoad).toMatchObject({
			ok: true,
			content: 'descriptor-3-materialized',
		});
		expect(await visibleSameLaneLoad).toMatchObject({
			ok: true,
			content: 'descriptor-2-materialized',
		});
		expect(startedDescriptorIds).toEqual(['descriptor-1', 'descriptor-3', 'descriptor-2']);
	});

	test('queues visible members behind active work instead of dropping membership', async () => {
		const registry = createRegistry();
		const firstDescriptor = makeAttachedDescriptor();
		const secondDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		registry.register(firstDescriptor);
		registry.register(secondDescriptor);
		const firstDeferred = createDeferred<BridgeResourceExecutorContent<string>>();
		let secondFetchCount = 0;
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId === firstDescriptor.descriptor.descriptorId) {
					return await firstDeferred.promise;
				}
				secondFetchCount += 1;
				return { content: 'visible-materialized', byteLength: 12 };
			},
		});

		const blockingLoad = executor.load(makeIntent(firstDescriptor.ref, { lane: 'foreground' }));
		const visibleLoad = executor.load(makeIntent(secondDescriptor.ref, { lane: 'visible' }));
		firstDeferred.resolve({ content: 'blocking-materialized', byteLength: 13 });

		expect(await blockingLoad).toMatchObject({ ok: true, content: 'blocking-materialized' });
		expect(await visibleLoad).toMatchObject({ ok: true, content: 'visible-materialized' });
		expect(secondFetchCount).toBe(1);
	});

	test('promotes pending work when a foreground request joins the same freshness', async () => {
		const registry = createRegistry();
		const blockingDescriptor = makeAttachedDescriptor();
		const promotedDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		const waitingDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-3',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-3?generation=1&revision=1',
			},
		});
		registry.register(blockingDescriptor);
		registry.register(promotedDescriptor);
		registry.register(waitingDescriptor);
		const blockingDeferred = createDeferred<BridgeResourceExecutorContent<string>>();
		const startedDescriptorIds: string[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor }) => {
				startedDescriptorIds.push(descriptor.descriptorId);
				if (descriptor.descriptorId === blockingDescriptor.descriptor.descriptorId) {
					return await blockingDeferred.promise;
				}
				return { content: `${descriptor.descriptorId}-materialized`, byteLength: 17 };
			},
		});
		const sharedActiveIntent = makeIntent(promotedDescriptor.ref, {
			dedupeKey: 'item-source:head',
			freshnessKey: 'item-source:head:revision-1',
			lane: 'active',
			orderingKey: '999',
		});
		const sharedForegroundIntent = makeIntent(promotedDescriptor.ref, {
			dedupeKey: sharedActiveIntent.dedupeKey,
			freshnessKey: sharedActiveIntent.freshnessKey,
			lane: 'foreground',
			orderingKey: '001',
		});
		const waitingIntent = makeIntent(waitingDescriptor.ref, {
			lane: 'active',
			orderingKey: '001',
		});

		const blockingLoad = executor.load(makeIntent(blockingDescriptor.ref));
		const sharedActiveLoad = executor.load(sharedActiveIntent);
		const waitingLoad = executor.load(waitingIntent);
		const sharedForegroundLoad = executor.load(sharedForegroundIntent);
		blockingDeferred.resolve({ content: 'blocking-materialized', byteLength: 13 });

		expect(await blockingLoad).toMatchObject({ ok: true, content: 'blocking-materialized' });
		expect(await sharedForegroundLoad).toMatchObject({
			ok: true,
			content: 'descriptor-2-materialized',
		});
		expect(await sharedActiveLoad).toEqual(await sharedForegroundLoad);
		expect(await waitingLoad).toMatchObject({
			ok: true,
			content: 'descriptor-3-materialized',
		});
		expect(startedDescriptorIds).toEqual(['descriptor-1', 'descriptor-2', 'descriptor-3']);
	});

	test('returns a typed failed result when the resource load rejects', async () => {
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async () => {
				throw new Error('content fetch unavailable');
			},
		});

		await expect(executor.load(makeIntent(attachedDescriptor.ref))).resolves.toEqual({
			ok: false,
			reason: 'load_failed',
		});
	});

	test('preserves sanitized load failure details when the classifier recognizes the rejection', async () => {
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			classifyLoadFailure: (error): 'integrity_mismatch' | null =>
				error instanceof Error && error.message === 'integrity failed'
					? 'integrity_mismatch'
					: null,
			loadResource: async () => {
				throw new Error('integrity failed');
			},
		});

		await expect(executor.load(makeIntent(attachedDescriptor.ref))).resolves.toEqual({
			ok: false,
			reason: 'load_failed',
			loadFailureKind: 'integrity_mismatch',
		});
	});

	test('enforces byte budgets and drops stale completions', async () => {
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor({
			descriptor: {
				content: {
					mediaType: 'text/plain',
					encoding: 'utf-8',
					expectedBytes: 2048,
					maxBytes: 2048,
				},
			},
		});
		registry.register(attachedDescriptor);
		const executor = createBridgeResourceExecutor({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			isFresh: () => false,
			loadResource: async () => ({ content: 'stale', byteLength: 5 }),
		});

		expect(await executor.load(makeIntent(attachedDescriptor.ref))).toEqual({
			ok: false,
			reason: 'byte_budget_exceeded',
		});

		const freshDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
				content: {
					mediaType: 'text/plain',
					encoding: 'utf-8',
					expectedBytes: 5,
					maxBytes: 1024,
				},
			},
		});
		registry.register(freshDescriptor);
		expect(await executor.load(makeIntent(freshDescriptor.ref))).toEqual({
			ok: false,
			reason: 'stale_completion',
		});
	});
});

function createRegistry(): ReturnType<typeof createBridgeResourceDescriptorRegistry> {
	return createBridgeResourceDescriptorRegistry({
		allowedResourceKindsByProtocol: { review: new Set(['content']) },
	});
}

interface MakeIntentOptions {
	readonly dedupeKey?: string;
	readonly demandRank?: number;
	readonly freshnessKey?: string;
	readonly lane?: BridgeDemandIntent['lane'];
	readonly orderingKey?: string;
}

function makeIntent(ref: BridgeDescriptorRef, options: MakeIntentOptions = {}): BridgeDemandIntent {
	return {
		descriptorRef: ref,
		lane: options.lane ?? 'foreground',
		...(options.demandRank === undefined ? {} : { demandRank: options.demandRank }),
		orderingKey: options.orderingKey ?? '001',
		dedupeKey: options.dedupeKey ?? ref.descriptorId,
		freshnessKey: options.freshnessKey ?? `${ref.descriptorId}:fresh`,
		cancellationGroup: 'review:package-1',
	};
}

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
	readonly reject: (error: Error) => void;
}

function createDeferred<TValue>(): Deferred<TValue> {
	let resolveValue: ((value: TValue) => void) | null = null;
	let rejectValue: ((error: Error) => void) | null = null;
	const promise = new Promise<TValue>((resolve, reject): void => {
		resolveValue = resolve;
		rejectValue = reject;
	});
	if (resolveValue === null || rejectValue === null) {
		throw new Error('Deferred promise handlers were not initialized.');
	}
	return {
		promise,
		resolve: resolveValue,
		reject: rejectValue,
	};
}

interface MakeAttachedDescriptorProps {
	readonly descriptor?: Partial<BridgeResourceDescriptor>;
}

function makeAttachedDescriptor(
	props: MakeAttachedDescriptorProps = {},
): BridgeAttachedResourceDescriptor {
	const descriptor = {
		descriptorId: 'descriptor-1',
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl: 'agentstudio://resource/review/content/descriptor-1?generation=1&revision=1',
		identity: {
			paneId: 'pane-1',
			protocol: 'review',
			sourceId: 'source-1',
			packageId: 'package-1',
			generation: 1,
			revision: 1,
		},
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: 64,
			maxBytes: 1024,
		},
		...props.descriptor,
	};
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
