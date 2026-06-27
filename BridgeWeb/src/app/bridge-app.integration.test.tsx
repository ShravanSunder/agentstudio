// @vitest-environment jsdom

import { act, type Dispatch, type SetStateAction } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { bridgeAttachedResourceDescriptorSchema } from '../core/models/bridge-resource-descriptor.js';
import {
	buildReviewDeltaFrame,
	buildReviewSnapshotFrame,
} from '../features/review/protocol/review-snapshot-frame-builder.js';
import {
	worktreeFileDescriptorSchema,
	type WorktreeFileDescriptor,
	type WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeFileClass,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import { makeReviewItemContentResourcesKey } from '../review-viewer/content/visible-review-content-hydration.js';
import {
	createBridgeMarkdownRenderWorkerClient,
	type BridgeMarkdownRenderWorkerTransport,
} from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import { buildBridgeMarkdownRenderWorkerSuccessResponse } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-renderer.js';
import {
	type BridgeMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerResponse,
} from '../review-viewer/workers/markdown/bridge-markdown-render-worker-rpc.js';
import {
	createBridgeReviewProjectionWorkerClient,
	type BridgeReviewProjectionWorkerTransport,
} from '../review-viewer/workers/projection/review-projection-worker-client.js';
import {
	buildBridgeReviewProjectionWorkerSuccessResponse,
	type BridgeReviewProjectionWorkerRequest,
	type BridgeReviewProjectionWorkerResponse,
} from '../review-viewer/workers/projection/review-projection-worker-rpc.js';
import type { BridgeAppControlCommand } from './bridge-app-control.js';
import {
	BridgeApp,
	bridgeReviewNavigationCommandForWorktreeDescriptor,
	scheduleSelectedContentRetry,
	selectedContentResourcesStateFromDemandLoadResult,
	selectedContentResourcesStateFromLoadResult,
	selectedContentUnavailablePathForCurrentSelection,
} from './bridge-app.js';
import type { BridgeViewerNavigationCommand } from './bridge-viewer-navigation-models.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('BridgeApp', () => {
	let mountedRoot: Root | null = null;

	beforeEach(() => {
		installCodeViewDomAPIs();
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);
	});

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-nonce');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
	});

	test('renders a ready empty review shell before package metadata arrives', async () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});

		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		expect(document.body.textContent).toContain('Bridge Review');
		expect(document.body.textContent).toContain('Waiting for review package');
	});

	test('builds a typed review file-target command from a worktree descriptor', () => {
		const descriptor = makeWorktreeNavigationDescriptor();

		const navigationCommand = bridgeReviewNavigationCommandForWorktreeDescriptor({
			descriptor,
			reviewSource: {
				sourceKind: 'reviewComparison',
				sourceId: 'review-source-1',
				comparisonId: 'comparison-1',
			},
		});

		expect(navigationCommand).toEqual({
			commandId: 'bridge:worktree:review:file:worktree-source-1:file-1:sha256:abcdef',
			commandKind: 'activateTarget',
			context: 'review',
			restoreMemory: true,
			source: {
				sourceKind: 'reviewComparison',
				sourceId: 'review-source-1',
				comparisonId: 'comparison-1',
			},
			target: {
				targetKind: 'file',
				comparisonId: 'comparison-1',
				fileRef: {
					sourceId: 'review-source-1',
					path: 'src/app.ts',
				},
				version: 'current',
			},
		});
	});

	test('preserves FileViewer memory when switching through the shared context control', async () => {
		const descriptor = makeWorktreeNavigationDescriptor();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fileViewerProps={{
						autoOpenInitialFile: true,
						initialFrames: makeWorktreeNavigationFrames(descriptor),
						fetchResource: async (): Promise<string> => 'export const selectedFile = true;\n',
					}}
					viewerMode="file"
				/>,
			);
		});

		await waitForFileViewerOpenPath('src/app.ts');
		const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
		const fileModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
		const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		expect(appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('file');
		expect(fileModeHost?.getAttribute('data-bridge-viewer-mode-active')).toBe('true');
		expect(fileModeHost?.hasAttribute('hidden')).toBe(false);
		expect(fileShell?.getAttribute('data-selected-display-path')).toBe('src/app.ts');

		const reviewContextButton = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-context-review"]'),
		);
		await act(async (): Promise<void> => {
			reviewContextButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});

		expect(appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('review');
		expect(fileModeHost?.getAttribute('data-bridge-viewer-mode-active')).toBe('false');
		expect(fileModeHost?.hasAttribute('hidden')).toBe(true);
		expect(fileShell?.getAttribute('data-selected-display-path')).toBe('src/app.ts');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		expect(document.querySelectorAll('[data-testid="bridge-app-root"]')).toHaveLength(1);
		expect(document.querySelector('[data-testid="worktree-file-app"]')).toBeNull();

		const fileContextButton = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-context-file"]'),
		);
		await act(async (): Promise<void> => {
			fileContextButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});

		expect(appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('file');
		expect(fileModeHost?.getAttribute('data-bridge-viewer-mode-active')).toBe('true');
		expect(fileModeHost?.hasAttribute('hidden')).toBe(false);
		expect(fileShell?.getAttribute('data-selected-display-path')).toBe('src/app.ts');
		expect(
			document
				.querySelector('[data-testid="bridge-viewer-context-file"]')
				?.getAttribute('data-slot'),
		).toBe('button');
	});

	test('keeps inactive Review mode from doing foreground work while preserving review state', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const descriptor = makeWorktreeNavigationDescriptor();
		const reviewPackage = makeSourceAndDocsReviewPackage();
		const requestedUrls: string[] = [];
		const commandDetails: unknown[] = [];
		const markdownRequests: BridgeMarkdownRenderWorkerRequest[] = [];
		const markdownAbortRequests: unknown[] = [];
		let markdownRequestIndex = 0;
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const transport: BridgeMarkdownRenderWorkerTransport = {
			send: (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => {
				markdownRequests.push(request);
				return new Promise<BridgeMarkdownRenderWorkerResponse>((): void => {});
			},
			abort: (request): void => {
				markdownAbortRequests.push(request);
			},
		};
		const markdownWorkerClient = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => {
				markdownRequestIndex += 1;
				return `inactive-review-markdown-${markdownRequestIndex}`;
			},
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fileViewerProps={{
						autoOpenInitialFile: true,
						initialFrames: makeWorktreeNavigationFrames(descriptor),
						fetchResource: async (): Promise<string> => 'export const selectedFile = true;\n',
					}}
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(
							url.includes('item-docs')
								? '# Review Plan\n\nReview state should resume only when active.'
								: "export const source = 'selected';\n",
						);
					}}
					markdownWorkerClient={markdownWorkerClient}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForSelectedItemId('item-source');
		await dispatchBridgeAppControl({
			method: 'bridge.fileView.showMarkdownPreview',
			itemId: 'item-docs',
		});
		await waitForSelectedItemId('item-docs');
		await waitForRequestedUrl(requestedUrls, 'item-docs');
		await waitForMarkdownRequestCount(markdownRequests, 1);

		const fileContextButton = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-context-file"]'),
		);
		await act(async (): Promise<void> => {
			fileContextButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
			await waitForAnimationFrame();
		});
		await waitForFileViewerOpenPath('src/app.ts');
		expect(
			document
				.querySelector('[data-testid="bridge-viewer-mode-host-review"]')
				?.getAttribute('data-bridge-viewer-mode-active'),
		).toBe('false');
		expect(selectedBridgeViewerPanelAttribute('data-selected-item-id')).toBe('item-docs');

		commandDetails.length = 0;
		const requestedUrlCountWhileActive = requestedUrls.length;
		const markdownRequestCountWhileActive = markdownRequests.length;
		const markdownAbortCountAfterDeactivation = markdownAbortRequests.length;

		await act(async (): Promise<void> => {
			window.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', { detail: { itemId: 'item-source' } }),
			);
			window.dispatchEvent(
				new CustomEvent('__bridge_review_control', {
					detail: {
						method: 'bridge.fileView.showMarkdownPreview',
						itemId: 'item-source',
					},
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
			await waitForAnimationFrame();
		});

		expect(requestedUrls).toHaveLength(requestedUrlCountWhileActive);
		expect(markdownRequests).toHaveLength(markdownRequestCountWhileActive);
		expect(markdownAbortRequests).toHaveLength(markdownAbortCountAfterDeactivation);
		expect(commandDetails.filter(isMarkFileViewedCommand)).toEqual([]);
		expect(selectedBridgeViewerPanelAttribute('data-selected-item-id')).toBe('item-docs');

		const reviewContextButton = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-context-review"]'),
		);
		await act(async (): Promise<void> => {
			reviewContextButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		await waitForSelectedItemId('item-docs');
		await waitForMarkdownRequestCount(markdownRequests, 2);
		expect(markdownRequests[1]).toMatchObject({
			method: 'markdown.render',
			itemId: 'item-docs',
			sourcePath: 'docs/plans/review-plan.md',
		});
	});

	test('selected unavailable state is owned by selected content demand', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const selectedItem = reviewPackage.itemsById['item-source'];
		expect(selectedItem).not.toBeUndefined();
		if (selectedItem === undefined) {
			throw new Error('Expected item-source fixture item');
		}
		const contentKey = makeReviewItemContentResourcesKey({
			item: selectedItem,
			reviewPackage,
		});

		expect(
			selectedContentUnavailablePathForCurrentSelection({
				reviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: {
					itemId: 'item-source',
					contentKey,
					status: 'loading',
					resources: null,
				},
			}),
		).toBeNull();
		expect(
			selectedContentUnavailablePathForCurrentSelection({
				reviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: {
					itemId: 'item-source',
					contentKey,
					status: 'failed',
					resources: null,
				},
			}),
		).toBe('Sources/App/View.swift');
	});

	test('selected content demand null materialization becomes failed state', () => {
		expect(
			selectedContentResourcesStateFromLoadResult({
				itemId: 'item-source',
				contentKey: 'review:item-source:1',
				contentResources: null,
			}),
		).toEqual({
			itemId: 'item-source',
			contentKey: 'review:item-source:1',
			status: 'failed',
			resources: null,
		});
	});

	test('selected content demand deferred materialization stays loading for retry', () => {
		expect(
			selectedContentResourcesStateFromDemandLoadResult({
				itemId: 'item-source',
				contentKey: 'review:item-source:1',
				loadResult: { status: 'deferred', reason: 'concurrency_exceeded' },
			}),
		).toEqual({
			itemId: 'item-source',
			contentKey: 'review:item-source:1',
			status: 'loading',
			resources: null,
		});
	});

	test('selected content retry coalesces while an animation frame is outstanding', () => {
		const originalRequestAnimationFrame = globalThis.requestAnimationFrame;
		const callbacks: FrameRequestCallback[] = [];
		Object.assign(globalThis, {
			requestAnimationFrame: (callback: FrameRequestCallback): number => {
				callbacks.push(callback);
				return callbacks.length;
			},
		});
		try {
			const scheduledRef = { current: false };
			const setSelectedContentRetryVersion = vi.fn((value: SetStateAction<number>): number =>
				typeof value === 'function' ? value(0) : value,
			) satisfies Dispatch<SetStateAction<number>>;

			scheduleSelectedContentRetry({
				scheduledRef,
				setSelectedContentRetryVersion,
			});
			scheduleSelectedContentRetry({
				scheduledRef,
				setSelectedContentRetryVersion,
			});

			expect(callbacks).toHaveLength(1);
			expect(setSelectedContentRetryVersion).not.toHaveBeenCalled();
			callbacks[0]?.(performance.now());
			expect(scheduledRef.current).toBe(false);
			expect(setSelectedContentRetryVersion).toHaveBeenCalledTimes(1);

			scheduleSelectedContentRetry({
				scheduledRef,
				setSelectedContentRetryVersion,
			});

			expect(callbacks).toHaveLength(2);
		} finally {
			Object.assign(globalThis, { requestAnimationFrame: originalRequestAnimationFrame });
		}
	});

	test('renders a shadcn package loading shell while native package metadata is loading', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'status-loading',
				__revision: 1,
				__epoch: 2,
				store: 'diff',
				op: 'replace',
				level: 'hot',
				slice: 'diff_status',
				data: { status: 'loading', error: null, epoch: 2 },
			});
			await Promise.resolve();
			await Promise.resolve();
		});

		expect(
			document.querySelector('[data-testid="bridge-review-package-loading-shell"]'),
		).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-review-shell-skeleton"]')).not.toBeNull();
		expect(document.querySelectorAll('[data-slot="skeleton"]')).toHaveLength(3);
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
	});

	test('renders package failure instead of an empty shell when native package loading fails', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'status-error',
						__revision: 1,
						__epoch: 2,
						store: 'diff',
						op: 'replace',
						level: 'hot',
						slice: 'diff_status',
						nonce: 'push-nonce',
						data: { status: 'error', error: 'loadFailed', epoch: 2 },
					},
				}),
			);
		});

		expect(
			document.querySelector('[data-testid="bridge-review-package-failed-shell"]'),
		).not.toBeNull();
		expect(document.body.textContent).toContain('Review package unavailable');
		expect(document.body.textContent).toContain('loadFailed');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
	});

	test('mounts transport in order renders pushed package and sends selection commands', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const commandDetails: unknown[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> =>
						new Response(url.includes('-base') ? 'base text' : 'loaded head text')
					}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(document.body.textContent).toContain('Sources/App/View.swift');
		expect(bridgeAppRenderedTextContent()).toContain('loaded head text');

		await act(async (): Promise<void> => {
			const selectedButton = findReviewTreeItemButton('Sources/App/View.swift');
			if (selectedButton === null) {
				throw new Error('expected selected review item button');
			}
			selectedButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});

		expect(commandDetails).toEqual([
			{
				jsonrpc: '2.0',
				method: 'review.markFileViewed',
				params: { fileId: 'item-source' },
				__nonce: 'bridge-nonce',
				__commandId: expect.stringMatching(/^cmd_/),
			},
		]);
	});

	test('renders deleted file packages with omitted Swift optional head path', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeDeletedFileReviewPackageWithOmittedHeadPath();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (): Promise<Response> => new Response('deleted base text')}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(document.body.textContent).toContain('Sources/Removed.swift');
		expect(bridgeAppRenderedTextContent()).toContain('deleted base text');
	});

	test('keeps CodeView and right rail scroll offsets independent from the document shell', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeLargeBridgeReviewPackage(80);
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});
		await pushReviewPackage(reviewPackage);

		const shell = requireHTMLElement(document.querySelector('[data-testid="review-viewer-shell"]'));
		const codeScroll = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-code-scroll"]'),
		);
		const railScroll = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-rail-scroll"]'),
		);

		document.documentElement.scrollTop = 0;
		document.body.scrollTop = 0;
		shell.scrollTop = 0;
		codeScroll.scrollTop = 280;
		railScroll.scrollTop = 160;
		codeScroll.dispatchEvent(new Event('scroll', { bubbles: true }));
		railScroll.dispatchEvent(new Event('scroll', { bubbles: true }));

		expect(codeScroll.scrollTop).toBe(280);
		expect(railScroll.scrollTop).toBe(160);
		expect(shell.scrollTop).toBe(0);
		expect(document.documentElement.scrollTop).toBe(0);
		expect(document.body.scrollTop).toBe(0);
	});

	test('telemetry-enabled package apply sends selected item RPC through command bridge', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const commandDetails: unknown[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (): Promise<Response> => new Response('loaded head text')}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', {
					detail: {
						pushNonce: 'push-nonce',
						telemetryConfig: {
							enabledScopes: ['web'],
							maxSamplesPerBatch: 32,
							maxEncodedBatchBytes: 16384,
							minimumFlushIntervalMilliseconds: 1,
							rpcMethodName: 'system.bridgeTelemetry',
							scenario: 'package_apply_content_fetch_v1',
						},
					},
				}),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-1',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				__traceContext: {
					traceId: '11111111111111111111111111111111',
					spanId: '2222222222222222',
					parentSpanId: null,
					sampled: true,
				},
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			await Promise.resolve();
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(commandDetails).toContainEqual(
			expect.objectContaining({
				method: 'review.markFileViewed',
				params: { fileId: 'item-source' },
				__nonce: 'bridge-nonce',
				__traceContext: expect.objectContaining({
					traceId: '11111111111111111111111111111111',
					parentSpanId: '2222222222222222',
				}),
			}),
		);
		const telemetrySamples = commandDetails.flatMap(extractTelemetrySamples);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.package_apply',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.plane': 'data',
					'agentstudio.bridge.priority': 'cold',
					'agentstudio.bridge.slice': 'diff_package_metadata',
				}),
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.first_render',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.plane': 'data',
					'agentstudio.bridge.priority': 'hot',
					'agentstudio.bridge.slice': 'diff_package_metadata',
				}),
				traceContext: expect.objectContaining({
					traceId: '11111111111111111111111111111111',
					parentSpanId: '2222222222222222',
				}),
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.content_fetch',
				traceContext: expect.objectContaining({
					traceId: '11111111111111111111111111111111',
					parentSpanId: '2222222222222222',
				}),
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.trees.projection_build',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'projection_build',
					'agentstudio.bridge.slice': 'review_projection',
					'agentstudio.bridge.transport': 'worker',
				}),
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.viewer.content_queue',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'content_queue',
					'agentstudio.bridge.slice': 'content_fetch',
					'agentstudio.bridge.transport': 'content',
				}),
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.pierre.item_update',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'item_update',
					'agentstudio.bridge.slice': 'code_view_item',
					'agentstudio.bridge.transport': 'swift',
				}),
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.shiki.highlight',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'highlight',
					'agentstudio.bridge.slice': 'shiki_highlight',
					'agentstudio.bridge.transport': 'worker',
				}),
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.worker.task',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'worker_task',
					'agentstudio.bridge.slice': 'worker_task',
					'agentstudio.bridge.transport': 'worker',
				}),
			}),
		);
	});

	test('passes abort signals to shared content fetches while selection moves to another item', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeTwoItemReviewPackage();
		const contentRequests: Array<{
			readonly signal: AbortSignal | undefined;
			readonly url: string;
		}> = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (_url: string, init?: RequestInit): Promise<Response> => {
						contentRequests.push({ signal: init?.signal ?? undefined, url: _url });
						return await new Promise<Response>((): void => {});
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForContentRequestCount(contentRequests, 2);

		const initialSignals = contentRequests
			.filter((request): boolean => request.url.includes('item-source'))
			.map((request): AbortSignal | undefined => request.signal);
		expect(initialSignals).toHaveLength(2);
		expect(initialSignals.every((signal): boolean => signal instanceof AbortSignal)).toBe(true);
		expect(initialSignals.every((signal): boolean => signal?.aborted === false)).toBe(true);

		await act(async (): Promise<void> => {
			const secondButton = findReviewTreeItemButton('Sources/App/Second.swift');
			if (secondButton === null) {
				throw new Error('expected second review item button');
			}
			secondButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
		});

		const codeViewPanel = document.querySelector<HTMLElement>(
			'[data-testid="bridge-code-view-panel"]',
		);
		expect(codeViewPanel?.dataset['selectedContentState']).toBe('pending');
	});

	test('connection push apply telemetry is classified as control plane', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const commandDetails: unknown[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', {
					detail: {
						pushNonce: 'push-nonce',
						telemetryConfig: {
							enabledScopes: ['web'],
							maxSamplesPerBatch: 8,
							maxEncodedBatchBytes: 16384,
							minimumFlushIntervalMilliseconds: 1,
							rpcMethodName: 'system.bridgeTelemetry',
							scenario: 'package_apply_content_fetch_v1',
						},
					},
				}),
			);
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-connection',
						__revision: 1,
						__epoch: 0,
						store: 'connection',
						op: 'replace',
						level: 'hot',
						slice: 'connection_health',
						nonce: 'push-nonce',
						data: { health: 'ready', latencyMs: null },
					},
				}),
			);
			await Promise.resolve();
		});

		const telemetrySamples = commandDetails.flatMap(extractTelemetrySamples);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.package_apply',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.plane': 'control',
					'agentstudio.bridge.priority': 'hot',
					'agentstudio.bridge.slice': 'connection_health',
				}),
			}),
		);
	});

	test('review telemetry keeps package parent after hot diff status arrives', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const commandDetails: unknown[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (): Promise<Response> => new Response('loaded head text')}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', {
					detail: {
						pushNonce: 'push-nonce',
						telemetryConfig: {
							enabledScopes: ['web'],
							maxSamplesPerBatch: 8,
							maxEncodedBatchBytes: 16384,
							minimumFlushIntervalMilliseconds: 1,
							rpcMethodName: 'system.bridgeTelemetry',
							scenario: 'package_apply_content_fetch_v1',
						},
					},
				}),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-diff',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				__traceContext: {
					traceId: '11111111111111111111111111111111',
					spanId: '2222222222222222',
					parentSpanId: null,
					sampled: true,
				},
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-status',
						__revision: 2,
						__epoch: 1,
						__traceContext: {
							traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
							spanId: 'bbbbbbbbbbbbbbbb',
							parentSpanId: null,
							sampled: true,
						},
						store: 'diff',
						op: 'replace',
						level: 'hot',
						slice: 'diff_status',
						nonce: 'push-nonce',
						data: { status: 'ready', error: null, epoch: 1 },
					},
				}),
			);
			await Promise.resolve();
			await Promise.resolve();
		});

		expect(commandDetails).toContainEqual(
			expect.objectContaining({
				method: 'review.markFileViewed',
				__traceContext: expect.objectContaining({
					traceId: '11111111111111111111111111111111',
					parentSpanId: '2222222222222222',
				}),
			}),
		);
		const telemetrySamples = commandDetails.flatMap(extractTelemetrySamples);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.content_fetch',
				traceContext: expect.objectContaining({
					traceId: '11111111111111111111111111111111',
					parentSpanId: '2222222222222222',
				}),
			}),
		);
	});

	test('clears stale review demand telemetry when the active package changes', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const replacementItem = makeBridgeReviewItem({
			itemId: 'item-replacement',
			path: 'Sources/App/Replacement.swift',
		});
		const replacementPackage: BridgeReviewPackage = {
			...reviewPackage,
			packageId: 'package-2',
			revision: 2,
			orderedItemIds: [replacementItem.itemId],
			itemsById: { [replacementItem.itemId]: replacementItem },
			summary: {
				...reviewPackage.summary,
				filesChanged: 1,
				visibleFileCount: 1,
			},
		};
		const requestedUrls: string[] = [];
		const deferredReplacementFetch = createDeferred<Response>();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return url.includes('item-replacement')
							? deferredReplacementFetch.promise
							: new Response('package one content');
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForReviewShellAttribute('data-review-selected-demand-package-id', 'package-1');
		expect(reviewShellAttribute('data-review-selected-demand-item-id')).toBe('item-source');

		try {
			await pushReviewPackage(replacementPackage);
			await waitForRequestedUrl(requestedUrls, 'handle-item-replacement-head');
			expect(reviewShellAttribute('data-review-package-id')).toBe('package-2');
			expect(reviewShellAttribute('data-review-selected-demand-package-id')).not.toBe('package-1');
			expect(reviewShellAttribute('data-review-selected-demand-item-id')).not.toBe('item-source');
			expect(reviewShellAttribute('data-review-visible-demand-package-id')).not.toBe('package-1');
			expect(reviewShellAttribute('data-review-visible-demand-item-id')).not.toBe('item-source');
		} finally {
			deferredReplacementFetch.resolve(new Response('package two content'));
		}
	});

	test('accepted delta refreshes package parent for follow-on telemetry', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const commandDetails: unknown[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (): Promise<Response> => new Response('loaded after delta')}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', {
					detail: {
						pushNonce: 'push-nonce',
						telemetryConfig: {
							enabledScopes: ['web'],
							maxSamplesPerBatch: 16,
							maxEncodedBatchBytes: 16384,
							minimumFlushIntervalMilliseconds: 1,
							rpcMethodName: 'system.bridgeTelemetry',
							scenario: 'package_apply_content_fetch_v1',
						},
					},
				}),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-metadata',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				__traceContext: {
					traceId: '11111111111111111111111111111111',
					spanId: '2222222222222222',
					parentSpanId: null,
					sampled: true,
				},
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			await Promise.resolve();
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-delta',
				__revision: reviewPackage.revision + 1,
				__epoch: reviewPackage.reviewGeneration,
				__traceContext: {
					traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
					spanId: 'bbbbbbbbbbbbbbbb',
					parentSpanId: null,
					sampled: true,
				},
				store: 'diff',
				op: 'merge',
				level: 'warm',
				slice: 'diff_package_delta',
				data: {
					delta: {
						packageId: reviewPackage.packageId,
						reviewGeneration: reviewPackage.reviewGeneration,
						revision: reviewPackage.revision + 1,
						operations: {
							addItems: [],
							updateItems: [],
							removeItems: [],
							moveItems: [],
							updateGroups: null,
							updateSummary: reviewPackage.summary,
							invalidateContent: [],
						},
					},
					protocolFrame: buildReviewDeltaFrame({
						package: {
							...reviewPackage,
							revision: reviewPackage.revision + 1,
						},
						fromRevision: reviewPackage.revision,
						toRevision: reviewPackage.revision + 1,
						paneId: 'bridge-app-test-pane',
						sourceIdentity: reviewPackage.query.queryId,
						streamId: 'review:bridge-app-test-pane',
						sequence: reviewPackage.revision + 1,
					}),
				},
			});
			await Promise.resolve();
			await Promise.resolve();
		});

		await act(async (): Promise<void> => {
			const selectedButton = findReviewTreeItemButton('Sources/App/View.swift');
			if (selectedButton === null) {
				throw new Error('expected selected review item button');
			}
			selectedButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
		});

		expect(commandDetails).toContainEqual(
			expect.objectContaining({
				method: 'review.markFileViewed',
				__traceContext: expect.objectContaining({
					traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
					parentSpanId: 'bbbbbbbbbbbbbbbb',
				}),
			}),
		);
		const telemetrySamples = commandDetails.flatMap(extractTelemetrySamples);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.content_fetch',
				traceContext: expect.objectContaining({
					traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
					parentSpanId: 'bbbbbbbbbbbbbbbb',
				}),
			}),
		);
	});

	test('telemetry-enabled file selection sends one mark command per selected item', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeTwoItemReviewPackage();
		const commandDetails: unknown[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (): Promise<Response> => new Response('loaded head text')}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', {
					detail: {
						pushNonce: 'push-nonce',
						telemetryConfig: {
							enabledScopes: ['web'],
							maxSamplesPerBatch: 8,
							maxEncodedBatchBytes: 16384,
							minimumFlushIntervalMilliseconds: 1,
							rpcMethodName: 'system.bridgeTelemetry',
							scenario: 'package_apply_content_fetch_v1',
						},
					},
				}),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-1',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				__traceContext: {
					traceId: '11111111111111111111111111111111',
					spanId: '2222222222222222',
					parentSpanId: null,
					sampled: true,
				},
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			await Promise.resolve();
			await Promise.resolve();
		});

		commandDetails.length = 0;

		await act(async (): Promise<void> => {
			const secondButton = findReviewTreeItemButton('Sources/App/Second.swift');
			if (secondButton === null) {
				throw new Error('expected second review item button');
			}
			secondButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
			await Promise.resolve();
		});

		const markCommands = commandDetails.filter(isMarkFileViewedCommand);

		expect(markCommands).toEqual([
			expect.objectContaining({
				method: 'review.markFileViewed',
				params: { fileId: 'item-second' },
			}),
		]);
	});

	test('routes large package projection through injected worker RPC before rendering', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeLargeBridgeReviewPackage(40);
		const deferredResponse = createDeferred<BridgeReviewProjectionWorkerResponse>();
		let capturedRequest: BridgeReviewProjectionWorkerRequest | null = null;
		const transport: BridgeReviewProjectionWorkerTransport = {
			send: (
				request: BridgeReviewProjectionWorkerRequest,
			): Promise<BridgeReviewProjectionWorkerResponse> => {
				capturedRequest = request;
				return deferredResponse.promise;
			},
		};
		const projectionWorkerClient = createBridgeReviewProjectionWorkerClient({
			transport,
			createRequestId: (): string => 'projection-worker-request-1',
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (): Promise<Response> => new Response('loaded head text')}
					projectionWorkerClient={projectionWorkerClient}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-large',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			await Promise.resolve();
			await Promise.resolve();
		});

		expect(capturedRequest).toMatchObject({
			method: 'reviewProjection.build',
			workloadId: 'interactive',
		});
		expect(document.querySelector('[data-testid="review-viewer-shell"]')).toBeNull();
		expect(document.body.textContent).toContain('Projecting review');

		const request = capturedRequest;
		if (request === null) {
			throw new Error('expected projection worker request');
		}
		deferredResponse.resolve(
			buildBridgeReviewProjectionWorkerSuccessResponse({
				request,
				durationMilliseconds: 7,
			}),
		);

		await act(async (): Promise<void> => {
			await Promise.resolve();
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(document.body.textContent).toContain('Sources/Large/File039.swift');
	});

	test('keeps mounted shell while worker recomputes an existing package projection', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeLargeBridgeReviewPackage(40);
		const deferredResponses: Array<
			ReturnType<typeof createDeferred<BridgeReviewProjectionWorkerResponse>>
		> = [];
		const capturedRequests: BridgeReviewProjectionWorkerRequest[] = [];
		const transport: BridgeReviewProjectionWorkerTransport = {
			send: (
				request: BridgeReviewProjectionWorkerRequest,
			): Promise<BridgeReviewProjectionWorkerResponse> => {
				capturedRequests.push(request);
				const deferredResponse = createDeferred<BridgeReviewProjectionWorkerResponse>();
				deferredResponses.push(deferredResponse);
				return deferredResponse.promise;
			},
		};
		const projectionWorkerClient = createBridgeReviewProjectionWorkerClient({
			transport,
			createRequestId: (): string => `projection-worker-request-${capturedRequests.length + 1}`,
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (): Promise<Response> => new Response('loaded head text')}
					projectionWorkerClient={projectionWorkerClient}
				/>,
			);
		});
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-large',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			await Promise.resolve();
		});
		const firstRequest = capturedRequests[0];
		if (firstRequest === undefined) {
			throw new Error('expected first projection worker request');
		}
		deferredResponses[0]?.resolve(
			buildBridgeReviewProjectionWorkerSuccessResponse({
				request: firstRequest,
				durationMilliseconds: 7,
			}),
		);
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();

		await act(async (): Promise<void> => {
			const guidedModeButton = document.querySelector<HTMLButtonElement>(
				'[data-testid="bridge-review-mode-segment"][aria-label="Guided review"]',
			);
			if (guidedModeButton === null) {
				throw new Error('expected guided review mode control');
			}
			guidedModeButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
		});

		expect(capturedRequests).toHaveLength(2);
		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(
			document.querySelector('[data-testid="bridge-review-projection-pending-shell"]'),
		).toBeNull();
	});

	test('does not reuse selected content across package revisions with new handles', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const updatedPackage = makeUpdatedSelectedContentPackage(reviewPackage);
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						if (url.includes('revision-2')) {
							return await new Promise<Response>((): void => {});
						}
						return new Response(
							url.includes('-base') ? 'old revision base text' : 'old revision head text',
						);
					}}
				/>,
			);
		});
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-original-package',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			await Promise.resolve();
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(bridgeAppRenderedTextContent()).toContain('old revision head text');

		await act(async (): Promise<void> => {
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-updated-package',
				__revision: updatedPackage.revision,
				__epoch: updatedPackage.reviewGeneration,
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(updatedPackage),
			});
			await Promise.resolve();
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(bridgeAppRenderedTextContent()).not.toContain('old revision head text');
		expect(bridgeAppRenderedTextContent()).not.toContain('old revision base text');
	});

	test('does not replay stale in-flight selected content into a newer package revision', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const updatedPackage = makeUpdatedSelectedContentPackage(reviewPackage);
		const oldBaseResponse = createDeferred<Response>();
		const oldHeadResponse = createDeferred<Response>();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						if (url.includes('handle-item-source-base-revision-2')) {
							return new Response('new revision base text');
						}
						if (url.includes('handle-item-source-head-revision-2')) {
							return new Response('new revision head text');
						}
						if (url.includes('handle-item-source-base')) {
							return await oldBaseResponse.promise;
						}
						if (url.includes('handle-item-source-head')) {
							return await oldHeadResponse.promise;
						}
						return new Response('unrelated text');
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-source-head');

		await pushReviewPackage(updatedPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-source-head-revision-2');

		oldBaseResponse.resolve(new Response('stale revision base text'));
		oldHeadResponse.resolve(new Response('stale revision head text'));
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		await waitForRenderedText('new revision head text');
		expect(bridgeAppRenderedTextContent()).not.toContain('stale revision head text');
		expect(bridgeAppRenderedTextContent()).not.toContain('stale revision base text');
	});

	test('rejects a stale protocol frame attached to a newer package revision', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const updatedPackage = makeUpdatedSelectedContentPackageWithStableHandleIds(reviewPackage);
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('stale protocol frame text');
					}}
				/>,
			);
		});

		await pushReviewPackageWithProtocolFrame({
			reviewPackage: updatedPackage,
			protocolFramePackage: reviewPackage,
		});
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(requestedUrls).not.toContain(
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
		);
		expect(bridgeAppRenderedTextContent()).not.toContain('stale protocol frame text');
	});

	test('rejects a snapshot frame from a foreign pane and stream', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);
		const reviewPackage = makeBridgeReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('foreign pane content');
					}}
				/>,
			);
		});

		await pushReviewPackageWithExplicitProtocolFrame({
			reviewPackage,
			protocolFrame: buildReviewSnapshotFrame({
				package: reviewPackage,
				paneId: 'foreign-pane',
				sourceIdentity: reviewPackage.query.queryId,
				streamId: 'review:foreign-pane',
				sequence: reviewPackage.revision,
			}),
		});
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(requestedUrls).toEqual([]);
		expect(bridgeAppRenderedTextContent()).not.toContain('foreign pane content');
	});

	test('keeps page-world review frames dependent on native content authority', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('native lease rejected', { status: 403 });
					}}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'forged-page-world-review-frame',
						__revision: reviewPackage.revision,
						__epoch: reviewPackage.reviewGeneration,
						store: 'diff',
						op: 'replace',
						level: 'cold',
						slice: 'diff_package_metadata',
						nonce: 'push-nonce',
						data: reviewPackagePushPayload(reviewPackage),
					},
				}),
			);
			await Promise.resolve();
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(bridgeAppRenderedTextContent()).not.toContain('forged page-world content');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/handle-item-source-base?generation=1',
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
		]);
	});

	test('rejects package pushes whose protocol frame omits a content descriptor', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const protocolFrame = buildReviewSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:bridge-app-test-pane',
			sequence: reviewPackage.revision,
		});
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('partial descriptor content');
					}}
				/>,
			);
		});

		await pushReviewPackageWithExplicitProtocolFrame({
			reviewPackage,
			protocolFrame: {
				...protocolFrame,
				package: {
					...protocolFrame.package,
					contentDescriptors: protocolFrame.package.contentDescriptors?.slice(0, 1),
				},
			},
		});
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(
			document.querySelector('[data-testid="bridge-review-package-failed-shell"]'),
		).not.toBeNull();
		expect(document.body.textContent).toContain('review_protocol_frame_unavailable');
		expect(document.querySelector('[data-testid="review-viewer-shell"]')).toBeNull();
		expect(requestedUrls).toEqual([]);
	});

	test('partial delta rejects omitted descriptor refs when stable handle lineage changed', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const updatedPackage = makeUpdatedSelectedContentPackageWithStableHandleIds(reviewPackage);
		const updatedSourceItem = updatedPackage.itemsById['item-source'];
		if (updatedSourceItem === undefined) {
			throw new Error('expected updated source item fixture');
		}
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(
							url.includes('revision=2') ? 'new stable-handle text' : 'old stable-handle text',
						);
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(
			requestedUrls,
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
		);
		requestedUrls.length = 0;

		await dispatchHostAdmittedEnvelope({
			__v: 1,
			__pushId: 'partial-delta-stable-handle-lineage-change',
			__revision: updatedPackage.revision,
			__epoch: updatedPackage.reviewGeneration,
			store: 'diff',
			op: 'merge',
			level: 'warm',
			slice: 'diff_package_delta',
			data: {
				delta: {
					packageId: updatedPackage.packageId,
					reviewGeneration: updatedPackage.reviewGeneration,
					revision: updatedPackage.revision,
					operations: {
						addItems: [],
						updateItems: [updatedSourceItem],
						removeItems: [],
						moveItems: [],
						updateGroups: null,
						updateSummary: updatedPackage.summary,
						invalidateContent: [],
					},
				},
				protocolFrame: partialReviewDeltaFrame(
					buildReviewDeltaFrame({
						package: updatedPackage,
						fromRevision: reviewPackage.revision,
						toRevision: updatedPackage.revision,
						paneId: 'bridge-app-test-pane',
						sourceIdentity: updatedPackage.query.queryId,
						streamId: 'review:bridge-app-test-pane',
						sequence: updatedPackage.revision,
					}),
				),
			},
		});
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', {
					detail: { itemId: 'item-source' },
					bubbles: true,
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(
			requestedUrls.some(
				(url: string): boolean =>
					url === 'agentstudio://resource/review/content/handle-item-source-head?generation=1',
			),
		).toBe(false);
		expect(bridgeAppRenderedTextContent()).not.toContain('old stable-handle text');
	});

	test('standalone reset revokes descriptor authority before another selected load', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('pre-reset content');
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-source-head');
		requestedUrls.length = 0;

		await pushStandaloneReviewReset({
			packageId: reviewPackage.packageId,
			sourceIdentity: reviewPackage.query.queryId,
		});
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', {
					detail: { itemId: 'item-second' },
					bubbles: true,
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(requestedUrls).toEqual([]);
	});

	test('rejects stale standalone reset before revoking descriptor authority', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeLargeBridgeReviewPackage(8);
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('post-stale-reset content');
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-large-source-000-head');
		requestedUrls.length = 0;

		await pushStandaloneReviewReset({
			generation: reviewPackage.reviewGeneration - 1,
			packageId: reviewPackage.packageId,
			sourceIdentity: reviewPackage.query.queryId,
		});
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', {
					detail: { itemId: 'large-source-007' },
					bubbles: true,
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		await waitForSelectedItemId('large-source-007');
		expect(selectedBridgeViewerPanelAttribute('data-selected-content-state')).toBe('ready');
	});

	test('standalone invalidate refetches targeted content without clearing descriptor authority', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeTwoItemReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('pre-invalidate content');
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-source-head');
		requestedUrls.length = 0;

		await pushStandaloneReviewInvalidation({
			generation: reviewPackage.reviewGeneration,
			itemIds: ['item-second'],
		});
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', {
					detail: { itemId: 'item-second' },
					bubbles: true,
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		await waitForRequestedUrl(requestedUrls, 'handle-item-second-head');
	});

	test('standalone invalidate keeps bypassing stale cache until refetch succeeds', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeTwoItemReviewPackage();
		const requestedUrls: string[] = [];
		let itemSecondMode: 'prime-cache' | 'abort-refetch' | 'fresh-refetch' = 'prime-cache';
		let abortedInvalidationRefetch = false;
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string, init?: RequestInit): Promise<Response> => {
						requestedUrls.push(url);
						if (!url.includes('handle-item-second-head')) {
							return new Response('source content');
						}
						if (itemSecondMode === 'prime-cache') {
							return new Response('old item-second content');
						}
						if (itemSecondMode === 'fresh-refetch') {
							return new Response('fresh item-second content');
						}
						return await new Promise<Response>((_resolve, reject): void => {
							const signal = init?.signal;
							if (signal?.aborted === true) {
								abortedInvalidationRefetch = true;
								reject(new Error('invalidation refetch aborted'));
								return;
							}
							signal?.addEventListener(
								'abort',
								(): void => {
									abortedInvalidationRefetch = true;
									reject(new Error('invalidation refetch aborted'));
								},
								{ once: true },
							);
						});
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', {
					detail: { itemId: 'item-second' },
					bubbles: true,
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});
		await waitForRenderedText('old item-second content');

		requestedUrls.length = 0;
		itemSecondMode = 'abort-refetch';
		await pushStandaloneReviewInvalidation({
			generation: reviewPackage.reviewGeneration,
			itemIds: ['item-second'],
		});
		await waitForRequestedUrl(requestedUrls, 'handle-item-second-head');

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', {
					detail: { itemId: 'item-source' },
					bubbles: true,
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});
		expect(abortedInvalidationRefetch).toBe(true);

		requestedUrls.length = 0;
		itemSecondMode = 'fresh-refetch';
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', {
					detail: { itemId: 'item-second' },
					bubbles: true,
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		await waitForRequestedUrl(requestedUrls, 'handle-item-second-head');
		await waitForRenderedText('fresh item-second content');
		expect(bridgeAppRenderedTextContent()).not.toContain('old item-second content');
	});

	test('standalone path invalidation refetches only matching content', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeTwoItemReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('path invalidation content');
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-source-head');
		requestedUrls.length = 0;

		await pushStandaloneReviewInvalidation({
			generation: reviewPackage.reviewGeneration,
			itemIds: [],
			pathHints: ['Sources/App/Second.swift'],
			scope: 'paths',
		});
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', {
					detail: { itemId: 'item-second' },
					bubbles: true,
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});
		await waitForRequestedUrl(requestedUrls, 'handle-item-second-head');
		expect(
			requestedUrls.some((url: string): boolean => url.includes('handle-item-source-head')),
		).toBe(false);

		requestedUrls.length = 0;
		await pushStandaloneReviewInvalidation({
			generation: reviewPackage.reviewGeneration,
			itemIds: [],
			pathHints: ['Sources/App/Unrelated.swift'],
			scope: 'paths',
		});
		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', {
					detail: { itemId: 'item-source' },
					bubbles: true,
				}),
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});
		expect(
			requestedUrls.some((url: string): boolean => url.includes('handle-item-source-head')),
		).toBe(false);
		expect(
			requestedUrls.some((url: string): boolean => url.includes('handle-item-second-head')),
		).toBe(false);
	});

	test('rejects foreign snapshot after page mutates review authority attributes', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);
		const reviewPackage = makeTwoItemReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('authority mutation content');
					}}
				/>,
			);
		});

		document.documentElement.setAttribute('data-bridge-review-pane-id', 'foreign-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', 'review:foreign-pane');

		await pushReviewPackageWithExplicitProtocolFrame({
			reviewPackage,
			protocolFrame: buildReviewSnapshotFrame({
				package: reviewPackage,
				paneId: 'foreign-pane',
				sourceIdentity: reviewPackage.query.queryId,
				streamId: 'review:foreign-pane',
				sequence: reviewPackage.revision,
			}),
		});
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(requestedUrls).toEqual([]);
		expect(document.body.textContent).toContain('review_protocol_frame_unavailable');
	});

	test('keeps review shell stable when selected content fetch rejects', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (): Promise<Response> => {
						throw new Error('content fetch unavailable');
					}}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-fetch-reject-package',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			await Promise.resolve();
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
			await Promise.resolve();
		});

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(document.body.textContent).toContain('Sources/App/View.swift');
		expect(bridgeAppRenderedTextContent()).not.toContain('content fetch unavailable');
	});

	test('aborts stale selected content fetches when selection moves to another item', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeTwoItemReviewPackage();
		const contentRequests: Array<{
			readonly signal: AbortSignal | undefined;
			readonly url: string;
		}> = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (_url: string, init?: RequestInit): Promise<Response> => {
						contentRequests.push({ signal: init?.signal ?? undefined, url: _url });
						return await new Promise<Response>((): void => {});
					}}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-abort-package',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			await Promise.resolve();
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await waitForContentRequestCount(contentRequests, 2);
		});

		const initialSignals = contentRequests
			.filter((request): boolean => request.url.includes('item-source'))
			.map((request): AbortSignal | undefined => request.signal);
		expect(initialSignals).toHaveLength(2);
		expect(initialSignals.every((signal): boolean => signal instanceof AbortSignal)).toBe(true);
		expect(initialSignals.every((signal): boolean => signal?.aborted === false)).toBe(true);

		await act(async (): Promise<void> => {
			const secondButton = findReviewTreeItemButton('Sources/App/Second.swift');
			if (secondButton === null) {
				throw new Error('expected second review item button');
			}
			secondButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
		});

		const codeViewPanel = document.querySelector<HTMLElement>(
			'[data-testid="bridge-code-view-panel"]',
		);
		expect(codeViewPanel?.dataset['selectedContentState']).toBe('pending');
		expect(initialSignals.every((signal): boolean => signal?.aborted === true)).toBe(true);
	});

	test('package apply telemetry priority is derived from slice, not push level', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const commandDetails: unknown[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', {
					detail: {
						pushNonce: 'push-nonce',
						telemetryConfig: {
							enabledScopes: ['web'],
							maxSamplesPerBatch: 8,
							maxEncodedBatchBytes: 16384,
							minimumFlushIntervalMilliseconds: 1,
							rpcMethodName: 'system.bridgeTelemetry',
							scenario: 'package_apply_content_fetch_v1',
						},
					},
				}),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-status',
				__revision: 1,
				__epoch: 1,
				store: 'diff',
				op: 'merge',
				level: 'cold',
				slice: 'diff_status',
				data: { status: 'ready' },
			});
			await Promise.resolve();
			await Promise.resolve();
		});

		const telemetrySamples = commandDetails.flatMap(extractTelemetrySamples);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.package_apply',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.priority': 'hot',
					'agentstudio.bridge.slice': 'diff_status',
				}),
			}),
		);
	});

	test('package apply telemetry flushes every accepted envelope inside the throttle window', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const commandDetails: unknown[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', {
					detail: {
						pushNonce: 'push-nonce',
						telemetryConfig: {
							enabledScopes: ['web'],
							maxSamplesPerBatch: 8,
							maxEncodedBatchBytes: 16384,
							minimumFlushIntervalMilliseconds: 250,
							rpcMethodName: 'system.bridgeTelemetry',
							scenario: 'package_apply_content_fetch_v1',
						},
					},
				}),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-status-1',
				__revision: 1,
				__epoch: 1,
				store: 'diff',
				op: 'replace',
				level: 'hot',
				slice: 'diff_status',
				data: { status: 'loading', error: null, epoch: 1 },
			});
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-status-2',
				__revision: 2,
				__epoch: 1,
				store: 'diff',
				op: 'replace',
				level: 'hot',
				slice: 'diff_status',
				data: { status: 'ready', error: null, epoch: 1 },
			});
			await Promise.resolve();
			await Promise.resolve();
		});

		const packageApplySamples = commandDetails
			.flatMap(extractTelemetrySamples)
			.filter(isPackageApplyTelemetrySample);
		expect(packageApplySamples).toHaveLength(2);
	});

	test('Bridge-owned selection event uses the same state path as sidebar selection', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeTwoItemReviewPackage();
		const commandDetails: unknown[] = [];
		const requestedUrls: string[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(
							url.includes('item-second-head')
								? 'second selected text'
								: url.includes('item-second-base')
									? 'second base text'
									: 'first text',
						);
					}}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			postHostAdmittedEnvelope({
				__v: 1,
				__pushId: 'push-selection-package',
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: reviewPackagePushPayload(reviewPackage),
			});
			await Promise.resolve();
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});
		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		commandDetails.length = 0;

		await act(async (): Promise<void> => {
			window.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', { detail: { itemId: 'item-second' } }),
			);
			await Promise.resolve();
			await Promise.resolve();
		});
		await waitForRequestedUrl(requestedUrls, 'item-second-head');
		await waitForRenderedText('second selected text');

		expect(bridgeAppRenderedTextContent()).toContain('second selected text');
		expect(commandDetails.filter(isMarkFileViewedCommand)).toEqual([
			expect.objectContaining({
				method: 'review.markFileViewed',
				params: { fileId: 'item-second' },
			}),
		]);
	});

	test('hydrates selected added source files as full CodeView content', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeAddedFileReviewPackage({
			itemId: 'item-added-source',
			path: 'Sources/NewFeature/AddedFile.ts',
			language: 'typescript',
			extension: 'ts',
			fileClass: 'source',
			mimeType: 'text/typescript',
		});
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response("export const addedFile = 'full content';\n");
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-added-source-head');
		await waitForRenderedText("export const addedFile = 'full content';");

		expect(bridgeAppRenderedTextContent()).toContain("export const addedFile = 'full content';");
	});

	test('keeps package push metadata-first and hydrates selected files through handles', async () => {
		const reviewPackage = makeTwoItemReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(
							url.includes('item-second-head')
								? 'second selected text'
								: url.includes('item-second-base')
									? 'second base text'
									: url.includes('item-source-base')
										? 'first base text'
										: 'first selected text',
						);
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRenderedText('first selected text');

		expect(requestedUrls.some((url: string): boolean => url.includes('item-source-head'))).toBe(
			true,
		);

		await act(async (): Promise<void> => {
			window.dispatchEvent(
				new CustomEvent('__bridge_select_review_item', { detail: { itemId: 'item-second' } }),
			);
			await Promise.resolve();
		});
		await waitForRequestedUrl(requestedUrls, 'item-second-head');
		await waitForRenderedText('second selected text');

		expect(bridgeAppRenderedTextContent()).toContain('second selected text');
	});

	test('renders selected added markdown through the markdown worker preview lane on command', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeAddedFileReviewPackage({
			itemId: 'item-added-plan',
			path: 'docs/plans/bridge-plan.md',
			language: 'markdown',
			extension: 'md',
			fileClass: 'docs',
			mimeType: 'text/markdown',
		});
		const requestedUrls: string[] = [];
		const capturedRequests: BridgeMarkdownRenderWorkerRequest[] = [];
		const deferredResponse = createDeferred<BridgeMarkdownRenderWorkerResponse>();
		const transport: BridgeMarkdownRenderWorkerTransport = {
			send: (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => {
				capturedRequests.push(request);
				return deferredResponse.promise;
			},
			abort: () => undefined,
		};
		const markdownWorkerClient = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => 'markdown-request-1',
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('# Bridge Plan\n\n```ts\nconst value = 1;\n```');
					}}
					markdownWorkerClient={markdownWorkerClient}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-added-plan-head');
		expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
		expect(capturedRequests).toHaveLength(0);

		await dispatchBridgeAppControl({
			method: 'bridge.fileView.showMarkdownPreview',
			itemId: 'item-added-plan',
		});
		await waitForMarkdownRequest(capturedRequests);
		const request = capturedRequests[0];
		if (request === undefined) {
			throw new Error('expected markdown render request');
		}
		expect(request).toMatchObject({
			method: 'markdown.render',
			packageId: reviewPackage.packageId,
			itemId: 'item-added-plan',
			contentCacheKey: 'item-added-plan:head',
			markdownText: '# Bridge Plan\n\n```ts\nconst value = 1;\n```',
			sourcePath: 'docs/plans/bridge-plan.md',
		});

		deferredResponse.resolve(
			await buildBridgeMarkdownRenderWorkerSuccessResponse({
				request,
				renderMarkdown: async (): Promise<string> =>
					'<h1>Bridge Plan</h1><script>window.bad = true</script>',
			}),
		);
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).not.toBeNull();
		expect(document.body.textContent).toContain('Bridge Plan');
		expect(document.querySelector('script')).toBeNull();
	});

	test('page control reports markdown preview pending until the mounted viewer actually shows it', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeAddedFileReviewPackage({
			itemId: 'item-control-plan',
			path: 'docs/plans/control-plan.md',
			language: 'markdown',
			extension: 'md',
			fileClass: 'docs',
			mimeType: 'text/markdown',
		});
		const requestedUrls: string[] = [];
		const capturedRequests: BridgeMarkdownRenderWorkerRequest[] = [];
		const deferredResponse = createDeferred<BridgeMarkdownRenderWorkerResponse>();
		const transport: BridgeMarkdownRenderWorkerTransport = {
			send: (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => {
				capturedRequests.push(request);
				return deferredResponse.promise;
			},
			abort: () => undefined,
		};
		const markdownWorkerClient = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => 'markdown-control-request',
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('# Control Plan\n');
					}}
					markdownWorkerClient={markdownWorkerClient}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-control-plan-head');
		expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
		expect(capturedRequests).toHaveLength(0);

		await dispatchBridgeAppControl({
			method: 'bridge.fileView.showMarkdownPreview',
			itemId: 'item-control-plan',
		});
		await waitForMarkdownRequest(capturedRequests);
		expect(window.bridgeReviewControlProbe).toMatchObject({
			method: 'bridge.fileView.showMarkdownPreview',
			status: 'pending',
			itemId: 'item-control-plan',
			reason: 'preview_render_pending',
			renderMode: { kind: 'markdownPreview' },
		});

		const request = capturedRequests[0];
		if (request === undefined) {
			throw new Error('expected markdown render request');
		}
		deferredResponse.resolve(
			await buildBridgeMarkdownRenderWorkerSuccessResponse({
				request,
				renderMarkdown: async (): Promise<string> => '<h1>Control Plan</h1>',
			}),
		);
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		await dispatchBridgeAppControl({
			method: 'bridge.fileView.showMarkdownPreview',
			itemId: 'item-control-plan',
		});
		expect(window.bridgeReviewControlProbe).toMatchObject({
			method: 'bridge.fileView.showMarkdownPreview',
			status: 'accepted',
			itemId: 'item-control-plan',
			reason: null,
			renderMode: { kind: 'markdownPreview' },
		});
	});

	test('page control starts markdown preview after selecting an off-selection docs item', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeSourceAndDocsReviewPackage();
		const requestedUrls: string[] = [];
		const capturedRequests: BridgeMarkdownRenderWorkerRequest[] = [];
		const deferredResponse = createDeferred<BridgeMarkdownRenderWorkerResponse>();
		const transport: BridgeMarkdownRenderWorkerTransport = {
			send: (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => {
				capturedRequests.push(request);
				return deferredResponse.promise;
			},
			abort: () => undefined,
		};
		const markdownWorkerClient = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => 'markdown-off-selection-request',
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(
							url.includes('item-docs')
								? '# Review Plan\n\nOpen from one command.'
								: "export const source = 'selected';\n",
						);
					}}
					markdownWorkerClient={markdownWorkerClient}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForSelectedItemId('item-source');

		await dispatchBridgeAppControl({
			method: 'bridge.fileView.showMarkdownPreview',
			itemId: 'item-docs',
		});

		await waitForSelectedItemId('item-docs');
		await waitForRequestedUrl(requestedUrls, 'item-docs');
		await waitForMarkdownRequest(capturedRequests);
		const request = capturedRequests[0];
		if (request === undefined) {
			throw new Error('expected markdown render request');
		}
		expect(request).toMatchObject({
			method: 'markdown.render',
			packageId: reviewPackage.packageId,
			itemId: 'item-docs',
			markdownText: '# Review Plan\n\nOpen from one command.',
			sourcePath: 'docs/plans/review-plan.md',
		});

		deferredResponse.resolve(
			await buildBridgeMarkdownRenderWorkerSuccessResponse({
				request,
				renderMarkdown: async (): Promise<string> => '<h1>Review Plan</h1>',
			}),
		);
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).not.toBeNull();
		expect(window.bridgeReviewControlProbe).toMatchObject({
			method: 'bridge.fileView.showMarkdownPreview',
			status: 'pending',
			itemId: 'item-docs',
			reason: 'preview_selection_pending',
			renderMode: { kind: 'markdownPreview' },
		});
	});

	test('page control only accepts diff collapse when the mounted CodeView owns the item', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(url.includes('-base') ? 'base text' : 'head text');
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-source-head');

		await dispatchBridgeAppControl({
			method: 'bridge.diff.collapseFile',
			itemId: 'item-source',
		});
		expect(window.bridgeReviewControlProbe).toMatchObject({
			method: 'bridge.diff.collapseFile',
			status: 'accepted',
			itemId: 'item-source',
			reason: null,
		});

		await dispatchBridgeAppControl({
			method: 'bridge.diff.collapseFile',
			itemId: 'item-not-rendered',
		});
		expect(window.bridgeReviewControlProbe).toMatchObject({
			method: 'bridge.diff.collapseFile',
			status: 'rejected',
			itemId: 'item-not-rendered',
			reason: 'item_not_found',
		});
	});

	test('page control rejects package items that are filtered out of the mounted CodeView', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});

		await dispatchBridgeAppControl({
			method: 'bridge.fileTree.setFilter',
			gitStatusFilter: 'all',
			fileClassFilter: 'docs',
		});
		await pushReviewPackage(reviewPackage);

		await dispatchBridgeAppControl({
			method: 'bridge.diff.collapseFile',
			itemId: 'item-source',
		});
		expect(window.bridgeReviewControlProbe).toMatchObject({
			method: 'bridge.diff.collapseFile',
			status: 'rejected',
			itemId: 'item-source',
			reason: 'item_not_rendered',
		});
	});

	test('filtering to docs reconciles selection to a visible projected file', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeSourceAndDocsReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(url.includes('item-docs') ? '# Plan\n' : 'source text');
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-source-head');

		await dispatchBridgeAppControl({
			method: 'bridge.fileTree.setFilter',
			gitStatusFilter: 'all',
			fileClassFilter: 'docs',
		});
		await waitForSelectedItemId('item-docs');
		await waitForRequestedUrl(requestedUrls, 'handle-item-docs-head');

		expect(selectedBridgeViewerPanelAttribute('data-selected-display-path')).toBe(
			'docs/plans/review-plan.md',
		);
		expect(selectedBridgeViewerPanelAttribute('data-selected-content-state')).toBe('ready');
	});

	test('applies review file target by reviewItemId before path fallback', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeDuplicatePathReviewPackage();
		const requestedUrls: string[] = [];
		const navigationCommand = makeReviewFileNavigationCommand({
			commandId: 'test:review:file-target:duplicate-path',
			path: 'Sources/App/View.swift',
			reviewItemId: 'item-duplicate-path',
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(url.includes('duplicate') ? 'duplicate text' : 'source text');
					}}
					navigationCommand={navigationCommand}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForSelectedItemId('item-duplicate-path');
		await waitForRequestedUrl(requestedUrls, 'handle-item-duplicate-path-head');
	});

	test('reapplies same review navigation command after selection moved elsewhere', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeTwoItemReviewPackage();
		const requestedUrls: string[] = [];
		const navigationCommand = makeReviewFileNavigationCommand({
			commandId: 'test:review:file-target:source',
			path: 'Sources/App/View.swift',
			reviewItemId: 'item-source',
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(url.includes('item-second') ? 'second text' : 'source text');
					}}
					navigationCommand={navigationCommand}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForSelectedItemId('item-source');
		await act(async (): Promise<void> => {
			const secondButton = findReviewTreeItemButton('Sources/App/Second.swift');
			if (secondButton === null) {
				throw new Error('expected second review item button');
			}
			secondButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
			await waitForAnimationFrame();
		});
		await waitForSelectedItemId('item-second');

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(url.includes('item-second') ? 'second text' : 'source text');
					}}
					navigationCommand={{ ...navigationCommand }}
				/>,
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		await waitForSelectedItemId('item-source');
	});

	test('explicit review file target clears retained filters hiding the target', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeSourceAndDocsReviewPackage();
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(url.includes('item-docs') ? '# Plan\n' : 'source text');
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForSelectedItemId('item-source');
		await dispatchBridgeAppControl({
			method: 'bridge.fileTree.setFilter',
			gitStatusFilter: 'all',
			fileClassFilter: 'docs',
		});
		await waitForSelectedItemId('item-docs');

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response(url.includes('item-docs') ? '# Plan\n' : 'source text');
					}}
					navigationCommand={makeReviewFileNavigationCommand({
						commandId: 'test:review:file-target:source-after-docs-filter',
						path: 'Sources/App/View.swift',
						reviewItemId: 'item-source',
					})}
				/>,
			);
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		await waitForSelectedItemId('item-source');
		await waitForRequestedUrl(requestedUrls, 'handle-item-source-head');
	});

	test('page control rejects scrollToFile for package items filtered out of the mounted CodeView', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});

		await dispatchBridgeAppControl({
			method: 'bridge.fileTree.setFilter',
			gitStatusFilter: 'all',
			fileClassFilter: 'docs',
		});
		await pushReviewPackage(reviewPackage);

		await dispatchBridgeAppControl({
			method: 'bridge.diff.scrollToFile',
			itemId: 'item-source',
		});
		expect(window.bridgeReviewControlProbe).toMatchObject({
			method: 'bridge.diff.scrollToFile',
			status: 'rejected',
			itemId: 'item-source',
			reason: 'item_not_rendered',
		});
	});

	test('direct tree search interactions update page control probe state', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});
		await pushReviewPackage(reviewPackage);

		await act(async (): Promise<void> => {
			const searchButton = document.querySelector(
				'[data-testid="bridge-review-search-control"] button',
			);
			if (!(searchButton instanceof HTMLButtonElement)) {
				throw new Error('expected Bridge review search button');
			}
			searchButton.click();
			await Promise.resolve();
		});

		const searchInput = findReviewTreeSearchInput();
		if (searchInput === null) {
			throw new Error('expected Bridge review tree search input');
		}
		await act(async (): Promise<void> => {
			searchInput.value = 'View';
			searchInput.dispatchEvent(new InputEvent('input', { bubbles: true, data: 'View' }));
			searchInput.dispatchEvent(new Event('change', { bubbles: true }));
			await Promise.resolve();
		});

		await dispatchBridgeAppControl({
			method: 'bridge.fileTree.revealPath',
			path: 'Sources/App/View.swift',
		});
		expect(window.bridgeReviewControlProbe).toMatchObject({
			method: 'bridge.fileTree.revealPath',
			status: 'accepted',
			treeSearchText: 'view',
		});
	});

	test('page control overwrites stale probes and rejects non-markdown preview requests', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeAddedFileReviewPackage({
			itemId: 'item-control-source',
			path: 'Sources/NewFeature/ControlFile.ts',
			language: 'typescript',
			extension: 'ts',
			fileClass: 'source',
			mimeType: 'text/typescript',
		});
		const requestedUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response("export const controlFile = 'source';\n");
					}}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-control-source-head');
		window.bridgeReviewControlProbe = {
			sequence: 99,
			method: 'bridge.fileTree.search',
			status: 'accepted',
			itemId: null,
			path: null,
			treeSearchText: 'stale',
			treeSearchMode: { kind: 'text' },
			gitStatusFilter: 'all',
			fileClassFilter: 'all',
			renderMode: { kind: 'codeView' },
			reason: null,
		};

		await dispatchBridgeAppControl({
			method: 'bridge.fileView.showMarkdownPreview',
			itemId: 'item-control-source',
		});

		expect(window.bridgeReviewControlProbe).toMatchObject({
			sequence: 1,
			method: 'bridge.fileView.showMarkdownPreview',
			status: 'rejected',
			itemId: 'item-control-source',
			reason: 'notMarkdown',
			renderMode: { kind: 'codeView' },
		});
	});

	test('falls back to CodeView when markdown worker output exceeds the preview budget', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeAddedFileReviewPackage({
			itemId: 'item-large-plan',
			path: 'docs/plans/large-plan.md',
			language: 'markdown',
			extension: 'md',
			fileClass: 'docs',
			mimeType: 'text/markdown',
		});
		const requestedUrls: string[] = [];
		const capturedRequests: BridgeMarkdownRenderWorkerRequest[] = [];
		const deferredResponse = createDeferred<BridgeMarkdownRenderWorkerResponse>();
		const transport: BridgeMarkdownRenderWorkerTransport = {
			send: (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => {
				capturedRequests.push(request);
				return deferredResponse.promise;
			},
			abort: () => undefined,
		};
		const markdownWorkerClient = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => 'markdown-request-large-output',
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (url: string): Promise<Response> => {
						requestedUrls.push(url);
						return new Response('# Large Bridge Plan\n');
					}}
					markdownWorkerClient={markdownWorkerClient}
				/>,
			);
		});

		await pushReviewPackage(reviewPackage);
		await waitForRequestedUrl(requestedUrls, 'handle-item-large-plan-head');
		expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
		expect(capturedRequests).toHaveLength(0);
		await dispatchBridgeAppControl({
			method: 'bridge.fileView.showMarkdownPreview',
			itemId: 'item-large-plan',
		});
		await waitForMarkdownRequest(capturedRequests);
		const request = capturedRequests[0];
		if (request === undefined) {
			throw new Error('expected markdown render request');
		}

		deferredResponse.resolve(
			await buildBridgeMarkdownRenderWorkerSuccessResponse({
				request,
				renderMarkdown: async (): Promise<string> => `<p>${'x'.repeat(600 * 1024)}</p>`,
			}),
		);
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
		expect(bridgeAppRenderedTextContent()).toContain('Large Bridge Plan');
	});

	test('ignores array-shaped review package internals', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeApp />);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-1',
						__revision: 1,
						__epoch: 1,
						store: 'diff',
						op: 'replace',
						level: 'cold',
						slice: 'diff_package_metadata',
						nonce: 'push-nonce',
						data: {
							package: {
								...makeBridgeReviewPackage(),
								itemsById: [],
							},
						},
					},
				}),
			);
			await Promise.resolve();
		});

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).toBeNull();
	});
});

