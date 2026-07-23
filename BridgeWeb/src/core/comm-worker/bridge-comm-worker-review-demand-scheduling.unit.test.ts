import { describe, expect, test } from 'vitest';

import type { BridgeCommWorkerDemandMember } from './bridge-comm-worker-reconciler.js';
import {
	createBridgeCommWorkerReviewDemandLedger,
	createBridgeCommWorkerReviewDemandScheduling,
	createBridgeCommWorkerVisibleSourceChurnDedupeState,
	recordBridgeCommWorkerVisibleSourceChurn,
} from './bridge-comm-worker-review-demand-scheduling.js';
import {
	createDeferredReviewContentStream,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeContentRequestDescriptor,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
	type DeferredReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

interface TestDemandAdmission {
	readonly itemId: string;
	readonly positionKind: 'dynamic' | 'reserved';
	readonly role: BridgeCommWorkerDemandMember['role'];
	readonly signal: AbortSignal;
}

describe('Bridge comm worker Review demand source-churn dedupe', () => {
	test('retains only the affected item membership for the current revision', () => {
		let state = createBridgeCommWorkerVisibleSourceChurnDedupeState();

		for (let sourceChurnRevision = 1; sourceChurnRevision <= 256; sourceChurnRevision += 1) {
			const result = recordBridgeCommWorkerVisibleSourceChurn({
				affectedItemIds: ['item-1', 'item-2'],
				identity: { epoch: 7, sourceChurnRevision },
				state,
			});

			expect(result.accepted).toBe(true);
			expect(result.unmarkedAffectedItemIds).toEqual(['item-1', 'item-2']);
			expect(result.state.currentIdentity).toEqual({ epoch: 7, sourceChurnRevision });
			expect([...result.state.markedItemIds]).toEqual(['item-1', 'item-2']);
			state = result.state;
		}

		const sameRevisionResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds: ['item-1', 'item-2', 'item-3'],
			identity: { epoch: 7, sourceChurnRevision: 256 },
			state,
		});
		expect(sameRevisionResult.accepted).toBe(true);
		expect(sameRevisionResult.unmarkedAffectedItemIds).toEqual(['item-3']);
		expect([...sameRevisionResult.state.markedItemIds]).toEqual(['item-1', 'item-2', 'item-3']);

		const repeatedRevisionResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds: ['item-1', 'item-2', 'item-3'],
			identity: { epoch: 7, sourceChurnRevision: 256 },
			state: sameRevisionResult.state,
		});
		expect(repeatedRevisionResult.accepted).toBe(true);
		expect(repeatedRevisionResult.unmarkedAffectedItemIds).toEqual([]);
		expect(repeatedRevisionResult.state.markedItemIds.size).toBe(3);
	});

	test('orders reset epochs and projection revisions without letting stale work erase dedupe', () => {
		const resetResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds: ['item-reset'],
			identity: { epoch: 8, sourceChurnRevision: null },
			state: createBridgeCommWorkerVisibleSourceChurnDedupeState(),
		});
		const firstRevisionResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds: ['item-revision'],
			identity: { epoch: 8, sourceChurnRevision: 1 },
			state: resetResult.state,
		});
		expect(firstRevisionResult.accepted).toBe(true);
		expect(firstRevisionResult.unmarkedAffectedItemIds).toEqual(['item-revision']);
		expect([...firstRevisionResult.state.markedItemIds]).toEqual(['item-revision']);

		const staleEpochResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds: ['item-stale-epoch'],
			identity: { epoch: 7, sourceChurnRevision: 99 },
			state: firstRevisionResult.state,
		});
		expect(staleEpochResult.accepted).toBe(false);
		expect(staleEpochResult.unmarkedAffectedItemIds).toEqual([]);
		expect(staleEpochResult.state).toBe(firstRevisionResult.state);

		const staleResetResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds: ['item-stale-reset'],
			identity: { epoch: 8, sourceChurnRevision: null },
			state: firstRevisionResult.state,
		});
		expect(staleResetResult.accepted).toBe(false);
		expect(staleResetResult.state).toBe(firstRevisionResult.state);

		const nextRevisionResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds: ['item-next-revision'],
			identity: { epoch: 8, sourceChurnRevision: 2 },
			state: firstRevisionResult.state,
		});
		expect(nextRevisionResult.accepted).toBe(true);
		expect([...nextRevisionResult.state.markedItemIds]).toEqual(['item-next-revision']);

		const nextEpochResetResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds: ['item-next-reset'],
			identity: { epoch: 9, sourceChurnRevision: null },
			state: nextRevisionResult.state,
		});
		expect(nextEpochResetResult.accepted).toBe(true);
		expect([...nextEpochResetResult.state.markedItemIds]).toEqual(['item-next-reset']);
	});
});

