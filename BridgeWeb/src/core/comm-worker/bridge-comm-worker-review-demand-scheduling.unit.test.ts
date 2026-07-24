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
	readonly attemptToken: number;
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

	test('resumes active work without starting stale pending membership', () => {
		const admissions: TestDemandAdmission[] = [];
		const resumedItemIds: string[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				admissions.push(admission);
				return {
					cancel: () => {},
					resume: () => resumedItemIds.push(admission.itemId),
					updateRole: () => {},
				};
			},
		});
		const initialMembership = [
			visibleMember('visible-1'),
			visibleMember('visible-2'),
			visibleMember('visible-3'),
			...Array.from(
				{ length: 10 },
				(_, index): BridgeCommWorkerDemandMember => ({
					itemId: `background-${index + 1}`,
					role: 'background',
				}),
			),
		];
		const initialResult = ledger.reconcile(initialMembership);
		const releasedAdmission = initialResult.active.find(
			({ itemId }) => itemId === 'background-1',
		);
		if (releasedAdmission === undefined) {
			throw new Error('Expected the first background Review admission.');
		}
		ledger.setSuspended(true);
		ledger.release('background-1', releasedAdmission.attemptToken, 'resident');

		ledger.setSuspended(false);

		expect(admissions).toHaveLength(12);
		expect(resumedItemIds).toHaveLength(11);
		const currentMembership = [
			...initialMembership.filter(
				({ itemId }) => itemId !== 'background-1' && itemId !== 'background-10',
			),
			{ itemId: 'current-background', role: 'background' },
		] satisfies readonly BridgeCommWorkerDemandMember[];
		ledger.reconcile(currentMembership);
		expect(admissions.at(-1)?.itemId).toBe('current-background');
		expect(admissions.map(({ itemId }) => itemId)).not.toContain('background-10');
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
		const initialResult = ledger.reconcile(initialMembership);
		const releasedAdmission = initialResult.active.find(({ itemId }) => itemId === 'background-1');
		if (releasedAdmission === undefined) {
			throw new Error('Expected the first background Review admission.');
		}

		ledger.reconcile([selectedMember('held'), ...initialMembership.slice(1)]);
		ledger.reconcile(initialMembership);
		const firstRelease = ledger.release('background-1', releasedAdmission.attemptToken, 'resident');
		const repeatedRelease = ledger.release(
			'background-1',
			releasedAdmission.attemptToken,
			'resident',
		);

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

	test('lets departed active work settle before refilling its physical position', () => {
		const admissions: TestDemandAdmission[] = [];
		const cancelledItemIds: string[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				admissions.push(admission);
				return {
					cancel: () => cancelledItemIds.push(admission.itemId),
					updateRole: () => {},
				};
			},
		});
		const membership = [
			visibleMember('visible-1'),
			visibleMember('visible-2'),
			visibleMember('visible-3'),
			...Array.from(
				{ length: 10 },
				(_, index): BridgeCommWorkerDemandMember => ({
					itemId: `background-${index + 1}`,
					role: 'background',
				}),
			),
		];
		const initialResult = ledger.reconcile(membership);
		const departingAdmission = initialResult.active.find(({ itemId }) => itemId === 'background-1');
		if (departingAdmission === undefined) {
			throw new Error('Expected the first background Review admission.');
		}

		const afterDeparture = ledger.reconcile(
			membership.filter(({ itemId }) => itemId !== departingAdmission.itemId),
		);

		expect(departingAdmission.signal.aborted).toBe(false);
		expect(cancelledItemIds).toEqual([]);
		expect(admissions).toHaveLength(12);
		expect(afterDeparture.active.map(({ itemId }) => itemId)).toContain(departingAdmission.itemId);
		expect(afterDeparture.wanted.map(({ itemId }) => itemId)).toEqual(['background-10']);

		expect(
			ledger.release(departingAdmission.itemId, departingAdmission.attemptToken, 'resident'),
		).toBe(true);
		expect(admissions.map(({ itemId }) => itemId)).toEqual([
			...membership.slice(0, 12).map(({ itemId }) => itemId),
			'background-10',
		]);
	});

	test('retains terminal background progress and restarts retry-wait only after retry-ready', () => {
		const admissions: TestDemandAdmission[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				admissions.push(admission);
				return { cancel: () => {}, updateRole: () => {} };
			},
		});
		const membership = [
			{ itemId: 'terminal', role: 'background' },
			{ itemId: 'retry', role: 'background' },
			{ itemId: 'added', role: 'background' },
		] satisfies readonly BridgeCommWorkerDemandMember[];
		ledger.reconcile(membership.slice(0, 2));
		const terminalAttempt = requireTestDemandAdmission(admissions, 0);
		const retryAttempt = requireTestDemandAdmission(admissions, 1);
		ledger.release('terminal', terminalAttempt.attemptToken, 'terminal');
		ledger.release('retry', retryAttempt.attemptToken, 'retryWait');

		ledger.reconcile(membership);
		ledger.markRetryReady('retry', retryAttempt.attemptToken);
		ledger.reconcile(membership.toReversed());

		expect(admissions.map(({ itemId }) => itemId)).toEqual(['terminal', 'retry', 'added', 'retry']);
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
		const initialResult = ledger.reconcile([visibleMember('resident'), visibleMember('active')]);
		const residentAdmission = initialResult.active.find(({ itemId }) => itemId === 'resident');
		if (residentAdmission === undefined) {
			throw new Error('Expected the resident Review admission.');
		}
		ledger.release('resident', residentAdmission.attemptToken, 'resident');

		ledger.updateGeneration(41);
		ledger.reconcile([visibleMember('active'), visibleMember('resident'), visibleMember('added')]);

		expect(startedItemIds).toEqual(['resident', 'active', 'added']);
		expect(cancelledItemIds).toEqual([]);

		ledger.updateGeneration(42);
		ledger.reconcile([visibleMember('resident'), visibleMember('active'), visibleMember('added')]);

		expect(cancelledItemIds).toEqual(['active', 'added']);
		expect(startedItemIds).toEqual(['resident', 'active', 'added', 'resident', 'active', 'added']);
	});

	test('ignores a cancelled attempt settlement after its replacement starts', () => {
		const admissions: TestDemandAdmission[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				admissions.push(admission);
				return { cancel: () => {}, updateRole: () => {} };
			},
		});
		ledger.reconcile([visibleMember('item')]);
		const firstAttempt = requireTestDemandAdmission(admissions, 0);
		ledger.invalidate('item');
		ledger.reconcile([visibleMember('item')]);
		const replacementAttempt = requireTestDemandAdmission(admissions, 1);

		const staleReleaseAccepted = ledger.release('item', firstAttempt.attemptToken, 'resident');
		const result = ledger.reconcile([visibleMember('item')]);

		expect(staleReleaseAccepted).toBe(false);
		expect(admissions).toHaveLength(2);
		expect(result.active.map(({ attemptToken }) => attemptToken)).toEqual([
			replacementAttempt.attemptToken,
		]);
	});

	test('ignores a stale retry wake after a newer attempt enters retry wait', () => {
		const admissions: TestDemandAdmission[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				admissions.push(admission);
				return { cancel: () => {}, updateRole: () => {} };
			},
		});
		ledger.reconcile([visibleMember('retry')]);
		const firstAttempt = requireTestDemandAdmission(admissions, 0);
		ledger.release('retry', firstAttempt.attemptToken, 'retryWait');
		expect(ledger.markRetryReady('retry', firstAttempt.attemptToken)).toBe(true);
		ledger.reconcile([visibleMember('retry')]);
		const replacementAttempt = requireTestDemandAdmission(admissions, 1);
		ledger.release('retry', replacementAttempt.attemptToken, 'retryWait');

		expect(ledger.markRetryReady('retry', firstAttempt.attemptToken)).toBe(false);
		ledger.reconcile([visibleMember('retry')]);
		expect(admissions).toHaveLength(2);
	});

	test('refills one vacant position after a rejected preparation', () => {
		const admissions: TestDemandAdmission[] = [];
		const ledger = createBridgeCommWorkerReviewDemandLedger({
			start: (admission) => {
				admissions.push(admission);
				return { cancel: () => {}, updateRole: () => {} };
			},
		});
		const membership = Array.from(
			{ length: 13 },
			(_, index): BridgeCommWorkerDemandMember => ({
				itemId: `background-${index + 1}`,
				role: 'background',
			}),
		);
		ledger.reconcile(membership);
		const rejectedAttempt = requireTestDemandAdmission(admissions, 0);

		expect(ledger.releaseRejected(rejectedAttempt.itemId, rejectedAttempt.attemptToken)).toBe(true);
		expect(admissions.map(({ itemId }) => itemId)).toEqual([
			...membership.slice(0, 9).map(({ itemId }) => itemId),
			'background-10',
		]);
	});
});

