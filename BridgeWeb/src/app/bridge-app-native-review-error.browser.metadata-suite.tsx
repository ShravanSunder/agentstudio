import { act } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import {
	buildReviewMetadataDeltaFrame,
	buildReviewMetadataSnapshotFrame,
	buildReviewMetadataWindowFrame,
} from '../features/review/protocol/review-metadata-frame-builder.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryBatch } from '../foundation/telemetry/bridge-telemetry-event.js';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerText,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import type {
	WorktreeFileFrameSubscriber,
	WorktreeFileInitialSurface,
} from '../worktree-file-surface/worktree-file-app.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import {
	actClick,
	actWait,
	chunkedTextResponse,
	dispatchHostAdmittedReviewIntakeFrame,
	makeWindowedReviewPackage,
	makeWorktreeFileDescriptorForFrameTest,
	makeWorktreeFileFramesForFrameTest,
	pollWithinAct,
	pollWithinActUntilEqual,
	pollWithinActUntilTruthy,
	recordBridgeTelemetryBatchFetch,
	telemetrySamplesFromBatches,
} from './bridge-app-native-review-error.browser.test-support.js';
import { BridgeApp } from './bridge-app.js';

describe('BridgeApp native review intake Browser Mode', () => {
	afterEach(() => {
		document.documentElement.removeAttribute('data-bridge-nonce');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		terminateBridgePierreWorkerPoolSingletonForTest();
		vi.restoreAllMocks();
	});

	test('keeps FileView mounted and ready across Review mode metadata loading', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const streamId = 'review:bridge-app-test-pane';
		const fileDescriptor = makeWorktreeFileDescriptorForFrameTest();
		const loadEvents: string[] = [];
		const fetchedFileResourceUrls: string[] = [];
		let publishWorktreeFileFrames: WorktreeFileFrameSubscriber | null = null;
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 80),
		});
		const handleBridgeCommand = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			if (
				typeof detail === 'object' &&
				detail !== null &&
				'method' in detail &&
				detail.method === 'bridge.ready' &&
				'id' in detail
			) {
				document.dispatchEvent(
					new CustomEvent('__bridge_response', {
						detail: { id: detail.id, result: null },
					}),
				);
			}
		};
		const handleBridgeHandshakeRequest = (): void => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
		};
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadEvents.push('worktree-file.load');
			return {
				frames: makeWorktreeFileFramesForFrameTest(fileDescriptor),
				source: fileDescriptor.sourceIdentity,
			};
		};
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource): Promise<Response> => {
			const resourceUrl =
				typeof resource === 'string'
					? resource
					: resource instanceof URL
						? resource.toString()
						: resource.url;
			return resourceUrl.startsWith('agentstudio://resource/review/content/')
				? chunkedTextResponse(['struct ReviewFixture {}\n'])
				: new Response('unexpected request', { status: 404 });
		});
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		document.addEventListener('__bridge_handshake_request', handleBridgeHandshakeRequest);
		document.addEventListener('__bridge_command', handleBridgeCommand);

		try {
			render(
				<BridgeApp
					fileViewerProps={{
						autoOpenInitialFile: true,
						worktreeFileSurfaceTransport: {
							fetchResource: async (props) => {
								fetchedFileResourceUrls.push(props.resourceUrl);
								return makeWorktreeFileSurfaceRuntimeFetchedResource(
									'export const stableAcrossModes = true;\n',
								);
							},
							loadInitialSurface,
							subscribeFrames: (subscriber): (() => void) => {
								publishWorktreeFileFrames = subscriber;
								return (): void => {
									publishWorktreeFileFrames = null;
								};
							},
						},
					}}
					viewerMode="file"
				/>,
			);
			await pollWithinAct({
				getValue: () =>
					document
						.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')
						?.getAttribute('data-worktree-open-file-body-preview'),
				isSatisfied: (value): boolean => (value ?? '').includes('stableAcrossModes'),
			});
			const fileModeHost = requireBridgeViewerHTMLElement(
				document.querySelector('[data-testid="bridge-viewer-mode-host-file"]'),
			);
			const fileShell = requireBridgeViewerHTMLElement(
				document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
			);
			const fileCodeCanvas = requireBridgeViewerHTMLElement(
				document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]'),
			);
			expect(loadEvents).toEqual(['worktree-file.load']);
			expect(fetchedFileResourceUrls).toEqual([
				'agentstudio://resource/worktree-file/worktree.fileContent/file-frame-stable-content?generation=1&cursor=file-frame-cursor',
			]);
			await actClick(
				requireBridgeViewerHTMLElement(
					document.querySelector('[data-testid="worktree-file-search-toggle"]'),
				),
			);
			await actWait(waitForBridgeViewerAnimationFrame);
			const fileSearchInput = requireHTMLInputElement(
				document.querySelector('[data-testid="worktree-file-search-input"]'),
			);
			await setReactInputValue(fileSearchInput, 'StableAcrossModes');
			await actWait(waitForBridgeViewerAnimationFrame);
			await actClick(
				requireBridgeViewerHTMLElement(
					document.querySelector('[data-testid="worktree-file-filter-menu"]'),
				),
			);
			await actWait(waitForBridgeViewerAnimationFrame);
			const textFilterOption = [
				...document.querySelectorAll('[data-testid="worktree-file-filter-menu-option"]'),
			]
				.filter((option): option is HTMLElement => option instanceof HTMLElement)
				.find((option): boolean => option.textContent?.includes('Text files') ?? false);
			if (textFilterOption === undefined) {
				throw new Error('Expected Worktree/File Text files filter option.');
			}
			await actClick(textFilterOption);
			await actWait(waitForBridgeViewerAnimationFrame);
			expect(fileSearchInput.value).toBe('StableAcrossModes');
			expect(
				document.querySelector('[data-testid="worktree-file-filter-menu-active-indicator"]'),
			).not.toBeNull();

			await actClick(
				requireBridgeViewerHTMLElement(
					document.querySelector('[data-testid="bridge-viewer-context-review"]'),
				),
			);
			await pollWithinAct({
				getValue: () =>
					document
						.querySelector('[data-testid="bridge-viewer-mode-host-review"]')
						?.getAttribute('data-bridge-viewer-mode-active'),
				isSatisfied: (value): boolean => value === 'true',
			});
			await dispatchHostAdmittedReviewIntakeFrame({
				kind: 'reset',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: 0,
				payload: {
					kind: 'reset',
					streamId,
					generation: reviewPackage.reviewGeneration,
					sequence: 0,
					frameKind: 'review.reset',
					reason: 'authorityChanged',
					sourceIdentity: reviewPackage.query.queryId,
				},
			});
			await pollWithinActUntilTruthy(() =>
				document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]'),
			);
			expect(fileModeHost.getAttribute('data-bridge-viewer-mode-active')).toBe('false');
			expect(document.querySelector('[data-testid="bridge-file-viewer-shell"]')).toBe(fileShell);
			expect(document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')).toBe(
				fileCodeCanvas,
			);
			expect(fileCodeCanvas.getAttribute('data-worktree-open-file-body-preview')).toContain(
				'stableAcrossModes',
			);
			await requireWorktreeFileFramePublisher(publishWorktreeFileFrames)([
				{
					kind: 'delta',
					streamId: 'worktree-file:bridge-worktree-dev-pane',
					generation: 1,
					sequence: 2,
					frameKind: 'worktree.treeWindow',
					projectionIdentity: {
						source: fileDescriptor.sourceIdentity,
						pathScope: [],
						sortKey: 'path',
						groupKey: 'none',
						filterKey: 'all',
						treeWindowKey: 'hidden-review-mode-window',
					},
					metadataLineage: {
						loadedBy: 'idle',
						lane: 'idle',
					},
					rows: [
						{
							rowId: 'row-hidden-mode-update',
							path: 'Sources/App/HiddenReviewModeUpdate.swift',
							name: 'HiddenReviewModeUpdate.swift',
							parentPath: 'Sources/App',
							depth: 2,
							isDirectory: false,
							fileId: 'file-hidden-mode-update',
						},
					],
					treeSizeFacts: {
						extentKind: 'exactPathCount',
						pathCount: 2,
						windowStartIndex: 1,
						windowRowCount: 1,
						rowHeightPixels: 24,
					},
				},
			]);
			await pollWithinAct({
				getValue: () =>
					document
						.querySelector('[data-testid="bridge-file-viewer-shell"]')
						?.getAttribute('data-worktree-metadata-tree-row-count'),
				isSatisfied: (value): boolean => value === '2',
			});
			expect(loadEvents).toEqual(['worktree-file.load']);
			expect(fetchedFileResourceUrls).toHaveLength(1);

			await dispatchHostAdmittedReviewIntakeFrame({
				kind: 'snapshot',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: snapshotFrame.sequence,
				payload: snapshotFrame,
			});
			await pollWithinActUntilTruthy(() =>
				document.querySelector('[data-testid="review-viewer-shell"]'),
			);
			expect(fileModeHost.getAttribute('data-bridge-viewer-mode-active')).toBe('false');
			expect(document.querySelector('[data-testid="bridge-file-viewer-shell"]')).toBe(fileShell);
			expect(document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')).toBe(
				fileCodeCanvas,
			);
			expect(loadEvents).toEqual(['worktree-file.load']);
			expect(fetchedFileResourceUrls).toHaveLength(1);

			await actClick(
				requireBridgeViewerHTMLElement(
					document.querySelector('[data-testid="bridge-viewer-context-file"]'),
				),
			);
			await pollWithinAct({
				getValue: () => fileModeHost.getAttribute('data-bridge-viewer-mode-active'),
				isSatisfied: (value): boolean => value === 'true',
			});
			expect(document.querySelector('[data-testid="bridge-file-viewer-shell"]')).toBe(fileShell);
			expect(document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')).toBe(
				fileCodeCanvas,
			);
			expect(fileCodeCanvas.getAttribute('data-worktree-open-file-state')).toBe('ready');
			expect(fileCodeCanvas.getAttribute('data-worktree-open-file-body-preview')).toContain(
				'stableAcrossModes',
			);
			expect(
				requireHTMLInputElement(
					document.querySelector('[data-testid="worktree-file-search-input"]'),
				).value,
			).toBe('StableAcrossModes');
			expect(
				document.querySelector('[data-testid="worktree-file-filter-menu-active-indicator"]'),
			).not.toBeNull();
			expect(loadEvents).toEqual(['worktree-file.load']);
			expect(fetchedFileResourceUrls).toHaveLength(1);
		} finally {
			document.removeEventListener('__bridge_handshake_request', handleBridgeHandshakeRequest);
			document.removeEventListener('__bridge_command', handleBridgeCommand);
		}
	});

	test('renders the review shell when modified base descriptors omit exact byte count', async () => {
		const basePackage = makeBridgeReviewPackage();
		const item = basePackage.itemsById['item-source'];
		if (
			item === undefined ||
			item.contentRoles.base === null ||
			item.contentRoles.base === undefined
		) {
			throw new Error('Expected modified item base content handle');
		}
		const reviewPackage: BridgeReviewPackage = {
			...basePackage,
			itemsById: {
				...basePackage.itemsById,
				[item.itemId]: {
					...item,
					contentRoles: {
						...item.contentRoles,
						base: {
							...item.contentRoles.base,
							sizeBytes: 2048,
							resourceUrl: `${item.contentRoles.base.resourceUrl}&cursor=old-base`,
						},
					},
				},
			},
		};
		const streamId = 'review:bridge-app-test-pane';
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 80),
		});
		const baseDescriptorId = item.contentRoles.base.handleId;
		const contentDescriptors =
			snapshotFrame.comparison.contentDescriptors?.map((attachedDescriptor) =>
				attachedDescriptor.ref.descriptorId === baseDescriptorId
					? {
							...attachedDescriptor,
							descriptor: {
								...attachedDescriptor.descriptor,
								content: {
									...attachedDescriptor.descriptor.content,
									expectedBytes: undefined,
									maxBytes: 8 * 1024 * 1024,
								},
							},
						}
					: attachedDescriptor,
			) ?? [];
		const inexactSnapshotFrame = {
			...snapshotFrame,
			comparison: {
				...snapshotFrame.comparison,
				contentDescriptors,
			},
		};
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource): Promise<Response> => {
			const resourceUrl =
				typeof resource === 'string'
					? resource
					: resource instanceof URL
						? resource.toString()
						: resource.url;
			return resourceUrl.startsWith('agentstudio://resource/review/content/')
				? chunkedTextResponse(['struct ModifiedBaseFixture {}\n'])
				: new Response('unexpected request', { status: 404 });
		});
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: reviewPackage.query.queryId,
			},
		});
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'snapshot',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: inexactSnapshotFrame.sequence,
			payload: inexactSnapshotFrame,
		});

		await pollWithinActUntilTruthy(() =>
			document.querySelector('[data-testid="review-viewer-shell"]'),
		);
		expect(
			document.querySelector('[data-testid="bridge-review-metadata-failed-shell"]'),
		).toBeNull();
	});

	test('selects and hydrates a modified file that arrives in a metadata window', async () => {
		const reviewPackage = makeWindowedReviewPackage(3);
		const streamId = 'review:bridge-app-test-pane';
		const visibleItemIds = reviewPackage.orderedItemIds.slice(0, 1);
		const targetItemId = reviewPackage.orderedItemIds[1];
		if (targetItemId === undefined) {
			throw new Error('Expected windowed target item');
		}
		const targetItem = reviewPackage.itemsById[targetItemId];
		if (
			targetItem === undefined ||
			typeof targetItem.headPath !== 'string' ||
			targetItem.contentRoles.base === null ||
			targetItem.contentRoles.base === undefined ||
			targetItem.contentRoles.head === null ||
			targetItem.contentRoles.head === undefined
		) {
			throw new Error('Expected target modified item with base and head content');
		}
		const targetHeadPath = targetItem.headPath;
		const fetchedResourceUrls: string[] = [];
		const telemetryBatches: BridgeTelemetryBatch[] = [];
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds,
		});
		const metadataWindowFrame = buildReviewMetadataWindowFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 2,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			itemIds: reviewPackage.orderedItemIds.slice(1, 3),
		});
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource, init): Promise<Response> => {
			const telemetryResponse = recordBridgeTelemetryBatchFetch(resource, init, telemetryBatches);
			if (telemetryResponse !== null) {
				return telemetryResponse;
			}
			const resourceUrl =
				typeof resource === 'string'
					? resource
					: resource instanceof URL
						? resource.toString()
						: resource.url;
			fetchedResourceUrls.push(resourceUrl);
			if (!resourceUrl.startsWith('agentstudio://resource/review/content/')) {
				return new Response('unexpected request', { status: 404 });
			}
			return resourceUrl.includes('-base')
				? chunkedTextResponse([`// previous ${targetItemId}\n`])
				: chunkedTextResponse([`struct ${targetItemId.replaceAll('-', '_')} {}\n`]);
		});
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: reviewPackage.query.queryId,
			},
		});
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'snapshot',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: snapshotFrame.sequence,
			payload: snapshotFrame,
		});
		await pollWithinAct({
			getValue: () =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-display-path'),
			isSatisfied: (value): boolean => value !== targetHeadPath,
		});

		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'delta',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: metadataWindowFrame.sequence,
			payload: metadataWindowFrame,
		});

		const targetButton = await actWait(() => waitForBridgeViewerTreeItemButton(targetHeadPath));
		await actClick(targetButton);

		await pollWithinActUntilEqual(
			() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-display-path'),
			targetHeadPath,
		);
		await pollWithinActUntilEqual(
			() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-content-state'),
			'ready',
		);
		expect(fetchedResourceUrls).toContain(targetItem.contentRoles.base.resourceUrl);
		expect(fetchedResourceUrls).toContain(targetItem.contentRoles.head.resourceUrl);
	});

	test('keeps last completed review tree when a newer bounded snapshot arrives before its refill window', async () => {
		const commands: unknown[] = [];
		const telemetryBatches: BridgeTelemetryBatch[] = [];
		const handleBridgeCommand = (event: Event): void => {
			commands.push('detail' in event ? event.detail : null);
		};
		const reviewPackage = makeWindowedReviewPackage(90);
		const streamId = 'review:bridge-app-test-pane';
		const initialVisibleItemIds = reviewPackage.orderedItemIds.slice(0, 80);
		const targetItemId = reviewPackage.orderedItemIds[84];
		if (targetItemId === undefined) {
			throw new Error('Expected windowed target item');
		}
		const targetItem = reviewPackage.itemsById[targetItemId];
		if (targetItem === undefined || typeof targetItem.headPath !== 'string') {
			throw new Error('Expected target modified item with head path');
		}
		const targetHeadPath = targetItem.headPath;
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: initialVisibleItemIds,
		});
		const metadataWindowFrame = buildReviewMetadataWindowFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 2,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			itemIds: reviewPackage.orderedItemIds.slice(80, 90),
		});
		const nextRevisionPackage = {
			...reviewPackage,
			revision: reviewPackage.revision + 1,
		};
		const boundedNextSnapshotFrame = buildReviewMetadataSnapshotFrame({
			package: nextRevisionPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 3,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 10),
		});
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource, init): Promise<Response> => {
			const telemetryResponse = recordBridgeTelemetryBatchFetch(resource, init, telemetryBatches);
			if (telemetryResponse !== null) {
				return telemetryResponse;
			}
			const resourceUrl =
				typeof resource === 'string'
					? resource
					: resource instanceof URL
						? resource.toString()
						: resource.url;
			return resourceUrl.startsWith('agentstudio://resource/review/content/')
				? chunkedTextResponse([`struct ${targetItemId.replaceAll('-', '_')} {}\n`])
				: new Response('unexpected request', { status: 404 });
		});
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		document.addEventListener('__bridge_command', handleBridgeCommand);

		try {
			render(
				<BridgeApp
					navigationCommand={{
						commandId: 'activate-stable-windowed-review-target',
						commandKind: 'activateTarget',
						context: 'review',
						source: {
							sourceKind: 'reviewComparison',
							sourceId: reviewPackage.query.queryId,
							comparisonId: reviewPackage.packageId,
						},
						target: {
							targetKind: 'file',
							fileRef: {
								sourceId: reviewPackage.query.queryId,
								path: targetHeadPath,
							},
							version: 'current',
							comparisonId: reviewPackage.packageId,
							reviewItemId: targetItemId,
						},
						restoreMemory: false,
					}}
				/>,
			);
			await dispatchHostAdmittedReviewIntakeFrame(
				{
					kind: 'reset',
					streamId,
					generation: reviewPackage.reviewGeneration,
					sequence: 0,
					payload: {
						kind: 'reset',
						streamId,
						generation: reviewPackage.reviewGeneration,
						sequence: 0,
						frameKind: 'review.reset',
						reason: 'authorityChanged',
						sourceIdentity: reviewPackage.query.queryId,
					},
				},
				{
					telemetryConfig: {
						enabledScopes: ['web'],
						maxSamplesPerBatch: 32,
						maxEncodedBatchBytes: 65_536,
						minimumFlushIntervalMilliseconds: 0,
						endpointUrl: 'agentstudio://telemetry/batch',
						scenario: 'bounded_snapshot_acceptance_v1',
					},
				},
			);
			await dispatchHostAdmittedReviewIntakeFrame({
				kind: 'snapshot',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: snapshotFrame.sequence,
				payload: snapshotFrame,
			});
			await dispatchHostAdmittedReviewIntakeFrame({
				kind: 'delta',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: metadataWindowFrame.sequence,
				payload: metadataWindowFrame,
			});
			await pollWithinActUntilEqual(
				() =>
					document
						.querySelector('[data-testid="review-viewer-shell"]')
						?.getAttribute('data-selected-display-path'),
				targetHeadPath,
			);
			await pollWithinActUntilEqual(
				() =>
					document
						.querySelector('[data-testid="review-viewer-shell"]')
						?.getAttribute('data-review-metadata-item-count'),
				'90',
			);

			await dispatchHostAdmittedReviewIntakeFrame({
				kind: 'snapshot',
				streamId,
				generation: nextRevisionPackage.reviewGeneration,
				sequence: boundedNextSnapshotFrame.sequence,
				payload: boundedNextSnapshotFrame,
			});
			await actWait(waitForBridgeViewerAnimationFrame);

			const reviewShell = requireBridgeViewerHTMLElement(
				document.querySelector('[data-testid="review-viewer-shell"]'),
			);
			expect(reviewShell.getAttribute('data-review-metadata-revision')).toBe(
				String(nextRevisionPackage.revision),
			);
			expect(reviewShell.getAttribute('data-review-metadata-item-count')).toBe('90');
			expect(reviewShell.getAttribute('data-review-metadata-tree-row-count')).toBe('90');
			expect(reviewShell.getAttribute('data-selected-display-path')).toBe(targetHeadPath);
			expect(reviewShell.getAttribute('data-selected-content-state')).toBe('ready');
			expect(telemetrySamplesFromBatches(telemetryBatches)).not.toContainEqual(
				expect.objectContaining({
					name: 'performance.bridge.web.review_metadata_apply',
					stringAttributes: expect.objectContaining({
						'agentstudio.bridge.result': 'failed',
						'agentstudio.bridge.result_reason': 'snapshot_materializer_rejected',
					}),
				}),
			);
		} finally {
			document.removeEventListener('__bridge_command', handleBridgeCommand);
		}
	});

	test('selects and hydrates a modified file that arrives in a metadata delta', async () => {
		const reviewPackage = makeWindowedReviewPackage(2);
		const streamId = 'review:bridge-app-test-pane';
		const initialItemId = reviewPackage.orderedItemIds[0];
		const deltaItemId = reviewPackage.orderedItemIds[1];
		if (initialItemId === undefined || deltaItemId === undefined) {
			throw new Error('Expected initial and delta target items');
		}
		const deltaItem = reviewPackage.itemsById[deltaItemId];
		if (
			deltaItem === undefined ||
			typeof deltaItem.headPath !== 'string' ||
			deltaItem.contentRoles.base === null ||
			deltaItem.contentRoles.base === undefined ||
			deltaItem.contentRoles.head === null ||
			deltaItem.contentRoles.head === undefined
		) {
			throw new Error('Expected delta modified item with base and head content');
		}
		const targetHeadPath = deltaItem.headPath;
		const fetchedResourceUrls: string[] = [];
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: initialItemId,
			visibleItemIds: [initialItemId],
		});
		const projectionItem = snapshotFrame.itemMetadata[0];
		const deltaProjectionItem = buildReviewMetadataWindowFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 2,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			itemIds: [deltaItemId],
		}).itemMetadata[0];
		if (projectionItem === undefined || deltaProjectionItem === undefined) {
			throw new Error('Expected metadata projection items');
		}
		const deltaFrame = buildReviewMetadataDeltaFrame({
			package: {
				...reviewPackage,
				revision: reviewPackage.revision + 1,
			},
			paneId: 'bridge-app-test-pane',
			sequence: 2,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			fromRevision: reviewPackage.revision,
			toRevision: reviewPackage.revision + 1,
			operations: [
				{ kind: 'appendItems', items: [deltaProjectionItem] },
				{
					kind: 'upsertTreeRows',
					rows: [
						{
							rowId: `row-${deltaItemId}`,
							itemId: deltaItemId,
							path: targetHeadPath,
							depth: 0,
							isDirectory: false,
						},
					],
				},
				{
					kind: 'upsertExtentFacts',
					facts: [
						{ itemId: deltaItemId, contentRole: 'base', lineCount: 9 },
						{ itemId: deltaItemId, contentRole: 'head', lineCount: 11 },
					],
				},
			],
		});
		const telemetryBatches: BridgeTelemetryBatch[] = [];
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource, init): Promise<Response> => {
			const telemetryResponse = recordBridgeTelemetryBatchFetch(resource, init, telemetryBatches);
			if (telemetryResponse !== null) {
				return telemetryResponse;
			}
			const resourceUrl =
				typeof resource === 'string'
					? resource
					: resource instanceof URL
						? resource.toString()
						: resource.url;
			fetchedResourceUrls.push(resourceUrl);
			if (!resourceUrl.startsWith('agentstudio://resource/review/content/')) {
				return new Response('unexpected request', { status: 404 });
			}
			return resourceUrl.includes('-base')
				? chunkedTextResponse([`// previous ${deltaItemId}\n`])
				: chunkedTextResponse([`struct ${deltaItemId.replaceAll('-', '_')} {}\n`]);
		});
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		render(<BridgeApp codeViewWorkerPoolEnabled={false} />);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: reviewPackage.query.queryId,
			},
		});
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'snapshot',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: snapshotFrame.sequence,
			payload: snapshotFrame,
		});
		await pollWithinAct({
			getValue: () =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-display-path'),
			isSatisfied: (value): boolean => value !== targetHeadPath,
		});

		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'delta',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: deltaFrame.sequence,
			payload: deltaFrame,
		});

		const targetButton = await actWait(() => waitForBridgeViewerTreeItemButton(targetHeadPath));
		await actClick(targetButton);

		await pollWithinActUntilEqual(
			() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-display-path'),
			targetHeadPath,
		);
		await pollWithinActUntilEqual(
			() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-content-state'),
			'ready',
		);
		await actWait(() => waitForBridgeViewerText('struct item_001'));
		expect(fetchedResourceUrls).toContain(deltaItem.contentRoles.base.resourceUrl);
		expect(fetchedResourceUrls).toContain(deltaItem.contentRoles.head.resourceUrl);
	});

	test('emits accepted review intake telemetry when web telemetry is enabled', async () => {
		const commands: unknown[] = [];
		const telemetryBatches: BridgeTelemetryBatch[] = [];
		const handleBridgeCommand = (event: Event): void => {
			commands.push('detail' in event ? event.detail : null);
		};
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource, init): Promise<Response> => {
			const telemetryResponse = recordBridgeTelemetryBatchFetch(resource, init, telemetryBatches);
			return telemetryResponse ?? new Response('unexpected request', { status: 404 });
		});
		document.addEventListener('__bridge_command', handleBridgeCommand);
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);

		render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame(
			{
				kind: 'reset',
				streamId: 'review:bridge-app-test-pane',
				generation: 1,
				sequence: 0,
				payload: {
					kind: 'reset',
					streamId: 'review:bridge-app-test-pane',
					generation: 1,
					sequence: 0,
					frameKind: 'review.reset',
					reason: 'authorityChanged',
					sourceIdentity: 'query-startup',
				},
			},
			{
				telemetryConfig: {
					enabledScopes: ['web'],
					maxSamplesPerBatch: 16,
					maxEncodedBatchBytes: 65_536,
					minimumFlushIntervalMilliseconds: 0,
					endpointUrl: 'agentstudio://telemetry/batch',
					scenario: 'metadata_apply_content_fetch_v1',
				},
			},
		);

		expect(telemetrySamplesFromBatches(telemetryBatches)).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.intake_frame',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.intake.frame_kind': 'review.reset',
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.result_reason': 'none',
					'agentstudio.bridge.transport': 'intake',
				}),
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.intake.generation': 1,
					'agentstudio.bridge.intake.sequence': 0,
				}),
			}),
		);
		document.removeEventListener('__bridge_command', handleBridgeCommand);
	});
});

function requireHTMLInputElement(element: Element | null): HTMLInputElement {
	if (!(element instanceof HTMLInputElement)) {
		throw new Error('Expected HTML input element.');
	}
	return element;
}

async function setReactInputValue(input: HTMLInputElement, value: string): Promise<void> {
	await act(async (): Promise<void> => {
		const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
		descriptor?.set?.call(input, value);
		input.dispatchEvent(new Event('input', { bubbles: true }));
		input.dispatchEvent(new Event('change', { bubbles: true }));
		await Promise.resolve();
	});
}

function requireWorktreeFileFramePublisher(
	publisher: WorktreeFileFrameSubscriber | null,
): (frames: Parameters<WorktreeFileFrameSubscriber>[0]) => Promise<void> {
	if (publisher === null) {
		throw new Error('Expected Worktree/File frame publisher.');
	}
	return async (frames): Promise<void> => {
		await act(async (): Promise<void> => {
			publisher(frames);
			await Promise.resolve();
		});
	};
}
