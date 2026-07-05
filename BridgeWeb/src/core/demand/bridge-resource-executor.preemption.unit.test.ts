import { describe, expect, test } from 'vitest';

import type { BridgeDemandIntent } from '../models/bridge-demand-models.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
	BridgeResourceDescriptor,
} from '../models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../resources/bridge-resource-registry.js';
import { demandRankForContentRole } from './bridge-content-demand-policy.js';
import {
	createBridgeResourceExecutor,
	type BridgeResourceExecutorContent,
} from './bridge-resource-executor.js';

describe('bridge resource executor preemption', () => {
	test('starts promoted selected pending work immediately without replacing its promise', async () => {
		const registry = createRegistry();
		const firstVisibleDescriptor = makeAttachedDescriptor();
		const secondVisibleDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-2',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-2?generation=1&revision=1',
			},
		});
		const promotedDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'descriptor-3',
				resourceUrl: 'agentstudio://resource/review/content/descriptor-3?generation=1&revision=1',
			},
		});
		registry.register(firstVisibleDescriptor);
		registry.register(secondVisibleDescriptor);
		registry.register(promotedDescriptor);
		const firstVisibleStarted = createDeferred<void>();
		const secondVisibleStarted = createDeferred<void>();
		const startedDescriptorIds: string[] = [];
		const visibleSignals: AbortSignal[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor, signal }) => {
				startedDescriptorIds.push(descriptor.descriptorId);
				if (descriptor.descriptorId === firstVisibleDescriptor.descriptor.descriptorId) {
					visibleSignals.push(signal);
					firstVisibleStarted.resolve();
					return await new Promise<BridgeResourceExecutorContent<string>>(() => {});
				}
				if (descriptor.descriptorId === secondVisibleDescriptor.descriptor.descriptorId) {
					visibleSignals.push(signal);
					secondVisibleStarted.resolve();
					return await new Promise<BridgeResourceExecutorContent<string>>(() => {});
				}
				return { content: 'selected-materialized', byteLength: 21 };
			},
		});
		const firstVisibleLoad = executor.load(
			makeIntent(firstVisibleDescriptor.ref, {
				lane: 'visible',
				orderingKey: '001-in-flight-visible',
			}),
		);
		const secondVisibleLoad = executor.load(
			makeIntent(secondVisibleDescriptor.ref, {
				lane: 'visible',
				orderingKey: '002-in-flight-visible',
			}),
		);
		await Promise.all([firstVisibleStarted.promise, secondVisibleStarted.promise]);
		const sharedVisibleIntent = makeIntent(promotedDescriptor.ref, {
			dedupeKey: 'item-source:head',
			freshnessKey: 'item-source:head:revision-1',
			lane: 'visible',
			orderingKey: '999-visible-pending',
		});
		const sharedSelectedIntent = makeIntent(promotedDescriptor.ref, {
			dedupeKey: sharedVisibleIntent.dedupeKey,
			freshnessKey: sharedVisibleIntent.freshnessKey,
			lane: 'foreground',
			demandRank: 0,
			orderingKey: '000-selected-click',
		});

		const visiblePendingLoad = executor.load(sharedVisibleIntent);
		await Promise.resolve();
		const selectedLoad = executor.load(sharedSelectedIntent);

		expect(visibleSignals.some((signal): boolean => signal.aborted)).toBe(true);
		expect(startedDescriptorIds).toEqual(['descriptor-1', 'descriptor-2', 'descriptor-3']);
		expect(selectedLoad).toBe(visiblePendingLoad);
		await expect(selectedLoad).resolves.toMatchObject({
			ok: true,
			content: 'selected-materialized',
		});
		await expect(Promise.race([firstVisibleLoad, secondVisibleLoad])).resolves.toEqual({
			ok: false,
			reason: 'aborted',
		});
		expect(executor.queuedLoadCount).toBe(0);
	});

	test('preempts speculative before nearby while preserving immediate selected work', async () => {
		const registry = createRegistry();
		const immediateDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'immediate-descriptor',
				resourceUrl:
					'agentstudio://resource/review/content/immediate-descriptor?generation=1&revision=1',
			},
		});
		const nearbyDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'nearby-descriptor',
				resourceUrl:
					'agentstudio://resource/review/content/nearby-descriptor?generation=1&revision=1',
			},
		});
		const speculativeDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'speculative-descriptor',
				resourceUrl:
					'agentstudio://resource/review/content/speculative-descriptor?generation=1&revision=1',
			},
		});
		const promotedDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'promoted-descriptor',
				resourceUrl:
					'agentstudio://resource/review/content/promoted-descriptor?generation=1&revision=1',
			},
		});
		const secondPromotedDescriptor = makeAttachedDescriptor({
			descriptor: {
				descriptorId: 'second-promoted-descriptor',
				resourceUrl:
					'agentstudio://resource/review/content/second-promoted-descriptor?generation=1&revision=1',
			},
		});
		for (const attachedDescriptor of [
			immediateDescriptor,
			nearbyDescriptor,
			speculativeDescriptor,
			promotedDescriptor,
			secondPromotedDescriptor,
		]) {
			registry.register(attachedDescriptor);
		}
		const startedDescriptorIds: string[] = [];
		const startedByDescriptorId = new Map<string, Deferred<void>>();
		const materializationByDescriptorId = new Map<
			string,
			Deferred<BridgeResourceExecutorContent<string>>
		>();
		const signalByDescriptorId = new Map<string, AbortSignal>();
		for (const attachedDescriptor of [
			immediateDescriptor,
			nearbyDescriptor,
			speculativeDescriptor,
			promotedDescriptor,
			secondPromotedDescriptor,
		]) {
			startedByDescriptorId.set(attachedDescriptor.descriptor.descriptorId, createDeferred<void>());
			materializationByDescriptorId.set(
				attachedDescriptor.descriptor.descriptorId,
				createDeferred<BridgeResourceExecutorContent<string>>(),
			);
		}
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 3,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 8,
			maxQueuedBytes: 1024,
			loadResource: async ({ descriptor, signal }) => {
				startedDescriptorIds.push(descriptor.descriptorId);
				signalByDescriptorId.set(descriptor.descriptorId, signal);
				startedByDescriptorId.get(descriptor.descriptorId)?.resolve();
				const materialization = materializationByDescriptorId.get(descriptor.descriptorId);
				if (materialization === undefined) {
					throw new Error(`missing materialization for ${descriptor.descriptorId}`);
				}
				return await materialization.promise;
			},
		});

		const immediateLoad = executor.load(
			makeIntent(immediateDescriptor.ref, {
				demandRank: demandRankForContentRole('selected'),
				lane: 'foreground',
				orderingKey: '001-immediate',
			}),
		);
		const nearbyLoad = executor.load(
			makeIntent(nearbyDescriptor.ref, {
				demandRank: demandRankForContentRole('nearby'),
				lane: 'nearby',
				orderingKey: '002-nearby',
			}),
		);
		const speculativeLoad = executor.load(
			makeIntent(speculativeDescriptor.ref, {
				demandRank: demandRankForContentRole('speculative'),
				lane: 'speculative',
				orderingKey: '003-speculative',
			}),
		);
		await Promise.all([
			startedByDescriptorId.get(immediateDescriptor.descriptor.descriptorId)?.promise,
			startedByDescriptorId.get(nearbyDescriptor.descriptor.descriptorId)?.promise,
			startedByDescriptorId.get(speculativeDescriptor.descriptor.descriptorId)?.promise,
		]);

		const promotedLoad = executor.load(
			makeIntent(promotedDescriptor.ref, {
				demandRank: demandRankForContentRole('selected'),
				lane: 'foreground',
				orderingKey: '004-promoted',
			}),
		);
		await startedByDescriptorId.get(promotedDescriptor.descriptor.descriptorId)?.promise;

		expect(signalByDescriptorId.get(speculativeDescriptor.descriptor.descriptorId)?.aborted).toBe(
			true,
		);
		expect(signalByDescriptorId.get(nearbyDescriptor.descriptor.descriptorId)?.aborted).toBe(false);
		expect(signalByDescriptorId.get(immediateDescriptor.descriptor.descriptorId)?.aborted).toBe(
			false,
		);

		const secondPromotedLoad = executor.load(
			makeIntent(secondPromotedDescriptor.ref, {
				demandRank: demandRankForContentRole('selected'),
				lane: 'foreground',
				orderingKey: '005-second-promoted',
			}),
		);
		await startedByDescriptorId.get(secondPromotedDescriptor.descriptor.descriptorId)?.promise;

		expect(signalByDescriptorId.get(nearbyDescriptor.descriptor.descriptorId)?.aborted).toBe(true);
		expect(signalByDescriptorId.get(immediateDescriptor.descriptor.descriptorId)?.aborted).toBe(
			false,
		);
		expect(signalByDescriptorId.get(promotedDescriptor.descriptor.descriptorId)?.aborted).toBe(
			false,
		);
		expect(startedDescriptorIds).toEqual([
			'immediate-descriptor',
			'nearby-descriptor',
			'speculative-descriptor',
			'promoted-descriptor',
			'second-promoted-descriptor',
		]);

		for (const descriptorId of [
			immediateDescriptor.descriptor.descriptorId,
			promotedDescriptor.descriptor.descriptorId,
			secondPromotedDescriptor.descriptor.descriptorId,
		]) {
			materializationByDescriptorId.get(descriptorId)?.resolve({
				content: `${descriptorId}:materialized`,
				byteLength: 24,
			});
		}

		await expect(speculativeLoad).resolves.toEqual({ ok: false, reason: 'aborted' });
		await expect(nearbyLoad).resolves.toEqual({ ok: false, reason: 'aborted' });
		await expect(immediateLoad).resolves.toMatchObject({
			ok: true,
			content: 'immediate-descriptor:materialized',
		});
		await expect(promotedLoad).resolves.toMatchObject({
			ok: true,
			content: 'promoted-descriptor:materialized',
		});
		await expect(secondPromotedLoad).resolves.toMatchObject({
			ok: true,
			content: 'second-promoted-descriptor:materialized',
		});
		expect(executor.inFlightCount).toBe(0);
		expect(executor.queuedLoadCount).toBe(0);
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
