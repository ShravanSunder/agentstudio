import { bridgeContentDemandExecutionPolicy } from '../demand/bridge-content-demand-policy.js';
import type {
	BridgeCommWorkerDemandExecutionScheduleRequest,
	BridgeCommWorkerReviewMetadataResetScheduleRequest,
	BridgeCommWorkerReviewRuntimeSource,
	BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import {
	reconcileBridgeCommWorkerDemandMembership,
	type BridgeCommWorkerDemandMember,
} from './bridge-comm-worker-reconciler.js';
import {
	enqueueBridgeWorkerReviewContentReadyPreparation,
	enqueueSelectedBridgeWorkerReviewContentReadyPreparation,
	reviewItemPreparationIdentity,
	type BridgeWorkerReviewContentReadyPreparationSettlement,
} from './bridge-comm-worker-review-preparation.js';
import { canRenderBridgeWorkerReviewContentForSemantics } from './bridge-comm-worker-review-runtime.js';
import { enqueueBridgeCommWorkerReviewSourceReset } from './bridge-comm-worker-review-source-reset.js';
import type {
	BridgeCommWorkerStore,
	BridgeCommWorkerStoreState,
} from './bridge-comm-worker-store.js';
import type { BridgeCommWorkerTelemetryRecorder } from './bridge-comm-worker-telemetry.js';
import type { WorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import {
	createSharedBridgeWorkerReviewContentResourceFetch,
	type BridgeWorkerReviewContentOpen,
} from './bridge-worker-review-content-fetch.js';

interface CreateBridgeCommWorkerReviewDemandSchedulingProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly createSequence: () => number;
	readonly isWorkAdmitted?: () => boolean;
	readonly markPreparationDrainRequired: () => void;
	readonly now?: () => number;
	readonly openReviewContent?: BridgeWorkerReviewContentOpen;
	readonly port: BridgeCommWorkerPort;
	readonly pump: WorkerContentPreparationPump;
	readonly recordPreparationCompletion: (completion: Promise<void>) => void;
	readonly requestPreparationDrain: () => void;
	readonly scheduleRetryWake?: (delayMilliseconds: number, wake: () => void) => void;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
	readonly usesProductTransport: boolean;
	readonly workSignal?: () => AbortSignal;
}

export interface BridgeCommWorkerReviewDemandScheduling {
	readonly resume: () => void;
	readonly scheduleDemandExecution: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => boolean;
	readonly scheduleMetadataReset: (
		request: BridgeCommWorkerReviewMetadataResetScheduleRequest,
	) => void;
	readonly scheduleSelectedContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly suspend: () => void;
	readonly updateRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource) => void;
	readonly updateWorkerDerivationEpoch: (workerDerivationEpoch: number) => void;
}

export interface BridgeCommWorkerVisibleSourceChurnIdentity {
	readonly epoch: number;
	readonly sourceChurnRevision: number | null;
}

export interface BridgeCommWorkerVisibleSourceChurnDedupeState {
	readonly currentIdentity: BridgeCommWorkerVisibleSourceChurnIdentity | null;
	readonly markedItemIds: ReadonlySet<string>;
}

interface RecordBridgeCommWorkerVisibleSourceChurnProps {
	readonly affectedItemIds: readonly string[];
	readonly identity: BridgeCommWorkerVisibleSourceChurnIdentity;
	readonly state: BridgeCommWorkerVisibleSourceChurnDedupeState;
}

export interface BridgeCommWorkerVisibleSourceChurnRecordResult {
	readonly accepted: boolean;
	readonly state: BridgeCommWorkerVisibleSourceChurnDedupeState;
	readonly unmarkedAffectedItemIds: readonly string[];
}

export type BridgeCommWorkerReviewDemandPositionKind = 'dynamic' | 'reserved';

export interface BridgeCommWorkerReviewDemandAdmission {
	readonly attemptToken: number;
	readonly itemId: string;
	readonly positionKind: BridgeCommWorkerReviewDemandPositionKind;
	readonly role: BridgeCommWorkerDemandMember['role'];
	readonly signal: AbortSignal;
}

export interface BridgeCommWorkerReviewDemandStartHandle {
	readonly cancel: () => void;
	readonly pause?: () => void;
	readonly resume?: () => void;
	readonly updateRole: (role: BridgeCommWorkerDemandMember['role']) => void;
}

