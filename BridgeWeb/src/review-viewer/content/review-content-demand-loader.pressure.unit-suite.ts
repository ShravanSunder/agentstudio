import { describe, expect, test } from 'vitest';

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

	test('loads selected modified diff content for an available side when a sibling descriptor ref is missing', async () => {
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
			executor,
		});

		expect(result).toMatchObject({ status: 'ready' });
		if (result.status !== 'ready') {
			throw new Error('expected ready partial modified diff content');
		}
		expect(result.resources.base).toBeUndefined();
		expect(result.resources.head?.readText()).toBe('retained head text');
		expect(requestedDescriptorIds).toEqual(['descriptor-handle-item-source-head']);
	});

	test('loads selected modified diff content when one side fails and the other side loads', async () => {
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
			executor,
		});

		expect(result).toMatchObject({ status: 'ready' });
		if (result.status !== 'ready') {
			throw new Error('expected ready partial modified diff content');
		}
		expect(result.resources.base?.readText()).toBe('base text');
		expect(result.resources.head).toBeUndefined();
	});

	test('records sanitized selected load failure details for a partially ready item', async () => {
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
			executor,
			onDemandTelemetry: (sample): void => {
				telemetrySamples.push(sample);
			},
		});

		expect(result).toMatchObject({ status: 'ready' });
		if (result.status !== 'ready') {
			throw new Error('expected ready partial modified diff content');
		}
		expect(result.resources.base?.readText()).toBe('base text');
		expect(telemetrySamples).toEqual([
			expect.objectContaining({
				failedCount: 1,
				loadedCount: 1,
				resultStatus: 'ready',
				resultLoadFailureKind: 'integrity_mismatch',
			}),
		]);
	});

	test('keeps sibling selected modified diff loads alive when one side fails terminally', async () => {
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
			executor,
		});
		await flushMicrotasks(4);

		expect(result).toMatchObject({ status: 'ready' });
		if (result.status !== 'ready') {
			throw new Error('expected ready partial modified diff content');
		}
		expect(result.resources.base?.readText()).toBe('base text');
		expect(result.resources.head).toBeUndefined();
		expect(capturedBaseSignals.length).toBe(1);
		expect(capturedBaseSignals.every((signal): boolean => signal.aborted)).toBe(false);
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
			executor,
		});

		expect(result).toEqual({ status: 'failed', reason: 'load_failed' });
	});

	test('queues visible demand behind foreground pressure instead of dropping membership', async () => {
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
		const foregroundLoad = executor.load({
			descriptorRef: blockingDescriptor.ref,
			lane: 'foreground',
			orderingKey: '000',
			dedupeKey: 'blocking',
			freshnessKey: 'blocking',
			cancellationGroup: 'blocking',
		});

		const resultPromise = loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			executor,
		});
		blockingLoad.resolve({ content: makeTextStreamResult('blocking text'), byteLength: 13 });

		await foregroundLoad;
		await expect(resultPromise).resolves.toMatchObject({ status: 'ready' });
	});

	test('loads every visible member instead of rejecting by removed lane caps', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackage();
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		let fetchCount = 0;

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
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

		expect(result).toMatchObject({ status: 'ready' });
		expect(fetchCount).toBe(2);
	});

	test('returns byte-budget failure when executor per-load budget rejects a role', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackageWithContentRoleBytes(2048);
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		let fetchCount = 0;

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			executor: createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
				registry,
				maxConcurrentLoads: 2,
				maxInFlightBytes: 1024,
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
		});

		expect(result).toEqual({ status: 'failed', reason: 'byte_budget_exceeded' });
		expect(fetchCount).toBe(0);
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
			// Background is the post-package fill tier and cancels descriptor-wide fill as one group.
			`${freshnessKey}:background`,
		]);
	});
});
