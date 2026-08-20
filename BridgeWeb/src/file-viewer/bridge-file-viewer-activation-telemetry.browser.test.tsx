import { act } from 'react';
import { afterAll, afterEach, beforeEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import { waitForBridgeViewerTreeItemButton } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import {
	makeFileContent,
	makeFileDescriptor,
	makeFileDescriptorForContent,
	makeFileMetadataEvents,
	type PublishFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	actUpdate,
	installBridgeFileViewerNoopResizeObserver,
	makeTestTelemetryRecorder,
	requireMetadataPublisher,
	settleBridgeFileViewerBrowserUpdates,
	waitForMetadataPublisher,
	waitForOpenFileState,
	waitForTelemetrySampleCount,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

const originalResizeObserver = globalThis.ResizeObserver;

describe('Bridge File activation telemetry', () => {
	beforeEach((): void => {
		installBridgeFileViewerNoopResizeObserver();
	});

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

	afterAll((): void => {
		Object.assign(globalThis, { ResizeObserver: originalResizeObserver });
	});

	test('records File TTFI when metadata arrives after the mounted tree setup frame', async () => {
		let publishMetadata: PublishFileMetadataEvents | null = null;
		const telemetrySamples: BridgeTelemetrySample[] = [];
		await render(
			<BridgeFileViewerApp
				isActive={true}
				telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
				fileProductSession={{
					onMetadataSubscription: (publisher) => {
						publishMetadata = publisher;
					},
				}}
			/>,
		);
		await waitForMetadataPublisher(() => publishMetadata);
		await actFrame();
		await actFrame();

		await actUpdate(() => {
			requireMetadataPublisher(publishMetadata)(
				makeFileMetadataEvents(
					makeFileDescriptor({
						contentHandle: 'delayed-ttfi-content',
						fileId: 'delayed-ttfi-file',
						path: 'src/delayed-ttfi.ts',
					}),
				),
			);
		});
		expect(await waitForBridgeViewerTreeItemButton('src/delayed-ttfi.ts')).not.toBeNull();

		const sample = await waitForTelemetrySampleCount({
			count: 1,
			name: 'performance.bridge.viewer.time_to_first_interaction',
			samples: telemetrySamples,
		});
		expect(sample.stringAttributes['agentstudio.bridge.viewer']).toBe('file');
	});

	test('records one File selection commit and one file-open-ready terminal', async () => {
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const content = makeFileContent('export const activationTelemetryReady = true;\n');
		const descriptor = await makeFileDescriptorForContent({
			content,
			contentHandle: 'activation-ready-content',
			fileId: 'activation-ready-file',
			path: 'src/activation-ready.ts',
		});

		await render(
			<BridgeFileViewerApp
				activationCause="review_file_corner"
				activationSequence={17}
				activationStartedAtPerfNow={performance.now()}
				isActive={true}
				initialMetadataEvents={makeFileMetadataEvents(descriptor)}
				openPathCommand={{
					activationStartedAtPerfNow: performance.now(),
					commandId: 17,
					path: 'src/activation-ready.ts',
					traceContext: null,
				}}
				telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
				fileProductSession={{ readContent: async () => content }}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('activationTelemetryReady');
		const selectionCommit = await waitForTelemetrySampleCount({
			count: 1,
			name: 'performance.bridge.web.selection_commit',
			samples: telemetrySamples,
		});
		const fileOpenReady = await waitForTelemetrySampleCount({
			count: 1,
			name: 'performance.bridge.web.file_open_ready',
			samples: telemetrySamples,
		});

		expect(selectionCommit.stringAttributes['agentstudio.bridge.viewer']).toBe('file');
		expect(fileOpenReady.stringAttributes['agentstudio.bridge.viewer']).toBe('file');
		expect(
			telemetrySamples.filter(
				(sample): boolean => sample.name === 'performance.bridge.web.file_open_ready',
			),
		).toHaveLength(1);
		expect(JSON.stringify([selectionCommit, fileOpenReady])).not.toContain('activation-ready.ts');
	});

	test('records context-switcher selection and open-ready without remounting File', async () => {
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const content = makeFileContent('export const contextSwitcherReady = true;\n');
		const descriptor = await makeFileDescriptorForContent({
			content,
			contentHandle: 'context-switcher-ready-content',
			fileId: 'context-switcher-ready-file',
			path: 'src/context-switcher-ready.ts',
		});
		const telemetryRecorder = makeTestTelemetryRecorder(telemetrySamples);
		const fileProductSession = { readContent: async (): Promise<string> => content };
		const initialMetadataEvents = makeFileMetadataEvents(descriptor);
		const { rerender } = await render(
			<BridgeFileViewerApp
				autoOpenInitialFile={true}
				initialMetadataEvents={initialMetadataEvents}
				isActive={false}
				telemetryRecorder={telemetryRecorder}
				fileProductSession={fileProductSession}
			/>,
		);
		expect(await waitForBridgeViewerTreeItemButton('src/context-switcher-ready.ts')).not.toBeNull();
		const activationStartedAtPerfNow = performance.now();

		await act(async (): Promise<void> => {
			await rerender(
				<BridgeFileViewerApp
					activationCause="context_switcher"
					activationSequence={3}
					activationStartedAtPerfNow={activationStartedAtPerfNow}
					autoOpenInitialFile={true}
					initialMetadataEvents={initialMetadataEvents}
					isActive={true}
					telemetryRecorder={telemetryRecorder}
					fileProductSession={fileProductSession}
				/>,
			);
			await Promise.resolve();
		});

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('contextSwitcherReady');
		const selectionCommit = await waitForTelemetrySampleCount({
			count: 1,
			name: 'performance.bridge.web.selection_commit',
			samples: telemetrySamples,
		});
		const fileOpenReady = await waitForTelemetrySampleCount({
			count: 1,
			name: 'performance.bridge.web.file_open_ready',
			samples: telemetrySamples,
		});

		expect(selectionCommit.stringAttributes['agentstudio.bridge.selection.origin']).toBe(
			'context_switcher',
		);
		expect(fileOpenReady.numericAttributes['agentstudio.bridge.demand.request.sequence']).toBe(3);
	});
});