export interface BridgeCommWorkerReviewDemandLedger {
	readonly invalidate: (
		itemId: string,
		activeAttempt?:
			| 'cancel'
			| {
					readonly preserveIfPreparationIdentity: string;
			  },
	) => void;
	readonly markRetryReady: (itemId: string, attemptToken?: number) => boolean;
	readonly setSuspended: (suspended: boolean) => void;
	readonly updateGeneration: (generation: number) => void;
	readonly reconcile: (membership: readonly BridgeCommWorkerDemandMember[]) => {
		readonly active: readonly BridgeCommWorkerReviewDemandAdmission[];
		readonly started: readonly BridgeCommWorkerReviewDemandAdmission[];
		readonly wanted: readonly BridgeCommWorkerDemandMember[];
	};
	readonly release: (
		itemId: string,
		attemptToken: number,
		disposition: BridgeWorkerReviewContentReadyPreparationSettlement,
	) => boolean;
	readonly releaseRejected: (itemId: string, attemptToken: number) => boolean;
}

interface ActiveBridgeCommWorkerReviewDemandRecord {
	readonly abortController: AbortController;
	readonly attemptToken: number;
	readonly handle: BridgeCommWorkerReviewDemandStartHandle;
	readonly itemId: string;
	readonly positionKind: BridgeCommWorkerReviewDemandPositionKind;
	readonly preparationIdentity: string | null;
	role: BridgeCommWorkerDemandMember['role'];
}

