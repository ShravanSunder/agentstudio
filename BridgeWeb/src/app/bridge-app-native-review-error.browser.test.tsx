import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import './bridge-app.css';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import {
	buildReviewMetadataDeltaFrame,
	buildReviewMetadataSnapshotFrame,
	buildReviewMetadataWindowFrame,
} from '../features/review/protocol/review-metadata-frame-builder.js';
import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerText,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { BridgeApp } from './bridge-app.js';

describe('BridgeApp native review intake Browser Mode', () => {
	afterEach(() => {
		document.documentElement.removeAttribute('data-bridge-nonce');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		terminateBridgePierreWorkerPoolSingletonForTest();
		vi.restoreAllMocks();
	});

	test('marks review intake ready after the command nonce arrives', async () => {
		const commands: unknown[] = [];
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);
		const handleBridgeCommand = (event: Event): void => {
			commands.push('detail' in event ? event.detail : null);
		};
		document.addEventListener('__bridge_command', handleBridgeCommand);

		render(<BridgeApp />);
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
		);
		await Promise.resolve();
		expect(commands).toEqual([]);

		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		await waitForBridgeViewerAnimationFrame();

		expect(commands).toEqual([
			{
				__nonce: 'bridge-nonce',
				jsonrpc: '2.0',
				method: 'bridge.intakeReady',
				params: {
					protocolId: 'review',
					streamId: 'review:bridge-app-test-pane',
				},
			},
		]);
		document.removeEventListener('__bridge_command', handleBridgeCommand);
	});

	test('renders package failure when native review intake publishes an error frame', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);

		render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame({
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
		});
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'error',
			streamId: 'review:bridge-app-test-pane',
			generation: 1,
			sequence: 1,
			message: 'loadFailed',
		});

		requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-metadata-failed-shell"]'),
		);
		expect(document.body.textContent).toContain('Review metadata unavailable');
		expect(document.body.textContent).toContain('loadFailed');
		expect(document.body.textContent).not.toContain('Waiting for review metadata');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
	});

	test('keeps loading shell when diff status is ready before streamed review metadata applies', async () => {
		const streamId = 'review:bridge-app-test-pane';
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId,
			generation: 1,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId,
				generation: 1,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: 'query-startup',
			},
		});
		await dispatchHostDiffStatus({
			epoch: 1,
			revision: 1,
			status: 'ready',
		});

		requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]'),
		);
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
		expect(document.querySelector('[data-testid="review-viewer-shell"]')).toBeNull();
	});

	test('renders metadata failure when native review snapshot descriptors are rejected', async () => {
		const commands: unknown[] = [];
		const handleBridgeCommand = (event: Event): void => {
			commands.push('detail' in event ? event.detail : null);
		};
		document.addEventListener('__bridge_command', handleBridgeCommand);
		const reviewPackage = makeBridgeReviewPackage();
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
		const firstContentDescriptor = snapshotFrame.comparison.contentDescriptors?.[0];
		if (firstContentDescriptor === undefined) {
			throw new Error('Expected snapshot content descriptor');
		}
		const rejectedSnapshotFrame = {
			...snapshotFrame,
			comparison: {
				...snapshotFrame.comparison,
				contentDescriptors: [
					{
						...firstContentDescriptor,
						descriptor: {
							...firstContentDescriptor.descriptor,
							resourceUrl: firstContentDescriptor.descriptor.resourceUrl.replace(
								'?generation=1',
								'?generation=2',
							),
						},
					},
					...(snapshotFrame.comparison.contentDescriptors?.slice(1) ?? []),
				],
			},
		};
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		render(<BridgeApp />);
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
					maxSamplesPerBatch: 16,
					maxEncodedBatchBytes: 65_536,
					minimumFlushIntervalMilliseconds: 0,
					rpcMethodName: 'system.bridgeTelemetry',
					scenario: 'metadata_apply_rejected_snapshot_v1',
				},
			},
		);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'snapshot',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: rejectedSnapshotFrame.sequence,
			payload: rejectedSnapshotFrame,
		});

		requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-metadata-failed-shell"]'),
		);
		expect(document.body.textContent).toContain('review_metadata_snapshot_rejected');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
		expect(
			commands.filter(isBridgeTelemetryCommand).flatMap((command) => command.params.samples),
		).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.review_metadata_apply',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.result': 'failed',
					'agentstudio.bridge.result_reason': 'snapshot_materializer_rejected',
				}),
			}),
		);
		document.removeEventListener('__bridge_command', handleBridgeCommand);
	});

	test('renders the review shell when native review intake publishes streamed metadata', async () => {
		const reviewPackage = makeBridgeReviewPackage();
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
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource): Promise<Response> => {
			const resourceUrl =
				typeof resource === 'string'
					? resource
					: resource instanceof URL
						? resource.toString()
						: resource.url;
			return resourceUrl.startsWith('agentstudio://resource/review/content/')
				? chunkedTextResponse(['struct FixtureView {}\n'])
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
			sequence: snapshotFrame.sequence,
			payload: snapshotFrame,
		});

		await expect
			.poll(() => document.querySelector('[data-testid="review-viewer-shell"]') !== null)
			.toBe(true);
		requireBridgeViewerHTMLElement(document.querySelector('[data-testid="review-viewer-shell"]'));
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
		expect(document.body.textContent).not.toContain('Waiting for review metadata');
	});

	test('starts FileView stream when a Review pane switches to Files mode', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const streamId = 'review:bridge-app-test-pane';
		const loadEvents: string[] = [];
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
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 80),
		});
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadEvents.push('worktree-file.load');
			return { frames: [] };
		};
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		document.addEventListener('__bridge_command', handleBridgeCommand);

		try {
			render(<BridgeApp fileViewerProps={{ loadInitialSurface }} />);
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
			await expect
				.poll(() => document.querySelector('[data-testid="review-viewer-shell"]') !== null)
				.toBe(true);
			expect(loadEvents).toEqual([]);

			requireBridgeViewerHTMLElement(
				document.querySelector('[data-testid="bridge-viewer-context-file"]'),
			).click();

			await expect.poll(() => loadEvents).toEqual(['worktree-file.load']);
			expect(
				document
					.querySelector('[data-testid="bridge-app-root"]')
					?.getAttribute('data-bridge-viewer-mode'),
			).toBe('file');
			expect(
				document
					.querySelector('[data-testid="bridge-viewer-mode-host-file"]')
					?.getAttribute('data-bridge-viewer-mode-active'),
			).toBe('true');
			expect(document.querySelector('[data-testid="bridge-file-viewer-shell"]')).not.toBeNull();
		} finally {
			document.removeEventListener('__bridge_command', handleBridgeCommand);
		}
	});

	test('keeps FileView mounted and ready across Review mode metadata loading', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const streamId = 'review:bridge-app-test-pane';
		const fileDescriptor = makeWorktreeFileDescriptorForFrameTest();
		const loadEvents: string[] = [];
		const fetchedFileResourceUrls: string[] = [];
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
						fetchResource: async (props) => {
							fetchedFileResourceUrls.push(props.resourceUrl);
							return makeWorktreeFileSurfaceRuntimeFetchedResource(
								'export const stableAcrossModes = true;\n',
							);
						},
						loadInitialSurface,
					}}
					viewerMode="file"
				/>,
			);
			await expect
				.poll(() =>
					document
						.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')
						?.getAttribute('data-worktree-open-file-body-preview'),
				)
				.toContain('stableAcrossModes');
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

			requireBridgeViewerHTMLElement(
				document.querySelector('[data-testid="bridge-viewer-context-review"]'),
			).click();
			await expect
				.poll(() =>
					document
						.querySelector('[data-testid="bridge-viewer-mode-host-review"]')
						?.getAttribute('data-bridge-viewer-mode-active'),
				)
				.toBe('true');
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
			await expect
				.poll(
					() =>
						document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]') !==
						null,
				)
				.toBe(true);
			expect(fileModeHost.getAttribute('data-bridge-viewer-mode-active')).toBe('false');
			expect(document.querySelector('[data-testid="bridge-file-viewer-shell"]')).toBe(fileShell);
			expect(document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')).toBe(
				fileCodeCanvas,
			);
			expect(fileCodeCanvas.getAttribute('data-worktree-open-file-body-preview')).toContain(
				'stableAcrossModes',
			);
			expect(loadEvents).toEqual(['worktree-file.load']);
			expect(fetchedFileResourceUrls).toHaveLength(1);

			await dispatchHostAdmittedReviewIntakeFrame({
				kind: 'snapshot',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: snapshotFrame.sequence,
				payload: snapshotFrame,
			});
			await expect
				.poll(() => document.querySelector('[data-testid="review-viewer-shell"]') !== null)
				.toBe(true);
			expect(fileModeHost.getAttribute('data-bridge-viewer-mode-active')).toBe('false');
			expect(document.querySelector('[data-testid="bridge-file-viewer-shell"]')).toBe(fileShell);
			expect(document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')).toBe(
				fileCodeCanvas,
			);
			expect(loadEvents).toEqual(['worktree-file.load']);
			expect(fetchedFileResourceUrls).toHaveLength(1);

			requireBridgeViewerHTMLElement(
				document.querySelector('[data-testid="bridge-viewer-context-file"]'),
			).click();
			await expect
				.poll(() => fileModeHost.getAttribute('data-bridge-viewer-mode-active'))
				.toBe('true');
			expect(document.querySelector('[data-testid="bridge-file-viewer-shell"]')).toBe(fileShell);
			expect(document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')).toBe(
				fileCodeCanvas,
			);
			expect(
				fileCodeCanvas.getAttribute('data-worktree-open-file-state'),
			).toBe('ready');
			expect(fileCodeCanvas.getAttribute('data-worktree-open-file-body-preview')).toContain(
				'stableAcrossModes',
			);
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

		await expect
			.poll(() => document.querySelector('[data-testid="review-viewer-shell"]') !== null)
			.toBe(true);
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
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource): Promise<Response> => {
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
		await expect
			.poll(() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-display-path'),
			)
			.not.toBe(targetHeadPath);

		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'delta',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: metadataWindowFrame.sequence,
			payload: metadataWindowFrame,
		});

		const targetButton = await waitForBridgeViewerTreeItemButton(targetHeadPath);
		targetButton.click();

		await expect
			.poll(() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-display-path'),
			)
			.toBe(targetHeadPath);
		await expect
			.poll(() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-content-state'),
			)
			.toBe('ready');
		expect(fetchedResourceUrls).toContain(targetItem.contentRoles.base.resourceUrl);
		expect(fetchedResourceUrls).toContain(targetItem.contentRoles.head.resourceUrl);
	});

	test('keeps last completed review tree when a newer bounded snapshot arrives before its refill window', async () => {
		const commands: unknown[] = [];
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
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource): Promise<Response> => {
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
						rpcMethodName: 'system.bridgeTelemetry',
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
			await expect
				.poll(() =>
					document
						.querySelector('[data-testid="review-viewer-shell"]')
						?.getAttribute('data-selected-display-path'),
				)
				.toBe(targetHeadPath);
			await expect
				.poll(() =>
					document
						.querySelector('[data-testid="review-viewer-shell"]')
						?.getAttribute('data-review-metadata-item-count'),
				)
				.toBe('90');

			await dispatchHostAdmittedReviewIntakeFrame({
				kind: 'snapshot',
				streamId,
				generation: nextRevisionPackage.reviewGeneration,
				sequence: boundedNextSnapshotFrame.sequence,
				payload: boundedNextSnapshotFrame,
			});
			await waitForBridgeViewerAnimationFrame();

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
			expect(
				commands.filter(isBridgeTelemetryCommand).flatMap((command) => command.params.samples),
			).not.toContainEqual(
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
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource): Promise<Response> => {
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
		await expect
			.poll(() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-display-path'),
			)
			.not.toBe(targetHeadPath);

		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'delta',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: deltaFrame.sequence,
			payload: deltaFrame,
		});

		const targetButton = await waitForBridgeViewerTreeItemButton(targetHeadPath);
		targetButton.click();

		await expect
			.poll(() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-display-path'),
			)
			.toBe(targetHeadPath);
		await expect
			.poll(() =>
				document
					.querySelector('[data-testid="review-viewer-shell"]')
					?.getAttribute('data-selected-content-state'),
			)
			.toBe('ready');
		await waitForBridgeViewerText('struct item_001');
		expect(fetchedResourceUrls).toContain(deltaItem.contentRoles.base.resourceUrl);
		expect(fetchedResourceUrls).toContain(deltaItem.contentRoles.head.resourceUrl);
	});

	test('emits accepted review intake telemetry when web telemetry is enabled', async () => {
		const commands: unknown[] = [];
		const handleBridgeCommand = (event: Event): void => {
			commands.push('detail' in event ? event.detail : null);
		};
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
					rpcMethodName: 'system.bridgeTelemetry',
					scenario: 'metadata_apply_content_fetch_v1',
				},
			},
		);

		const telemetryCommand = commands.find(isBridgeTelemetryCommand);
		expect(telemetryCommand?.params.samples).toContainEqual(
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

interface DispatchHostAdmittedReviewIntakeFrameOptions {
	readonly telemetryConfig?: unknown;
}

async function dispatchHostAdmittedReviewIntakeFrame(
	frame: BridgeIntakeFrame,
	options: DispatchHostAdmittedReviewIntakeFrameOptions = {},
): Promise<void> {
	document.dispatchEvent(
		new CustomEvent('__bridge_handshake', {
			detail: { pushNonce: 'push-nonce', telemetryConfig: options.telemetryConfig },
		}),
	);
	document.dispatchEvent(
		new CustomEvent('__bridge_intake_json', {
			detail: {
				json: JSON.stringify(frame),
				nonce: 'push-nonce',
			},
		}),
	);
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
}

async function dispatchHostDiffStatus(props: {
	readonly epoch: number;
	readonly revision: number;
	readonly status: 'idle' | 'loading' | 'ready' | 'error';
	readonly error?: string | null;
}): Promise<void> {
	document.dispatchEvent(
		new CustomEvent('__bridge_push_json', {
			detail: {
				json: JSON.stringify({
					__v: 1,
					__pushId: `push-${props.epoch}-${props.revision}`,
					__revision: props.revision,
					__epoch: props.epoch,
					store: 'diff',
					op: 'replace',
					level: 'hot',
					slice: 'diff_status',
					data: {
						status: props.status,
						error: props.error ?? null,
						epoch: props.epoch,
					},
				}),
				nonce: 'push-nonce',
			},
		}),
	);
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
}

function isBridgeTelemetryCommand(value: unknown): value is {
	readonly method: 'system.bridgeTelemetry';
	readonly params: {
		readonly samples: readonly {
			readonly name: string;
			readonly numericAttributes: Readonly<Record<string, number>>;
			readonly stringAttributes: Readonly<Record<string, string>>;
		}[];
	};
} {
	return (
		typeof value === 'object' &&
		value !== null &&
		'method' in value &&
		value.method === 'system.bridgeTelemetry' &&
		'params' in value &&
		typeof value.params === 'object' &&
		value.params !== null &&
		'samples' in value.params &&
		Array.isArray(value.params.samples)
	);
}

function makeWindowedReviewPackage(itemCount: number): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const items = Array.from({ length: itemCount }, (_value, index) => {
		const itemIndex = String(index).padStart(3, '0');
		return makeBridgeReviewItem({
			itemId: `item-${itemIndex}`,
			path: `Sources/Windowed/File${itemIndex}.swift`,
		});
	});
	const itemsById: BridgeReviewPackage['itemsById'] = {};
	for (const item of items) {
		itemsById[item.itemId] = item;
	}
	return {
		...basePackage,
		orderedItemIds: items.map((item) => item.itemId),
		itemsById,
		summary: {
			...basePackage.summary,
			filesChanged: itemCount,
			visibleFileCount: itemCount,
			additions: itemCount,
			deletions: itemCount,
		},
	};
}

