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
		case 'reviewIntakeReady':
			return {
				command: {
					method: 'bridge.intakeReady',
					params: {
						protocolId: message.protocolId,
						streamId: message.streamId ?? null,
						reason: message.reason ?? null,
					},
				},
				requestId: message.requestId,
			};
		case 'worktreeFileIntakeReady':
			return {
				command: {
					method: 'bridge.intakeReady',
					params: {
						protocolId: message.protocolId,
						streamId: message.streamId,
						generation: message.generation,
					},
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
		case 'fileViewSourceUpdate':
		case 'hover':
		case 'mode':
		case 'reviewInvalidate':
		case 'reviewSourceUpdate':
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
		case 'hover':
		case 'reviewInvalidate':
			return 'visible';
		case 'fileViewSourceUpdate':
			return 'file_view';
		case 'metadataInterestUpdate':
			return message.request.lane === 'foreground' ? 'selected' : 'visible';
		case 'activeViewerModeUpdate':
			return 'background';
		case 'markFileViewed':
		case 'mode':
		case 'reviewIntakeReady':
		case 'worktreeFileIntakeReady':
		case 'reviewSourceUpdate':
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