export function createBridgeCommWorkerReviewDemandLedger(props: {
	readonly resolvePreparationIdentity?: (itemId: string) => string;
	readonly start: (
		admission: BridgeCommWorkerReviewDemandAdmission,
	) => BridgeCommWorkerReviewDemandStartHandle;
}): BridgeCommWorkerReviewDemandLedger {
	const activeRecordsByItemId = new Map<string, ActiveBridgeCommWorkerReviewDemandRecord>();
	const completedItemIds = new Set<string>();
	const retryWaitingAttemptTokenByItemId = new Map<string, number>();
	let latestMembership: readonly BridgeCommWorkerDemandMember[] = [];
	let suspended = false;
	let currentGeneration: number | null = null;
	let nextAttemptToken = 1;

	const startMember = (
		member: BridgeCommWorkerDemandMember,
		positionKind: BridgeCommWorkerReviewDemandPositionKind,
	): BridgeCommWorkerReviewDemandAdmission => {
		const abortController = new AbortController();
		const attemptToken = nextAttemptToken;
		nextAttemptToken += 1;
		const admission: BridgeCommWorkerReviewDemandAdmission = {
			attemptToken,
			itemId: member.itemId,
			positionKind,
			role: member.role,
			signal: abortController.signal,
		};
		activeRecordsByItemId.set(member.itemId, {
			abortController,
			attemptToken,
			handle: props.start(admission),
			itemId: member.itemId,
			positionKind,
			preparationIdentity: props.resolvePreparationIdentity?.(member.itemId) ?? null,
			role: member.role,
		});
		return admission;
	};

	const reconcile = (
		membership: readonly BridgeCommWorkerDemandMember[],
	): ReturnType<BridgeCommWorkerReviewDemandLedger['reconcile']> => {
		latestMembership = membership;
		const memberByItemId = new Map(membership.map((member) => [member.itemId, member]));
		for (const [itemId, activeRecord] of activeRecordsByItemId) {
			const currentMember = memberByItemId.get(itemId);
			if (currentMember === undefined) {
				activeRecord.abortController.abort('review_demand_identity_invalidated');
				activeRecord.handle.cancel();
				activeRecordsByItemId.delete(itemId);
				continue;
			}
			if (currentMember.role !== activeRecord.role) {
				activeRecord.role = currentMember.role;
				activeRecord.handle.updateRole(currentMember.role);
			}
		}
		const pendingMembers = membership.filter(
			(member) =>
				!activeRecordsByItemId.has(member.itemId) &&
				!completedItemIds.has(member.itemId) &&
				!retryWaitingAttemptTokenByItemId.has(member.itemId),
		);
		if (suspended) {
			return {
				active: [...activeRecordsByItemId.values()].map((record) => ({
					attemptToken: record.attemptToken,
					itemId: record.itemId,
					positionKind: record.positionKind,
					role: record.role,
					signal: record.abortController.signal,
				})),
				started: [],
				wanted: pendingMembers,
			};
		}
		let availableReservedPositions =
			3 -
			[...activeRecordsByItemId.values()].filter(({ positionKind }) => positionKind === 'reserved')
				.length;
		let availableDynamicPositions =
			9 -
			[...activeRecordsByItemId.values()].filter(({ positionKind }) => positionKind === 'dynamic')
				.length;
		const startedItemIds = new Set<string>();
		const startedAdmissions: BridgeCommWorkerReviewDemandAdmission[] = [];
		for (const member of pendingMembers) {
			if (availableReservedPositions === 0 || !roleCanUseReservedPosition(member.role)) {
				continue;
			}
			startedAdmissions.push(startMember(member, 'reserved'));
			startedItemIds.add(member.itemId);
			availableReservedPositions -= 1;
		}
		for (const member of pendingMembers) {
			if (availableDynamicPositions === 0) break;
			if (startedItemIds.has(member.itemId)) continue;
			startedAdmissions.push(startMember(member, 'dynamic'));
			startedItemIds.add(member.itemId);
			availableDynamicPositions -= 1;
		}
		return {
			active: [...activeRecordsByItemId.values()].map((record) => ({
				attemptToken: record.attemptToken,
				itemId: record.itemId,
				positionKind: record.positionKind,
				role: record.role,
				signal: record.abortController.signal,
			})),
			started: startedAdmissions,
			wanted: pendingMembers.filter((member) => !startedItemIds.has(member.itemId)),
		};
	};

	return {
		invalidate: (itemId, activeAttempt = 'cancel'): void => {
			const activeRecord = activeRecordsByItemId.get(itemId);
			const shouldCancelActiveAttempt =
				activeRecord !== undefined &&
				(activeAttempt === 'cancel' ||
					activeRecord.preparationIdentity !== activeAttempt.preserveIfPreparationIdentity);
			if (activeRecord !== undefined && shouldCancelActiveAttempt) {
				activeRecord.abortController.abort('review_demand_identity_invalidated');
				activeRecord.handle.cancel();
				activeRecordsByItemId.delete(itemId);
			}
			completedItemIds.delete(itemId);
			retryWaitingAttemptTokenByItemId.delete(itemId);
			latestMembership = latestMembership.filter((member) => member.itemId !== itemId);
		},
		markRetryReady: (itemId, attemptToken): boolean => {
			const waitingAttemptToken = retryWaitingAttemptTokenByItemId.get(itemId);
			if (waitingAttemptToken === undefined) return false;
			if (attemptToken !== undefined && waitingAttemptToken !== attemptToken) return false;
			retryWaitingAttemptTokenByItemId.delete(itemId);
			return true;
		},
		reconcile,
		setSuspended: (nextSuspended): void => {
			if (suspended === nextSuspended) return;
			suspended = nextSuspended;
			for (const activeRecord of activeRecordsByItemId.values()) {
				if (suspended) {
					activeRecord.handle.pause?.();
				} else {
					activeRecord.handle.resume?.();
				}
			}
			if (!suspended) reconcile(latestMembership);
		},
		updateGeneration: (generation): void => {
			if (currentGeneration === generation) return;
			currentGeneration = generation;
			for (const activeRecord of activeRecordsByItemId.values()) {
				activeRecord.abortController.abort('review_demand_generation_changed');
				activeRecord.handle.cancel();
			}
			activeRecordsByItemId.clear();
			completedItemIds.clear();
			retryWaitingAttemptTokenByItemId.clear();
			latestMembership = [];
		},
		release: (itemId, attemptToken, disposition): boolean => {
			const activeRecord = activeRecordsByItemId.get(itemId);
			if (activeRecord?.attemptToken !== attemptToken) return false;
			activeRecordsByItemId.delete(itemId);
			if (disposition === 'invalidated') {
				latestMembership = latestMembership.filter((member) => member.itemId !== itemId);
				return true;
			}
			if (disposition === 'teardown') return true;
			if (disposition === 'retryWait') {
				retryWaitingAttemptTokenByItemId.set(itemId, attemptToken);
			} else {
				completedItemIds.add(itemId);
			}
			reconcile(latestMembership);
			return true;
		},
		releaseRejected: (itemId, attemptToken): boolean => {
			const activeRecord = activeRecordsByItemId.get(itemId);
			if (activeRecord?.attemptToken !== attemptToken) return false;
			activeRecordsByItemId.delete(itemId);
			latestMembership = latestMembership.filter((member) => member.itemId !== itemId);
			reconcile(latestMembership);
			return true;
		},
	};
}

