import { describe, expect, test } from 'vitest';

import type { BridgeDemandIntent } from '../models/bridge-demand-models.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
	BridgeResourceDescriptor,
} from '../models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../resources/bridge-resource-registry.js';
import { createBridgeBodyRegistry } from './bridge-body-registry.js';
import { createBridgeDemandScheduler } from './bridge-demand-scheduler.js';
import { createBridgeResourceExecutor } from './bridge-resource-executor.js';

describe('bridge demand runtime integration', () => {
	test('orders descriptor-backed demand through scheduler executor and materialized registry', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const firstDescriptor = makeAttachedDescriptor({
			descriptorId: 'descriptor-a',
			revision: 1,
		});
		const secondDescriptor = makeAttachedDescriptor({
			descriptorId: 'descriptor-b',
			revision: 1,
		});
		expect(registry.register(firstDescriptor)).toEqual({ ok: true });
		expect(registry.register(secondDescriptor)).toEqual({ ok: true });
		const bodyRegistry = createBridgeBodyRegistry<string>({ maxBytes: 4096 });
		const cacheHitDescriptorIds: string[] = [];
		const cacheMissDescriptorIds: string[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 4,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor, intent }) => {
				const cachedBody = bodyRegistry.get({
					cacheKey: descriptor.resourceUrl,
					freshnessKey: intent.freshnessKey,
				});
				if (cachedBody !== null) {
					cacheHitDescriptorIds.push(descriptor.descriptorId);
					return {
						content: cachedBody,
						byteLength: cachedBody.length,
					};
				}
				cacheMissDescriptorIds.push(descriptor.descriptorId);
				const materialized = `${descriptor.descriptorId}:materialized`;
				bodyRegistry.put({
					cacheKey: descriptor.resourceUrl,
					freshnessKey: intent.freshnessKey,
					body: materialized,
					byteLength: materialized.length,
				});
				return {
					content: materialized,
					byteLength: materialized.length,
				};
			},
		});
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 4,
			maxQueuedEstimatedBytes: 4096,
		});
		const visibleIntent = makeIntent(secondDescriptor.ref, {
			lane: 'visible',
			orderingKey: '002',
		});
		const selectedIntent = makeIntent(firstDescriptor.ref, {
			lane: 'foreground',
			orderingKey: '001',
		});

		expect(scheduler.enqueue({ intent: visibleIntent, estimatedBytes: 16 })).toEqual({
			ok: true,
			status: 'queued',
		});
		expect(scheduler.enqueue({ intent: selectedIntent, estimatedBytes: 16 })).toEqual({
			ok: true,
			status: 'queued',
		});

		const firstResult = await loadNextScheduledIntent({ scheduler, executor });
		const secondResult = await loadNextScheduledIntent({ scheduler, executor });

		expect(firstResult).toMatchObject({ ok: true, content: 'descriptor-a:materialized' });
		expect(secondResult).toMatchObject({ ok: true, content: 'descriptor-b:materialized' });
		const cachedResult = await executor.load(selectedIntent);

		expect(cachedResult).toMatchObject({ ok: true, content: 'descriptor-a:materialized' });
		expect(cacheMissDescriptorIds).toEqual(['descriptor-a', 'descriptor-b']);
		expect(cacheHitDescriptorIds).toEqual(['descriptor-a']);
		expect(bodyRegistry.snapshot()).toEqual({ entryCount: 2, totalBytes: 50 });
		expect(scheduler.dequeueNext()).toBeNull();
		expect(executor.inFlightCount).toBe(0);
		expect(executor.queuedLoadCount).toBe(0);
	});

	test('fails closed when scheduler demand references an unregistered descriptor', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		let fetchCount = 0;
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 4,
			maxQueuedBytes: 4096,
			loadResource: async () => {
				fetchCount += 1;
				return { content: 'must-not-fetch', byteLength: 14 };
			},
		});
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 4,
			maxQueuedEstimatedBytes: 4096,
		});
		const descriptorRef = makeAttachedDescriptor({
			descriptorId: 'unregistered-descriptor',
			revision: 1,
		}).ref;
		const intent = makeIntent(descriptorRef, {
			lane: 'foreground',
			orderingKey: '001',
		});

		expect(scheduler.enqueue({ intent, estimatedBytes: 16 })).toEqual({
			ok: true,
			status: 'queued',
		});

		const result = await loadNextScheduledIntent({ scheduler, executor });

		expect(result).toEqual({ ok: false, reason: 'descriptor_missing' });
		expect(fetchCount).toBe(0);
	});
});

async function loadNextScheduledIntent(props: {
	readonly scheduler: ReturnType<typeof createBridgeDemandScheduler>;
	readonly executor: ReturnType<typeof createBridgeResourceExecutor<string>>;
}): ReturnType<typeof props.executor.load> {
	const nextIntent = props.scheduler.dequeueNext();
	if (nextIntent === null) {
		throw new Error('Expected queued demand intent.');
	}
	return await props.executor.load(nextIntent);
}

interface MakeIntentOptions {
	readonly lane: BridgeDemandIntent['lane'];
	readonly orderingKey: string;
}

function makeIntent(ref: BridgeDescriptorRef, options: MakeIntentOptions): BridgeDemandIntent {
	return {
		descriptorRef: ref,
		lane: options.lane,
		orderingKey: options.orderingKey,
		dedupeKey: `${options.lane}:${ref.descriptorId}`,
		freshnessKey: `${ref.descriptorId}:fresh`,
		cancellationGroup: 'review:package-1',
	};
}

interface MakeAttachedDescriptorProps {
	readonly descriptorId: string;
	readonly revision: number;
}

function makeAttachedDescriptor(
	props: MakeAttachedDescriptorProps,
): BridgeAttachedResourceDescriptor {
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl: `agentstudio://resource/review/content/${props.descriptorId}?generation=1&revision=${props.revision}`,
		identity: {
			paneId: 'pane-1',
			protocol: 'review',
			sourceId: 'source-1',
			packageId: 'package-1',
			generation: 1,
			revision: props.revision,
		},
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: 64,
			maxBytes: 1024,
		},
	} satisfies BridgeResourceDescriptor;
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
