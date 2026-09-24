import { act } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import { waitForBridgeViewerTreeItemButton } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import {
	makeFileMemberGroupsMetadataEvent,
	makeSourceAcceptedMetadataEvent,
	makeSourceIdentity,
	makeTreeRow,
	parseFileMetadataEvent,
	type FileMetadataEvent,
	type FileTreeRow,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	settleBridgeFileViewerBrowserUpdates,
} from './bridge-file-viewer-browser-test-harness.js';

const startupLineage = { lane: 'foreground', loadedBy: 'startup_window' } as const;

describe('Bridge File collection tree', () => {
	afterEach(async () => {
		await settleBridgeFileViewerBrowserUpdates();
		await act(async (): Promise<void> => {
			await cleanup();
			await Promise.resolve();
		});
		await actFrame();
		document.body.replaceChildren();
		terminateBridgePierreWorkerPoolSingletonForTest();
	});

	test('renders members streamed as positional windows ending in an empty final window', async () => {
		// Arrange — the native collection sends each member's group row, then its
		// rows, then one empty window that carries the total.
		const source = makeSourceIdentity();
		const frontendRows: readonly FileTreeRow[] = [
			makeTreeRow({
				depth: 0,
				isDirectory: true,
				name: 'frontend',
				parentPath: null,
				path: 'frontend',
			}),
			makeTreeRow({
				depth: 1,
				isDirectory: true,
				name: 'src',
				parentPath: 'frontend',
				path: 'frontend/src',
			}),
			makeTreeRow({
				depth: 2,
				fileId: 'mfrontend.file-app',
				isDirectory: false,
				name: 'app.ts',
				parentPath: 'frontend/src',
				path: 'frontend/src/app.ts',
			}),
		];
		const backendRows: readonly FileTreeRow[] = [
			makeTreeRow({
				depth: 0,
				isDirectory: true,
				name: 'backend',
				parentPath: null,
				path: 'backend',
			}),
			makeTreeRow({
				depth: 1,
				fileId: 'mbackend.file-app',
				isDirectory: false,
				name: 'app.ts',
				parentPath: 'backend',
				path: 'backend/app.ts',
			}),
		];
		const windows = [[frontendRows[0]], frontendRows.slice(1), backendRows];
		let startIndex = 0;
		const windowEvents: FileMetadataEvent[] = [];
		for (const rows of windows) {
			windowEvents.push(treeWindow({ finalWindow: false, rows, source, startIndex, total: null }));
			startIndex += rows.length;
		}
		windowEvents.push(
			treeWindow({ finalWindow: true, rows: [], source, startIndex, total: startIndex }),
		);

		// Act
		await render(
			<BridgeFileViewerApp
				isActive={true}
				initialMetadataEvents={[
					makeSourceAcceptedMetadataEvent(source),
					makeFileMemberGroupsMetadataEvent({
						groups: [
							{ groupPath: 'frontend', worktreeId: 'worktree-frontend' },
							{ groupPath: 'backend', worktreeId: 'worktree-backend' },
						],
						source,
					}),
					...windowEvents,
				]}
			/>,
		);

		// Assert
		expect(await waitForBridgeViewerTreeItemButton('frontend/src/app.ts')).not.toBeNull();
		expect(await waitForBridgeViewerTreeItemButton('backend/app.ts')).not.toBeNull();
	});
});

function treeWindow(props: {
	readonly finalWindow: boolean;
	readonly rows: readonly (FileTreeRow | undefined)[];
	readonly source: ReturnType<typeof makeSourceIdentity>;
	readonly startIndex: number;
	readonly total: number | null;
}): FileMetadataEvent {
	return parseFileMetadataEvent({
		eventKind: 'file.treeWindow',
		finalWindow: props.finalWindow,
		lineage: startupLineage,
		pathScope: [],
		rows: props.rows,
		source: props.source,
		startIndex: props.startIndex,
		totalRowCount: props.total,
	});
}
