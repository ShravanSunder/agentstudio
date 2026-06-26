import { describe, expect, test } from 'vitest';

import { createBridgeDemandScheduler } from '../../core/demand/bridge-demand-scheduler.js';
import { createBridgeResourceExecutor } from '../../core/demand/bridge-resource-executor.js';
import type { BridgeResourceExecutorResult } from '../../core/demand/bridge-resource-executor.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
} from '../../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../../core/resources/bridge-resource-registry.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeContentHandle } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryFlushProps,
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTelemetryScope } from '../../foundation/telemetry/bridge-telemetry-scope.js';
import {
	loadReviewItemContentResourcesThroughDemand,
	loadReviewItemContentResourcesThroughDemandResult,
} from './review-content-demand-loader.js';

describe('review content demand loader', () => {
	test('loads review item resources through descriptor-backed generic demand', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const requestedUrls: string[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				requestedUrls.push(descriptor.resourceUrl);
				return {
					body: descriptor.descriptorId.includes('base') ? 'base text' : 'head text',
					byteLength: 9,
				};
			},
		});

		const resources = await loadReviewItemContentResourcesThroughDemand({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor,
		});

		expect(resources?.base?.text).toBe('base text');
		expect(resources?.head?.text).toBe('head text');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/descriptor-handle-item-source-base?generation=1&revision=1',
			'agentstudio://resource/review/content/descriptor-handle-item-source-head?generation=1&revision=1',
		]);
	});

	test('records demand fetch telemetry with interest result and throttled flushes', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const telemetryRecorder = makeTelemetryRecorder();
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => ({
				body: `${descriptor.descriptorId} text`,
				byteLength: 20,
			}),
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor,
			telemetryRecorder,
		});

		expect(result.status).toBe('ready');
		const fetchSamples = telemetryRecorder.samples.filter(
			(sample): boolean => sample.name === 'performance.bridge.web.content_fetch',
		);
		expect(fetchSamples).toHaveLength(2);
		expect(fetchSamples).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					stringAttributes: expect.objectContaining({
						'agentstudio.bridge.content.interest': 'visible',
						'agentstudio.bridge.result': 'success',
						'agentstudio.bridge.result_reason': 'none',
					}),
				}),
			]),
		);
		expect(telemetryRecorder.flushForces).toEqual([false, false]);
	});

	test('publishes selected demand pressure telemetry for foreground proof', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const pressureSamples: unknown[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => ({
				body: `${descriptor.descriptorId} text`,
				byteLength: 20,
			}),
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor,
			onDemandTelemetry: (sample: unknown): void => {
				pressureSamples.push(sample);
			},
		});

		expect(result.status).toBe('ready');
		expect(pressureSamples).toEqual([
			expect.objectContaining({
				itemId: 'item-source',
				interest: 'selected',
				foregroundIntentCount: 2,
				visibleIntentCount: 0,
				enqueueAcceptedCount: 2,
				enqueueRejectedCount: 0,
				admittedBytes: 40,
				deferredCount: 0,
				failedCount: 0,
				loadedCount: 2,
				maxExecutorInFlightCount: 2,
				maxSchedulerQueuedIntentCount: 2,
				schedulerQueuedIntentCountAfter: 0,
				executorInFlightCountAfter: 0,
			}),
		]);
	});

	test('does not dequeue unrelated work from a shared scheduler', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 8,
			maxQueuedEstimatedBytes: 4096,
		});
		const unrelatedIntent = {
			descriptorRef: makeUnrelatedDescriptorRef(),
			lane: 'foreground',
			orderingKey: '000',
			dedupeKey: 'unrelated',
			freshnessKey: 'unrelated:fresh',
			cancellationGroup: 'review:other-package',
		} as const;
		expect(scheduler.enqueue({ intent: unrelatedIntent, estimatedBytes: 1 })).toEqual({
			ok: true,
			status: 'queued',
		});
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => ({
				body: `${descriptor.descriptorId} text`,
				byteLength: 20,
			}),
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler,
			executor,
		});

		expect(result.status).toBe('ready');
		expect(scheduler.dequeueNext()).toEqual(unrelatedIntent);
	});

	test('loads two-sided content when each role fits executor budget but combined role bytes exceed scheduler cap', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackageWithContentRoleBytes(5 * 1024 * 1024);
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const requestedDescriptorIds: string[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 8 * 1024 * 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 8 * 1024 * 1024,
			loadResource: async ({ descriptor }) => {
				requestedDescriptorIds.push(descriptor.descriptorId);
				return {
					body: descriptor.descriptorId.includes('base') ? 'large base' : 'large head',
					byteLength: 10,
				};
			},
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 8 * 1024 * 1024,
			}),
			executor,
		});

		expect(result).toMatchObject({
			status: 'ready',
			resources: {
				base: { text: 'large base' },
				head: { text: 'large head' },
			},
		});
		expect(requestedDescriptorIds).toEqual([
			'descriptor-handle-item-source-base',
			'descriptor-handle-item-source-head',
		]);
	});

	test('fails closed when a handle has no accepted descriptor ref', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		let fetchCount = 0;
		const resources = await loadReviewItemContentResourcesThroughDemand({
			reviewPackage: makeBridgeReviewPackage(),
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (): BridgeDescriptorRef | null => null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor: createBridgeResourceExecutor<string>({
				registry,
				maxConcurrentLoads: 2,
				maxInFlightBytes: 4096,
				maxQueuedLoads: 8,
				maxQueuedBytes: 4096,
				loadResource: async () => {
					fetchCount += 1;
					return { body: 'must not fetch', byteLength: 14 };
				},
			}),
		});

		expect(resources).toBeNull();
		expect(fetchCount).toBe(0);
	});

	test('returns null as soon as one required role fails', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const headFailureObserved = createDeferred<void>();
		const unresolvedBaseResult = createDeferred<BridgeResourceExecutorResult<string>>();
		const resourcesPromise = loadReviewItemContentResourcesThroughDemand({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor: {
				load: async (intent) => {
					if (intent.descriptorRef.descriptorId.includes('head')) {
						headFailureObserved.resolve();
						return { ok: false, reason: 'load_failed' };
					}
					return await unresolvedBaseResult.promise;
				},
				cancelGroup: () => 0,
				inFlightCount: 0,
				inFlightBytes: 0,
				maxConcurrentLoads: 2,
				maxInFlightBytes: 4096,
				maxQueuedBytes: 4096,
				maxQueuedLoads: 8,
				queuedLoadCount: 0,
				queuedBytes: 0,
			},
		});
		let resolvedResources: BridgeContentResourcesResult = 'pending';
		void resourcesPromise.then((resources): void => {
			resolvedResources = resources;
		});

		await headFailureObserved.promise;
		await flushMicrotasks(6);

		expect(resolvedResources).toBeNull();
	});

	test('aborts sibling role loads when one required role fails terminally', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const capturedBaseSignals: AbortSignal[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor, signal }) => {
				if (descriptor.descriptorId.includes('head')) {
					throw new Error('head content failed');
				}
				capturedBaseSignals.push(signal);
				return await new Promise<{ readonly body: string; readonly byteLength: number }>(() => {});
			},
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor,
		});
		await flushMicrotasks(4);

		expect(result).toEqual({ status: 'failed', reason: 'load_failed' });
		expect(capturedBaseSignals.length).toBe(1);
		expect(capturedBaseSignals.every((signal): boolean => signal.aborted)).toBe(true);
		expect(executor.inFlightCount).toBe(0);
		expect(executor.inFlightBytes).toBe(0);
	});

	test('returns deferred instead of terminal null when visible demand hits pressure', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const blockingDescriptor = registeredDescriptorsByHandleId.get('handle-item-source-base');
		if (blockingDescriptor === undefined) {
			throw new Error('expected base descriptor');
		}
		const blockingLoad = createDeferred<{ readonly body: string; readonly byteLength: number }>();
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId === blockingDescriptor.ref.descriptorId) {
					return await blockingLoad.promise;
				}
				return { body: 'visible text', byteLength: 12 };
			},
		});
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 8,
			maxQueuedEstimatedBytes: 4096,
		});
		const foregroundLoad = executor.load({
			descriptorRef: blockingDescriptor.ref,
			lane: 'foreground',
			orderingKey: '000',
			dedupeKey: 'blocking',
			freshnessKey: 'blocking',
			cancellationGroup: 'blocking',
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler,
			executor,
		});
		blockingLoad.resolve({ body: 'blocking text', byteLength: 13 });

		expect(result).toEqual({ status: 'deferred', reason: 'concurrency_exceeded' });
		await expect(foregroundLoad).resolves.toMatchObject({ ok: true });
	});

	test('returns deferred and rolls back partial enqueues when scheduler lane rejects a role', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		let fetchCount = 0;
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 1,
			maxQueuedEstimatedBytes: 4096,
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler,
			executor: createBridgeResourceExecutor<string>({
				registry,
				maxConcurrentLoads: 2,
				maxInFlightBytes: 4096,
				maxQueuedLoads: 8,
				maxQueuedBytes: 4096,
				loadResource: async () => {
					fetchCount += 1;
					return { body: 'must not load after partial enqueue', byteLength: 36 };
				},
			}),
		});

		expect(result).toEqual({ status: 'deferred', reason: 'concurrency_exceeded' });
		expect(fetchCount).toBe(0);
		expect(scheduler.queuedIntentCount).toBe(0);
	});

	test('propagates external aborts into executor demand cancellation', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const capturedSignals: AbortSignal[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ signal }) => {
				capturedSignals.push(signal);
				return await new Promise<{ readonly body: string; readonly byteLength: number }>(() => {});
			},
		});
		const abortController = new AbortController();
		const resultPromise = loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor,
			signal: abortController.signal,
		});
		await flushMicrotasks(4);

		abortController.abort();
		await flushMicrotasks(4);

		expect(capturedSignals.length).toBeGreaterThan(0);
		expect(capturedSignals.every((signal): boolean => signal.aborted)).toBe(true);
		await expect(resultPromise).resolves.toEqual({ status: 'deferred', reason: 'aborted' });
	});

	test('propagates selected external aborts into executor demand cancellation', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const capturedSignals: AbortSignal[] = [];
		const deferredBody = createDeferred<{ readonly body: string; readonly byteLength: number }>();
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ signal }) => {
				capturedSignals.push(signal);
				return await deferredBody.promise;
			},
		});
		const abortController = new AbortController();
		const resultPromise = loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor,
			signal: abortController.signal,
		});
		await flushMicrotasks(4);

		abortController.abort();
		await flushMicrotasks(4);
		deferredBody.resolve({ body: 'stale selected body', byteLength: 19 });

		expect(capturedSignals.length).toBeGreaterThan(0);
		expect(capturedSignals.every((signal): boolean => signal.aborted)).toBe(true);
		await expect(resultPromise).resolves.toEqual({ status: 'deferred', reason: 'aborted' });
	});
});

