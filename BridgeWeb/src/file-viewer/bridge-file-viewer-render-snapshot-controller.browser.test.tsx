// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must prove owned shadcn styling.
import '../app/bridge-app.css';
import type { ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { page } from 'vitest/browser';

import { BridgeViewerContextPanelProvider } from '../app/bridge-viewer-context-panel-host.js';
import { createBridgePaneRuntime } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerViewRecoveryStatusEvent,
} from '../core/comm-worker/bridge-worker-contracts.js';
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
		expect(dispatchedMessages.map(({ command }) => command)).toEqual(['fileDisplayResync']);
	});

	test('shows one File Retry for a failed view, runs both recovery jobs, and keeps last good content', async () => {
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
		fileViewClient.renderStore.applyViewRecoveryStatusEvent({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'viewRecoveryStatus',
			view: { kind: 'file.metadata', subscriptionId: 'file-view-retry-1' },
			status: 'failedRetryable',
		} satisfies BridgeWorkerViewRecoveryStatusEvent);
		const existingFileContent = 'Last good file contents stay visible.';

		// Act
		const rendered = await render(
			<BridgeFileViewerSurfaceClientProvider surfaceClient={fileViewClient}>
				<BridgeViewerContextPanelProvider>
					<WorktreeAnnotationSurfaceProvider surfaceClient={fileViewClient}>
						<BridgeFileViewerAppImplementation shellComponent={HeaderControlsProbe} />
					</WorktreeAnnotationSurfaceProvider>
				</BridgeViewerContextPanelProvider>
			</BridgeFileViewerSurfaceClientProvider>,
		);
		await rendered.getByRole('button', { name: 'Retry' }).click();

		// Assert
		expect(document.querySelectorAll('button[aria-label="Retry"]')).toHaveLength(1);
		expect(dispatchedMessages.slice(-2).map(({ command }) => command)).toEqual([
			'viewRecoveryRetry',
			'fileRefreshRetry',
		]);
		await expect.element(rendered.getByText(existingFileContent, { exact: true })).toBeVisible();
		await page.screenshot({ path: '../../../tmp/bridgeweb-file-view-retry.png' });
	});
});

function BridgeFileViewerRenderSnapshotProbe(): ReactElement {
	useBridgeFileViewerRenderSnapshotController({ selection: null });
	return <div />;
}

function HeaderControlsProbe(props: BridgeFileViewerShellProps): ReactElement {
	return (
		<div className="flex items-center gap-1 p-3">
			<p>{'Last good file contents stay visible.'}</p>
			{props.viewerHeaderControls}
		</div>
	);
}