function extractEventDetail(event: Event): unknown {
	return 'detail' in event ? event.detail : null;
}

function bridgeAppRenderedTextContent(): string {
	const codeViewShadowText = [...document.querySelectorAll('diffs-container')]
		.map((element: Element): string => element.shadowRoot?.textContent ?? '')
		.join(' ');
	return `${document.body.textContent ?? ''} ${codeViewShadowText}`;
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('expected HTML element');
	}
	return element;
}

async function waitForAnimationFrame(): Promise<void> {
	await new Promise<void>((resolve) => {
		requestAnimationFrame((): void => {
			resolve();
		});
	});
}

async function waitForContentRequestCount(
	contentRequests: readonly unknown[],
	expectedCount: number,
	remainingAttempts = 20,
): Promise<void> {
	if (contentRequests.length >= expectedCount) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected at least ${expectedCount} content requests, got ${contentRequests.length}`,
		);
	}
	await Promise.resolve();
	await waitForContentRequestCount(contentRequests, expectedCount, remainingAttempts - 1);
}

async function waitForRequestedUrl(
	requestedUrls: readonly string[],
	urlPart: string,
	remainingAttempts = 20,
): Promise<void> {
	if (requestedUrls.some((url: string): boolean => url.includes(urlPart))) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected content request URL to contain ${urlPart}; urls=${requestedUrls.join(',')}`,
		);
	}
	await Promise.resolve();
	await waitForAnimationFrame();
	await waitForRequestedUrl(requestedUrls, urlPart, remainingAttempts - 1);
}

