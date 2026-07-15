import { parseDiffFromFile } from '@pierre/diffs';
import { act, useMemo, type ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import './bridge-app.css';
import {
	createBridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderFulfillmentCoordinator,
} from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerFileDisplayPatchEvent,
	BridgeWorkerReviewDisplayPatchEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { makeBridgeWorkerRenderReceiptIdentity } from '../core/comm-worker/bridge-worker-render-fulfillment.test-support.js';
import type { BridgeWorkerRpcCommandInput } from '../core/comm-worker/bridge-worker-rpc-client.js';
import { createBridgeWorkerRpcLifecycleStore } from '../core/comm-worker/bridge-worker-rpc-lifecycle-store.js';
import {
	bridgeFileViewerDisplayModelForSnapshot,
	type BridgeFileViewerDisplaySource,
} from '../file-viewer/bridge-file-viewer-display-model.js';
import {
	BridgeFileViewerSurfaceClientProvider,
	useBridgeFileViewerRenderSnapshotController,
} from '../file-viewer/bridge-file-viewer-render-snapshot-controller.js';
import { useBridgeFileViewerDisplaySourceReporter } from '../file-viewer/use-bridge-file-viewer-display-source-reporter.js';
import { createBridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	hierarchicalReviewDisplayEvent,
	reviewDisplayItem,
} from './bridge-app-review-render-snapshot-controller.browser.test-support.js';
import {
	createBridgeReviewWorkerPierreCourier,
	useBridgeReviewRenderSnapshotController,
} from './bridge-app-review-render-snapshot-controller.js';
import { BridgeReviewViewerMode } from './bridge-app-review-viewer-mode.js';

describe('useBridgeReviewRenderSnapshotController Browser Mode', () => {
	test('publishes real keyed Review facts and a later metadata window without a package adapter', async () => {
		// Arrange
		const harness = makeReviewSurfaceHarness();
		const rendered = render(<ReviewDirectDisplayProbe reviewClient={harness.reviewClient} />);
		await expect.element(rendered.getByTestId('review-direct-display-probe')).toBeInTheDocument();

		// Act
		await act(async (): Promise<void> => {
			harness.publish(
				reviewDisplayEvent({
					itemId: 'item-1',
					path: 'Sources/First.swift',
					projectionRevision: 1,
					sequence: 1,
					startIndex: 0,
				}),
			);
		});
		await act(async (): Promise<void> => {
			harness.publish(
				reviewDisplayEvent({
					itemId: 'item-2',
					path: 'Sources/Later.swift',
					projectionRevision: 2,
					sequence: 2,
					startIndex: 1,
				}),
			);
		});

		// Assert
		await expect
			.element(rendered.getByTestId('review-direct-display-probe'))
			.toHaveAttribute('data-review-source-status', 'ready');
		await expect
			.element(rendered.getByTestId('review-direct-display-probe'))
			.toHaveAttribute('data-review-item-order-length', '2');
		await expect
			.element(rendered.getByTestId('review-direct-display-probe'))
			.toHaveAttribute('data-review-tree-row-order-length', '2');
		await expect
			.element(rendered.getByTestId('review-direct-display-probe'))
			.toHaveAttribute('data-review-later-row-path', 'Sources/Later.swift');
	});

	test('keeps an inactive recovered Review mount stable across a streamed metadata-window burst', async () => {
		// Arrange
		const harness = makeReviewSurfaceHarness();
		const streamedWindowCount = 32;
		const rendered = render(
			<BridgeReviewViewerMode
				isActive={false}
				onActiveSourceChange={vi.fn()}
				reviewClient={harness.reviewClient}
				telemetryRecorderRef={{ current: createBridgeTelemetryRecorder(null) }}
				viewerHeaderControls={<div />}
			/>,
		);
		await expect.element(rendered.getByTestId('bridge-review-fallback-frame')).toBeInTheDocument();

		// Act
		await act(async (): Promise<void> => {
			for (let windowIndex = 0; windowIndex < streamedWindowCount; windowIndex += 1) {
				harness.publish(
					reviewDisplayEvent({
						itemId: `item-${windowIndex + 1}`,
						path: `Sources/Streamed-${windowIndex + 1}.swift`,
						projectionRevision: windowIndex + 1,
						sequence: windowIndex + 1,
						startIndex: windowIndex,
						totalItemCount: streamedWindowCount,
					}),
				);
			}
			await Promise.resolve();
		});

		// Assert
		await expect.element(rendered.getByTestId('bridge-review-fallback-frame')).toBeInTheDocument();
		expect(document.querySelector('[data-testid="review-viewer-shell"]')).toBeNull();
		expect(harness.reviewClient.renderStore.getReviewCatalogSnapshot()).toMatchObject({
			itemOrderLength: streamedWindowCount,
			revision: streamedWindowCount,
			treeRowOrderLength: streamedWindowCount,
		});
		expect(
			harness.reviewClient.renderStore.getReviewTreeRowSnapshot(`row-item-${streamedWindowCount}`),
		).toMatchObject({
			itemId: `item-${streamedWindowCount}`,
			path: `Sources/Streamed-${streamedWindowCount}.swift`,
		});
		expect(harness.sentCommands.filter((command) => command.command === 'viewport')).toEqual([]);
	});

	test('reports a semantically stable File display source once across streamed patches', async () => {
		// Arrange
		const harness = makeFileSurfaceHarness();
		const reportedSources: Array<{ readonly generation: number; readonly sourceId: string }> = [];
		const rendered = render(
			<BridgeFileViewerSurfaceClientProvider surfaceClient={harness.fileViewClient}>
				<FileDisplaySourceProbe
					onDisplaySourceChange={(source): void => {
						if (source !== null) reportedSources.push(source);
					}}
				/>
			</BridgeFileViewerSurfaceClientProvider>,
		);
		await expect.element(rendered.getByTestId('file-display-source-probe')).toBeInTheDocument();

		// Act
		for (let patchIndex = 0; patchIndex < 32; patchIndex += 1) {
			// oxlint-disable-next-line no-await-in-loop -- Separate React commits reproduce the passive-effect update boundary.
			await act(async (): Promise<void> => {
				harness.publish(
					fileDisplayEvent({
						projectionRevision: patchIndex + 1,
						sequence: patchIndex + 1,
					}),
				);
				await Promise.resolve();
			});
		}

		// Assert
		expect(reportedSources).toEqual([{ generation: 1, sourceId: 'source-1' }]);
	});

	test('mounts terminal Review content from worker display and Pierre messages', async () => {
		// Arrange
		const harness = makeReviewSurfaceHarness();
		const onActiveSourceChange = vi.fn();
		const telemetryRecorderRef = { current: createBridgeTelemetryRecorder(null) };
		const rendered = render(
			<BridgeReviewViewerMode
				isActive={true}
				onActiveSourceChange={onActiveSourceChange}
				reviewClient={harness.reviewClient}
				telemetryRecorderRef={telemetryRecorderRef}
				viewerHeaderControls={<div />}
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			harness.publish(hierarchicalReviewDisplayEvent());
			await import('../review-viewer/shell/review-viewer-shell.js');
			await settleRenderedReviewFrame();
		});
		await expect
			.poll(() => harness.sentCommands.some((command) => command.command === 'select'))
			.toBe(true);
		await expect.element(rendered.getByTestId('bridge-review-trees-panel')).toBeInTheDocument();
		await act(async (): Promise<void> => {
			for (const message of reviewContentReadyEvents()) harness.publish(message);
			await settleRenderedReviewFrame();
		});

		// Assert
		const shell = rendered.getByTestId('review-viewer-shell');
		const codePanel = rendered.getByTestId('bridge-code-view-panel');
		await expect.element(rendered.getByTestId('bridge-review-trees-panel')).toBeInTheDocument();
		await expect.element(shell).toHaveAttribute('data-selected-content-state', 'ready');
		await expect
			.element(shell)
			.toHaveAttribute('data-selected-display-path', 'Sources/First.swift');
		await expect
			.element(codePanel)
			.toHaveAttribute('data-selected-display-path', 'Sources/First.swift');
		const codePanelElement = requireHTMLElement(
			document.querySelector('[data-testid="bridge-code-view-panel"]'),
		);
		expect(
			Number(codePanelElement.getAttribute('data-selected-content-character-count')),
		).toBeGreaterThan(0);
		expect(
			Number(codePanelElement.getAttribute('data-selected-content-line-count')),
		).toBeGreaterThan(0);
		expect(
			Number(codePanelElement.getAttribute('data-selected-content-cache-key-count')),
		).toBeGreaterThan(0);
		expect(document.querySelectorAll('[data-testid="review-viewer-shell"]')).toHaveLength(1);
		expect(document.querySelector('[data-testid="bridge-review-tree-scroll"]')).toBeNull();
		expect(
			harness.sentCommands.some(
				(command) => command.command === 'viewport' && command.visibleItemIds.length > 0,
			),
		).toBe(true);

		// Act: retain the recovered shell while Review becomes inactive.
		await act(async (): Promise<void> => {
			rendered.rerender(
				<BridgeReviewViewerMode
					isActive={false}
					onActiveSourceChange={onActiveSourceChange}
					reviewClient={harness.reviewClient}
					telemetryRecorderRef={telemetryRecorderRef}
					viewerHeaderControls={<div />}
				/>,
			);
			await settleRenderedReviewFrame();
		});

		// Assert: one transition clear replaces foreground Review demand.
		const viewportCommands = harness.sentCommands.filter(
			(command) => command.command === 'viewport',
		);
		expect(viewportCommands.at(-1)).toMatchObject({ command: 'viewport', visibleItemIds: [] });
		expect(
			viewportCommands.filter(
				(command) => command.command === 'viewport' && command.visibleItemIds.length === 0,
			),
		).toHaveLength(1);
	});
});

