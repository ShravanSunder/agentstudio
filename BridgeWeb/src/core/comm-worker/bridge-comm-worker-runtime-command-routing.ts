import type { BridgeCommWorkerTelemetryLane } from './bridge-comm-worker-telemetry.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import type { BridgeWorkerMainToServerMessage } from './bridge-worker-contracts.js';

export function bridgeWorkerRuntimeProductControlCommandForMessage(
	message: BridgeWorkerMainToServerMessage,
): { readonly command: BridgeProductControlCommand; readonly requestId: string } | null {
	switch (message.command) {
		case 'markFileViewed':
			return {
				command: {
					method: 'review.markFileViewed',
					params: { fileId: message.fileId },
				},
				requestId: message.requestId,
			};
		case 'activeViewerModeUpdate':
			return {
				command: {
					method: 'bridge.activeViewerMode.update',
					params: message.update,
				},
				requestId: message.requestId,
			};
		case 'reviewIntakeReady':
			return {
				command: {
					method: 'bridge.intakeReady',
					params: {
						protocolId: message.protocolId,
						reason: message.reason,
						streamId: message.streamId,
					},
				},
				requestId: message.requestId,
			};
		case 'reviewComparisonUpdate':
			return {
				command: {
					method: 'review.comparison.update',
					params: { target: message.target },
				},
				requestId: message.requestId,
			};
		case 'reviewComparisonTargetsQuery':
			return {
				command: {
					method: 'review.comparisonTargets.query',
					params: {},
				},
				requestId: message.requestId,
			};
		case 'reviewComparisonTargetsQueryCancel':
		case 'hover':
		case 'metadataInterestUpdate':
		case 'fileQueryUpdate':
		case 'fileDisplayResync':
		case 'mode':
		case 'reviewInvalidate':
		case 'reviewProjectionUpdate':
		case 'renderDisposition':
		case 'select':
		case 'viewport':
			return null;
		default:
			return assertNeverBridgeWorkerMessage(message);
	}
}

export function bridgeCommWorkerTelemetryLaneForMessage(
	message: BridgeWorkerMainToServerMessage,
): BridgeCommWorkerTelemetryLane {
	switch (message.command) {
		case 'select':
			return 'selected';
		case 'viewport':
		case 'fileQueryUpdate':
		case 'fileDisplayResync':
		case 'hover':
		case 'reviewInvalidate':
		case 'reviewProjectionUpdate':
		case 'renderDisposition':
			return 'visible';
		case 'metadataInterestUpdate':
			return message.request.lane === 'foreground' ? 'selected' : 'visible';
		case 'activeViewerModeUpdate':
			return 'background';
		case 'markFileViewed':
		case 'mode':
		case 'reviewIntakeReady':
		case 'reviewComparisonUpdate':
		case 'reviewComparisonTargetsQuery':
		case 'reviewComparisonTargetsQueryCancel':
			return 'background';
		default:
			return assertNeverBridgeWorkerMessage(message);
	}
}
function assertNeverBridgeWorkerMessage(_message: never): never {
	throw new Error('Unhandled bridge worker message.');
}