async function waitForSelectedItemId(itemId: string, remainingAttempts = 20): Promise<void> {
	if (selectedBridgeViewerPanelAttribute('data-selected-item-id') === itemId) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected selected item ${itemId}; selected=${
				selectedBridgeViewerPanelAttribute('data-selected-item-id') ?? 'null'
			}`,
		);
	}
	await Promise.resolve();
	await waitForAnimationFrame();
	await waitForSelectedItemId(itemId, remainingAttempts - 1);
}

async function waitForFileViewerOpenPath(path: string, remainingAttempts = 20): Promise<void> {
	if (
		document
			.querySelector('[data-worktree-open-file-path]')
			?.getAttribute('data-worktree-open-file-path') === path
	) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected FileViewer open path ${path}; selected=${
				document
					.querySelector('[data-worktree-open-file-path]')
					?.getAttribute('data-worktree-open-file-path') ?? 'null'
			}`,
		);
	}
	await Promise.resolve();
	await waitForAnimationFrame();
	await waitForFileViewerOpenPath(path, remainingAttempts - 1);
}

function selectedBridgeViewerPanelAttribute(attributeName: string): string | null {
	return (
		document.querySelector('[data-testid="bridge-code-view-panel"]')?.getAttribute(attributeName) ??
		null
	);
}