function roleCanUseReservedPosition(role: BridgeCommWorkerDemandMember['role']): boolean {
	return role === 'selected' || role === 'visible';
}

export function createBridgeCommWorkerVisibleSourceChurnDedupeState(): BridgeCommWorkerVisibleSourceChurnDedupeState {
	return {
		currentIdentity: null,
		markedItemIds: new Set(),
	};
}

export function recordBridgeCommWorkerVisibleSourceChurn(
	props: RecordBridgeCommWorkerVisibleSourceChurnProps,
): BridgeCommWorkerVisibleSourceChurnRecordResult {
	const identityOrder = compareBridgeCommWorkerVisibleSourceChurnIdentity(
		props.identity,
		props.state.currentIdentity,
	);
	if (identityOrder < 0) {
		return {
			accepted: false,
			state: props.state,
			unmarkedAffectedItemIds: [],
		};
	}
	const affectedItemIds = [...new Set(props.affectedItemIds)];
	if (identityOrder > 0) {
		return {
			accepted: true,
			state: {
				currentIdentity: props.identity,
				markedItemIds: new Set(affectedItemIds),
			},
			unmarkedAffectedItemIds: affectedItemIds,
		};
	}
	const unmarkedAffectedItemIds = affectedItemIds.filter(
		(itemId) => !props.state.markedItemIds.has(itemId),
	);
	if (unmarkedAffectedItemIds.length === 0) {
		return {
			accepted: true,
			state: props.state,
			unmarkedAffectedItemIds,
		};
	}
	return {
		accepted: true,
		state: {
			currentIdentity: props.state.currentIdentity,
			markedItemIds: new Set([...props.state.markedItemIds, ...unmarkedAffectedItemIds]),
		},
		unmarkedAffectedItemIds,
	};
}

function compareBridgeCommWorkerVisibleSourceChurnIdentity(
	incomingIdentity: BridgeCommWorkerVisibleSourceChurnIdentity,
	currentIdentity: BridgeCommWorkerVisibleSourceChurnIdentity | null,
): number {
	if (currentIdentity === null) return 1;
	if (incomingIdentity.epoch !== currentIdentity.epoch) {
		return incomingIdentity.epoch > currentIdentity.epoch ? 1 : -1;
	}
	if (incomingIdentity.sourceChurnRevision === currentIdentity.sourceChurnRevision) return 0;
	if (incomingIdentity.sourceChurnRevision === null) return -1;
	if (currentIdentity.sourceChurnRevision === null) return 1;
	return incomingIdentity.sourceChurnRevision > currentIdentity.sourceChurnRevision ? 1 : -1;
}

interface BridgeCommWorkerVisibleSourceChurnAdmission {
	readonly accepted: boolean;
	readonly sourceChurnItemIds: ReadonlySet<string>;
}

