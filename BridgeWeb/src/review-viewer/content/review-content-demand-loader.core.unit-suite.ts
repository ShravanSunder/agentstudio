import { describe, expect, test } from 'vitest';

import { createBridgeDemandScheduler } from '../../core/demand/bridge-demand-scheduler.js';
import { createBridgeResourceExecutor } from '../../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeContentHandle } from '../../foundation/review-package/bridge-review-package.js';
import {
	loadReviewItemContentResourcesThroughDemand,
	loadReviewItemContentResourcesThroughDemandResult,
} from './review-content-demand-loader.js';
import {
	createDeferred,
	type Deferred,
	flushMicrotasks,
	makeBridgeReviewPackageWithContentRoleBytes,
	makeTelemetryRecorder,
	makeTextStreamResult,
	makeUnrelatedDescriptorRef,
	registerPackageContentDescriptors,
	totalRequestCount,
} from './review-content-demand-loader.test-support.js';

describe('review content demand loader core', () => {
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
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				requestedUrls.push(descriptor.resourceUrl);
				return {
					content: makeTextStreamResult(
						descriptor.descriptorId.includes('base') ? 'base text' : 'head text',
					),
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

		expect(resources?.base?.readText()).toBe('base text');
		expect(resources?.head?.readText()).toBe('head text');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/descriptor-handle-item-source-base?generation=1&revision=1',
			'agentstudio://resource/review/content/descriptor-handle-item-source-head?generation=1&revision=1',
		]);
	});

	test('loads only the requested file-presentation side for selected modified items', async () => {
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
				if (descriptor.descriptorId.includes('base')) {
					throw new Error('base side should not be required for current file presentation');
				}
				return { content: makeTextStreamResult('current head text'), byteLength: 17 };
			},
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			presentation: { kind: 'file', version: 'current' },
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 4096,
			}),
			executor,
		});

		expect(result).toMatchObject({ status: 'ready' });
		expect(requestedDescriptorIds).toEqual(['descriptor-handle-item-source-head']);
		if (result.status !== 'ready') {
			throw new Error('expected ready current file-presentation content');
		}
		expect(result.resources.head?.readText()).toBe('current head text');
		expect(result.resources.base).toBeUndefined();
	});

	test('does not mark preview-only descriptor-backed demand as ready content', async () => {
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
			loadResource: async ({ descriptor }) => ({
				authoritative: false,
				content: makeTextStreamResult(`${descriptor.descriptorId} preview`),
				byteLength: 24,
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
		});

		expect(result).toEqual({
			status: 'deferred',
			reason: 'stale_completion',
		});
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
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => ({
				content: makeTextStreamResult(`${descriptor.descriptorId} text`),
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
						'agentstudio.bridge.content.interest': 'selected',
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
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => ({
				content: makeTextStreamResult(`${descriptor.descriptorId} text`),
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
				packageId: reviewPackage.packageId,
				reviewGeneration: reviewPackage.reviewGeneration,
				revision: reviewPackage.revision,
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
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => ({
				content: makeTextStreamResult(`${descriptor.descriptorId} text`),
				byteLength: 20,
			}),
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

		expect(result.status).toBe('ready');
		expect(scheduler.dequeueNext()).toEqual(unrelatedIntent);
	});

	test('joins selected demand to visible in-flight descriptor work instead of refetching by interest', async () => {
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
		const inFlightResultsByDescriptorId = new Map<
			string,
			Deferred<{
				readonly content: BridgeTextResourceStreamResult;
				readonly byteLength: number;
			}>
		>();
		const requestCountsByDescriptorId = new Map<string, number>();
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				requestCountsByDescriptorId.set(
					descriptor.descriptorId,
					(requestCountsByDescriptorId.get(descriptor.descriptorId) ?? 0) + 1,
				);
				const inFlightResult = createDeferred<{
					readonly content: BridgeTextResourceStreamResult;
					readonly byteLength: number;
				}>();
				inFlightResultsByDescriptorId.set(descriptor.descriptorId, inFlightResult);
				return await inFlightResult.promise;
			},
		});
		const resolveDescriptorRef = (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
			registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null;

		const visibleResultPromise = loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef,
			scheduler,
			executor,
		});
		await flushMicrotasks(4);
		expect(totalRequestCount(requestCountsByDescriptorId)).toBe(2);

		const selectedResultPromise = loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef,
			scheduler,
			executor,
		});
		await flushMicrotasks(4);

		expect(totalRequestCount(requestCountsByDescriptorId)).toBe(2);
		for (const [descriptorId, inFlightResult] of inFlightResultsByDescriptorId) {
			inFlightResult.resolve({
				content: makeTextStreamResult(`${descriptorId} materialized once`),
				byteLength: 26,
			});
		}

		await expect(visibleResultPromise).resolves.toMatchObject({ status: 'ready' });
		await expect(selectedResultPromise).resolves.toMatchObject({ status: 'ready' });
		expect(totalRequestCount(requestCountsByDescriptorId)).toBe(2);
	});

	test('keeps selected demand alive when joined visible in-flight work is aborted', async () => {
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
		const inFlightResultsByDescriptorId = new Map<
			string,
			Deferred<{
				readonly content: BridgeTextResourceStreamResult;
				readonly byteLength: number;
			}>
		>();
		const requestCountsByDescriptorId = new Map<string, number>();
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				requestCountsByDescriptorId.set(
					descriptor.descriptorId,
					(requestCountsByDescriptorId.get(descriptor.descriptorId) ?? 0) + 1,
				);
				const inFlightResult = createDeferred<{
					readonly content: BridgeTextResourceStreamResult;
					readonly byteLength: number;
				}>();
				inFlightResultsByDescriptorId.set(descriptor.descriptorId, inFlightResult);
				return await inFlightResult.promise;
			},
		});
		const resolveDescriptorRef = (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
			registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null;
		const visibleAbortController = new AbortController();

		const visibleResultPromise = loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef,
			scheduler,
			executor,
			signal: visibleAbortController.signal,
		});
		await flushMicrotasks(4);
		expect(totalRequestCount(requestCountsByDescriptorId)).toBe(2);

		const selectedResultPromise = loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef,
			scheduler,
			executor,
		});
		await flushMicrotasks(4);
		visibleAbortController.abort();
		await flushMicrotasks(4);

		for (const [descriptorId, inFlightResult] of inFlightResultsByDescriptorId) {
			inFlightResult.resolve({
				content: makeTextStreamResult(`${descriptorId} materialized after visible abort`),
				byteLength: 38,
			});
		}

		await expect(visibleResultPromise).resolves.toEqual({
			status: 'deferred',
			reason: 'aborted',
		});
		await expect(selectedResultPromise).resolves.toMatchObject({ status: 'ready' });
		expect(totalRequestCount(requestCountsByDescriptorId)).toBe(2);
	});

	test('returns byte-budget failure when combined role bytes exceed scheduler queued-byte cap', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const reviewPackage = makeBridgeReviewPackageWithContentRoleBytes(5 * 1024 * 1024);
		const registeredDescriptorsByHandleId = registerPackageContentDescriptors({
			registry,
			reviewPackage,
		});
		const requestedDescriptorIds: string[] = [];
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 8 * 1024 * 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 8 * 1024 * 1024,
			loadResource: async ({ descriptor }) => {
				requestedDescriptorIds.push(descriptor.descriptorId);
				return {
					content: makeTextStreamResult(
						descriptor.descriptorId.includes('base') ? 'large base' : 'large head',
					),
					byteLength: 10,
				};
			},
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'visible',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: 8 * 1024 * 1024,
			}),
			executor,
		});

		expect(result).toMatchObject({
			status: 'failed',
			reason: 'byte_budget_exceeded',
		});
		expect(requestedDescriptorIds).toEqual([]);
	});
});