function reviewShellAttribute(attributeName: string): string | null {
	return (
		document.querySelector('[data-testid="review-viewer-shell"]')?.getAttribute(attributeName) ??
		null
	);
}

async function waitForReviewShellAttribute(
	attributeName: string,
	expectedValue: string,
	remainingAttempts = 20,
): Promise<void> {
	if (reviewShellAttribute(attributeName) === expectedValue) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected review shell ${attributeName}=${expectedValue}; actual=${
				reviewShellAttribute(attributeName) ?? 'null'
			}`,
		);
	}
	await Promise.resolve();
	await waitForAnimationFrame();
	await waitForReviewShellAttribute(attributeName, expectedValue, remainingAttempts - 1);
}

async function waitForRenderedText(text: string, remainingAttempts = 20): Promise<void> {
	if (bridgeAppRenderedTextContent().includes(text)) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected rendered Bridge app text to contain ${text}; rendered=${bridgeAppRenderedTextContent().slice(0, 500)}`,
		);
	}
	await Promise.resolve();
	await waitForAnimationFrame();
	await waitForRenderedText(text, remainingAttempts - 1);
}

async function waitForMarkdownRequest(
	requests: readonly BridgeMarkdownRenderWorkerRequest[],
	remainingAttempts = 20,
): Promise<void> {
	if (requests.length > 0) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error('expected markdown render worker request');
	}
	await Promise.resolve();
	await waitForAnimationFrame();
	await waitForMarkdownRequest(requests, remainingAttempts - 1);
}

