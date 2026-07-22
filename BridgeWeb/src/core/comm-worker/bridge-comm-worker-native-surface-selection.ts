import type { BridgeProductMetadataFrame } from './bridge-product-session-contracts.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerNativeSurfaceSelectionRequestSchema,
	type BridgeWorkerNativeSurfaceSelectionRequest,
} from './bridge-worker-contracts.js';

export function bridgeWorkerNativeSurfaceSelectionRequestFromMetadataFrame(
	frame: BridgeProductMetadataFrame,
): BridgeWorkerNativeSurfaceSelectionRequest {
	if (frame.kind !== 'pane.surfaceSelectionRequested') {
		throw new Error('Bridge native surface selection requires its dedicated metadata frame.');
	}
	return bridgeWorkerNativeSurfaceSelectionRequestSchema.parse({
		direction: 'serverWorkerToMain',
		kind: 'nativeSurfaceSelectionRequest',
		metadataStreamId: frame.metadataStreamId,
		nativeSelectionRequestId: frame.requestId,
		paneSessionId: frame.paneSessionId,
		selectionRevision: frame.selectionRevision,
		surface: frame.surface,
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		workerInstanceId: frame.workerInstanceId,
	});
}
