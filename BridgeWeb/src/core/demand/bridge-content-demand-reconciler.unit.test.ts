import { describe, expect, test } from 'vitest';

import type { BridgeDemandIntent } from '../models/bridge-demand-models.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
} from '../models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../resources/bridge-resource-registry.js';
import { demandRankForContentRole } from './bridge-content-demand-policy.js';
import {
	reconcileBridgeContentDemand,
	type BridgeContentDemandCandidate,
} from './bridge-content-demand-reconciler.js';
import { createBridgeResourceExecutor } from './bridge-resource-executor.js';

describe('bridge content demand reconciler', () => {
	test('keeps every visible member and does not truncate membership to executor capacity', () => {
		const candidates = Array.from({ length: 16 }, (_, index): BridgeContentDemandCandidate => {
			const descriptorId = `visible-${String(index).padStart(3, '0')}`;
			return {
				role: 'visible',
				intent: makeIntent({
					descriptorId,
					lane: 'visible',
					orderingKey: `visible:${String(index).padStart(3, '0')}`,
				}),
			};
		});

		const plan = reconcileBridgeContentDemand({
			candidates,
			generation: 7,
			inFlightDedupeKeys: new Set(),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: [],
		});

		expect(plan.generation).toBe(7);
		expect(plan.entries.map((entry) => entry.intent.descriptorRef.descriptorId)).toEqual(
			candidates.map((candidate) => candidate.intent.descriptorRef.descriptorId),
		);
		expect(plan.operations.filter((operation) => operation.kind === 'enqueue')).toHaveLength(16);
	});

	test('dedupes to the highest role and orders selected ahead of same-lane visible work', () => {
		const sharedVisible = makeCandidate({ descriptorId: 'shared', role: 'visible' });
		const sharedSelected = makeCandidate({
			descriptorId: 'shared',
			role: 'selected',
			orderingKey: 'z-selected',
		});
		const earlyVisible = makeCandidate({
			descriptorId: 'early-visible',
			role: 'visible',
			orderingKey: 'a-visible',
		});

		const plan = reconcileBridgeContentDemand({
			candidates: [sharedVisible, earlyVisible, sharedSelected],
			generation: 1,
			inFlightDedupeKeys: new Set(),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: [],
		});

		expect(plan.entries.map((entry) => `${entry.role}:${entry.intent.dedupeKey}`)).toEqual([
			'selected:content:shared',
			'visible:content:early-visible',
		]);
	});

	test('orders all content tiers by selected-first demand rank before ordering key', () => {
		const candidates = [
			makeCandidate({
				descriptorId: 'background',
				role: 'background',
				orderingKey: 'a-background',
			}),
			makeCandidate({
				descriptorId: 'speculative',
				role: 'speculative',
				orderingKey: 'a-speculative',
			}),
			makeCandidate({
				descriptorId: 'nearby',
				role: 'nearby',
				orderingKey: 'a-nearby',
			}),
			makeCandidate({
				descriptorId: 'visible',
				role: 'visible',
				orderingKey: 'a-visible',
			}),
			makeCandidate({
				descriptorId: 'selected',
				role: 'selected',
				orderingKey: 'z-selected',
			}),
		];

		const plan = reconcileBridgeContentDemand({
			candidates,
			generation: 1,
			inFlightDedupeKeys: new Set(),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: [],
		});

		expect(plan.entries.map((entry) => entry.role)).toEqual([
			'selected',
			'visible',
			'nearby',
			'speculative',
			'background',
		]);
		expect(plan.entries.map((entry) => entry.rank)).toEqual(
			plan.entries.map((entry) => demandRankForContentRole(entry.role)),
		);
		expect(plan.entries.map((entry) => entry.intent.demandRank)).toEqual(
			plan.entries.map((entry) => demandRankForContentRole(entry.role)),
		);
	});

	test('treats loadedSet as cache-present and excludes cache hits from membership', () => {
		const loadedCandidate = makeCandidate({ descriptorId: 'loaded', role: 'selected' });
		const unloadedCandidate = makeCandidate({ descriptorId: 'unloaded', role: 'visible' });

		const plan = reconcileBridgeContentDemand({
			candidates: [loadedCandidate, unloadedCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set(),
			loadedDedupeKeys: new Set([loadedCandidate.intent.dedupeKey]),
			paused: false,
			previousEntries: [],
		});

		expect(plan.entries.map((entry) => entry.intent.dedupeKey)).toEqual([
			unloadedCandidate.intent.dedupeKey,
		]);
		expect(plan.operations).toContainEqual({
			kind: 'cacheHit',
			dedupeKey: loadedCandidate.intent.dedupeKey,
			role: 'selected',
		});
	});

	test('treats speculative and background loaded sets as cache-present without membership', () => {
		const speculativeCandidate = makeCandidate({
			descriptorId: 'speculative-loaded',
			role: 'speculative',
		});
		const backgroundCandidate = makeCandidate({
			descriptorId: 'background-loaded',
			role: 'background',
		});

		const plan = reconcileBridgeContentDemand({
			candidates: [backgroundCandidate, speculativeCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set(),
			loadedDedupeKeys: new Set([
				speculativeCandidate.intent.dedupeKey,
				backgroundCandidate.intent.dedupeKey,
			]),
			paused: false,
			previousEntries: [],
		});

		expect(plan.entries).toEqual([]);
		expect(plan.operations).toEqual([
			{
				kind: 'cacheHit',
				dedupeKey: backgroundCandidate.intent.dedupeKey,
				role: 'background',
			},
			{
				kind: 'cacheHit',
				dedupeKey: speculativeCandidate.intent.dedupeKey,
				role: 'speculative',
			},
		]);
	});

	test('resets the epoch and cancels previous generation members', () => {
		const previousCandidate = makeCandidate({ descriptorId: 'old', role: 'visible' });
		const previousPlan = reconcileBridgeContentDemand({
			candidates: [previousCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set(),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: [],
		});

		const nextCandidate = makeCandidate({ descriptorId: 'new', role: 'selected' });
		const nextPlan = reconcileBridgeContentDemand({
			candidates: [nextCandidate],
			generation: 2,
			inFlightDedupeKeys: new Set(),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: previousPlan.entries,
		});

		expect(nextPlan.entries.map((entry) => entry.generation)).toEqual([2]);
		expect(nextPlan.operations).toContainEqual({
			kind: 'cancel',
			cancellationGroup: previousCandidate.intent.cancellationGroup,
			dedupeKey: previousCandidate.intent.dedupeKey,
			reason: 'generation-reset',
		});
	});

	test('pause gates below-selected starts while selected stays start-eligible', () => {
		const selectedCandidate = makeCandidate({ descriptorId: 'selected', role: 'selected' });
		const visibleCandidate = makeCandidate({ descriptorId: 'visible', role: 'visible' });

		const plan = reconcileBridgeContentDemand({
			candidates: [visibleCandidate, selectedCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set(),
			loadedDedupeKeys: new Set(),
			paused: true,
			previousEntries: [],
		});

		expect(
			plan.entries.map((entry) => ({
				role: entry.role,
				startEligible: entry.startEligible,
			})),
		).toEqual([
			{ role: 'selected', startEligible: true },
			{ role: 'visible', startEligible: false },
		]);
	});

	test('promotes retained members instead of restarting them', () => {
		const previousCandidate = makeCandidate({ descriptorId: 'same', role: 'nearby' });
		const previousPlan = reconcileBridgeContentDemand({
			candidates: [previousCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set([previousCandidate.intent.dedupeKey]),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: [],
		});
		const promotedCandidate = makeCandidate({ descriptorId: 'same', role: 'selected' });

		const nextPlan = reconcileBridgeContentDemand({
			candidates: [promotedCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set([promotedCandidate.intent.dedupeKey]),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: previousPlan.entries,
		});

		expect(nextPlan.operations).toContainEqual({
			kind: 'promote',
			dedupeKey: promotedCandidate.intent.dedupeKey,
			fromRole: 'nearby',
			toRole: 'selected',
		});
		expect(nextPlan.operations.some((operation) => operation.kind === 'enqueue')).toBe(false);
	});

	test('promotes and demotes retained speculative and background members without restart', () => {
		const previousBackgroundCandidate = makeCandidate({
			descriptorId: 'same-background',
			role: 'background',
		});
		const previousBackgroundPlan = reconcileBridgeContentDemand({
			candidates: [previousBackgroundCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set([previousBackgroundCandidate.intent.dedupeKey]),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: [],
		});
		const promotedSpeculativeCandidate = makeCandidate({
			descriptorId: 'same-background',
			role: 'speculative',
		});

		const promotedPlan = reconcileBridgeContentDemand({
			candidates: [promotedSpeculativeCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set([promotedSpeculativeCandidate.intent.dedupeKey]),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: previousBackgroundPlan.entries,
		});

		expect(promotedPlan.operations).toContainEqual({
			kind: 'promote',
			dedupeKey: promotedSpeculativeCandidate.intent.dedupeKey,
			fromRole: 'background',
			toRole: 'speculative',
		});
		expect(promotedPlan.operations.some((operation) => operation.kind === 'enqueue')).toBe(false);

		const previousSpeculativeCandidate = makeCandidate({
			descriptorId: 'same-speculative',
			role: 'speculative',
		});
		const previousSpeculativePlan = reconcileBridgeContentDemand({
			candidates: [previousSpeculativeCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set([previousSpeculativeCandidate.intent.dedupeKey]),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: [],
		});
		const demotedBackgroundCandidate = makeCandidate({
			descriptorId: 'same-speculative',
			role: 'background',
		});

		const demotedPlan = reconcileBridgeContentDemand({
			candidates: [demotedBackgroundCandidate],
			generation: 1,
			inFlightDedupeKeys: new Set([demotedBackgroundCandidate.intent.dedupeKey]),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: previousSpeculativePlan.entries,
		});

		expect(demotedPlan.operations).toContainEqual({
			kind: 'demote',
			dedupeKey: demotedBackgroundCandidate.intent.dedupeKey,
			fromRole: 'speculative',
			toRole: 'background',
		});
		expect(demotedPlan.operations.some((operation) => operation.kind === 'enqueue')).toBe(false);
	});

	test('feeds generation-stamped plan intents into the existing executor', async () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const attachedDescriptors = [
			makeAttachedDescriptor('visible'),
			makeAttachedDescriptor('selected'),
		];
		for (const attachedDescriptor of attachedDescriptors) {
			expect(registry.register(attachedDescriptor)).toEqual({ ok: true });
		}
		const startedDescriptorIds: string[] = [];
		const executor = createBridgeResourceExecutor<string>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 1024,
			maxQueuedLoads: 4,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				startedDescriptorIds.push(descriptor.descriptorId);
				return { content: descriptor.descriptorId, byteLength: 16 };
			},
		});
		const plan = reconcileBridgeContentDemand({
			candidates: [
				{
					role: 'visible',
					intent: makeIntent({ descriptorId: 'visible', lane: 'visible' }),
				},
				{
					role: 'selected',
					intent: makeIntent({ descriptorId: 'selected', lane: 'foreground' }),
				},
			],
			generation: 3,
			inFlightDedupeKeys: new Set(),
			loadedDedupeKeys: new Set(),
			paused: false,
			previousEntries: [],
		});

		const results = await Promise.all(plan.entries.map((entry) => executor.load(entry.intent)));

		expect(startedDescriptorIds).toEqual(['selected', 'visible']);
		expect(results.every((result) => result.ok)).toBe(true);
	});
});

function makeCandidate(props: {
	readonly descriptorId: string;
	readonly role: BridgeContentDemandCandidate['role'];
	readonly orderingKey?: string;
}): BridgeContentDemandCandidate {
	return {
		role: props.role,
		intent: makeIntent({
			descriptorId: props.descriptorId,
			lane: laneForRole(props.role),
			...(props.orderingKey === undefined ? {} : { orderingKey: props.orderingKey }),
		}),
	};
}

function laneForRole(role: BridgeContentDemandCandidate['role']): BridgeDemandIntent['lane'] {
	switch (role) {
		case 'selected':
			return 'foreground';
		case 'visible':
			return 'visible';
		case 'nearby':
			return 'nearby';
		case 'speculative':
			return 'speculative';
		case 'background':
			return 'idle';
	}
	throw new Error(`Unhandled content demand role: ${String(role)}`);
}

function makeIntent(props: {
	readonly descriptorId: string;
	readonly lane: BridgeDemandIntent['lane'];
	readonly orderingKey?: string;
}): BridgeDemandIntent {
	return {
		descriptorRef: makeDescriptorRef(props.descriptorId),
		lane: props.lane,
		orderingKey: props.orderingKey ?? `order:${props.descriptorId}`,
		dedupeKey: `content:${props.descriptorId}`,
		freshnessKey: `fresh:${props.descriptorId}`,
		cancellationGroup: `cancel:${props.descriptorId}`,
	};
}

function makeDescriptorRef(descriptorId: string): BridgeDescriptorRef {
	return {
		descriptorId,
		expectedProtocol: 'review',
		expectedResourceKind: 'content',
		expectedIdentity: {
			paneId: 'pane-1',
			protocol: 'review',
			sourceId: 'source-1',
			packageId: 'package-1',
			generation: 1,
			revision: 1,
		},
	};
}

function makeAttachedDescriptor(descriptorId: string): BridgeAttachedResourceDescriptor {
	const identity = makeDescriptorRef(descriptorId).expectedIdentity;
	return bridgeAttachedResourceDescriptorSchema.parse({
		ref: makeDescriptorRef(descriptorId),
		descriptor: {
			descriptorId,
			protocol: 'review',
			resourceKind: 'content',
			resourceUrl: `agentstudio://resource/review/content/${descriptorId}?generation=1&revision=1`,
			identity,
			content: {
				mediaType: 'text/plain',
				encoding: 'utf-8',
				expectedBytes: 16,
				maxBytes: 1024,
			},
		},
	});
}