export function createBridgeCommWorkerReviewDemandScheduling(
	props: CreateBridgeCommWorkerReviewDemandSchedulingProps,
): BridgeCommWorkerReviewDemandScheduling {
	const defaultWorkSignal = new AbortController().signal;
	const isWorkAdmitted = props.isWorkAdmitted ?? bridgeCommWorkerWorkIsAdmitted;
	const paneWorkSignal = props.workSignal ?? ((): AbortSignal => defaultWorkSignal);
	let surfaceActive = false;
	let surfaceWorkLifecycle = createBridgeCommWorkerReviewSurfaceWorkLifecycle(paneWorkSignal());
	const isReviewWorkAdmitted = (): boolean => surfaceActive && isWorkAdmitted();
	let reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource = {
		contentItems: [],
		contentRequestDescriptors: [],
		renderSemantics: [],
		rows: [],
	};
	let visibleSourceChurnDedupeState = createBridgeCommWorkerVisibleSourceChurnDedupeState();
	let latestDemandExecutionRequest: BridgeCommWorkerDemandExecutionScheduleRequest | null = null;
	let latestMetadataResetRequest: BridgeCommWorkerReviewMetadataResetScheduleRequest | null = null;
	let activeSourceResetEpoch: number | null = null;
	let activeWorkerDerivationEpoch: number | null = null;
	let latestSchedulingStore: BridgeCommWorkerStore | null = null;
	let latestSchedulingEpoch: number | null = null;
	let currentMembershipByItemId = new Map<string, BridgeCommWorkerDemandMember>();
	let previousFirstVisibleOrderedIndex: number | null = null;
	const retryAttemptByItemId = new Map<string, number>();
	const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
		openContent: props.openReviewContent,
		resolveBodyRegistry: () => latestSchedulingStore?.reviewBodyRegistry,
	});
	const scheduleRetryWake =
		props.scheduleRetryWake ??
		((delayMilliseconds: number, wake: () => void): void => {
			setTimeout(wake, delayMilliseconds);
		});

	const reviewDemandLedger = createBridgeCommWorkerReviewDemandLedger({
		resolvePreparationIdentity: (itemId): string =>
			reviewItemPreparationIdentity({ itemId, source: reviewRuntimeSource }),
		start: (admission): BridgeCommWorkerReviewDemandStartHandle => {
			const store = latestSchedulingStore;
			const epoch = latestSchedulingEpoch;
			const workerDerivationEpoch = props.usesProductTransport
				? activeWorkerDerivationEpoch
				: epoch;
			const member = currentMembershipByItemId.get(admission.itemId);
			if (
				store === null ||
				epoch === null ||
				workerDerivationEpoch === null ||
				member === undefined
			) {
				throw new Error(
					'Bridge Review demand admission is missing its current scheduling context.',
				);
			}
			const demandKey =
				member.role === 'selected'
					? `selected:${member.selectedDemandEpoch}`
					: `review-ledger:${admission.itemId}`;
			const ledgerStore = bridgeCommWorkerStoreWithDemandKey(store, admission.itemId, demandKey);
			const ticket =
				member.role === 'selected'
					? enqueueSelectedBridgeWorkerReviewContentReadyPreparation({
							bridgeDemandRank: props.bridgeDemandRank,
							budget: props.budget,
							contentRequestDescriptors: reviewRuntimeSource.contentRequestDescriptors,
							epoch: member.selectedDemandEpoch,
							...(props.openReviewContent === undefined
								? {}
								: { openContent: props.openReviewContent }),
							fetchReviewContentResource,
							itemId: admission.itemId,
							port: props.port,
							pump: props.pump,
							renderSemantics: reviewRuntimeSource.renderSemantics,
							requestPreparationDrain: props.requestPreparationDrain,
							sequence: props.createSequence(),
							signal: admission.signal,
							store: ledgerStore,
							workerDerivationEpoch,
							...(props.telemetryClient === undefined
								? {}
								: { telemetryClient: props.telemetryClient }),
						})
					: enqueueBridgeWorkerReviewContentReadyPreparation({
							bridgeDemandRank: bridgeDemandRankForReviewRole(member.role),
							budget: bridgeDemandBudgetForReviewRole(member.role, props.budget),
							contentRequestDescriptors: reviewRuntimeSource.contentRequestDescriptors,
							demandKey,
							epoch,
							fetchReviewContentResource,
							...(props.openReviewContent === undefined
								? {}
								: { openContent: props.openReviewContent }),
							isDemandCurrent: (): boolean => !admission.signal.aborted,
							itemId: admission.itemId,
							port: props.port,
							preparationRank: member.role,
							pump: props.pump,
							renderSemantics: reviewRuntimeSource.renderSemantics,
							requestPreparationDrain: props.requestPreparationDrain,
							sequence: props.createSequence(),
							signal: admission.signal,
							store: ledgerStore,
							workerDerivationEpoch,
						});
			const trackedCompletion = ticket.completion.then(
				(settlement): void => {
					if (!reviewDemandLedger.release(admission.itemId, admission.attemptToken, settlement)) {
						return;
					}
					if (settlement !== 'retryWait') {
						retryAttemptByItemId.delete(admission.itemId);
						return;
					}
					const retryAttempt = (retryAttemptByItemId.get(admission.itemId) ?? 0) + 1;
					retryAttemptByItemId.set(admission.itemId, retryAttempt);
					const retryGeneration = activeWorkerDerivationEpoch;
					scheduleRetryWake(reviewDemandRetryDelayMilliseconds(retryAttempt), (): void => {
						if (
							activeWorkerDerivationEpoch !== retryGeneration ||
							!reviewDemandLedger.markRetryReady(admission.itemId, admission.attemptToken)
						) {
							return;
						}
						if (
							latestSchedulingStore !== null &&
							latestSchedulingEpoch !== null &&
							isReviewWorkAdmitted()
						) {
							reconcileCurrentReviewDemand(latestSchedulingStore, latestSchedulingEpoch);
						}
					});
				},
				(error: unknown): never => {
					reviewDemandLedger.releaseRejected(admission.itemId, admission.attemptToken);
					throw error;
				},
			);
			props.recordPreparationCompletion(trackedCompletion.then((): void => {}));
			if (ticket.enqueued) props.requestPreparationDrain();
			return {
				cancel: (): void => ticket.cancel('invalidated'),
				pause: (): void => ticket.pause(),
				resume: (): void => ticket.resume(),
				updateRole: (role): void => {
					ticket.updateDemand({
						bridgeDemandRank:
							role === 'selected' ? props.bridgeDemandRank : bridgeDemandRankForReviewRole(role),
						budget:
							role === 'selected'
								? props.budget
								: bridgeDemandBudgetForReviewRole(role, props.budget),
						preparationRank: role,
					});
				},
			};
		},
	});

	const markVisibleDemandSourceChurnFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	): BridgeCommWorkerVisibleSourceChurnAdmission => {
		if (request.cause !== 'reviewInvalidate' && request.cause !== 'reviewMetadata') {
			return { accepted: true, sourceChurnItemIds: new Set() };
		}
		const affectedItemIds =
			request.affectedItemIds ??
			reviewRuntimeSource.contentItems.map(({ itemId }): string => itemId);
		const dedupeResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds,
			identity: {
				epoch: request.epoch,
				sourceChurnRevision: request.sourceChurnRevision ?? null,
			},
			state: visibleSourceChurnDedupeState,
		});
		if (!dedupeResult.accepted) {
			return { accepted: false, sourceChurnItemIds: new Set() };
		}
		visibleSourceChurnDedupeState = dedupeResult.state;
		return {
			accepted: true,
			sourceChurnItemIds: new Set(dedupeResult.unmarkedAffectedItemIds),
		};
	};

	const reconcileDemandExecutionFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
		forcedSourceChurnItemIds: ReadonlySet<string> = new Set(),
		shouldMarkSourceChurn = true,
	): boolean => {
		latestDemandExecutionRequest = request;
		if (!isReviewWorkAdmitted()) {
			return false;
		}
		const workerDerivationEpoch = props.usesProductTransport
			? activeWorkerDerivationEpoch
			: request.epoch;
		if (workerDerivationEpoch === null) {
			return false;
		}
		const sourceChurnAdmission = shouldMarkSourceChurn
			? markVisibleDemandSourceChurnFromRequest(request)
			: { accepted: true, sourceChurnItemIds: new Set<string>() };
		if (!sourceChurnAdmission.accepted) {
			return false;
		}
		const forceExecutionItemIds = new Set([
			...sourceChurnAdmission.sourceChurnItemIds,
			...(request.forceExecutionItemIds ?? []),
			...forcedSourceChurnItemIds,
		]);
		for (const itemId of forceExecutionItemIds) {
			retryAttemptByItemId.delete(itemId);
			reviewDemandLedger.invalidate(
				itemId,
				request.cause === 'reviewMetadata'
					? {
							preserveIfPreparationIdentity: reviewItemPreparationIdentity({
								itemId,
								source: reviewRuntimeSource,
							}),
						}
					: 'cancel',
			);
		}
		if (request.cause === 'renderFulfillment') {
			for (const itemId of request.affectedItemIds ?? []) {
				reviewDemandLedger.markRetryReady(itemId);
			}
		}
		const startedNewWork = reconcileCurrentReviewDemand(
			request.store,
			request.epoch,
			forceExecutionItemIds,
		);
		if ((request.forceExecutionItemIds?.length ?? 0) > 0) {
			latestDemandExecutionRequest = { ...request, forceExecutionItemIds: [] };
		}
		return startedNewWork;
	};

	function reconcileCurrentReviewDemand(
		store: BridgeCommWorkerStore,
		epoch: number,
		forceExecutionItemIds: ReadonlySet<string> = new Set(),
	): boolean {
		latestSchedulingStore = store;
		latestSchedulingEpoch = epoch;
		const state = store.getState();
		const orderedItemIds = reviewRuntimeSource.contentItems.map(({ itemId }) => itemId);
		const firstVisibleOrderedIndex = state.visibleIds.reduce<number | null>(
			(currentIndex, itemId) => {
				const orderedIndex = orderedItemIds.indexOf(itemId);
				if (orderedIndex < 0) return currentIndex;
				return currentIndex === null ? orderedIndex : Math.min(currentIndex, orderedIndex);
			},
			null,
		);
		const viewportDirection =
			firstVisibleOrderedIndex === null || previousFirstVisibleOrderedIndex === null
				? 'unknown'
				: firstVisibleOrderedIndex > previousFirstVisibleOrderedIndex
					? 'forward'
					: firstVisibleOrderedIndex < previousFirstVisibleOrderedIndex
						? 'backward'
						: 'unknown';
		previousFirstVisibleOrderedIndex = firstVisibleOrderedIndex;
		const selectedDemandEpoch = selectedDemandEpochFromState(state);
		const membership = reconcileBridgeCommWorkerDemandMembership({
			contentMetadataByItemId: state.contentMetadataByItemId,
			hoveredItemId: state.hoveredItemId,
			orderedItemIds,
			selectedDemandEpoch,
			selectedId: state.selectedId,
			viewportDirection,
			visibleIds: state.visibleIds,
		});
		currentMembershipByItemId = new Map(
			[...membership.membersByItemId]
				.filter(
					([itemId]) =>
						hasReviewRuntimeSourceContent(reviewRuntimeSource, itemId) &&
						(forceExecutionItemIds.has(itemId) || doesReviewDemandNeedExecution(store, itemId)),
				)
				.sort(
					([, left], [, right]) =>
						reviewDemandRoleOrder(left.role) - reviewDemandRoleOrder(right.role),
				),
		);
		const result = reviewDemandLedger.reconcile([...currentMembershipByItemId.values()]);
		return result.started.length > 0;
	}

	const scheduleSelectedContentReadyPreparation = (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	): void => {
		if (!isReviewWorkAdmitted()) {
			return;
		}
		reconcileCurrentReviewDemand(request.store, request.epoch);
	};

	const scheduleMetadataReset = (
		request: BridgeCommWorkerReviewMetadataResetScheduleRequest,
	): void => {
		latestMetadataResetRequest = request;
		if (!isReviewWorkAdmitted()) return;
		const sourceChurnAdmission = markVisibleDemandSourceChurnFromRequest({
			affectedItemIds: request.affectedItemIds,
			cause: request.cause,
			epoch: request.epoch,
			store: request.store,
		});
		if (!sourceChurnAdmission.accepted) return;
		activeSourceResetEpoch = request.epoch;
		const ticket = enqueueBridgeCommWorkerReviewSourceReset({
			createSequence: props.createSequence,
			isCurrentResetEpoch: () => isReviewWorkAdmitted() && activeSourceResetEpoch === request.epoch,
			onResetComplete: () => {
				if (activeSourceResetEpoch === request.epoch) {
					activeSourceResetEpoch = null;
					if (latestMetadataResetRequest === request) {
						latestMetadataResetRequest = null;
					}
				}
			},
			pump: props.pump,
			request,
			requestPreparationDrain: props.requestPreparationDrain,
			scheduleDemandExecution: reconcileDemandExecutionFromRequest,
			scheduleSelectedReviewContentReadyPreparation: scheduleSelectedContentReadyPreparation,
		});
		if (ticket.enqueued) props.markPreparationDrainRequired();
	};

	const suspend = (): void => {
		surfaceActive = false;
		reviewDemandLedger.setSuspended(true);
		if (activeSourceResetEpoch !== null) {
			props.pump.cancel(`review-source-reset:${activeSourceResetEpoch}`);
			activeSourceResetEpoch = null;
		}
	};

	const resume = (): void => {
		surfaceActive = true;
		if (!isWorkAdmitted()) return;
		if (surfaceWorkLifecycle.signal.aborted) {
			surfaceWorkLifecycle = createBridgeCommWorkerReviewSurfaceWorkLifecycle(paneWorkSignal());
		}
		if (surfaceWorkLifecycle.signal.aborted) return;
		reviewDemandLedger.setSuspended(false);
		if (latestMetadataResetRequest !== null) {
			scheduleMetadataReset(latestMetadataResetRequest);
		} else if (latestDemandExecutionRequest !== null) {
			reconcileDemandExecutionFromRequest(latestDemandExecutionRequest);
		} else if (latestSchedulingStore !== null && latestSchedulingEpoch !== null) {
			reconcileCurrentReviewDemand(latestSchedulingStore, latestSchedulingEpoch);
		}
		if (props.pump.getPendingWorkIds().length > 0) props.requestPreparationDrain();
	};

	return {
		resume,
		scheduleDemandExecution: reconcileDemandExecutionFromRequest,
		scheduleMetadataReset,
		scheduleSelectedContentReadyPreparation,
		suspend,
		updateRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource): void => {
			reviewRuntimeSource = source;
		},
		updateWorkerDerivationEpoch: (workerDerivationEpoch: number): void => {
			reviewDemandLedger.updateGeneration(workerDerivationEpoch);
			retryAttemptByItemId.clear();
			activeWorkerDerivationEpoch = workerDerivationEpoch;
		},
	};
}