async function waitForMarkdownRequestCount(
	requests: readonly BridgeMarkdownRenderWorkerRequest[],
	expectedCount: number,
	remainingAttempts = 20,
): Promise<void> {
	if (requests.length >= expectedCount) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected ${expectedCount} markdown requests, got ${requests.length}`);
	}
	await Promise.resolve();
	await waitForAnimationFrame();
	await waitForMarkdownRequestCount(requests, expectedCount, remainingAttempts - 1);
}

async function dispatchBridgeAppControl(command: BridgeAppControlCommand): Promise<void> {
	await act(async (): Promise<void> => {
		window.dispatchEvent(new CustomEvent('__bridge_review_control', { detail: command }));
		await Promise.resolve();
	});
}

async function pushReviewPackage(reviewPackage: BridgeReviewPackage): Promise<void> {
	await dispatchHostAdmittedEnvelope({
		__v: 1,
		__pushId: `push-${reviewPackage.packageId}`,
		__revision: reviewPackage.revision,
		__epoch: reviewPackage.reviewGeneration,
		store: 'diff',
		op: 'replace',
		level: 'cold',
		slice: 'diff_package_metadata',
		data: reviewPackagePushPayload(reviewPackage),
	});
}

async function pushReviewPackageWithProtocolFrame(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly protocolFramePackage: BridgeReviewPackage;
}): Promise<void> {
	await pushReviewPackageWithExplicitProtocolFrame({
		reviewPackage: props.reviewPackage,
		protocolFrame: buildReviewSnapshotFrame({
			package: props.protocolFramePackage,
			paneId: 'bridge-app-test-pane',
			sourceIdentity: props.protocolFramePackage.query.queryId,
			streamId: 'review:bridge-app-test-pane',
			sequence: props.protocolFramePackage.revision,
		}),
	});
}

async function pushReviewPackageWithExplicitProtocolFrame(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly protocolFrame: ReturnType<typeof buildReviewSnapshotFrame>;
}): Promise<void> {
	await dispatchHostAdmittedEnvelope({
		__v: 1,
		__pushId: `push-${props.reviewPackage.packageId}-${props.reviewPackage.revision}`,
		__revision: props.reviewPackage.revision,
		__epoch: props.reviewPackage.reviewGeneration,
		store: 'diff',
		op: 'replace',
		level: 'cold',
		slice: 'diff_package_metadata',
		data: {
			package: props.reviewPackage,
			protocolFrame: props.protocolFrame,
		},
	});
}

async function pushStandaloneReviewReset(props: {
	readonly sourceIdentity: string;
	readonly packageId: string;
	readonly generation?: number;
}): Promise<void> {
	const generation = props.generation ?? 99;
	await dispatchHostAdmittedEnvelope({
		__v: 1,
		__pushId: `reset-${props.packageId}`,
		__revision: generation,
		__epoch: generation,
		store: 'diff',
		op: 'merge',
		level: 'hot',
		slice: 'diff_package_delta',
		data: {
			protocolFrame: {
				kind: 'reset',
				streamId: 'review:bridge-app-test-pane',
				generation,
				sequence: generation,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: props.sourceIdentity,
				packageId: props.packageId,
			},
		},
	});
}

async function pushStandaloneReviewInvalidation(props: {
	readonly generation: number;
	readonly itemIds: readonly string[];
	readonly pathHints?: readonly string[];
	readonly scope?: 'items' | 'paths';
	readonly streamId?: string;
}): Promise<void> {
	await dispatchHostAdmittedEnvelope({
		__v: 1,
		__pushId: `invalidate-${props.generation}-${props.itemIds.join('-')}`,
		__revision: props.generation,
		__epoch: props.generation,
		store: 'diff',
		op: 'merge',
		level: 'hot',
		slice: 'diff_package_delta',
		data: {
			protocolFrame: {
				kind: 'delta',
				streamId: props.streamId ?? 'review:bridge-app-test-pane',
				generation: props.generation,
				sequence: props.generation,
				frameKind: 'review.invalidate',
				invalidation: {
					scope: props.scope ?? 'items',
					...(props.itemIds.length === 0 ? {} : { itemIds: props.itemIds }),
					...(props.pathHints === undefined ? {} : { pathHints: props.pathHints }),
					reason: 'watchEvent',
				},
			},
		},
	});
}

async function dispatchHostAdmittedEnvelope(envelope: object): Promise<void> {
	await act(async (): Promise<void> => {
		postHostAdmittedEnvelope(envelope);
		await Promise.resolve();
		await Promise.resolve();
	});
	await act(async (): Promise<void> => {
		await waitForAnimationFrame();
	});
}

function postHostAdmittedEnvelope(envelope: object): void {
	document.dispatchEvent(
		new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
	);
	const channel = new MessageChannel();
	window.dispatchEvent(
		new MessageEvent('message', {
			data: {
				type: 'agentstudio.bridge.hostPushPort',
				version: 1,
			},
			ports: [channel.port2],
		}),
	);
	channel.port1.postMessage({
		type: 'agentstudio.bridge.hostPushEnvelopeJSON',
		version: 1,
		json: JSON.stringify(envelope),
	});
	window.setTimeout((): void => {
		channel.port1.close();
	}, 0);
}

function reviewPackagePushPayload(reviewPackage: BridgeReviewPackage): {
	readonly package: BridgeReviewPackage;
	readonly protocolFrame: ReturnType<typeof buildReviewSnapshotFrame>;
} {
	return {
		package: reviewPackage,
		protocolFrame: buildReviewSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:bridge-app-test-pane',
			sequence: reviewPackage.revision,
		}),
	};
}

function partialReviewDeltaFrame(
	frame: ReturnType<typeof buildReviewDeltaFrame>,
): ReturnType<typeof buildReviewDeltaFrame> {
	return {
		...frame,
		contentDescriptors: frame.contentDescriptors?.slice(0, 1),
	};
}

function makeLargeBridgeReviewPackage(itemCount: number): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const items = Array.from({ length: itemCount }, (_, index) =>
		makeBridgeReviewItem({
			itemId: `large-source-${String(index).padStart(3, '0')}`,
			path: `Sources/Large/File${String(index).padStart(3, '0')}.swift`,
		}),
	);

	return {
		...basePackage,
		orderedItemIds: items.map((item): string => item.itemId),
		itemsById: Object.fromEntries(items.map((item) => [item.itemId, item])),
		summary: {
			filesChanged: items.length,
			additions: items.reduce((total, item): number => total + item.additions, 0),
			deletions: items.reduce((total, item): number => total + item.deletions, 0),
			visibleFileCount: items.length,
			hiddenFileCount: 0,
		},
	};
}

function makeDeletedFileReviewPackageWithOmittedHeadPath(): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const sourceItem = basePackage.itemsById['item-source'];
	if (sourceItem === undefined) {
		throw new Error('expected source item fixture');
	}
	const baseHandle = sourceItem.contentRoles.base;
	if (baseHandle === undefined || baseHandle === null) {
		throw new Error('expected source base fixture');
	}
	const deletedBaseHandle: BridgeContentHandle = {
		...baseHandle,
		handleId: 'handle-deleted-source-base',
		itemId: 'deleted-source',
		resourceUrl: 'agentstudio://resource/review/content/handle-deleted-source-base?generation=1',
		contentHash: 'sha256:deleted-source:base',
		cacheKey: 'deleted-source:base',
		mimeType: 'text/x-swift',
		language: 'swift',
		sizeBytes: 256,
		isBinary: false,
	};
	const { headPath: omittedHeadPath, ...deletedItem } = {
		...sourceItem,
		itemId: 'deleted-source',
		basePath: 'Sources/Removed.swift',
		headPath: null,
		changeKind: 'deleted' as const,
		additions: 0,
		deletions: 4,
		headContentHash: null,
		contentRoles: {
			base: deletedBaseHandle,
			head: null,
			diff: null,
			file: null,
		},
		cacheKey: deletedBaseHandle.cacheKey,
	};
	void omittedHeadPath;

	return {
		...basePackage,
		orderedItemIds: [deletedItem.itemId],
		itemsById: { [deletedItem.itemId]: deletedItem },
		query: {
			...basePackage.query,
			pathScope: [],
		},
		summary: {
			filesChanged: 1,
			additions: 0,
			deletions: deletedItem.deletions,
			visibleFileCount: 1,
			hiddenFileCount: 0,
		},
	};
}

interface MakeAddedFileReviewPackageProps {
	readonly itemId: string;
	readonly path: string;
	readonly language: string;
	readonly extension: string;
	readonly fileClass: BridgeFileClass;
	readonly mimeType: string;
}

function makeAddedFileReviewPackage(props: MakeAddedFileReviewPackageProps): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const sourceItem = basePackage.itemsById['item-source'];
	if (sourceItem === undefined) {
		throw new Error('expected source item fixture');
	}
	const sourceHead = sourceItem.contentRoles.head;
	if (sourceHead === undefined || sourceHead === null) {
		throw new Error('expected source head fixture');
	}
	const headHandle: BridgeContentHandle = {
		...sourceHead,
		handleId: `handle-${props.itemId}-head`,
		itemId: props.itemId,
		resourceUrl: `agentstudio://resource/review/content/handle-${props.itemId}-head?generation=1`,
		contentHash: `sha256:${props.itemId}:head`,
		cacheKey: `${props.itemId}:head`,
		mimeType: props.mimeType,
		language: props.language,
		sizeBytes: 256,
		isBinary: false,
	};
	const addedItem = {
		...sourceItem,
		itemId: props.itemId,
		basePath: null,
		headPath: props.path,
		changeKind: 'added' as const,
		fileClass: props.fileClass,
		language: props.language,
		extension: props.extension,
		sizeBytes: headHandle.sizeBytes,
		baseContentHash: null,
		headContentHash: headHandle.contentHash,
		additions: 4,
		deletions: 0,
		contentRoles: {
			base: null,
			head: headHandle,
			diff: null,
			file: null,
		},
		cacheKey: headHandle.cacheKey,
	};

	return {
		...basePackage,
		orderedItemIds: [addedItem.itemId],
		itemsById: { [addedItem.itemId]: addedItem },
		query: {
			...basePackage.query,
			pathScope: [],
		},
		summary: {
			filesChanged: 1,
			additions: addedItem.additions,
			deletions: 0,
			visibleFileCount: 1,
			hiddenFileCount: 0,
		},
	};
}

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
	readonly reject: (error: Error) => void;
}