type BridgeContentResourcesResult =
	| 'pending'
	| Awaited<ReturnType<typeof loadReviewItemContentResourcesThroughDemand>>;

interface TestTelemetryRecorder extends BridgeTelemetryRecorder {
	readonly samples: BridgeTelemetrySample[];
	readonly flushForces: readonly boolean[];
}

function makeTelemetryRecorder(): TestTelemetryRecorder {
	const samples: BridgeTelemetrySample[] = [];
	const flushForces: boolean[] = [];
	return {
		samples,
		flushForces,
		isEnabled: (scope: BridgeTelemetryScope): boolean => scope === 'web',
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
		flush: (props?: BridgeTelemetryFlushProps): boolean => {
			flushForces.push(props?.force === true);
			return true;
		},
	};
}

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
}

function createDeferred<TValue>(): Deferred<TValue> {
	let resolveDeferred: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((resolve): void => {
		resolveDeferred = resolve;
	});
	if (resolveDeferred === null) {
		throw new Error('Deferred was not initialized.');
	}
	return {
		promise,
		resolve: resolveDeferred,
	};
}

async function flushMicrotasks(count: number): Promise<void> {
	let flushPromise = Promise.resolve();
	for (let index = 0; index < count; index += 1) {
		flushPromise = flushPromise.then((): void => {});
	}
	await flushPromise;
}