function reviewDemandRetryDelayMilliseconds(retryAttempt: number): number {
	return Math.min(
		bridgeContentDemandExecutionPolicy.deliveryFailureBackoffMaxMilliseconds,
		bridgeContentDemandExecutionPolicy.deliveryFailureBackoffInitialMilliseconds *
			bridgeContentDemandExecutionPolicy.deliveryFailureBackoffMultiplier ** (retryAttempt - 1),
	);
}

function doesReviewDemandNeedExecution(store: BridgeCommWorkerStore, itemId: string): boolean {
	const availability = store.getState().availabilityByItemId.get(itemId);
	if (availability === 'failed' || availability === 'unavailable') return false;
	const fulfillment = store.renderFulfillmentRegistry.getItemState(itemId);
	return (
		fulfillment === null || fulfillment.stage === 'desired' || fulfillment.stage === 'retry_wait'
	);
}

function bridgeCommWorkerStoreWithDemandKey(
	store: BridgeCommWorkerStore,
	itemId: string,
	demandKey: string,
): BridgeCommWorkerStore {
	return {
		...store,
		getState: (): BridgeCommWorkerStoreState => {
			const state = store.getState();
			return {
				...state,
				demandByKey: new Map([...state.demandByKey, [itemId, demandKey]]),
			};
		},
	};
}

