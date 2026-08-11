import type { BridgeProductPanePresentationFrame } from './bridge-product-transport.js';

export function requirePanePresentationSink(
	sink: ((frame: BridgeProductPanePresentationFrame) => void) | null,
): (frame: BridgeProductPanePresentationFrame) => void {
	if (sink === null) throw new Error('Expected Bridge pane presentation sink registration.');
	return sink;
}

export function makeReviewPanePresentationFrame(
	activityRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
): BridgeProductPanePresentationFrame {
	return {
		activityRevision,
		kind: 'pane.presentation',
		metadataStreamId: 'metadata-stream-review-pane-suppression',
		nativeActivity,
		paneSessionId: 'pane-session-review-pane-suppression',
		refreshingLanes: [],
		streamSequence: activityRevision,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-review-pane-suppression',
	};
}
