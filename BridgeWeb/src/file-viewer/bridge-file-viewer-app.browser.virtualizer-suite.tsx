import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
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
	makeSourceAcceptedMetadataEvent,
	makeTreeRow,
	makeTreeWindowedMetadataEvents,
	parseFileMetadataEvent,
	type FileMetadataEvent,
	type PublishFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	actUpdate,
	requireMetadataPublisher,
	makeTestTelemetryRecorder,
	settleBridgeFileViewerBrowserUpdates,
	waitForMetadataTreeRowCount,
	waitForTreeScrollHeightAtLeast,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp virtualizer anchoring', () => {
	afterEach(async () => {
		await settleBridgeFileViewerBrowserUpdates();
		cleanup();
		await waitForBridgeViewerAnimationFrame();
		document.body.replaceChildren();
	});

	test('does not app-side anchor restore when a reset prepends rows above the viewport', async () => {
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;
		const telemetrySamples: BridgeTelemetrySample[] = [];

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeTreeWindowedMetadataEvents({
					rowCount: 240,
					totalPathCount: 240,
				})}
				telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
				fileProductSession={{
					onMetadataSubscription: (handler): (() => void) => {
						publishMetadataEvents = handler;
						return (): void => {
							publishMetadataEvents = null;
						};
					},
				}}
			/>,
		);

		await waitForMetadataTreeRowCount(240);
		await waitForTreeScrollHeightAtLeast(240 * 24);
		const scrollOwner = requireTreeScrollOwner();
		await actUpdate((): void => {
			scrollOwner.scrollTo({ top: 150 * 24 });
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		});
		await actFrame();
		await actFrame();
		await waitForBridgeViewerTreeItemButton('File-150.swift');
		const anchorPath = requireFirstVisibleTreePath(scrollOwner);
		const scrollTopBefore = scrollOwner.scrollTop;

		await actUpdate((): void => {
			requireMetadataPublisher(publishMetadataEvents)(makeResetWithPrependedRows());
		});
		expect(scrollOwner.scrollTop).toBe(scrollTopBefore);

		await waitForMetadataTreeRowCount(250);
		expect(scrollOwner.scrollTop).toBe(scrollTopBefore);
		await waitForTreeScrollHeightAtLeast(250 * 24);
		expect(scrollOwner.scrollTop).toBe(scrollTopBefore);
		await actFrame();
		await actFrame();
		const firstVisiblePathAfter = requireFirstVisibleTreePath(scrollOwner);

		expect(requireTreeScrollOwner()).toBe(scrollOwner);
		expect(scrollOwner.isConnected).toBe(true);
		expect(firstVisiblePathAfter).not.toBe(anchorPath);
		expect(scrollOwner.scrollTop).toBe(scrollTopBefore);
		expect(
			telemetrySamples.filter(
				(sample): boolean => sample.name === 'performance.bridge.trees.anchor_restore',
			),
		).toEqual([]);
	});
});

function makeResetWithPrependedRows(): readonly FileMetadataEvent[] {
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
	const rows = [...prependedRows, ...makeFlatFileTreeRows({ count: 240, startIndex: 0 })];
	return [
		makeSourceAcceptedMetadataEvent(source),
		parseFileMetadataEvent({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: {
				loadedBy: 'replacement',
				lane: 'foreground',
			},
			pathScope: [],
			rows,
			source,
			startIndex: 0,
			totalRowCount: rows.length,
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
