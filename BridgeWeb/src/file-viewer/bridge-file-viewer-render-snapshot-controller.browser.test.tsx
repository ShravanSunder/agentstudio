import type { ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import { createBridgePaneRuntime } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeWorkerMainToServerMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import {
	BridgeFileViewerSurfaceClientProvider,
	useBridgeFileViewerRenderSnapshotController,
} from './bridge-file-viewer-render-snapshot-controller.js';

describe('Bridge File viewer render snapshot controller Browser Mode', () => {
	test('requests the retained worker display snapshot when the File viewer mounts late', async () => {
		// Arrange
		const dispatchedMessages: BridgeWorkerMainToServerMessage[] = [];
		const paneRuntime = createBridgePaneRuntime({
			sessionFactory: () => ({
				createDispatcher: () => ({
					dispatch: (message): void => {
						dispatchedMessages.push(message);
					},
					dispose: (): void => {},
				}),
				dispose: (): void => {},
				installNativeBootstrap: (): void => {},
			}),
		});

		// Act
		render(
			<BridgeFileViewerSurfaceClientProvider surfaceClient={paneRuntime.surfaceClient('fileView')}>
				<BridgeFileViewerRenderSnapshotProbe />
			</BridgeFileViewerSurfaceClientProvider>,
		);

		// Assert
		await expect
			.poll(() => dispatchedMessages.map(({ command }) => command))
			.toEqual(['fileDisplayResync']);
	});
});

function BridgeFileViewerRenderSnapshotProbe(): ReactElement {
	useBridgeFileViewerRenderSnapshotController({ selection: null });
	return <div />;
}
