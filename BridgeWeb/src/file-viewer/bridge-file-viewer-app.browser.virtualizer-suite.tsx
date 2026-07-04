import { act } from 'react';
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
import { BridgeFileViewerApp } from './bridge-file-viewer-app.js';
import {
	makeFlatFileTreeRows,
	makeSourceIdentity,
	makeTreeRow,
	makeTreeWindowedSnapshotFrame,
	type PublishWorktreeFileFrames,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	requireFramePublisher,
	makeTestTelemetryRecorder,
	waitForMetadataTreeRowCount,
	waitForTreeScrollHeightAtLeast,
} from './bridge-file-viewer-browser-test-harness.js';

/**
 * Advances exactly one real animation frame inside its own `act()` scope.
 * Wrapping a whole multi-frame recursive poll in a single `act()` call
 * instead defers React's DOM commits until that call resolves, so a
 * condition that depends on rAF-driven virtualizer/tree layout can never
 * become true while still inside it. Each tick must open and close its own
 * scope so the update from that tick actually commits before the next check.
 */
async function actAnimationFrame(): Promise<void> {
	await act(async (): Promise<void> => {
		await waitForBridgeViewerAnimationFrame();
	});
}

describe('BridgeFileViewerApp virtualizer anchoring', () => {
	afterEach(async () => {
		cleanup();
		await waitForBridgeViewerAnimationFrame();
		document.body.replaceChildren();
	});

	test('keeps the first visible tree row anchored when a reset prepends rows above it', async () => {
		let publishFrames: PublishWorktreeFileFrames | null = null;
		const telemetrySamples: BridgeTelemetrySample[] = [];

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={[makeTreeWindowedSnapshotFrame({ rowCount: 300, totalPathCount: 300 })]}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
				telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
			/>,
		);

		await waitForMetadataTreeRowCount(300);
		await waitForTreeScrollHeightAtLeast(300 * 24);
		const scrollOwner = requireTreeScrollOwner();
		await act(async (): Promise<void> => {
			scrollOwner.scrollTo({ top: 150 * 24 });
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
			await Promise.resolve();
		});
		await actAnimationFrame();
		await actAnimationFrame();
		await waitForBridgeViewerTreeItemButton('File-150.swift');
		const anchorPath = requireFirstVisibleTreePath(scrollOwner);
		const anchorOffsetBefore = requireTreeItemOffsetFromScrollOwner({
			path: anchorPath,
			scrollOwner,
		});
		const scrollTopBefore = scrollOwner.scrollTop;

		await act(async (): Promise<void> => {
			requireFramePublisher(publishFrames)(makeResetWithPrependedRows());
			await Promise.resolve();
		});

		await waitForMetadataTreeRowCount(310);
		await waitForTreeScrollHeightAtLeast(310 * 24);
		await waitForBridgeViewerTreeItemButton(anchorPath);
		await waitForTreeItemOffsetFromScrollOwner({
			expectedOffset: anchorOffsetBefore,
			maxDelta: 1,
			path: anchorPath,
			scrollOwner,
		});

		expect(scrollOwner.scrollTop).toBeGreaterThan(scrollTopBefore);
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

async function waitForTreeItemOffsetFromScrollOwner(props: {
	readonly expectedOffset: number;
	readonly maxDelta: number;
	readonly path: string;
	readonly remainingAttempts?: number;
	readonly scrollOwner: HTMLElement;
}): Promise<void> {
	const currentOffset = requireTreeItemOffsetFromScrollOwner({
		path: props.path,
		scrollOwner: props.scrollOwner,
	});
	if (Math.abs(currentOffset - props.expectedOffset) <= props.maxDelta) {
		return;
	}
	const remainingAttempts = props.remainingAttempts ?? 12;
	if (remainingAttempts <= 0) {
		throw new Error(
			`Expected FileView tree path ${props.path} near offset ${props.expectedOffset}; actual=${currentOffset}; scrollTop=${props.scrollOwner.scrollTop}`,
		);
	}
	await actAnimationFrame();
	await waitForTreeItemOffsetFromScrollOwner({
		...props,
		remainingAttempts: remainingAttempts - 1,
	});
}
