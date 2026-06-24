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
	type BridgeResourceExecutorBody,
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
			loadResource: async () => ({ body: 'unreachable', byteLength: 11 }),
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
				return { body: 'body', byteLength: 4 };
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
			body: 'body',
			byteLength: 4,
			descriptor: attachedDescriptor.descriptor,
			freshnessKey: intent.freshnessKey,
		});
		expect(secondResult).toEqual(firstResult);
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
		const firstDeferred = createDeferred<BridgeResourceExecutorBody<string>>();
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
				return { body: 'fresh-body', byteLength: 10 };
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
		firstDeferred.resolve({ body: 'stale-body', byteLength: 10 });

		expect(secondResult).toEqual({
			ok: true,
			body: 'fresh-body',
			byteLength: 10,
			descriptor: secondDescriptor.descriptor,
			freshnessKey: secondIntent.freshnessKey,
		});
		expect(await firstLoad).toEqual({
			ok: true,
			body: 'stale-body',
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
		const firstDeferred = createDeferred<BridgeResourceExecutorBody<string>>();
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
				return { body: 'queued-body', byteLength: 11 };
			},
		});

		const firstLoad = executor.load(makeIntent(firstDescriptor.ref));
		const queuedLoad = executor.load(makeIntent(secondDescriptor.ref, { lane: 'foreground' }));
		await Promise.resolve();
		firstDeferred.resolve({ body: 'first-body', byteLength: 10 });

		expect(await firstLoad).toMatchObject({ ok: true, body: 'first-body' });
		expect(await queuedLoad).toMatchObject({ ok: true, body: 'queued-body' });
		expect(executor.inFlightCount).toBe(0);
	});

	test('bounds queued foreground pressure instead of growing pending work without limit', async () => {
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
		const blockingDeferred = createDeferred<BridgeResourceExecutorBody<string>>();
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
				return { body: `${descriptor.descriptorId}-body`, byteLength: 17 };
			},
		});

		const blockingLoad = executor.load(makeIntent(blockingDescriptor.ref));
		const queuedLoad = executor.load(makeIntent(queuedDescriptor.ref, { lane: 'foreground' }));
		const rejectedResult = await executor.load(
			makeIntent(rejectedDescriptor.ref, { lane: 'foreground' }),
		);
		blockingDeferred.resolve({ body: 'blocking-body', byteLength: 13 });

		expect(rejectedResult).toEqual({ ok: false, reason: 'concurrency_exceeded' });
		expect(await blockingLoad).toMatchObject({ ok: true, body: 'blocking-body' });
		expect(await queuedLoad).toMatchObject({ ok: true, body: 'descriptor-2-body' });
		expect(executor.queuedLoadCount).toBe(0);
		expect(executor.queuedBytes).toBe(0);
	});

	test('admits foreground pressure by evicting lower-priority active pending work', async () => {
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
		const blockingDeferred = createDeferred<BridgeResourceExecutorBody<string>>();
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
				return { body: `${descriptor.descriptorId}-body`, byteLength: 17 };
			},
		});

		const blockingLoad = executor.load(makeIntent(blockingDescriptor.ref));
		const activeLoad = executor.load(makeIntent(activeDescriptor.ref, { lane: 'active' }));
		const foregroundLoad = executor.load(
			makeIntent(foregroundDescriptor.ref, { lane: 'foreground' }),
		);
		blockingDeferred.resolve({ body: 'blocking-body', byteLength: 13 });

		await expect(activeLoad).resolves.toEqual({ ok: false, reason: 'aborted' });
		expect(await blockingLoad).toMatchObject({ ok: true, body: 'blocking-body' });
		expect(await foregroundLoad).toMatchObject({ ok: true, body: 'descriptor-3-body' });
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
					return await new Promise<BridgeResourceExecutorBody<string>>(() => {});
				}
				return { body: 'foreground-body', byteLength: 15 };
			},
		});

		const visibleLoad = executor.load(makeIntent(visibleDescriptor.ref, { lane: 'visible' }));
		await visibleLoadStarted.promise;
		const foregroundLoad = executor.load(
			makeIntent(foregroundDescriptor.ref, { lane: 'foreground' }),
		);

		await expect(visibleLoad).resolves.toEqual({ ok: false, reason: 'aborted' });
		await expect(foregroundLoad).resolves.toMatchObject({ ok: true, body: 'foreground-body' });
		expect(capturedVisibleSignals.every((signal): boolean => signal.aborted)).toBe(true);
		expect(executor.inFlightCount).toBe(0);
		expect(executor.queuedLoadCount).toBe(0);
	});

	test('keeps visible pressure opportunistic instead of queueing behind active work', async () => {
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
		const firstDeferred = createDeferred<BridgeResourceExecutorBody<string>>();
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
				return { body: 'visible-body', byteLength: 12 };
			},
		});

		const blockingLoad = executor.load(makeIntent(firstDescriptor.ref, { lane: 'foreground' }));
		const visibleResult = await executor.load(
			makeIntent(secondDescriptor.ref, { lane: 'visible' }),
		);
		firstDeferred.resolve({ body: 'blocking-body', byteLength: 13 });

		expect(visibleResult).toEqual({ ok: false, reason: 'concurrency_exceeded' });
		expect(secondFetchCount).toBe(0);
		expect(await blockingLoad).toMatchObject({ ok: true, body: 'blocking-body' });
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
		const blockingDeferred = createDeferred<BridgeResourceExecutorBody<string>>();
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
				return { body: `${descriptor.descriptorId}-body`, byteLength: 17 };
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
		blockingDeferred.resolve({ body: 'blocking-body', byteLength: 13 });

		expect(await blockingLoad).toMatchObject({ ok: true, body: 'blocking-body' });
		expect(await sharedForegroundLoad).toMatchObject({ ok: true, body: 'descriptor-2-body' });
		expect(await sharedActiveLoad).toEqual(await sharedForegroundLoad);
		expect(await waitingLoad).toMatchObject({ ok: true, body: 'descriptor-3-body' });
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
			loadResource: async () => ({ body: 'stale', byteLength: 5 }),
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
	readonly freshnessKey?: string;
	readonly lane?: BridgeDemandIntent['lane'];
	readonly orderingKey?: string;
}

function makeIntent(ref: BridgeDescriptorRef, options: MakeIntentOptions = {}): BridgeDemandIntent {
	return {
		descriptorRef: ref,
		lane: options.lane ?? 'foreground',
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