function bridgeDemandRankForReviewRole(
	role: Exclude<BridgeCommWorkerDemandMember['role'], 'selected'>,
): BridgeWorkerDemandRank {
	return { lane: role, priority: 1 };
}

function bridgeDemandBudgetForReviewRole(
	role: Exclude<BridgeCommWorkerDemandMember['role'], 'selected'>,
	budget: BridgeWorkerPierreRenderBudget,
): BridgeWorkerPierreRenderBudget {
	return {
		className: role === 'visible' ? 'visible' : 'background',
		maxBytes: budget.maxBytes,
		maxWindowLines: budget.maxWindowLines,
	};
}

function selectedDemandEpochFromState(state: BridgeCommWorkerStoreState): number | null {
	if (state.selectedId === null) return null;
	const selectedDemandKey = state.demandByKey.get(state.selectedId);
	const match = /^selected:(\d+)$/u.exec(selectedDemandKey ?? '');
	return match === null ? null : Number(match[1]);
}

function reviewDemandRoleOrder(role: BridgeCommWorkerDemandMember['role']): number {
	switch (role) {
		case 'selected':
			return 0;
		case 'visible':
			return 1;
		case 'nearby':
			return 2;
		case 'speculative':
			return 3;
		case 'background':
			return 4;
	}
}

