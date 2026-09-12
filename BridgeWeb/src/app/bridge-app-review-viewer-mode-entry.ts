import { ReviewViewerShell } from '../review-viewer/shell/review-viewer-shell.js';
import { BridgeReviewViewerMode } from './bridge-app-review-viewer-mode.js';

interface BridgeReviewViewerModeEntry {
	readonly modeComponent: typeof BridgeReviewViewerMode;
	readonly shellBarrierComponent: typeof ReviewViewerShell;
}

export const bridgeReviewViewerModeEntry = {
	modeComponent: BridgeReviewViewerMode,
	shellBarrierComponent: ReviewViewerShell,
} satisfies BridgeReviewViewerModeEntry;