function chunkedTextResponse(chunks: readonly string[]): Response {
	return new Response(
		new ReadableStream<Uint8Array>({
			start(controller): void {
				const encoder = new TextEncoder();
				for (const chunk of chunks) {
					controller.enqueue(encoder.encode(chunk));
				}
				controller.close();
			},
		}),
		{
			headers: {
				'content-type': 'text/plain; charset=utf-8',
			},
		},
	);
}

function makeWorktreeFileSourceIdentityForFrameTest(): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'file-frame-source',
		repoId: 'file-frame-repo',
		worktreeId: 'file-frame-worktree',
		subscriptionGeneration: 1,
		sourceCursor: 'file-frame-cursor',
	};
}

function makeWorktreeFileDescriptorForFrameTest(): WorktreeFileDescriptor {
	const sourceIdentity = makeWorktreeFileSourceIdentityForFrameTest();
		return {
			path: 'Sources/App/StableAcrossModes.swift',
			fileId: 'file-frame-stable',
			contentHandle: 'file-frame-stable-content',
			contentDescriptor: {
				ref: {
					descriptorId: 'file-frame-stable-content',
					expectedProtocol: 'worktree-file',
					expectedResourceKind: 'worktree.fileContent',
					expectedIdentity: {
						paneId: 'bridge-worktree-dev-pane',
						protocol: 'worktree-file',
					sourceId: sourceIdentity.sourceId,
					generation: sourceIdentity.subscriptionGeneration,
					streamId: 'worktree-file:bridge-worktree-dev-pane',
					cursor: sourceIdentity.sourceCursor,
					},
				},
				descriptor: {
					descriptorId: 'file-frame-stable-content',
					protocol: 'worktree-file',
					resourceKind: 'worktree.fileContent',
					resourceUrl:
						'agentstudio://resource/worktree-file/worktree.fileContent/file-frame-stable-content?generation=1&cursor=file-frame-cursor',
					identity: {
						paneId: 'bridge-worktree-dev-pane',
						protocol: 'worktree-file',
						sourceId: sourceIdentity.sourceId,
						generation: sourceIdentity.subscriptionGeneration,
						streamId: 'worktree-file:bridge-worktree-dev-pane',
						cursor: sourceIdentity.sourceCursor,
					},
					content: {
						mediaType: 'text/plain',
						encoding: 'utf-8',
						expectedBytes: 39,
						maxBytes: 39,
					},
				},
			},
			sourceIdentity,
		sizeBytes: 39,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 1,
		isBinary: false,
		language: 'swift',
		fileExtension: 'swift',
	};
}

