import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerReviewPierreRenderJobEvent,
	BridgeWorkerReviewRenderPatch,
	BridgeWorkerReviewRenderPatchEvent,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerReviewRenderPatchEventSchema,
} from './bridge-worker-contracts.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
	BridgeWorkerPierreRenderJob,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import {
	createBridgeWorkerReviewPierreRenderJobPlanningSession,
	prepareBridgeWorkerReviewPierreRenderJobEventFromJob,
} from './bridge-worker-review-pierre-job-planner.js';
import {
	prepareBridgeWorkerStructuredMessage,
	type PreparedBridgeWorkerStructuredMessage,
} from './bridge-worker-transfer-list.js';

export interface PrepareBridgeWorkerReviewContentReadyEventsProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly publicationSequence: number;
	readonly renderReceiptIdentity: BridgeWorkerReviewPierreRenderJobEvent['renderReceiptIdentity'];
	readonly resources: readonly BridgeWorkerFetchedReviewContentResource[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
	readonly workerDerivationEpoch: number;
}

export type PlanBridgeWorkerReviewContentReadyRenderJobProps = Omit<
	PrepareBridgeWorkerReviewContentReadyEventsProps,
	'publicationSequence' | 'renderReceiptIdentity' | 'workerDerivationEpoch'
>;

export interface CommitBridgeWorkerReviewContentReadyRenderPatchProps {
	readonly preparedJobEvent: PreparedBridgeWorkerStructuredMessage<BridgeWorkerReviewPierreRenderJobEvent>;
	readonly publicationSequence: number;
	readonly store: BridgeCommWorkerStore;
	readonly workerDerivationEpoch: number;
}

export interface BridgeWorkerReviewContentReadyRenderPatchCommit {
	readonly touchedKeys: readonly string[];
	readonly preparedMessage: PreparedBridgeWorkerStructuredMessage<BridgeWorkerReviewRenderPatchEvent>;
}

export type BridgeWorkerReviewContentRenderJobPreparationStepResult =
	| { readonly status: 'pending' }
	| {
			readonly job: BridgeWorkerPierreRenderJob | null;
			readonly status: 'complete';
	  };

export interface BridgeWorkerReviewContentRenderJobPreparation {
	readonly runNextStage: () => BridgeWorkerReviewContentRenderJobPreparationStepResult;
}

export type BridgeWorkerPreparedServerToMainMessage =
	PreparedBridgeWorkerStructuredMessage<BridgeWorkerServerToMainMessage>;

export function prepareBridgeWorkerReviewContentRenderJobEvent(
	props: PrepareBridgeWorkerReviewContentReadyEventsProps,
): PreparedBridgeWorkerStructuredMessage<BridgeWorkerReviewPierreRenderJobEvent> | null {
	const preparation = createBridgeWorkerReviewContentRenderJobPreparation(props);
	while (true) {
		const result = preparation.runNextStage();
		if (result.status !== 'complete') continue;
		return result.job === null
			? null
			: prepareBridgeWorkerReviewPierreRenderJobEventFromJob({
					job: result.job,
					renderReceiptIdentity: props.renderReceiptIdentity,
				});
	}
}

export function createBridgeWorkerReviewContentRenderJobPreparation(
	props: PlanBridgeWorkerReviewContentReadyRenderJobProps,
): BridgeWorkerReviewContentRenderJobPreparation {
	const planningSession = createBridgeWorkerReviewPierreRenderJobPlanningSession({
		bridgeDemandRank: props.bridgeDemandRank,
		budget: props.budget,
		resources: props.resources,
		semantics: props.semantics,
	});
	let plannedJob: BridgeWorkerReviewPierreRenderJobEvent['job'] | null = null;
	let planningComplete = false;

	return {
		runNextStage: (): BridgeWorkerReviewContentRenderJobPreparationStepResult => {
			if (!planningComplete) {
				const planningResult = planningSession.runNextStage();
				if (planningResult.status === 'pending') return planningResult;
				planningComplete = true;
				plannedJob = planningResult.job;
				if (plannedJob === null) return { job: null, status: 'complete' };
				return { status: 'pending' };
			}
			if (plannedJob === null) {
				throw new Error('Bridge worker Review render job planning completed without a job.');
			}
			return {
				job: plannedJob,
				status: 'complete',
			};
		},
	};
}

export function commitBridgeWorkerReviewContentReadyRenderPatch(
	props: CommitBridgeWorkerReviewContentReadyRenderPatchProps,
): BridgeWorkerReviewContentReadyRenderPatchCommit {
	const contentReadyResult = props.store.actions.applyContentReady({
		itemId: props.preparedJobEvent.message.job.itemId,
		contentCacheKey: props.preparedJobEvent.message.job.contentCacheKey,
	});
	const slicePatchEvent = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.workerDerivationEpoch,
		sequence: props.publicationSequence,
	});
	const reviewRenderPatches = bridgeWorkerReviewRenderPatchesFromSlicePatchEvent(slicePatchEvent);

	return {
		touchedKeys: contentReadyResult.touchedKeys,
		preparedMessage: prepareBridgeWorkerReviewRenderPatchEvent({
			patches: reviewRenderPatches,
			publicationSequence: props.publicationSequence,
			workerDerivationEpoch: props.workerDerivationEpoch,
		}),
	};
}

export function prepareBridgeWorkerReviewRenderPatchEvent(props: {
	readonly patches: readonly BridgeWorkerReviewRenderPatch[];
	readonly publicationSequence: number;
	readonly workerDerivationEpoch: number;
}): PreparedBridgeWorkerStructuredMessage<BridgeWorkerReviewRenderPatchEvent> {
	return prepareBridgeWorkerStructuredMessage({
		message: bridgeWorkerReviewRenderPatchEventSchema.parse({
			direction: 'serverWorkerToMain',
			kind: 'reviewRenderPatch',
			patches: props.patches,
			publicationSequence: props.publicationSequence,
			surface: 'review',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			workerDerivationEpoch: props.workerDerivationEpoch,
		}),
		declaredFields: [],
	});
}

export function bridgeWorkerReviewRenderPatchesFromSlicePatchEvent(
	event: BridgeWorkerServerToMainMessage | null,
): readonly BridgeWorkerReviewRenderPatch[] {
	if (event === null) {
		throw new Error('Bridge worker Review content-ready commit produced no render patch event.');
	}
	if (event.kind !== 'slicePatch') {
		throw new Error('Bridge worker Review content-ready commit produced an invalid patch event.');
	}
	return event.patches.map((patch): BridgeWorkerReviewRenderPatch => {
		if (patch.slice !== 'rowPaint' && patch.slice !== 'contentAvailability') {
			throw new Error('Bridge worker Review content-ready commit produced a non-render patch.');
		}
		return patch;
	});
}