function createDeferred<TValue>(): Deferred<TValue> {
	let resolveValue: ((value: TValue) => void) | null = null;
	let rejectValue: ((error: Error) => void) | null = null;
	const promise = new Promise<TValue>((resolve, reject): void => {
		resolveValue = resolve;
		rejectValue = reject;
	});
	if (resolveValue === null || rejectValue === null) {
		throw new Error('Deferred promise handlers were not initialized.');
	}

	return {
		promise,
		resolve: resolveValue,
		reject: rejectValue,
	};
}

function installCodeViewDomAPIs(): void {
	if (!('ResizeObserver' in globalThis)) {
		Object.assign(globalThis, { ResizeObserver: TestResizeObserver });
	}
	if (HTMLElement.prototype.scrollTo === undefined) {
		HTMLElement.prototype.scrollTo = testElementScrollTo;
	}
}

function testElementScrollTo(): void {}

class TestResizeObserver implements ResizeObserver {
	readonly #callback: ResizeObserverCallback;

	constructor(callback: ResizeObserverCallback) {
		this.#callback = callback;
	}

	observe(target: Element): void {
		const entry = {
			target,
			contentRect: {
				x: 0,
				y: 0,
				width: 900,
				height: 500,
				top: 0,
				right: 900,
				bottom: 500,
				left: 0,
				toJSON: (): Record<string, number> => ({}),
			},
			borderBoxSize: [{ blockSize: 500, inlineSize: 900 }],
			contentBoxSize: [{ blockSize: 500, inlineSize: 900 }],
			devicePixelContentBoxSize: [{ blockSize: 500, inlineSize: 900 }],
		} satisfies ResizeObserverEntry;
		this.#callback([entry], this);
	}