describe('Bridge comm worker Review logical-position ledger', () => {
	test('holds twelve positions with three interactive reservations and leaves the thirteenth wanted', () => {
		const admissions: TestDemandAdmission[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				admissions.push(admission);
				return { cancel: () => {}, updateRole: () => {} };
			},
		});
		const membership: BridgeCommWorkerDemandMember[] = [
			selectedMember('selected-1'),
			selectedMember('selected-2'),
			visibleMember('visible-1'),
			visibleMember('visible-2'),
			...Array.from(
				{ length: 9 },
				(_, index): BridgeCommWorkerDemandMember => ({
					itemId: `background-${index + 1}`,
					role: 'background',
				}),
			),
		];

		const result = ledger.reconcile(membership);

		expect(admissions).toHaveLength(12);
		expect(
			admissions.slice(0, 3).map(({ itemId, positionKind }) => [itemId, positionKind]),
		).toEqual([
			['selected-1', 'reserved'],
			['selected-2', 'reserved'],
			['visible-1', 'reserved'],
		]);
		expect(admissions.slice(3).every(({ positionKind }) => positionKind === 'dynamic')).toBe(true);
		expect(result.wanted.map(({ itemId }) => itemId)).toEqual(['background-9']);
	});

	test('never lends empty reserved positions to nearby, speculative, or background work', () => {
		const admissions: TestDemandAdmission[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				admissions.push(admission);
				return { cancel: () => {}, updateRole: () => {} };
			},
		});
		const membership = [
			visibleMember('visible'),
			{ itemId: 'nearby', role: 'nearby' },
			{ itemId: 'speculative', role: 'speculative' },
			...Array.from(
				{ length: 8 },
				(_, index): BridgeCommWorkerDemandMember => ({
					itemId: `background-${index + 1}`,
					role: 'background',
				}),
			),
		] satisfies readonly BridgeCommWorkerDemandMember[];

		const result = ledger.reconcile(membership);

		expect(admissions.filter(({ positionKind }) => positionKind === 'reserved')).toHaveLength(1);
		expect(admissions.filter(({ positionKind }) => positionKind === 'dynamic')).toHaveLength(9);
		expect(result.wanted.map(({ itemId }) => itemId)).toEqual(['background-8']);
	});

	test('reranks one held identity without cancellation and refills exactly once after release', () => {
		const cancelledItemIds: string[] = [];
		const updatedRoles: Array<readonly [string, BridgeCommWorkerDemandMember['role']]> = [];
		const startCountsByItemId = new Map<string, number>();
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				startCountsByItemId.set(
					admission.itemId,
					(startCountsByItemId.get(admission.itemId) ?? 0) + 1,
				);
				return {
					cancel: () => cancelledItemIds.push(admission.itemId),
					updateRole: (role) => updatedRoles.push([admission.itemId, role]),
				};
			},
		});
		const initialMembership = [
			visibleMember('held'),
			visibleMember('reserved-2'),
			visibleMember('reserved-3'),
			...Array.from(
				{ length: 10 },
				(_, index): BridgeCommWorkerDemandMember => ({
					itemId: `background-${index + 1}`,
					role: 'background',
				}),
			),
		];
		ledger.reconcile(initialMembership);

		ledger.reconcile([selectedMember('held'), ...initialMembership.slice(1)]);
		ledger.reconcile(initialMembership);
		const firstRelease = ledger.release('background-1', 'resident');
		const repeatedRelease = ledger.release('background-1', 'resident');

		expect(startCountsByItemId.get('held')).toBe(1);
		expect(cancelledItemIds).toEqual([]);
		expect(updatedRoles).toEqual([
			['held', 'selected'],
			['held', 'visible'],
		]);
		expect(firstRelease).toBe(true);
		expect(repeatedRelease).toBe(false);
		expect(startCountsByItemId.get('background-10')).toBe(1);
	});

	test('retains terminal background progress and restarts retry-wait only after retry-ready', () => {
		const startedItemIds: string[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				startedItemIds.push(admission.itemId);
				return { cancel: () => {}, updateRole: () => {} };
			},
		});
		const membership = [
			{ itemId: 'terminal', role: 'background' },
			{ itemId: 'retry', role: 'background' },
			{ itemId: 'added', role: 'background' },
		] satisfies readonly BridgeCommWorkerDemandMember[];
		ledger.reconcile(membership.slice(0, 2));
		ledger.release('terminal', 'terminal');
		ledger.release('retry', 'retryWait');

		ledger.reconcile(membership);
		ledger.markRetryReady('retry');
		ledger.reconcile(membership.toReversed());

		expect(startedItemIds).toEqual(['terminal', 'retry', 'added', 'retry']);
	});

	test('waits for a fresh membership reconciliation before restarting an invalidated identity', () => {
		const startedItemIds: string[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				startedItemIds.push(admission.itemId);
				return { cancel: () => {}, updateRole: () => {} };
			},
		});
		ledger.reconcile([visibleMember('invalidated')]);

		ledger.invalidate('invalidated');

		expect(startedItemIds).toEqual(['invalidated']);
		ledger.reconcile([visibleMember('invalidated')]);
		expect(startedItemIds).toEqual(['invalidated', 'invalidated']);
	});

	test('preserves progress within one generation and restarts identities after generation transition', () => {
		const cancelledItemIds: string[] = [];
		const startedItemIds: string[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				startedItemIds.push(admission.itemId);
				return {
					cancel: () => cancelledItemIds.push(admission.itemId),
					updateRole: () => {},
				};
			},
		});
		ledger.updateGeneration(41);
		ledger.reconcile([visibleMember('resident'), visibleMember('active')]);
		ledger.release('resident', 'resident');

		ledger.updateGeneration(41);
		ledger.reconcile([visibleMember('active'), visibleMember('resident'), visibleMember('added')]);

		expect(startedItemIds).toEqual(['resident', 'active', 'added']);
		expect(cancelledItemIds).toEqual([]);

		ledger.updateGeneration(42);
		ledger.reconcile([visibleMember('resident'), visibleMember('active'), visibleMember('added')]);

		expect(cancelledItemIds).toEqual(['active', 'added']);
		expect(startedItemIds).toEqual(['resident', 'active', 'added', 'resident', 'active', 'added']);
	});
});

