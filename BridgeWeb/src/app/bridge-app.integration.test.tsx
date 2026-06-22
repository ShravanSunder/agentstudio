// @vitest-environment jsdom

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';

import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeFileClass,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
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
import { BridgeApp } from './bridge-app.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('BridgeApp', () => {
	let mountedRoot: Root | null = null;

	beforeEach(() => {
		installCodeViewDomAPIs();
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
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'status-loading',
						__revision: 1,
						__epoch: 2,
						store: 'diff',
						op: 'replace',
						level: 'hot',
						slice: 'diff_status',
						nonce: 'push-nonce',
						data: { status: 'loading', error: null, epoch: 2 },
					},
				}),
			);
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
						data: { package: reviewPackage },
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
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-1',
						__revision: 1,
						__epoch: 1,
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
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
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
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-large',
						__revision: 1,
						__epoch: 1,
						store: 'diff',
						op: 'replace',
						level: 'cold',
						slice: 'diff_package_metadata',
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
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
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-large',
						__revision: 1,
						__epoch: 1,
						store: 'diff',
						op: 'replace',
						level: 'cold',
						slice: 'diff_package_metadata',
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
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
			const projectionMenuControl = document.querySelector<HTMLButtonElement>(
				'[data-testid="bridge-review-projection-menu-control"]',
			);
			if (projectionMenuControl === null) {
				throw new Error('expected projection menu control');
			}
			projectionMenuControl.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
			const guidedMenuItem = document.querySelector<HTMLElement>(
				'[data-testid="bridge-review-projection-guided-review"]',
			);
			if (guidedMenuItem === null) {
				throw new Error('expected guided review projection menu item');
			}
			guidedMenuItem.dispatchEvent(new MouseEvent('click', { bubbles: true }));
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
						data: { package: reviewPackage },
					},
				}),
			);
			await Promise.resolve();
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(bridgeAppRenderedTextContent()).toContain('old revision head text');

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-2',
						__revision: 2,
						__epoch: 1,
						store: 'diff',
						op: 'replace',
						level: 'cold',
						slice: 'diff_package_metadata',
						nonce: 'push-nonce',
						data: { package: updatedPackage },
					},
				}),
			);
			await Promise.resolve();
			await Promise.resolve();
			await waitForAnimationFrame();
		});

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(bridgeAppRenderedTextContent()).not.toContain('old revision head text');
		expect(bridgeAppRenderedTextContent()).not.toContain('old revision base text');
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
						data: { package: reviewPackage },
					},
				}),
			);
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

	test('keeps shared content fetches alive while selection moves to another item', async () => {
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
						data: { package: reviewPackage },
					},
				}),
			);
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
		expect(initialSignals).toEqual([undefined, undefined]);

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
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-status',
						__revision: 1,
						__epoch: 1,
						store: 'diff',
						op: 'merge',
						level: 'cold',
						slice: 'diff_status',
						nonce: 'push-nonce',
						data: { status: 'ready' },
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
					'agentstudio.bridge.priority': 'hot',
					'agentstudio.bridge.slice': 'diff_status',
				}),
			}),
		);
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
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-diff',
						__revision: 1,
						__epoch: 1,
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
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
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
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-metadata',
						__revision: 1,
						__epoch: 1,
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
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
			await Promise.resolve();
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-delta',
						__revision: 2,
						__epoch: 1,
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
						nonce: 'push-nonce',
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
						},
					},
				}),
			);
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
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-1',
						__revision: 1,
						__epoch: 1,
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
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
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
						data: { package: reviewPackage },
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

function selectedBridgeViewerPanelAttribute(attributeName: string): string | null {
	return (
		document.querySelector('[data-testid="bridge-code-view-panel"]')?.getAttribute(attributeName) ??
		null
	);
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

async function dispatchBridgeAppControl(command: BridgeAppControlCommand): Promise<void> {
	await act(async (): Promise<void> => {
		window.dispatchEvent(new CustomEvent('__bridge_review_control', { detail: command }));
		await Promise.resolve();
	});
}

async function pushReviewPackage(reviewPackage: BridgeReviewPackage): Promise<void> {
	await act(async (): Promise<void> => {
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
		);
		document.dispatchEvent(
			new CustomEvent('__bridge_push', {
				detail: {
					__v: 1,
					__pushId: `push-${reviewPackage.packageId}`,
					__revision: reviewPackage.revision,
					__epoch: reviewPackage.reviewGeneration,
					store: 'diff',
					op: 'replace',
					level: 'cold',
					slice: 'diff_package_metadata',
					nonce: 'push-nonce',
					data: { package: reviewPackage },
				},
			}),
		);
		await Promise.resolve();
		await Promise.resolve();
	});
	await act(async (): Promise<void> => {
		await waitForAnimationFrame();
	});
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
		resourceUrl: 'agentstudio://resource/content/handle-deleted-source-base?generation=1',
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
		resourceUrl: `agentstudio://resource/content/handle-${props.itemId}-head?generation=1`,
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
				resourceUrl: 'agentstudio://resource/content/handle-item-second-base?generation=1',
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
				resourceUrl: 'agentstudio://resource/content/handle-item-second-head?generation=1',
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
					'agentstudio://resource/content/handle-item-source-base-revision-2?generation=1',
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
					'agentstudio://resource/content/handle-item-source-head-revision-2?generation=1',
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

function isMissingContentHandle(
	handle: BridgeContentHandle | null | undefined,
): handle is null | undefined {
	return handle === null || handle === undefined;
}
