import type {
	BridgeCommWorkerSelectedDemandResult,
	BridgeCommWorkerStore,
	BridgeCommWorkerTouchedResult,
} from './bridge-comm-worker-store.js';
import {
	recordBridgeCommWorkerTaskTelemetry,
	type BridgeCommWorkerTelemetryAction,
	type BridgeCommWorkerTelemetryLane,
	type BridgeCommWorkerTelemetryRecorder,
} from './bridge-comm-worker-telemetry.js';
import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerSlicePatch,
} from './bridge-worker-contracts.js';

interface InstrumentBridgeCommWorkerStoreActionsProps {
	readonly actions: BridgeCommWorkerStore['actions'];
	readonly now: () => number;
	readonly pendingSlicePatches: readonly BridgeWorkerSlicePatch[];
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}

export function instrumentBridgeCommWorkerStoreActions(
	props: InstrumentBridgeCommWorkerStoreActionsProps,
): BridgeCommWorkerStore['actions'] {
	const telemetryProps = {
		now: props.now,
		pendingSlicePatches: props.pendingSlicePatches,
		...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
	};
	return {
		applyHoveredFact: props.actions.applyHoveredFact,
		applySelectedFact: (fact): BridgeCommWorkerTouchedResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applySelectedFact',
				lane: 'selected',
				operation: () => props.actions.applySelectedFact(fact),
				...telemetryProps,
			}),
		applyViewportFact: (fact): BridgeCommWorkerTouchedResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applyViewportFact',
				lane: 'visible',
				operation: () => props.actions.applyViewportFact(fact),
				...telemetryProps,
			}),
		applyContentReady: (fact): BridgeCommWorkerTouchedResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applyContentReady',
				lane: 'visible',
				operation: () => props.actions.applyContentReady(fact),
				...telemetryProps,
			}),
		applyContentTerminalAvailability: (fact): BridgeCommWorkerTouchedResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applyContentTerminalAvailability',
				lane: 'visible',
				operation: () => props.actions.applyContentTerminalAvailability(fact),
				resultReason: fact.reason,
				sourceEpoch: fact.sourceEpoch,
				...telemetryProps,
			}),
		applyReviewInvalidationFact: (fact): BridgeCommWorkerTouchedResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applyReviewInvalidationFact',
				lane: 'visible',
				operation: () => props.actions.applyReviewInvalidationFact(fact),
				...telemetryProps,
			}),
		applySelectedSourceChurnFact: (fact): BridgeCommWorkerSelectedDemandResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applySelectedSourceChurnFact',
				lane: 'selected',
				operation: () => props.actions.applySelectedSourceChurnFact(fact),
				...telemetryProps,
			}),
		applyReviewSourceUpdateFact: (fact): BridgeCommWorkerTouchedResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applyReviewSourceUpdateFact',
				lane: 'background',
				operation: () => props.actions.applyReviewSourceUpdateFact(fact),
				...telemetryProps,
			}),
		applyReviewRowMutationFact: (fact): BridgeCommWorkerTouchedResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applyReviewRowMutationFact',
				lane: 'background',
				operation: () => props.actions.applyReviewRowMutationFact(fact),
				...telemetryProps,
			}),
		applyFileViewSourceUpdateFact: (fact): BridgeCommWorkerTouchedResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applyFileViewSourceUpdateFact',
				lane: 'file_view',
				operation: () => props.actions.applyFileViewSourceUpdateFact(fact),
				...telemetryProps,
			}),
		applyFileViewSourceMutationFact: (fact): BridgeCommWorkerTouchedResult =>
			recordBridgeCommWorkerStoreActionTelemetry({
				action: 'applyFileViewSourceMutationFact',
				lane: 'file_view',
				operation: () => props.actions.applyFileViewSourceMutationFact(fact),
				...telemetryProps,
			}),
		takePendingSlicePatchEvent: props.actions.takePendingSlicePatchEvent,
		buildRootSnapshotPayload: props.actions.buildRootSnapshotPayload,
	};
}

function recordBridgeCommWorkerStoreActionTelemetry<
	TResult extends BridgeCommWorkerTouchedResult,
>(props: {
	readonly action: BridgeCommWorkerTelemetryAction;
	readonly lane: BridgeCommWorkerTelemetryLane;
	readonly now: () => number;
	readonly operation: () => TResult;
	readonly pendingSlicePatches: readonly BridgeWorkerSlicePatch[];
	readonly resultReason?: NonNullable<BridgeWorkerContentAvailabilityPatchPayload['reason']>;
	readonly sourceEpoch?: number;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}): TResult {
	const patchCountBefore = props.pendingSlicePatches.length;
	const startedAtMilliseconds = props.now();
	const result = props.operation();
	const durationMilliseconds = props.now() - startedAtMilliseconds;
	const resultReason = props.resultReason ?? result.resultReason;
	const sourceEpoch = props.sourceEpoch ?? result.sourceEpoch;
	recordBridgeCommWorkerTaskTelemetry({
		action: props.action,
		durationMilliseconds,
		lane: props.lane,
		patchCount: props.pendingSlicePatches.length - patchCountBefore,
		...(resultReason === undefined ? {} : { resultReason }),
		...(sourceEpoch === undefined ? {} : { sourceEpoch }),
		taskKind: 'store_action',
		touchedKeyCount: result.touchedKeys.length,
		...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
	});
	return result;
}
