// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must prove owned shadcn styling.
import '../app/bridge-app.css';
import type { ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { page } from 'vitest/browser';

import { createBridgePaneRuntime } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeWorkerMainToServerMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import { WorktreeAnnotationSurfaceProvider } from '../worktree-annotations/worktree-annotation-surface-provider.js';
import { BridgeFileViewerAppImplementation } from './bridge-file-viewer-app.js';
import {
	BridgeFileViewerSurfaceClientProvider,
	useBridgeFileViewerRenderSnapshotController,
} from './bridge-file-viewer-render-snapshot-controller.js';
import type { BridgeFileViewerShellProps } from './bridge-file-viewer-shell.js';

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
		await render(
			<BridgeFileViewerSurfaceClientProvider surfaceClient={paneRuntime.surfaceClient('fileView')}>
				<BridgeFileViewerRenderSnapshotProbe />
			</BridgeFileViewerSurfaceClientProvider>,
		);

		// Assert
		await expect
			.poll(() => dispatchedMessages.map(({ command }) => command))
			.toEqual(['fileDisplayResync']);
	});

	test('shows the owned shadcn retry action and sends the typed File refresh command', async () => {
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
		const fileViewClient = paneRuntime.surfaceClient('fileView');
		fileViewClient.renderStore.applyWorkerPatch({
			operation: 'upsert',
			payload: {
				fileRefreshFailure: { failureKind: 'fileSourceUnavailable', retryable: true },
				message: 'Files unavailable',
			},
			slice: 'panelChrome',
		});

		// Act
		const rendered = await render(
			<BridgeFileViewerSurfaceClientProvider surfaceClient={fileViewClient}>
				<WorktreeAnnotationSurfaceProvider surfaceClient={fileViewClient}>
					<BridgeFileViewerAppImplementation shellComponent={HeaderControlsProbe} />
				</WorktreeAnnotationSurfaceProvider>
			</BridgeFileViewerSurfaceClientProvider>,
		);
		await rendered.getByRole('button', { name: 'Retry' }).click();

		// Assert
		await expect
			.poll(() => dispatchedMessages.map(({ command }) => command))
			.toContain('fileRefreshRetry');
		await page.screenshot({ path: '../../../tmp/bridgeweb-file-refresh-retry.png' });
	});
});

function BridgeFileViewerRenderSnapshotProbe(): ReactElement {
	useBridgeFileViewerRenderSnapshotController({ selection: null });
	return <div />;
}

function HeaderControlsProbe(props: BridgeFileViewerShellProps): ReactElement {
	return <div className="flex items-center gap-1 p-3">{props.viewerHeaderControls}</div>;
}