	unobserve(): void {}

	disconnect(): void {}
}

function findReviewTreeItemButton(path: string): HTMLButtonElement | null {
	const fileTreeContainer = document.querySelector('file-tree-container');
	const shadowRoot = fileTreeContainer?.shadowRoot;
	if (shadowRoot === undefined || shadowRoot === null) {
		return null;
	}
	const buttons = [...shadowRoot.querySelectorAll('button[data-item-path]')];
	return (
		buttons.find(
			(button): button is HTMLButtonElement =>
				button instanceof HTMLButtonElement && button.dataset['itemPath'] === path,
		) ?? null
	);
}

function findReviewTreeSearchInput(): HTMLInputElement | null {
	const fileTreeContainer = document.querySelector('file-tree-container');
	const shadowRoot = fileTreeContainer?.shadowRoot;
	if (shadowRoot === undefined || shadowRoot === null) {
		return null;
	}
	const input = shadowRoot.querySelector('input[type="search"], input');
	return input instanceof HTMLInputElement ? input : null;
}

function isMarkFileViewedCommand(commandDetail: unknown): boolean {
	return (
		typeof commandDetail === 'object' &&
		commandDetail !== null &&
		'method' in commandDetail &&
		commandDetail.method === 'review.markFileViewed'
	);
}

function extractTelemetrySamples(commandDetail: unknown): readonly unknown[] {
	if (
		typeof commandDetail !== 'object' ||
		commandDetail === null ||
		!('method' in commandDetail) ||
		commandDetail.method !== 'system.bridgeTelemetry' ||
		!('params' in commandDetail) ||
		typeof commandDetail.params !== 'object' ||
		commandDetail.params === null ||
		!('samples' in commandDetail.params) ||
		!Array.isArray(commandDetail.params.samples)
	) {
		return [];
	}
	return commandDetail.params.samples;
}

function isPackageApplyTelemetrySample(sample: unknown): boolean {
	return (
		typeof sample === 'object' &&
		sample !== null &&
		'name' in sample &&
		sample.name === 'performance.bridge.web.package_apply'
	);
}