describe('Bridge comm worker Review production demand scheduling', () => {
	test('promotes and demotes one held fetch without cancellation or a second start, then refills once', async () => {
		const itemIds = Array.from({ length: 13 }, (_, index) => `item-${index + 1}`);
		const contentItems = itemIds.map((itemId) => makeWorkerReviewContentMetadata({ itemId }));
		const contentRequestDescriptors = itemIds.flatMap((itemId) => [
			makeContentRequestDescriptor({ itemId, role: 'base', text: `${itemId} base\n` }),
			makeContentRequestDescriptor({ itemId, role: 'head', text: `${itemId} head\n` }),
		]);
		const renderSemantics = itemIds.map((itemId) => makeRenderSemantics({ itemId }));
		const rows = itemIds.map((itemId, index) => ({ id: itemId, index, parentId: null }));
		const deferredStreamsByItemId = new Map<string, DeferredReviewContentStream[]>();
		const signalsByItemId = new Map<string, AbortSignal[]>();
		let requestedPreparationDrainCount = 0;
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		const pump = createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => 0 });
		const store = createBridgeCommWorkerStore({ contentItems, rows, surface: 'review' });
		store.actions.applyViewportFact({
			firstVisibleIndex: 0,
			lastVisibleIndex: 2,
			visibleItemIds: itemIds.slice(0, 3),
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 1 });
		const scheduling = createBridgeCommWorkerReviewDemandScheduling({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 1024, maxWindowLines: 50 },
			createSequence: (() => {
				let sequence = 0;
				return (): number => (sequence += 1);
			})(),
			markPreparationDrainRequired: () => {},
			openReviewContent: (descriptor, signal) => {
				const deferredStream = createDeferredReviewContentStream(descriptor);
				deferredStreamsByItemId.set(descriptor.itemId, [
					...(deferredStreamsByItemId.get(descriptor.itemId) ?? []),
					deferredStream,
				]);
				signalsByItemId.set(descriptor.itemId, [
					...(signalsByItemId.get(descriptor.itemId) ?? []),
					signal,
				]);
				return deferredStream.stream;
			},
			port: dispatch.port,
			pump,
			recordPreparationCompletion: () => {},
			requestPreparationDrain: (): void => {
				requestedPreparationDrainCount += 1;
			},
			usesProductTransport: false,
		});
		scheduling.updateRuntimeSource({
			contentItems,
			contentRequestDescriptors,
			renderSemantics,
			rows,
		});
		scheduling.resume();
		scheduling.scheduleDemandExecution({ cause: 'viewport', epoch: 7, store });
		pump.runUntilBudget();
		await flushBridgeWorkerRuntimeContinuations();
		const initiallyStartedItemIds = [...deferredStreamsByItemId.keys()];
		expect(initiallyStartedItemIds).toHaveLength(12);
		expect(initiallyStartedItemIds).not.toContain('item-13');
		expect(requestedPreparationDrainCount).toBe(12);

		store.actions.applySelectedFact({ epoch: 8, itemId: 'item-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 8, sequence: 2 });
		scheduling.scheduleSelectedContentReadyPreparation({ epoch: 8, itemId: 'item-1', store });
		store.actions.applySelectedFact({ epoch: 9, itemId: 'item-2' });
		store.actions.takePendingSlicePatchEvent({ epoch: 9, sequence: 3 });
		scheduling.scheduleSelectedContentReadyPreparation({ epoch: 9, itemId: 'item-2', store });
		pump.runUntilBudget();
		await flushBridgeWorkerRuntimeContinuations();

		expect(deferredStreamsByItemId.get('item-1')).toHaveLength(2);
		expect(signalsByItemId.get('item-1')?.every((signal) => !signal.aborted)).toBe(true);
		expect(requestedPreparationDrainCount).toBe(12);

		for (const deferredStream of deferredStreamsByItemId.get('item-4') ?? []) {
			deferredStream.resolve('released item body\n');
		}
		await flushBridgeWorkerRuntimeContinuations();
		for (let drainIndex = 0; drainIndex < 12; drainIndex += 1) {
			pump.runUntilBudget();
			// oxlint-disable-next-line no-await-in-loop -- Each publication stage schedules the next owned continuation.
			await flushBridgeWorkerRuntimeContinuations();
			if (deferredStreamsByItemId.has('item-13')) break;
		}

		expect(deferredStreamsByItemId.get('item-13')).toHaveLength(2);
		expect(requestedPreparationDrainCount).toBe(14);
	});
});

function selectedMember(itemId: string): BridgeCommWorkerDemandMember {
	return { itemId, role: 'selected', selectedDemandEpoch: 1 };
}

function visibleMember(itemId: string): BridgeCommWorkerDemandMember {
	return { itemId, role: 'visible' };
}
