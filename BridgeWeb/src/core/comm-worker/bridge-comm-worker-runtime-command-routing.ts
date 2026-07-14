import type { BridgeRPCCommand } from '../../bridge/bridge-rpc-client.js';
import type { BridgeCommWorkerTelemetryLane } from './bridge-comm-worker-telemetry.js';
import type { BridgeWorkerMainToServerMessage } from './bridge-worker-contracts.js';

export function bridgeWorkerRuntimeSchemeRpcCommandForMessage(
	message: BridgeWorkerMainToServerMessage,
): { readonly command: BridgeRPCCommand; readonly requestId: string } | null {
	switch (message.command) {
		case 'markFileViewed':
			return {
				command: {
					method: 'review.markFileViewed',
					params: { fileId: message.fileId },
				},
				requestId: message.requestId,
			};
		case 'metadataInterestUpdate':
			return {
				command: {
					method: 'bridge.metadata_interest.update',
					params: bridgeMetadataInterestUpdateParamsFromWorkerRequest(message.request),
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
		case 'hover':
		case 'fileQueryUpdate':
		case 'fileDisplayResync':
		case 'mode':
		case 'reviewInvalidate':
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
			return 'visible';
		case 'metadataInterestUpdate':
			return message.request.lane === 'foreground' ? 'selected' : 'visible';
		case 'activeViewerModeUpdate':
			return 'background';
		case 'markFileViewed':
		case 'mode':
		case 'reviewIntakeReady':
			return 'background';
		default:
			return assertNeverBridgeWorkerMessage(message);
	}
}

function bridgeMetadataInterestUpdateParamsFromWorkerRequest(
	request: Extract<
		BridgeWorkerMainToServerMessage,
		{ readonly command: 'metadataInterestUpdate' }
	>['request'],
): Extract<BridgeRPCCommand, { readonly method: 'bridge.metadata_interest.update' }>['params'] {
	return {
		protocol: request.protocol,
		lane: request.lane,
		...(request.streamId === undefined ? {} : { streamId: request.streamId }),
		...(request.generation === undefined ? {} : { generation: request.generation }),
		...(request.itemIds === undefined ? {} : { itemIds: [...request.itemIds] }),
		...(request.paths === undefined ? {} : { paths: [...request.paths] }),
		...(request.loaded_by === undefined ? {} : { loaded_by: request.loaded_by }),
	};
}

function assertNeverBridgeWorkerMessage(_message: never): never {
	throw new Error('Unhandled bridge worker message.');
}