function ReviewDirectDisplayProbe(props: {
	readonly reviewClient: BridgePaneSurfaceClient;
}): ReactElement {
	const pierreCourier = useMemo(() => createBridgeReviewWorkerPierreCourier(), []);
	const controller = useBridgeReviewRenderSnapshotController({
		pierreCourier,
		reviewClient: props.reviewClient,
	});
	return (
		<output
			data-review-item-order-length={controller.catalogSnapshot.itemOrderLength}
			data-review-later-row-path={controller.displayStore.getReviewTreeRowAtIndex(1)?.path ?? ''}
			data-review-source-status={controller.reviewSourceSlice?.status ?? 'absent'}
			data-review-tree-row-order-length={controller.catalogSnapshot.treeRowOrderLength}
			data-testid="review-direct-display-probe"
		/>
	);
}

function FileDisplaySourceProbe(props: {
	readonly onDisplaySourceChange: (source: BridgeFileViewerDisplaySource | null) => void;
}): ReactElement {
	const renderSnapshotController = useBridgeFileViewerRenderSnapshotController({ selection: null });
	const displayModel = useMemo(
		() => bridgeFileViewerDisplayModelForSnapshot(renderSnapshotController.fileDisplaySnapshot),
		[renderSnapshotController.fileDisplaySnapshot],
	);
	useBridgeFileViewerDisplaySourceReporter({
		onDisplaySourceChange: props.onDisplaySourceChange,
		source: displayModel.source,
	});
	return <output data-testid="file-display-source-probe" />;
}

