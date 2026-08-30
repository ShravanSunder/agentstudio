import { BridgeFileViewerMode } from './bridge-app-file-viewer-mode.js';

interface BridgeFileViewerModeEntry {
	readonly modeComponent: typeof BridgeFileViewerMode;
}

export const bridgeFileViewerModeEntry = {
	modeComponent: BridgeFileViewerMode,
} satisfies BridgeFileViewerModeEntry;