function makeTwoItemReviewPackage(): ReturnType<typeof makeBridgeReviewPackage> {
	const reviewPackage = makeBridgeReviewPackage();
	const sourceItem = reviewPackage.itemsById['item-source'];
	if (sourceItem === undefined) {
		throw new Error('expected source item fixture');
	}
	const secondBaseHandle: BridgeContentHandle | null = isMissingContentHandle(
		sourceItem.contentRoles.base,
	)
		? null
		: {
				...sourceItem.contentRoles.base,
				handleId: 'handle-item-second-base',
				itemId: 'item-second',
				resourceUrl: 'agentstudio://resource/review/content/handle-item-second-base?generation=1',
				cacheKey: 'item-second:base',
			};
	const secondHeadHandle: BridgeContentHandle | null = isMissingContentHandle(
		sourceItem.contentRoles.head,
	)
		? null
		: {
				...sourceItem.contentRoles.head,
				handleId: 'handle-item-second-head',
				itemId: 'item-second',
				resourceUrl: 'agentstudio://resource/review/content/handle-item-second-head?generation=1',
				cacheKey: 'item-second:head',
			};
	const secondItem = {
		...sourceItem,
		itemId: 'item-second',
		basePath: 'Sources/App/Second.swift',
		headPath: 'Sources/App/Second.swift',
		contentRoles: {
			base: secondBaseHandle,
			head: secondHeadHandle,
			diff: null,
			file: null,
		},
		cacheKey: 'item-second:base|item-second:head',
	};

	return {
		...reviewPackage,
		orderedItemIds: ['item-source', 'item-second'],
		itemsById: {
			...reviewPackage.itemsById,
			'item-second': secondItem,
		},
		summary: {
			...reviewPackage.summary,
			filesChanged: 2,
			visibleFileCount: 2,
		},
	};
}

function makeDuplicatePathReviewPackage(): ReturnType<typeof makeBridgeReviewPackage> {
	const reviewPackage = makeBridgeReviewPackage();
	const sourceItem = reviewPackage.itemsById['item-source'];
	if (sourceItem === undefined) {
		throw new Error('expected source item fixture');
	}
	const duplicateBaseHandle: BridgeContentHandle | null = isMissingContentHandle(
		sourceItem.contentRoles.base,
	)
		? null
		: {
				...sourceItem.contentRoles.base,
				handleId: 'handle-item-duplicate-path-base',
				itemId: 'item-duplicate-path',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-duplicate-path-base?generation=1',
				cacheKey: 'item-duplicate-path:base',
			};
	const duplicateHeadHandle: BridgeContentHandle | null = isMissingContentHandle(
		sourceItem.contentRoles.head,
	)
		? null
		: {
				...sourceItem.contentRoles.head,
				handleId: 'handle-item-duplicate-path-head',
				itemId: 'item-duplicate-path',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-duplicate-path-head?generation=1',
				cacheKey: 'item-duplicate-path:head',
			};
	const duplicateItem = {
		...sourceItem,
		itemId: 'item-duplicate-path',
		contentRoles: {
			base: duplicateBaseHandle,
			head: duplicateHeadHandle,
			diff: null,
			file: null,
		},
		cacheKey: 'item-duplicate-path:base|item-duplicate-path:head',
	};

	return {
		...reviewPackage,
		orderedItemIds: ['item-source', 'item-duplicate-path'],
		itemsById: {
			...reviewPackage.itemsById,
			'item-duplicate-path': duplicateItem,
		},
		summary: {
			...reviewPackage.summary,
			filesChanged: 2,
			visibleFileCount: 2,
		},
	};
}

function makeReviewFileNavigationCommand(props: {
	readonly commandId: string;
	readonly path: string;
	readonly reviewItemId: string;
}): BridgeViewerNavigationCommand {
	return {
		commandId: props.commandId,
		commandKind: 'activateTarget',
		context: 'review',
		restoreMemory: true,
		source: {
			sourceKind: 'reviewComparison',
			sourceId: 'review-source-1',
			comparisonId: 'comparison-1',
		},
		target: {
			targetKind: 'file',
			comparisonId: 'comparison-1',
			fileRef: {
				sourceId: 'review-source-1',
				path: props.path,
			},
			reviewItemId: props.reviewItemId,
			version: 'current',
		},
	};
}

function makeSourceAndDocsReviewPackage(): BridgeReviewPackage {
	const reviewPackage = makeBridgeReviewPackage();
	const docsItem = makeBridgeReviewItem({
		itemId: 'item-docs',
		path: 'docs/plans/review-plan.md',
	});
	const docsBaseHandle = isMissingContentHandle(docsItem.contentRoles.base)
		? null
		: {
				...docsItem.contentRoles.base,
				mimeType: 'text/markdown',
				language: 'markdown',
			};
	const docsHeadHandle = isMissingContentHandle(docsItem.contentRoles.head)
		? null
		: {
				...docsItem.contentRoles.head,
				mimeType: 'text/markdown',
				language: 'markdown',
			};
	const docsReviewItem = {
		...docsItem,
		fileClass: 'docs' as const,
		language: 'markdown',
		extension: 'md',
		contentRoles: {
			...docsItem.contentRoles,
			base: docsBaseHandle,
			head: docsHeadHandle,
		},
	};

	return {
		...reviewPackage,
		orderedItemIds: ['item-source', docsReviewItem.itemId],
		itemsById: {
			...reviewPackage.itemsById,
			[docsReviewItem.itemId]: docsReviewItem,
		},
		summary: {
			...reviewPackage.summary,
			filesChanged: 2,
			visibleFileCount: 2,
		},
	};
}

function makeUpdatedSelectedContentPackage(
	reviewPackage: BridgeReviewPackage,
): BridgeReviewPackage {
	const sourceItem = reviewPackage.itemsById['item-source'];
	if (sourceItem === undefined) {
		throw new Error('expected source item fixture');
	}
	const baseHandle: BridgeContentHandle | null = isMissingContentHandle(
		sourceItem.contentRoles.base,
	)
		? null
		: {
				...sourceItem.contentRoles.base,
				handleId: 'handle-item-source-base-revision-2',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-source-base-revision-2?generation=1',
				contentHash: 'sha256:item-source:base:revision-2',
				cacheKey: 'item-source:base:revision-2',
			};
	const headHandle: BridgeContentHandle | null = isMissingContentHandle(
		sourceItem.contentRoles.head,
	)
		? null
		: {
				...sourceItem.contentRoles.head,
				handleId: 'handle-item-source-head-revision-2',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-source-head-revision-2?generation=1',
				contentHash: 'sha256:item-source:head:revision-2',
				cacheKey: 'item-source:head:revision-2',
			};
	const updatedItem = {
		...sourceItem,
		itemVersion: sourceItem.itemVersion + 1,
		baseContentHash: baseHandle?.contentHash ?? sourceItem.baseContentHash,
		headContentHash: headHandle?.contentHash ?? sourceItem.headContentHash,
		contentRoles: {
			...sourceItem.contentRoles,
			base: baseHandle,
			head: headHandle,
		},
		cacheKey: `${baseHandle?.cacheKey ?? 'missing-base'}|${headHandle?.cacheKey ?? 'missing-head'}`,
	};

	return {
		...reviewPackage,
		revision: reviewPackage.revision + 1,
		itemsById: {
			...reviewPackage.itemsById,
			'item-source': updatedItem,
		},
	};
}

function makeUpdatedSelectedContentPackageWithStableHandleIds(
	reviewPackage: BridgeReviewPackage,
): BridgeReviewPackage {
	const sourceItem = reviewPackage.itemsById['item-source'];
	if (sourceItem === undefined) {
		throw new Error('expected source item fixture');
	}
	const baseHandle: BridgeContentHandle | null = isMissingContentHandle(
		sourceItem.contentRoles.base,
	)
		? null
		: {
				...sourceItem.contentRoles.base,
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-source-base?generation=1&revision=2',
				contentHash: 'sha256:item-source:base:stable-handle-revision-2',
				cacheKey: 'item-source:base:stable-handle-revision-2',
			};
	const headHandle: BridgeContentHandle | null = isMissingContentHandle(
		sourceItem.contentRoles.head,
	)
		? null
		: {
				...sourceItem.contentRoles.head,
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-source-head?generation=1&revision=2',
				contentHash: 'sha256:item-source:head:stable-handle-revision-2',
				cacheKey: 'item-source:head:stable-handle-revision-2',
			};
	const updatedItem = {
		...sourceItem,
		itemVersion: sourceItem.itemVersion + 1,
		baseContentHash: baseHandle?.contentHash ?? sourceItem.baseContentHash,
		headContentHash: headHandle?.contentHash ?? sourceItem.headContentHash,
		contentRoles: {
			...sourceItem.contentRoles,
			base: baseHandle,
			head: headHandle,
		},
		cacheKey: `${baseHandle?.cacheKey ?? 'missing-base'}|${headHandle?.cacheKey ?? 'missing-head'}`,
	};
	return {
		...reviewPackage,
		revision: reviewPackage.revision + 1,
		itemsById: {
			...reviewPackage.itemsById,
			'item-source': updatedItem,
		},
	};
}

function makeWorktreeNavigationDescriptor(): WorktreeFileDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'worktree-source-1',
		generation: 1,
		streamId: 'worktree-file:pane-1',
	};
	const contentDescriptor = {
		descriptorId: 'content-1',
		protocol: 'worktree-file',
		resourceKind: 'worktree.fileContent',
		resourceUrl: 'agentstudio://resource/worktree-file/worktree.fileContent/content-1?generation=1',
		identity,
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: 24,
			maxBytes: 1024,
		},
	};
	return worktreeFileDescriptorSchema.parse({
		path: 'src/app.ts',
		fileId: 'file-1',
		contentHandle: 'content-1',
		contentHash: 'sha256:abcdef',
		contentDescriptor: bridgeAttachedResourceDescriptorSchema.parse({
			ref: {
				descriptorId: contentDescriptor.descriptorId,
				expectedProtocol: contentDescriptor.protocol,
				expectedResourceKind: contentDescriptor.resourceKind,
				expectedIdentity: contentDescriptor.identity,
			},
			descriptor: contentDescriptor,
		}),
		sourceIdentity: {
			sourceId: 'worktree-source-1',
			repoId: 'repo-1',
			worktreeId: 'worktree-1',
			subscriptionGeneration: 1,
			sourceCursor: 'cursor-1',
		},
		sizeBytes: 24,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 1,
		isBinary: false,
		language: 'typescript',
		fileExtension: 'ts',
	});
}

function makeWorktreeNavigationFrames(
	descriptor: WorktreeFileDescriptor,
): readonly WorktreeFileProtocolFrame[] {
	return [
		{
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: descriptor.sourceIdentity,
			treeDescriptor: bridgeAttachedResourceDescriptorSchema.parse({
				ref: {
					descriptorId: 'tree-window-1',
					expectedProtocol: 'worktree-file',
					expectedResourceKind: 'worktree.treeWindow',
					expectedIdentity: {
						paneId: 'pane-1',
						protocol: 'worktree-file',
						sourceId: descriptor.sourceIdentity.sourceId,
						generation: 1,
						streamId: 'worktree-file:pane-1',
					},
				},
				descriptor: {
					descriptorId: 'tree-window-1',
					protocol: 'worktree-file',
					resourceKind: 'worktree.treeWindow',
					resourceUrl:
						'agentstudio://resource/worktree-file/worktree.treeWindow/tree-window-1?generation=1',
					identity: {
						paneId: 'pane-1',
						protocol: 'worktree-file',
						sourceId: descriptor.sourceIdentity.sourceId,
						generation: 1,
						streamId: 'worktree-file:pane-1',
					},
					content: {
						mediaType: 'application/json',
						encoding: 'utf-8',
						expectedBytes: 2,
						maxBytes: 1024,
					},
				},
			}),
			treeSizeFacts: {
				pathCount: 1,
				estimatedTotalHeightPixels: 24,
				rowHeightPixels: 24,
				windowRowCount: 1,
				windowStartIndex: 0,
			},
		},
		{
			kind: 'delta',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 1,
			frameKind: 'worktree.fileDescriptor',
			descriptor,
		},
	];
}

function isMissingContentHandle(
	handle: BridgeContentHandle | null | undefined,
): handle is null | undefined {
	return handle === null || handle === undefined;
}
