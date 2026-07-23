import { parseDiffFromFile } from '@pierre/diffs';
import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import './bridge-app.css';
import { createBridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { makeBridgeWorkerRenderReceiptIdentity } from '../core/comm-worker/bridge-worker-render-fulfillment.test-support.js';
import { BridgeFileViewerSurfaceClientProvider } from '../file-viewer/bridge-file-viewer-render-snapshot-controller.js';
import { createBridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	FileDisplaySourceProbe,
	ReviewDirectDisplayProbe,
	ReviewIntakeLifecycleProbe,
	fileDisplayEvent,
	hierarchicalReviewDisplayEvent,
	makeFileSurfaceHarness,
	makeReviewSurfaceHarness,
	requireDefined,
	requireHTMLElement,
	reviewDisplayEvent,
	reviewIntakeReadyCommands,
	reviewIntakeReadyRequestIds,
	settleRenderedReviewFrame,
} from './bridge-app-review-render-snapshot-controller.browser-harness.test-support.js';
import { BridgeReviewViewerMode } from './bridge-app-review-viewer-mode.js';
describe('useBridgeReviewRenderSnapshotController Browser Mode', () => {
	test('publishes real keyed Review facts and a later metadata window without a package adapter', async () => {
		// Arrange
		const harness = makeReviewSurfaceHarness();
		const rendered = await render(<ReviewDirectDisplayProbe reviewClient={harness.reviewClient} />);
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

	test('emits one initial Review intake-ready command and does not duplicate it on rerender', async () => {
		// Arrange
		const harness = makeReviewSurfaceHarness();
		const onActiveSourceChange = vi.fn();
		const telemetryRecorderRef = { current: createBridgeTelemetryRecorder(null) };
		const viewerHeaderControls = <div />;
		const rendered = await render(
			<BridgeReviewViewerMode
				isActive={false}
				onActiveSourceChange={onActiveSourceChange}
				reviewClient={harness.reviewClient}
				telemetryRecorderRef={telemetryRecorderRef}
				viewerHeaderControls={viewerHeaderControls}
			/>,
		);
		await expect.element(rendered.getByTestId('bridge-review-fallback-frame')).toBeInTheDocument();

		// Assert
		const initialIntakeReadyCommands = harness.sentCommands.filter(
			(command) => command.command === 'reviewIntakeReady',
		);
		expect(initialIntakeReadyCommands).toHaveLength(1);
		expect(initialIntakeReadyCommands[0]).toMatchObject({
			command: 'reviewIntakeReady',
			protocolId: 'review',
			reason: null,
			streamId: null,
		});

		// Act
		await act(async (): Promise<void> => {
			await rendered.rerender(
				<BridgeReviewViewerMode
					isActive={false}
					onActiveSourceChange={onActiveSourceChange}
					reviewClient={harness.reviewClient}
					telemetryRecorderRef={telemetryRecorderRef}
					viewerHeaderControls={viewerHeaderControls}
				/>,
			);
			await Promise.resolve();
		});

		// Assert
		expect(
			harness.sentCommands.filter((command) => command.command === 'reviewIntakeReady'),
		).toHaveLength(1);
	});

	test('shows loaded Review chrome and explicit empty states for a ready zero-item source', async () => {
		// Arrange
		const harness = makeReviewSurfaceHarness();
		const rendered = await render(
			<BridgeReviewViewerMode
				isActive
				onActiveSourceChange={vi.fn()}
				reviewClient={harness.reviewClient}
				telemetryRecorderRef={{ current: createBridgeTelemetryRecorder(null) }}
				viewerHeaderControls={<div />}
			/>,
		);
		await expect.element(rendered.getByTestId('bridge-review-empty-shell')).toBeVisible();

		// Act
		await act(async (): Promise<void> => {
			harness.publish({
				direction: 'serverWorkerToMain',
				epoch: 1,
				kind: 'reviewDisplayPatch',
				patches: [
					{
						operation: 'upsert',
						payload: {
							metadataWindowIdentity: 'review-window-empty',
							reviewGeneration: 1,
							status: 'ready',
							summary: {
								additions: 0,
								deletions: 0,
								filesChanged: 0,
								hiddenFileCount: 0,
								visibleFileCount: 0,
							},
							totalItemCount: 0,
							totalTreeRowCount: 0,
						},
						slice: 'reviewSource',
					},
					{
						operation: 'batch',
						payload: { items: [], operations: [], reset: true, startIndex: 0 },
						slice: 'reviewItem',
					},
					{
						operation: 'batch',
						payload: { reset: true, windows: [] },
						slice: 'reviewTree',
					},
				],
				projectionRevision: 1,
				sequence: 1,
				surface: 'review',
				transferDescriptors: [],
				wireVersion: 1,
			});
			await import('../review-viewer/shell/review-viewer-shell.js');
			await settleRenderedReviewFrame();
		});

		// Assert
		await expect.element(rendered.getByTestId('review-viewer-shell')).toBeVisible();
		await expect.element(rendered.getByText('Nothing to review')).toBeVisible();
		await expect.element(rendered.getByText('No changed files')).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-mode-segmented-control'))
			.toBeVisible();
		await expect.element(rendered.getByTestId('bridge-review-facet-menu-control')).toBeVisible();
		await expect.element(rendered.getByTestId('bridge-review-search-control')).toBeVisible();
		expect(document.querySelector('[data-testid="bridge-review-fallback-frame"]')).toBeNull();
		expect(
			document.querySelector('[data-testid="bridge-review-projection-pending-shell"]'),
		).toBeNull();
		expect(document.querySelector('[data-slot="skeleton"]')).toBeNull();
		expect(
			rendered
				.getByTestId('bridge-review-rail-tree-slot')
				.element()
				.querySelectorAll('[data-item-path]'),
		).toHaveLength(0);
	});

	test('retries timed-out Review intake-ready delivery until acknowledgement with newer shared epochs', async () => {
		// Arrange
		const harness = makeReviewSurfaceHarness();
		const rendered = await render(
			<ReviewIntakeLifecycleProbe reviewClient={harness.reviewClient} />,
		);
		await expect.element(rendered.getByTestId('review-intake-lifecycle-probe')).toBeInTheDocument();
		const initialRequestId = requireDefined(
			reviewIntakeReadyRequestIds(harness.lifecycleStore)[0],
			'Expected an initial Review intake-ready request.',
		);

		// Act: fail the flushed initial request after the component has already rendered.
		await act(async (): Promise<void> => {
			harness.lifecycleStore.timeoutRequest({ requestId: initialRequestId });
			await Promise.resolve();
		});

		// Assert: exactly one retry uses the next shared Review epoch.
		const retriedCommands = reviewIntakeReadyCommands(harness.sentCommands);
		expect(retriedCommands).toHaveLength(2);
		const initialCommand = requireDefined(
			retriedCommands[0],
			'Expected the initial Review intake-ready command.',
		);
		const retryCommand = requireDefined(
			retriedCommands[1],
			'Expected a retried Review intake-ready command.',
		);
		expect(retryCommand.epoch).toBeGreaterThan(initialCommand.epoch);
		const retryRequestId = requireDefined(
			reviewIntakeReadyRequestIds(harness.lifecycleStore)[1],
			'Expected a retried Review intake-ready request.',
		);

		// Act: acknowledge the retry, rerender, then exercise later select and viewport intents.
		await act(async (): Promise<void> => {
			harness.lifecycleStore.ackRequest({
				acknowledgedAtSequence: 1,
				requestId: retryRequestId,
			});
			await rendered.rerender(<ReviewIntakeLifecycleProbe reviewClient={harness.reviewClient} />);
			await Promise.resolve();
		});
		expect(reviewIntakeReadyCommands(harness.sentCommands)).toHaveLength(2);
		await act(async (): Promise<void> => {
			requireHTMLElement(
				document.querySelector('[data-testid="review-intake-lifecycle-probe"]'),
			).click();
			await Promise.resolve();
		});
		await expect
			.poll(() =>
				harness.sentCommands.some(
					(command) =>
						command.command === 'viewport' && command.visibleItemIds.includes('item-after-intake'),
				),
			)
			.toBe(true);

		// Assert: acknowledgement is terminal and subsequent Review intents remain newer.
		const retryEpoch = retryCommand.epoch;
		const laterSelectCommand = harness.sentCommands.findLast(
			(command) => command.command === 'select',
		);
		const laterViewportCommand = harness.sentCommands.findLast(
			(command) =>
				command.command === 'viewport' && command.visibleItemIds.includes('item-after-intake'),
		);
		expect(laterSelectCommand?.epoch).toBeGreaterThan(retryEpoch);
		expect(laterViewportCommand?.epoch).toBeGreaterThan(retryEpoch);
		expect(reviewIntakeReadyCommands(harness.sentCommands)).toHaveLength(2);
	});

	test('bounds unacknowledged Review intake-ready delivery attempts', async () => {
		// Arrange
		const harness = makeReviewSurfaceHarness();
		const rendered = await render(
			<ReviewIntakeLifecycleProbe reviewClient={harness.reviewClient} />,
		);
		await expect.element(rendered.getByTestId('review-intake-lifecycle-probe')).toBeInTheDocument();

		// Act: exhaust each permitted attempt without acknowledging delivery.
		for (let attemptIndex = 0; attemptIndex < 3; attemptIndex += 1) {
			const requestId = requireDefined(
				reviewIntakeReadyRequestIds(harness.lifecycleStore)[attemptIndex],
				`Expected Review intake-ready request ${attemptIndex + 1}.`,
			);
			// oxlint-disable-next-line no-await-in-loop -- Each timeout synchronously creates the next bounded attempt.
			await act(async (): Promise<void> => {
				harness.lifecycleStore.timeoutRequest({ requestId });
				await Promise.resolve();
			});
		}
		await rendered.rerender(<ReviewIntakeLifecycleProbe reviewClient={harness.reviewClient} />);

		// Assert
		expect(reviewIntakeReadyCommands(harness.sentCommands)).toHaveLength(3);
	});
	test('keeps an inactive recovered Review mount stable across a streamed metadata-window burst', async () => {
		// Arrange
		const harness = makeReviewSurfaceHarness();
		const streamedWindowCount = 32;
		const rendered = await render(
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
		const viewportCommands = harness.sentCommands.filter(
			(command) => command.command === 'viewport',
		);
		expect(viewportCommands).toHaveLength(1);
		expect(viewportCommands[0]).toMatchObject({
			command: 'viewport',
			phase: 'settled',
			visibleItemIds: [],
		});
		expect(viewportCommands.filter((command) => command.visibleItemIds.length > 0)).toEqual([]);
	});
	test('reports a semantically stable File display source once across streamed patches', async () => {
		// Arrange
		const harness = makeFileSurfaceHarness();
		const reportedSources: Array<{ readonly generation: number; readonly sourceId: string }> = [];
		const rendered = await render(
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
		const renderFulfillmentCoordinator = createBridgeMainRenderFulfillmentCoordinator({
			cancelAnimationFrame: (frameHandle): void => cancelAnimationFrame(frameHandle),
			nowMilliseconds: (): number => performance.now(),
			requestAnimationFrame: (callback): number => requestAnimationFrame(callback),
			sendDisposition: (): void => {},
		});
		const reviewClient = {
			...harness.reviewClient,
			renderFulfillmentCoordinator,
		};
		const renderContainer = document.createElement('div');
		renderContainer.style.height = '100vh';
		renderContainer.style.width = '100vw';
		document.body.append(renderContainer);
		const rendered = await render(
			<BridgeReviewViewerMode
				codeViewWorkerPoolEnabled={false}
				isActive={true}
				onActiveSourceChange={onActiveSourceChange}
				reviewClient={reviewClient}
				telemetryRecorderRef={telemetryRecorderRef}
				viewerHeaderControls={<div />}
			/>,
			{ container: renderContainer },
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
		await expect
			.poll(() =>
				harness.sentCommands.some(
					(command) => command.command === 'viewport' && command.visibleItemIds.length > 0,
				),
			)
			.toBe(true);
		await act(async (): Promise<void> => {
			await settleRenderedReviewFrame();
		});
		const viewportCommandCountBeforeDeactivation = harness.sentCommands.filter(
			(command) => command.command === 'viewport',
		).length;

		// Act: retain the recovered shell while Review becomes inactive.
		await act(async (): Promise<void> => {
			await rendered.rerender(
				<BridgeReviewViewerMode
					codeViewWorkerPoolEnabled={false}
					isActive={false}
					onActiveSourceChange={onActiveSourceChange}
					reviewClient={reviewClient}
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
		const deactivationViewportCommands = viewportCommands.slice(
			viewportCommandCountBeforeDeactivation,
		);
		expect(deactivationViewportCommands).toHaveLength(1);
		expect(deactivationViewportCommands[0]).toMatchObject({
			command: 'viewport',
			phase: 'settled',
			visibleItemIds: [],
		});
		renderFulfillmentCoordinator.dispose();
	});
});

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