interface RegisterPackageContentDescriptorsProps {
	readonly registry: ReturnType<typeof createBridgeResourceDescriptorRegistry>;
	readonly reviewPackage: ReturnType<typeof makeBridgeReviewPackage>;
}

function registerPackageContentDescriptors(
	props: RegisterPackageContentDescriptorsProps,
): ReadonlyMap<string, BridgeAttachedResourceDescriptor> {
	const descriptorsByHandleId = new Map<string, BridgeAttachedResourceDescriptor>();
	for (const item of Object.values(props.reviewPackage.itemsById)) {
		for (const handle of [
			item.contentRoles.base,
			item.contentRoles.head,
			item.contentRoles.diff,
			item.contentRoles.file,
		]) {
			if (handle === null || handle === undefined) {
				continue;
			}
			const attachedDescriptor = attachedDescriptorForHandle(handle);
			expect(props.registry.register(attachedDescriptor)).toEqual({ ok: true });
			descriptorsByHandleId.set(handle.handleId, attachedDescriptor);
		}
	}
	return descriptorsByHandleId;
}

function attachedDescriptorForHandle(
	handle: BridgeContentHandle,
): BridgeAttachedResourceDescriptor {
	const descriptorId = `descriptor-${handle.handleId}`;
	const identity = {
		paneId: 'pane-1',
		protocol: 'review',
		sourceId: 'source-1',
		packageId: 'package-1',
		generation: handle.reviewGeneration,
		revision: 1,
	};
	const descriptor = {
		descriptorId,
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl: `agentstudio://resource/review/content/${descriptorId}?generation=1&revision=1`,
		identity,
		content: {
			mediaType: handle.mimeType,
			encoding: 'utf-8',
			expectedBytes: handle.sizeBytes,
			maxBytes: 1024,
		},
	};
	return bridgeAttachedResourceDescriptorSchema.parse({
		ref: {
			descriptorId,
			expectedProtocol: 'review',
			expectedResourceKind: 'content',
			expectedIdentity: identity,
		},
		descriptor,
	});
}