describe('Bridge comm worker Review production demand scheduling', () => {
	test('retains departed current-generation bodies without publishing stale Review UI', async () => {
		const itemId = 'departed-item';
		const contentItems = [makeWorkerReviewContentMetadata({ itemId })];
		const contentRequestDescriptors = [
			makeContentRequestDescriptor({ itemId, role: 'base', text: 'base body\n' }),
			makeContentRequestDescriptor({ itemId, role: 'head', text: 'head body\n' }),
		];
		const renderSemantics = [makeRenderSemantics({ itemId })];
		const rows = [{ id: itemId, index: 0, parentId: null }];
		const deferredStreams: DeferredReviewContentStream[] = [];
		const signals: AbortSignal[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const pump = createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => 0 });
		const store = createBridgeCommWorkerStore({ contentItems, rows, surface: 'review' });
		store.actions.applyViewportFact({
			firstVisibleIndex: 0,
			lastVisibleIndex: 0,
			visibleItemIds: [itemId],
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
				deferredStreams.push(deferredStream);
				signals.push(signal);
				return deferredStream.stream;
			},
			port: dispatch.port,
			pump,
			recordPreparationCompletion: () => {},
			requestPreparationDrain: () => {},
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
		expect(deferredStreams).toHaveLength(2);

		scheduling.updateRuntimeSource({
			contentItems: [],
			contentRequestDescriptors: [],
			renderSemantics: [],
			rows: [],
		});
		scheduling.scheduleDemandExecution({ cause: 'viewport', epoch: 7, store });
		for (const deferredStream of deferredStreams) {
			deferredStream.resolve('departed body\n');
		}
		await flushBridgeWorkerRuntimeContinuations();
		for (let drainIndex = 0; drainIndex < 8; drainIndex += 1) {
			pump.runUntilBudget();
			// oxlint-disable-next-line no-await-in-loop -- Each publication stage schedules the next owned continuation.
			await flushBridgeWorkerRuntimeContinuations();
		}

		expect(signals.every((signal) => !signal.aborted)).toBe(true);
		expect(store.reviewBodyRegistry.snapshot().entryCount).toBe(2);
		expect(postedMessages).toEqual([]);
	});

	test('replaces one active composite when Review metadata changes its preparation identity', async () => {
		const itemId = 'item-1';
		const contentItems = [makeWorkerReviewContentMetadata({ itemId })];
		const initialBaseDescriptor = makeContentRequestDescriptor({
			itemId,
			role: 'base',
			text: 'base body\n',
		});
		const initialHeadDescriptor = makeContentRequestDescriptor({
			itemId,
			role: 'head',
			text: 'initial head body\n',
		});
		const replacementHeadDescriptor = makeContentRequestDescriptor({
			generation: initialHeadDescriptor.reviewGeneration,
			itemId,
			role: 'head',
			text: 'replacement head body\n',
		});
		const renderSemantics = [makeRenderSemantics({ itemId })];
		const rows = [{ id: itemId, index: 0, parentId: null }];
		const attempts: Array<{
			readonly descriptorId: string;
			readonly signal: AbortSignal;
		}> = [];
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		const pump = createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => 0 });
		const store = createBridgeCommWorkerStore({ contentItems, rows, surface: 'review' });
		store.actions.applyViewportFact({
			firstVisibleIndex: 0,
			lastVisibleIndex: 0,
			visibleItemIds: [itemId],
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
				attempts.push({ descriptorId: descriptor.descriptorId, signal });
				return createDeferredReviewContentStream(descriptor).stream;
			},
			port: dispatch.port,
			pump,
			recordPreparationCompletion: () => {},
			requestPreparationDrain: () => {},
			usesProductTransport: false,
		});
		scheduling.updateRuntimeSource({
			contentItems,
			contentRequestDescriptors: [initialBaseDescriptor, initialHeadDescriptor],
			renderSemantics,
			rows,
		});
		scheduling.resume();
		scheduling.scheduleDemandExecution({ cause: 'viewport', epoch: 7, store });
		pump.runUntilBudget();
		await flushBridgeWorkerRuntimeContinuations();

		scheduling.updateRuntimeSource({
			contentItems,
			contentRequestDescriptors: [initialBaseDescriptor, replacementHeadDescriptor],
			renderSemantics,
			rows,
		});
		scheduling.scheduleDemandExecution({
			cause: 'reviewMetadata',
			epoch: 7,
			forceExecutionItemIds: [itemId],
			store,
		});
		pump.runUntilBudget();
		await flushBridgeWorkerRuntimeContinuations();

		expect(attempts.map(({ descriptorId, signal }) => [descriptorId, signal.aborted])).toEqual([
			[initialBaseDescriptor.descriptorId, true],
			[initialHeadDescriptor.descriptorId, true],
			[initialBaseDescriptor.descriptorId, false],
			[replacementHeadDescriptor.descriptorId, false],
		]);
	});

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

function requireTestDemandAdmission(
	admissions: readonly TestDemandAdmission[],
	index: number,
): TestDemandAdmission {
	const admission = admissions[index];
	if (admission === undefined) {
		throw new Error(`Expected Review demand admission at index ${index}.`);
	}
	return admission;
}