interface ReviewSurfaceHarness {
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
	readonly reviewClient: BridgePaneSurfaceClient;
	readonly sentCommands: BridgeWorkerRpcCommandInput[];
}

interface FileSurfaceHarness {
	readonly fileViewClient: BridgePaneSurfaceClient;
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
}

function makeFileSurfaceHarness(): FileSurfaceHarness {
	const displayStore = createBridgeMainRenderSnapshotStore();
	const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
	let messageListener: ((message: BridgeWorkerServerToMainMessage) => void) | null = null;
	return {
		fileViewClient: {
			lifecycle: lifecycleStore,
			renderFulfillmentCoordinator: createTestRenderFulfillmentCoordinator(),
			renderStore: displayStore,
			send: vi.fn((): string => 'file-request-1'),
			subscribeMessages: (listener): (() => void) => {
				messageListener = listener;
				return (): void => {
					messageListener = null;
				};
			},
			surface: 'fileView',
		},
		publish: (message): void => {
			if (messageListener === null) throw new Error('Expected the File message listener.');
			messageListener(message);
		},
	};
}

function makeReviewSurfaceHarness(): ReviewSurfaceHarness {
	const displayStore = createBridgeMainRenderSnapshotStore();
	const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
	const sentCommands: BridgeWorkerRpcCommandInput[] = [];
	let messageListener: ((message: BridgeWorkerServerToMainMessage) => void) | null = null;
	return {
		publish: (message): void => {
			if (messageListener === null) throw new Error('Expected the Review message listener.');
			messageListener(message);
		},
		reviewClient: {
			lifecycle: lifecycleStore,
			renderFulfillmentCoordinator: createTestRenderFulfillmentCoordinator(),
			renderStore: displayStore,
			send: vi.fn((command): string => {
				sentCommands.push(command);
				return `review-request-${sentCommands.length}`;
			}),
			subscribeMessages: (listener): (() => void) => {
				messageListener = listener;
				return (): void => {
					messageListener = null;
				};
			},
			surface: 'review',
		},
		sentCommands,
	};
}

function createTestRenderFulfillmentCoordinator(): BridgeMainRenderFulfillmentCoordinator {
	return createBridgeMainRenderFulfillmentCoordinator({
		cancelAnimationFrame: (_frameHandle): void => {},
		nowMilliseconds: (): number => 0,
		requestAnimationFrame: (_callback): number => {
			throw new Error('Review Browser fixture must not schedule paint validation.');
		},
		sendDisposition: (_receipt): void => {},
	});
}