function makeUnrelatedDescriptorRef(): BridgeDescriptorRef {
	return {
		descriptorId: 'unrelated-descriptor',
		expectedProtocol: 'review',
		expectedResourceKind: 'content',
		expectedIdentity: {
			paneId: 'pane-1',
			protocol: 'review',
			sourceId: 'source-1',
			packageId: 'other-package',
			generation: 1,
			revision: 1,
		},
	};
}

function makeBridgeReviewPackageWithContentRoleBytes(
	sizeBytes: number,
): ReturnType<typeof makeBridgeReviewPackage> {
	const reviewPackage = makeBridgeReviewPackage();
	const sourceItem = reviewPackage.itemsById['item-source'];
	if (sourceItem === undefined) {
		throw new Error('expected source item fixture');
	}
	return {
		...reviewPackage,
		itemsById: {
			...reviewPackage.itemsById,
			'item-source': {
				...sourceItem,
				contentRoles: {
					...sourceItem.contentRoles,
					base: contentHandleWithSize(sourceItem.contentRoles.base, sizeBytes),
					head: contentHandleWithSize(sourceItem.contentRoles.head, sizeBytes),
				},
			},
		},
	};
}

function contentHandleWithSize(
	handle: BridgeContentHandle | null | undefined,
	sizeBytes: number,
): BridgeContentHandle | null {
	return handle === null || handle === undefined ? null : { ...handle, sizeBytes };
}
