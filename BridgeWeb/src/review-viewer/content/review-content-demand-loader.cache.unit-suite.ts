import { describe, expect, test } from 'vitest';

import { createBridgeDemandScheduler } from '../../core/demand/bridge-demand-scheduler.js';
import { createBridgeResourceExecutor } from '../../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeContentHandle } from '../../foundation/review-package/bridge-review-package.js';
import { loadReviewItemContentResourcesThroughDemandResult } from './review-content-demand-loader.js';
import {
	makeTextStreamResult,
	registerPackageContentDescriptors,
} from './review-content-demand-loader.test-support.js';
import { createBridgeReviewContentRegistry } from './review-content-registry.js';

describe('review content demand loader registry cache', () => {
	test('returns ready from the content registry without demand traffic when all roles are cached', async () => {
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
				return { content: makeTextStreamResult('should not fetch'), byteLength: 15 };
			},
		});
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 8,
			maxQueuedEstimatedBytes: 4096,
		});
		const contentRegistry = createBridgeReviewContentRegistry();
		contentRegistry.storeResource({
			resource: makeCachedResource(makeBridgeContentHandle('item-source', 'base'), 'cached base'),
		});
		contentRegistry.storeResource({
			resource: makeCachedResource(makeBridgeContentHandle('item-source', 'head'), 'cached head'),
		});

		const result = await loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle: BridgeContentHandle): BridgeDescriptorRef | null =>
				registeredDescriptorsByHandleId.get(handle.handleId)?.ref ?? null,
			scheduler,
			executor,
			contentRegistry,
		});

		expect(result).toMatchObject({ status: 'ready' });
		if (result.status !== 'ready') {
			throw new Error('expected ready cached content');
		}
		expect(result.resources.base?.readText()).toBe('cached base');
		expect(result.resources.head?.readText()).toBe('cached head');
		expect(requestedUrls).toEqual([]);
		expect(scheduler.queuedIntentCount).toBe(0);
	});

	test('stores loaded role resources into the content registry after a successful demand load', async () => {
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
				content: makeTextStreamResult(
					descriptor.descriptorId.includes('base') ? 'loaded base' : 'loaded head',
				),
				byteLength: 11,
			}),
		});
		const contentRegistry = createBridgeReviewContentRegistry();

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
			contentRegistry,
		});

		expect(result).toMatchObject({ status: 'ready' });
		expect(
			contentRegistry.peekResource(makeBridgeContentHandle('item-source', 'base'))?.readText(),
		).toBe('loaded base');
		expect(
			contentRegistry.peekResource(makeBridgeContentHandle('item-source', 'head'))?.readText(),
		).toBe('loaded head');
	});

	test('partial cache coverage still performs a full demand load', async () => {
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
				return {
					content: makeTextStreamResult(
						descriptor.descriptorId.includes('base') ? 'fresh base' : 'fresh head',
					),
					byteLength: 10,
				};
			},
		});
		const contentRegistry = createBridgeReviewContentRegistry();
		contentRegistry.storeResource({
			resource: makeCachedResource(makeBridgeContentHandle('item-source', 'base'), 'cached base'),
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
			contentRegistry,
		});

		expect(result).toMatchObject({ status: 'ready' });
		expect(requestedDescriptorIds.toSorted()).toEqual([
			'descriptor-handle-item-source-base',
			'descriptor-handle-item-source-head',
		]);
	});
});

function makeCachedResource(
	handle: BridgeContentHandle,
	text: string,
): {
	readonly authoritative: boolean;
	readonly byteLength: number;
	readonly handle: BridgeContentHandle;
	readonly readText: () => string;
} {
	return {
		authoritative: true,
		byteLength: text.length,
		handle,
		readText: (): string => text,
	};
}
