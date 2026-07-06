import { createRoot } from 'react-dom/client';

import { createBridgeAppNativeWorktreeFileBackend } from './bridge-app-native-worktree-file.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';
import { createBridgeFileViewerWorktreeFileSurfaceTransport } from './bridge-file-viewer-worktree-file-surface-transport-adapter.js';

// oxlint-disable-next-line import/no-unassigned-import -- The packaged app loads compiled CSS from index.html; this source import keeps dev/build contracts explicit.
import './bridge-app.css';

const rootElement = document.querySelector('#root');

if (rootElement !== null) {
	const nativeWorktreeFileBackend = createBridgeAppNativeWorktreeFileBackend();
	window.addEventListener(
		'beforeunload',
		(): void => {
			nativeWorktreeFileBackend?.dispose();
		},
		{ once: true },
	);
	createRoot(rootElement).render(
		<BridgeAppProtocolRouter
			{...(nativeWorktreeFileBackend === null
				? {}
				: {
						fileViewerProps: {
							autoOpenInitialFile: true,
							worktreeFileSurfaceTransport:
								createBridgeFileViewerWorktreeFileSurfaceTransport(nativeWorktreeFileBackend),
						},
					})}
		/>,
	);
}
