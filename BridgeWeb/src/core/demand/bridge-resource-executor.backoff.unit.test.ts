import { afterEach, describe, expect, test, vi } from 'vitest';

import type { BridgeDemandIntent } from '../models/bridge-demand-models.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
	BridgeResourceDescriptor,
} from '../models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../resources/bridge-resource-registry.js';
import { createBridgeResourceExecutor } from './bridge-resource-executor.js';

describe('bridge resource executor delivery failure backoff', () => {
	afterEach(() => {
		vi.useRealTimers();
	});

	test('paces retry starts after a delivery failure until the first backoff elapses', async () => {
		vi.useFakeTimers();
		let nowMilliseconds = 1_000;
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);
		let startCount = 0;
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			now: () => nowMilliseconds,
			loadResource: async () => {
				startCount += 1;
				if (startCount === 1) {
					throw new Error('transient delivery failure');
				}
				return { content: 'retried-materialized', byteLength: 20 };
			},
		});
		const intent = makeIntent(attachedDescriptor.ref);

		await expect(executor.load(intent)).resolves.toEqual({
			ok: false,
			reason: 'load_failed',
		});
		const retryLoad = executor.load(intent);
		await Promise.resolve();
		expect(startCount).toBe(1);
		expect(executor.queuedLoadCount).toBe(1);

		nowMilliseconds = 1_499;
		await vi.advanceTimersByTimeAsync(499);
		expect(startCount).toBe(1);

		nowMilliseconds = 1_500;
		await vi.advanceTimersByTimeAsync(1);

		await expect(retryLoad).resolves.toMatchObject({
			ok: true,
			content: 'retried-materialized',
		});
		expect(startCount).toBe(2);
	});

	test('bounds persistent delivery failure starts by escalating backoff windows', async () => {
		vi.useFakeTimers();
		let nowMilliseconds = 2_000;
		const registry = createRegistry();
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);
		let startCount = 0;
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 1,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			now: () => nowMilliseconds,
			loadResource: async () => {
				startCount += 1;
				throw new Error('persistent delivery failure');
			},
		});
		const intent = makeIntent(attachedDescriptor.ref);

		await expect(executor.load(intent)).resolves.toEqual({
			ok: false,
			reason: 'load_failed',
		});
		expect(startCount).toBe(1);

		const secondLoad = executor.load(intent);
		await Promise.resolve();
		nowMilliseconds = 2_499;
		await vi.advanceTimersByTimeAsync(499);
		expect(startCount).toBe(1);
		nowMilliseconds = 2_500;
		await vi.advanceTimersByTimeAsync(1);
		await expect(secondLoad).resolves.toEqual({
			ok: false,
			reason: 'load_failed',
		});
		expect(startCount).toBe(2);

		const thirdLoad = executor.load(intent);
		await Promise.resolve();
		nowMilliseconds = 4_499;
		await vi.advanceTimersByTimeAsync(1_999);
		expect(startCount).toBe(2);
		nowMilliseconds = 4_500;
		await vi.advanceTimersByTimeAsync(1);
		await expect(thirdLoad).resolves.toEqual({
			ok: false,
			reason: 'load_failed',
		});
		expect(startCount).toBe(3);

		const fourthLoad = executor.load(intent);
		await Promise.resolve();
		nowMilliseconds = 12_499;
		await vi.advanceTimersByTimeAsync(7_999);
		expect(startCount).toBe(3);
		nowMilliseconds = 12_500;
		await vi.advanceTimersByTimeAsync(1);
		await expect(fourthLoad).resolves.toEqual({
			ok: false,
			reason: 'load_failed',
		});
		expect(startCount).toBe(4);
	});
});

function createRegistry(): ReturnType<typeof createBridgeResourceDescriptorRegistry> {
	return createBridgeResourceDescriptorRegistry({
		allowedResourceKindsByProtocol: { review: new Set(['content']) },
	});
}

interface MakeIntentOptions {
	readonly freshnessKey?: string;
}

function makeIntent(ref: BridgeDescriptorRef, options: MakeIntentOptions = {}): BridgeDemandIntent {
	return {
		descriptorRef: ref,
		lane: 'foreground',
		orderingKey: '001',
		dedupeKey: ref.descriptorId,
		freshnessKey: options.freshnessKey ?? `${ref.descriptorId}:fresh`,
		cancellationGroup: 'review:package-1',
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