function hasReviewRuntimeSourceContent(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): boolean {
	const semantics = source.renderSemantics.find((candidate) => candidate.itemId === itemId) ?? null;
	return (
		source.contentItems.some((metadata) => metadata.itemId === itemId) &&
		semantics !== null &&
		canRenderBridgeWorkerReviewContentForSemantics({
			descriptors: source.contentRequestDescriptors,
			semantics,
		})
	);
}

interface BridgeCommWorkerReviewSurfaceWorkLifecycle {
	readonly abort: (reason: unknown) => void;
	readonly signal: AbortSignal;
}

function createBridgeCommWorkerReviewSurfaceWorkLifecycle(
	paneWorkSignal: AbortSignal,
): BridgeCommWorkerReviewSurfaceWorkLifecycle {
	const abortController = new AbortController();
	const detachPaneAbort = (): void => {
		paneWorkSignal.removeEventListener('abort', abortFromPane);
	};
	const abort = (reason: unknown): void => {
		detachPaneAbort();
		if (!abortController.signal.aborted) abortController.abort(reason);
	};
	const abortFromPane = (): void => {
		abort(paneWorkSignal.reason);
	};
	if (paneWorkSignal.aborted) {
		abortFromPane();
	} else {
		paneWorkSignal.addEventListener('abort', abortFromPane, { once: true });
	}
	return { abort, signal: abortController.signal };
}

function bridgeCommWorkerWorkIsAdmitted(): boolean {
	return true;
}
