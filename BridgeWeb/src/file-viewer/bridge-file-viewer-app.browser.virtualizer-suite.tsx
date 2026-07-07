import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import { worktreeFileProtocolFrameSchema } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { WorktreeFileProtocolFrame } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import {
	bridgeViewerVisibleTreeItemPaths,
	findBridgeViewerTreeScrollOwner,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import {
	makeFlatFileTreeRows,
	makeSourceIdentity,
	makeTreeRow,
	makeTreeWindowedSnapshotFrame,
	type PublishWorktreeFileFrames,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	actUpdate,
	requireFramePublisher,
	makeTestTelemetryRecorder,
	waitForMetadataTreeRowCount,
	waitForTreeScrollHeightAtLeast,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp virtualizer anchoring', () => {
	afterEach(async () => {
		cleanup();
		await waitForBridgeViewerAnimationFrame();
		document.body.replaceChildren();
	});

	test('does not app-side anchor restore when a reset prepends rows above the viewport', async () => {
		let publishFrames: PublishWorktreeFileFrames | null = null;
		const telemetrySamples: BridgeTelemetrySample[] = [];

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={[makeTreeWindowedSnapshotFrame({ rowCount: 300, totalPathCount: 300 })]}
				telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
				worktreeFileSurfaceTransport={{
					subscribeFrames: (handler): (() => void) => {
						publishFrames = handler;
						return (): void => {
							publishFrames = null;
						};
					},
				}}
			/>,
		);

		await waitForMetadataTreeRowCount(300);
		await waitForTreeScrollHeightAtLeast(300 * 24);
		const scrollOwner = requireTreeScrollOwner();
		await actUpdate((): void => {
			scrollOwner.scrollTo({ top: 150 * 24 });
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		});
		await actFrame();
		await actFrame();
		await waitForBridgeViewerTreeItemButton('File-150.swift');
		const anchorPath = requireFirstVisibleTreePath(scrollOwner);
		const anchorOffsetBefore = requireTreeItemOffsetFromScrollOwner({
			path: anchorPath,
			scrollOwner,
		});
		const scrollTopBefore = scrollOwner.scrollTop;

		await actUpdate((): void => {
			requireFramePublisher(publishFrames)(makeResetWithPrependedRows());
		});

		await waitForMetadataTreeRowCount(310);
		await waitForTreeScrollHeightAtLeast(310 * 24);
		await waitForBridgeViewerTreeItemButton(anchorPath);
		const anchorOffsetAfter = requireTreeItemOffsetFromScrollOwner({
			path: anchorPath,
			scrollOwner,
		});

		expect(anchorOffsetAfter - anchorOffsetBefore).toBeGreaterThanOrEqual(10 * 24 - 1);
		expect(scrollOwner.scrollTop).toBe(scrollTopBefore);
		expect(
			telemetrySamples.filter(
				(sample): boolean => sample.name === 'performance.bridge.trees.anchor_restore',
			),
		).toEqual([]);
	});
});

function makeResetWithPrependedRows(): readonly WorktreeFileProtocolFrame[] {
	const source = makeSourceIdentity({
		sourceCursor: 'cursor-reset-anchor',
		subscriptionGeneration: 2,
	});
	const prependedRows = Array.from({ length: 10 }, (_value, index) =>
		makeTreeRow({
			depth: 0,
			fileId: `file-anchor-prepended-${index}`,
			isDirectory: false,
			name: `Anchor-Prepended-${String(index).padStart(3, '0')}.swift`,
			parentPath: null,
			path: `Anchor-Prepended-${String(index).padStart(3, '0')}.swift`,
			sizeBytes: 24,
		}),
	);
	const rows = [...prependedRows, ...makeFlatFileTreeRows({ count: 300, startIndex: 0 })];
	return [
		worktreeFileProtocolFrameSchema.parse({
			kind: 'reset',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 0,
			frameKind: 'worktree.reset',
			source,
			reason: 'sourceChanged',
		}),
		worktreeFileProtocolFrameSchema.parse({
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 1,
			frameKind: 'worktree.snapshot',
			source,
			metadataLineage: {
				loadedBy: 'reset',
				lane: 'foreground',
			},
			treeRows: rows,
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: rows.length,
				windowStartIndex: 0,
				windowRowCount: rows.length,
				rowHeightPixels: 24,
			},
		}),
	];
}

function requireTreeScrollOwner(): HTMLElement {
	const scrollOwner = findBridgeViewerTreeScrollOwner();
	if (scrollOwner === null) {
		throw new Error('Expected FileView tree scroll owner.');
	}
	return scrollOwner;
}

function requireFirstVisibleTreePath(scrollOwner: HTMLElement): string {
	const visiblePaths = bridgeViewerVisibleTreeItemPaths(scrollOwner);
	const firstVisiblePath = visiblePaths[0];
	if (firstVisiblePath === undefined) {
		throw new Error('Expected at least one visible FileView tree path.');
	}
	return firstVisiblePath;
}

function requireTreeItemOffsetFromScrollOwner(props: {
	readonly path: string;
	readonly scrollOwner: HTMLElement;
}): number {
	const fileTreeContainer = document.querySelector('file-tree-container');
	const button = fileTreeContainer?.shadowRoot?.querySelector(
		`button[data-item-type="file"][data-item-path="${CSS.escape(props.path)}"]`,
	);
	if (!(button instanceof HTMLElement)) {
		throw new Error(`Expected FileView tree item ${props.path}.`);
	}
	return button.getBoundingClientRect().top - props.scrollOwner.getBoundingClientRect().top;
}
