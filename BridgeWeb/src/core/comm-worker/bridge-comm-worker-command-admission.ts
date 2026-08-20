import {
	assertNeverBridgeWorkerCommand,
	buildBridgeWorkerDegradedHealthEvent,
} from './bridge-comm-worker-command-support.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

export type BridgeCommWorkerIntentEpochDomain =
	| 'fileAnnotation'
	| 'fileView'
	| 'pane'
	| 'review'
	| 'reviewAnnotation';

export function bridgeCommWorkerIntentEpochDomain(
	message: BridgeWorkerMainToServerMessage,
): BridgeCommWorkerIntentEpochDomain {
	switch (message.command) {
		case 'annotationCommand':
		case 'annotationOutputInspect':
		case 'annotationOutputCandidatesQuery':
		case 'annotationProjectionRetry':
			return message.surface === 'fileView' ? 'fileAnnotation' : 'reviewAnnotation';
		case 'hover':
		case 'select':
		case 'viewport':
			return message.surface;
		case 'fileDisplayResync':
		case 'fileQueryUpdate':
		case 'fileRefreshRetry':
			return 'fileView';
		case 'markFileViewed':
		case 'metadataInterestUpdate':
		case 'reviewIntakeReady':
		case 'reviewComparisonUpdate':
		case 'reviewComparisonTargetsQuery':
		case 'reviewComparisonTargetsQueryCancel':
		case 'reviewInvalidate':
		case 'reviewProjectionUpdate':
			return 'review';
		case 'renderDisposition':
			return message.receipt.surface === 'file' ? 'fileView' : 'review';
		case 'activeViewerModeUpdate':
		case 'mode':
			return 'pane';
		default:
			return assertNeverBridgeWorkerCommand(message);
	}
}

export function bridgeCommWorkerCommandUsesIntentEpochAdmission(
	message: BridgeWorkerMainToServerMessage,
): boolean {
	return message.command !== 'renderDisposition';
}

interface RejectStaleOrReplayedBridgeWorkerCommandProps {
	readonly currentEpoch: number;
	readonly message: BridgeWorkerMainToServerMessage;
	readonly seenRequestIds: ReadonlySet<string>;
}

export function rejectStaleOrReplayedBridgeWorkerCommand(
	props: RejectStaleOrReplayedBridgeWorkerCommandProps,
): BridgeWorkerServerToMainMessage | null {
	if (props.message.epoch < props.currentEpoch) {
		return buildBridgeWorkerDegradedHealthEvent({
			message: `Bridge comm worker rejected stale epoch ${props.message.epoch} after ${props.currentEpoch}.`,
			requestId: props.message.requestId,
		});
	}
	if (props.seenRequestIds.has(props.message.requestId)) {
		return buildBridgeWorkerDegradedHealthEvent({
			message: `Bridge comm worker rejected replayed request ${props.message.requestId}.`,
			requestId: props.message.requestId,
		});
	}
	return null;
}
