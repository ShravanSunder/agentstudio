import { describe, expect, test } from 'vitest';

import { createBridgeDemandScheduler } from '../../core/demand/bridge-demand-scheduler.js';
import { createBridgeResourceExecutor } from '../../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeContentHandle } from '../../foundation/review-package/bridge-review-package.js';
import {
	demandCancellationGroupForReviewDescriptorRef,
	demandCancellationGroupsForReviewDescriptorRef,
	demandFreshnessKeyForReviewDescriptorRef,
	loadReviewItemContentResourcesThroughDemand,
	loadReviewItemContentResourcesThroughDemandResult,
	type ReviewContentDemandTelemetry,
} from './review-content-demand-loader.js';
import {
	createDeferred,
	flushMicrotasks,
	makeBridgeReviewPackageWithContentRoleBytes,
	makeTextStreamResult,
	registerPackageContentDescriptors,
} from './review-content-demand-loader.test-support.js';

describe('review content demand loader pressure and cancellation', () => {
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
			executor: createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
				registry,
				maxConcurrentLoads: 2,
				maxInFlightBytes: 4096,
				maxQueuedLoads: 8,
				maxQueuedBytes: 4096,
				loadResource: async () => {
					fetchCount += 1;
					return { content: makeTextStreamResult('must not fetch'), byteLength: 14 };
				},
			}),
		});

		expect(resources).toBeNull();
		expect(fetchCount).toBe(0);
	});

	test('rejects selected modified diff content when a sibling descriptor ref is missing', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const requestedDescriptorIds: string[] = [];
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				requestedDescriptorIds.push(descriptor.descriptorId);
				return { content: makeTextStreamResult('retained head text'), byteLength: 18 };
			},
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				handle.role === 'base'
					? null
					: (registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null),
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor,
		});

		expect(result).toEqual({ status: 'failed', reason: 'descriptor_missing' });
		expect(requestedDescriptorIds).toEqual([]);
	});

	test('rejects selected modified diff content when one side fails and the other side loads', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId.includes('head')) {
					throw new Error('head content failed');
				}
				return { content: makeTextStreamResult('base text'), byteLength: 9 };
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

		expect(result).toEqual({ status: 'failed', reason: 'load_failed' });
	});

	test('records sanitized selected load failure details when one side fails', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const telemetrySamples: ReviewContentDemandTelemetry[] = [];
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			classifyLoadFailure: (error): 'integrity_mismatch' | null =>
				error instanceof Error && error.message === 'integrity failed'
					? 'integrity_mismatch'
					: null,
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId.includes('head')) {
					throw new Error('integrity failed');
				}
				return { content: makeTextStreamResult('base text'), byteLength: 9 };
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
			onDemandTelemetry: (sample): void => {
				telemetrySamples.push(sample);
			},
		});

		expect(result).toEqual({ status: 'failed', reason: 'load_failed' });
		expect(telemetrySamples).toEqual([
			expect.objectContaining({
				resultStatus: 'failed',
				resultReason: 'load_failed',
				resultLoadFailureKind: 'integrity_mismatch',
			}),
		]);
	});

	test('aborts sibling selected modified diff loads when one side fails terminally', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const capturedBaseSignals: AbortSignal[] = [];
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
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
				await flushMicrotasks(4);
				return { content: makeTextStreamResult('base text'), byteLength: 9 };
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

	test('keeps terminal failure authoritative when no selected modified diff side loads', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId.includes('head')) {
					throw new Error('head content failed');
				}
				throw new Error('base content failed');
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

		expect(result).toEqual({ status: 'failed', reason: 'load_failed' });
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
		const blockingLoad = createDeferred<{
			readonly content: BridgeTextResourceStreamResult;
			readonly byteLength: number;
		}>();
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				if (descriptor.descriptorId === blockingDescriptor.ref.descriptorId) {
					return await blockingLoad.promise;
				}
				return { content: makeTextStreamResult('visible text'), byteLength: 12 };
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
		blockingLoad.resolve({ content: makeTextStreamResult('blocking text'), byteLength: 13 });

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
			interest: 'visible',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler,
			executor: createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
				registry,
				maxConcurrentLoads: 2,
				maxInFlightBytes: 4096,
				maxQueuedLoads: 8,
				maxQueuedBytes: 4096,
				loadResource: async () => {
					fetchCount += 1;
					return {
						content: makeTextStreamResult('must not load after partial enqueue'),
						byteLength: 36,
					};
				},
			}),
		});

		expect(result).toEqual({ status: 'deferred', reason: 'concurrency_exceeded' });
		expect(fetchCount).toBe(0);
		expect(scheduler.queuedIntentCount).toBe(0);
	});

	test('returns byte-budget failure when scheduler rejects a role by queued byte limit', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackageWithContentRoleBytes(2048);
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		let fetchCount = 0;
		const pressureSamples: unknown[] = [];
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 8,
			maxQueuedEstimatedBytes: 1024,
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler,
			executor: createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
				registry,
				maxConcurrentLoads: 2,
				maxInFlightBytes: 4096,
				maxQueuedLoads: 8,
				maxQueuedBytes: 4096,
				loadResource: async () => {
					fetchCount += 1;
					return {
						content: makeTextStreamResult('must not load after byte-budget rejection'),
						byteLength: 48,
					};
				},
			}),
			onDemandTelemetry: (sample: unknown): void => {
				pressureSamples.push(sample);
			},
		});

		expect(result).toEqual({ status: 'failed', reason: 'byte_budget_exceeded' });
		expect(fetchCount).toBe(0);
		expect(scheduler.queuedIntentCount).toBe(0);
		expect(pressureSamples).toEqual([
			expect.objectContaining({
				enqueueAcceptedCount: 0,
				enqueueRejectedCount: 1,
				droppedEstimatedBytesByLane: expect.objectContaining({ visible: 2048 }),
			}),
		]);
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
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ signal }) => {
				capturedSignals.push(signal);
				return await new Promise<{
					readonly content: BridgeTextResourceStreamResult;
					readonly byteLength: number;
				}>(() => {});
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
		const deferredMaterialized = createDeferred<{
			readonly content: BridgeTextResourceStreamResult;
			readonly byteLength: number;
		}>();
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ signal }) => {
				capturedSignals.push(signal);
				return await deferredMaterialized.promise;
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
		deferredMaterialized.resolve({
			content: makeTextStreamResult('stale selected body'),
			byteLength: 19,
		});

		expect(capturedSignals.length).toBeGreaterThan(0);
		expect(capturedSignals.every((signal): boolean => signal.aborted)).toBe(true);
		await expect(resultPromise).resolves.toEqual({ status: 'deferred', reason: 'aborted' });
	});

	test('exports selected and descriptor-wide cancellation groups for review content demand', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const descriptorRef =
			registeredDescriptorsByHandleId.get('handle-item-source-head')?.ref ?? null;
		if (descriptorRef === null) {
			throw new Error('expected registered head descriptor ref');
		}
		const freshnessKey = demandFreshnessKeyForReviewDescriptorRef(descriptorRef);

		expect(demandCancellationGroupForReviewDescriptorRef(descriptorRef)).toBe(
			`${freshnessKey}:selected`,
		);
		expect(demandCancellationGroupsForReviewDescriptorRef(descriptorRef)).toEqual([
			`${freshnessKey}:selected`,
			`${freshnessKey}:visible`,
			`${freshnessKey}:nearby`,
			`${freshnessKey}:speculative`,
		]);
	});
});