function fileDisplayEvent(props: {
	readonly projectionRevision: number;
	readonly sequence: number;
}): BridgeWorkerFileDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'fileDisplayPatch',
		patches: [
			{
				operation: 'reset',
				payload: {
					sourceGeneration: 1,
					sourceId: 'source-1',
				},
				slice: 'fileTree',
			},
			{
				itemId: 'file-1',
				operation: 'upsert',
				payload: {
					availability: { kind: 'available' },
					displayPath: 'README.md',
					endsMidLine: false,
					endsWithNewline: true,
					extent: { kind: 'exactLineCount', lineCount: 1 },
					fileExtension: 'md',
					language: 'markdown',
					payloadByteCount: 6,
					payloadLineCount: 1,
					rowId: 'row-1',
					sizeBytes: 6,
					totalLineCount: 1,
					truncationKind: 'none',
				},
				slice: 'fileItem',
			},
		],
		projectionRevision: props.projectionRevision,
		sequence: props.sequence,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function reviewContentReadyEvents(): readonly BridgeWorkerServerToMainMessage[] {
	const job = buildBridgeWorkerPierreRenderJob({
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
		contentCacheKey: 'pierre-content:base|pierre-content:head',
		contentHash: 'review-content-1',
		itemId: 'item-1',
		language: 'swift',
		payload: {
			item: {
				bridgeMetadata: {
					cacheKey: 'pierre-content:base|pierre-content:head',
					contentRoles: ['base', 'head'],
					contentState: 'hydrated',
					displayPath: 'Sources/First.swift',
					itemId: 'item-1',
					lineCount: 2,
				},
				fileDiff: parseDiffFromFile(
					{
						cacheKey: 'pierre-content:base',
						contents: 'let answer = 41\n',
						name: 'Sources/First.swift',
					},
					{
						cacheKey: 'pierre-content:head',
						contents: 'let answer = 42\n',
						name: 'Sources/First.swift',
					},
				),
				id: 'item-1',
				type: 'diff',
				version: 1,
			},
			kind: 'codeViewDiffItem',
		},
		renderKind: 'reviewDiff',
		window: { endLine: 2, startLine: 1, totalLineCount: 2 },
	});
	return [
		{
			direction: 'serverWorkerToMain',
			job,
			kind: 'reviewPierreRenderJob',
			publicationSequence: 2,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: job.itemId,
				publicationSequence: 2,
				surface: 'review',
				workerDerivationEpoch: 1,
			}),
			surface: 'review',
			transferDescriptors: [
				{
					byteLength: job.payloadByteLength,
					fieldPath: ['job', 'payload'],
					messageKind: 'reviewPierreRenderJob',
					mode: 'clone',
				},
			],
			wireVersion: 1,
			workerDerivationEpoch: 1,
		},
		{
			direction: 'serverWorkerToMain',
			kind: 'reviewRenderPatch',
			patches: [
				{
					itemId: 'item-1',
					operation: 'upsert',
					payload: { contentCacheKey: 'pierre-content:base|pierre-content:head' },
					slice: 'rowPaint',
				},
				{
					itemId: 'item-1',
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
			],
			publicationSequence: 2,
			surface: 'review',
			transferDescriptors: [],
			wireVersion: 1,
			workerDerivationEpoch: 1,
		},
	];
}

function reviewDisplayEvent(props: {
	readonly itemId: string;
	readonly path: string;
	readonly projectionRevision: number;
	readonly sequence: number;
	readonly startIndex: number;
	readonly totalItemCount?: number;
}): BridgeWorkerReviewDisplayPatchEvent {
	const totalItemCount = props.totalItemCount ?? 2;
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					metadataWindowIdentity: `review-window-${props.projectionRevision}`,
					status: 'ready',
					summary: {
						additions: 1,
						deletions: 0,
						filesChanged: 2,
						hiddenFileCount: 0,
						visibleFileCount: 2,
					},
					totalItemCount,
					totalTreeRowCount: totalItemCount,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: [reviewDisplayItem(props.itemId, props.path)],
					operations: [],
					reset: props.startIndex === 0,
					startIndex: props.startIndex,
				},
				slice: 'reviewItem',
			},
			{
				operation: 'batch',
				payload: {
					reset: props.startIndex === 0,
					windows: [
						{
							rows: [
								{
									depth: 1,
									isDirectory: false,
									itemId: props.itemId,
									path: props.path,
									rowId: `row-${props.itemId}`,
								},
							],
							startIndex: props.startIndex,
						},
					],
				},
				slice: 'reviewTree',
			},
		],
		projectionRevision: props.projectionRevision,
		sequence: props.sequence,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected an HTML element.');
	return element;
}

async function settleRenderedReviewFrame(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve) => {
		requestAnimationFrame((): void => resolve());
	});
	await Promise.resolve();
}
