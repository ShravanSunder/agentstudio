// @vitest-environment jsdom

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import { BridgeApp } from './bridge-app.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('BridgeApp', () => {
	let mountedRoot: Root | null = null;

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
					fetchContent={async (): Promise<Response> => new Response('loaded head text')}
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
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
			await Promise.resolve();
			await Promise.resolve();
		});

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(document.body.textContent).toContain('Sources/App/View.swift');
		expect(document.body.textContent).toContain('loaded head text');

		await act(async (): Promise<void> => {
			const selectedButton = document.querySelector('button');
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
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
			await Promise.resolve();
			await Promise.resolve();
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
				name: 'performance.bridge.web.first_render',
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
	});

	test('review telemetry keeps diff push parent after connection push arrives', async () => {
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
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-connection',
						__revision: 2,
						__epoch: 1,
						__traceContext: {
							traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
							spanId: 'bbbbbbbbbbbbbbbb',
							parentSpanId: null,
							sampled: true,
						},
						store: 'connection',
						op: 'merge',
						level: 'hot',
						nonce: 'push-nonce',
						data: { health: 'ready' },
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
			const secondButton = [...document.querySelectorAll('button')].find((button) =>
				button.textContent?.includes('Second.swift'),
			);
			if (secondButton === undefined) {
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
	const secondItem = {
		...sourceItem,
		itemId: 'item-second',
		basePath: 'Sources/App/Second.swift',
		headPath: 'Sources/App/Second.swift',
		contentRoles: {
			base: sourceItem.contentRoles.base
				? {
						...sourceItem.contentRoles.base,
						handleId: 'handle-item-second-base',
						itemId: 'item-second',
						cacheKey: 'item-second:base',
					}
				: null,
			head: sourceItem.contentRoles.head
				? {
						...sourceItem.contentRoles.head,
						handleId: 'handle-item-second-head',
						itemId: 'item-second',
						cacheKey: 'item-second:head',
					}
				: null,
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
