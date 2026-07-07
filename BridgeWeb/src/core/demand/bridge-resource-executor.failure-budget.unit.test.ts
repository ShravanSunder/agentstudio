import { describe, expect, test } from 'vitest';

import type { BridgeDemandIntent } from '../models/bridge-demand-models.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
	BridgeResourceDescriptor,
} from '../models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../resources/bridge-resource-registry.js';
import { createBridgeResourceExecutor } from './bridge-resource-executor.js';

describe('bridge resource executor failure and budget cases', () => {
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
