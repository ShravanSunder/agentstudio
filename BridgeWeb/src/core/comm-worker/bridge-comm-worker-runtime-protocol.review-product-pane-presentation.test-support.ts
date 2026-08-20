import type { BridgeProductPanePresentationFrame } from './bridge-product-transport.js';

export function requirePanePresentationSink(
	sink: ((frame: BridgeProductPanePresentationFrame) => void) | null,
): (frame: BridgeProductPanePresentationFrame) => void {
	if (sink === null) throw new Error('Expected Bridge pane presentation sink registration.');
	return sink;
}

export function makeReviewPanePresentationFrame(
	presentationRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
): BridgeProductPanePresentationFrame {
	return {
		fileRefreshFailure: null,
		presentationRevision,
		kind: 'pane.presentation',
		metadataStreamId: 'metadata-stream-review-pane-suppression',
		nativeActivity,
		paneSessionId: 'pane-session-review-pane-suppression',
		refreshingLanes: [],
		reviewComparison: null,
		streamSequence: presentationRevision,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-review-pane-suppression',
	};
}