function makeWorktreeFileFramesForFrameTest(
	descriptor: WorktreeFileDescriptor,
): readonly WorktreeFileProtocolFrame[] {
	return [
		{
			kind: 'snapshot',
			streamId: 'worktree-file:bridge-worktree-dev-pane',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: descriptor.sourceIdentity,
			treeDescriptor: {
				ref: {
					descriptorId: 'file-frame-tree-window',
					expectedProtocol: 'worktree-file',
					expectedResourceKind: 'worktree.treeWindow',
					expectedIdentity: {
						paneId: 'bridge-worktree-dev-pane',
						protocol: 'worktree-file',
						sourceId: descriptor.sourceIdentity.sourceId,
						generation: descriptor.sourceIdentity.subscriptionGeneration,
						streamId: 'worktree-file:bridge-worktree-dev-pane',
						cursor: descriptor.sourceIdentity.sourceCursor,
					},
				},
				descriptor: {
					descriptorId: 'file-frame-tree-window',
					protocol: 'worktree-file',
					resourceKind: 'worktree.treeWindow',
					resourceUrl:
						'agentstudio://resource/worktree-file/worktree.treeWindow/file-frame-tree-window?generation=1&cursor=file-frame-cursor',
					identity: {
						paneId: 'bridge-worktree-dev-pane',
						protocol: 'worktree-file',
						sourceId: descriptor.sourceIdentity.sourceId,
						generation: descriptor.sourceIdentity.subscriptionGeneration,
						streamId: 'worktree-file:bridge-worktree-dev-pane',
						cursor: descriptor.sourceIdentity.sourceCursor,
					},
					content: {
						mediaType: 'application/json',
						encoding: 'utf-8',
						expectedBytes: 128,
						maxBytes: 128,
					},
				},
			},
			treeRows: [
				{
					rowId: 'row-stable-across-modes',
					path: descriptor.path,
					name: 'StableAcrossModes.swift',
					parentPath: 'Sources/App',
					depth: 2,
					isDirectory: false,
					fileId: descriptor.fileId,
				},
			],
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 1,
				windowStartIndex: 0,
				windowRowCount: 1,
				rowHeightPixels: 24,
			},
		},
		{
			kind: 'delta',
			streamId: 'worktree-file:bridge-worktree-dev-pane',
			generation: 1,
			sequence: 1,
			frameKind: 'worktree.fileDescriptor',
			descriptor,
		},
	];
}
