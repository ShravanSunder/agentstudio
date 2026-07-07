import { afterEach, describe, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode geometry assertions need app CSS.
import './bridge-app.css';
import type { BridgeRPCCommand } from '../bridge/bridge-rpc-client.js';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { buildReviewMetadataSnapshotFrame } from '../features/review/protocol/review-metadata-frame-builder.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import {
	actClick,
	actUpdate,
	actWait,
	installBridgeReadyHandshake,
	pollWithinAct,
	pollWithinActUntilEqual,
	pollWithinActUntilTruthy,
	recordBridgeSchemeRPCFetch,
} from './bridge-app-native-review-error.browser.test-support.js';
import { makeSnapshotFrame } from './bridge-app-native-worktree-file.browser.test-support.js';
import {
	BridgeAppProtocolRouter,
	resolveBridgeAppProtocolFromElement,
} from './bridge-app-protocol-router.js';
import { BridgeApp } from './bridge-app.js';

type ActiveViewerModeUpdateDetail = Extract<
	BridgeRPCCommand,
	{ readonly method: 'bridge.activeViewerMode.update' }
>;

let activeDisposers: readonly (() => void)[] = [];

function registerDisposer(dispose: () => void): void {
	activeDisposers = [...activeDisposers, dispose];
}

describe('BridgeAppProtocolRouter', () => {
	afterEach(async () => {
		cleanup();
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		for (const dispose of activeDisposers) {
			dispose();
		}
		activeDisposers = [];
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		vi.restoreAllMocks();
	});

	test('defaults to Review when no app protocol is declared', async () => {
		render(<BridgeAppProtocolRouter />);

		const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
		const contextSwitcher = document.querySelector(
			'[data-testid="bridge-viewer-context-switcher"]',
		);
		const fileContextButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
		const reviewContextButton = document.querySelector(
			'[data-testid="bridge-viewer-context-review"]',
		);
		expect(appRoot?.getAttribute('data-bridge-app-owner')).toBe('BridgeApp');
		expect(appRoot?.getAttribute('data-bridge-viewer-shell-owner')).toBe('BridgeViewerAppShell');
		expect(appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('review');
		expect(contextSwitcher).not.toBeNull();
		expect(fileContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('false');
		expect(reviewContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('true');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		assertSharedResizableRailFallbackGeometry({
			contentPanelTestId: 'bridge-review-content-panel',
			frameTestId: 'bridge-review-fallback-frame',
			handleId: 'bridge-review-rail-resize-handle',
			railPanelTestId: 'bridge-review-resizable-rail',
		});
		expect(document.querySelector('[data-testid="worktree-file-app"]')).toBeNull();
	});

	test('routes Worktree/File protocol through the shared Bridge app shell', async () => {
		render(<BridgeAppProtocolRouter protocol="worktree-file" />);

		expect(document.querySelector('[data-testid="worktree-file-app"]')).toBeNull();
		const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
		const contextSwitcher = document.querySelector(
			'[data-testid="bridge-viewer-context-switcher"]',
		);
		const contentTopbar = document.querySelector('[data-testid="bridge-viewer-content-topbar"]');
		const fileContextButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
		const reviewContextButton = document.querySelector(
			'[data-testid="bridge-viewer-context-review"]',
		);
		const modeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
		const reviewModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-review"]');
		const lazyLoadingFrame = document.querySelector(
			'[data-testid="bridge-file-viewer-lazy-loading-frame"]',
		);
		expect(appRoot?.getAttribute('data-bridge-app-owner')).toBe('BridgeApp');
		expect(appRoot?.getAttribute('data-bridge-viewer-shell-owner')).toBe('BridgeViewerAppShell');
		expect(appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('file');
		expect(contentTopbar?.getAttribute('data-bridge-viewer-content-topbar')).toBe('true');
		expect(contextSwitcher?.closest('[data-testid="bridge-viewer-content-topbar"]')).toBe(
			contentTopbar,
		);
		expect(contextSwitcher).not.toBeNull();
		expect(fileContextButton?.getAttribute('data-slot')).toBe('button');
		expect(fileContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('true');
		expect(reviewContextButton?.getAttribute('data-slot')).toBe('button');
		expect(reviewContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('false');
		expect(modeHost?.parentElement).toBe(appRoot);
		expect(modeHost?.getAttribute('data-bridge-viewer-mode-active')).toBe('true');
		expect(modeHost?.className).not.toContain('pt-9');
		expect(reviewModeHost?.parentElement).toBe(appRoot);
		expect(reviewModeHost?.getAttribute('data-bridge-viewer-mode-active')).toBe('false');
		expect(reviewModeHost?.hasAttribute('hidden')).toBe(true);
		expect(document.querySelectorAll('[data-slot="resizable-panel-group"]')).toHaveLength(1);
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		expect(lazyLoadingFrame?.parentElement).toBe(modeHost);
		assertSharedResizableRailFallbackGeometry({
			contentPanelTestId: 'bridge-file-viewer-content-panel',
			frameTestId: 'bridge-file-viewer-lazy-loading-frame',
			handleId: 'bridge-file-viewer-rail-resize-handle',
			railPanelTestId: 'bridge-file-viewer-resizable-rail',
		});
		await actClick(requireActiveContextButton('review'));
		expect(
			await pollWithinActUntilEqual(
				() => appRoot?.getAttribute('data-bridge-viewer-mode'),
				'review',
			),
		).toBe('review');
		expect(document.querySelectorAll('[data-slot="resizable-panel-group"]')).toHaveLength(1);
		assertSharedResizableRailFallbackGeometry({
			contentPanelTestId: 'bridge-review-content-panel',
			frameTestId: 'bridge-review-fallback-frame',
			handleId: 'bridge-review-rail-resize-handle',
			railPanelTestId: 'bridge-review-resizable-rail',
		});
		await actClick(requireActiveContextButton('file'));
		expect(
			await pollWithinActUntilEqual(() => appRoot?.getAttribute('data-bridge-viewer-mode'), 'file'),
		).toBe('file');
		expect(document.querySelectorAll('[data-slot="resizable-panel-group"]')).toHaveLength(1);
		assertSharedResizableRailFallbackGeometry({
			contentPanelTestId: 'bridge-file-viewer-content-panel',
			frameTestId: 'bridge-file-viewer-lazy-loading-frame',
			handleId: 'bridge-file-viewer-rail-resize-handle',
			railPanelTestId: 'bridge-file-viewer-resizable-rail',
		});
		expect(document.querySelector('[data-testid="bridge-file-viewer-shell"]')).toBeNull();
	});

	test('starts Worktree/File native loading after the page bridge-ready event is emitted', async () => {
		const eventNames: string[] = [];
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			eventNames.push('worktree-file.load');
			return { frames: [] };
		};
		document.addEventListener(
			'__bridge_ready',
			(event): void => {
				eventNames.push('__bridge_ready');
				const detail = event instanceof CustomEvent ? event.detail : null;
				const requestId =
					typeof detail === 'object' &&
					detail !== null &&
					'requestId' in detail &&
					typeof detail.requestId === 'string'
						? detail.requestId
						: null;
				if (requestId !== null) {
					document.dispatchEvent(
						new CustomEvent('__bridge_ready_ack', {
							detail: { jsonrpc: '2.0', id: requestId, result: null },
						}),
					);
				}
			},
			{ once: true },
		);
		document.addEventListener(
			'__bridge_handshake_request',
			(): void => {
				eventNames.push('__bridge_handshake_request');
				document.dispatchEvent(
					new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
				);
			},
			{ once: true },
		);

		render(
			<BridgeAppProtocolRouter
				fileViewerProps={{ worktreeFileSurfaceTransport: { loadInitialSurface } }}
				protocol="worktree-file"
			/>,
		);

		await pollWithinActUntilTruthy(() => eventNames.includes('worktree-file.load'));
		expect(eventNames).toEqual([
			'__bridge_handshake_request',
			'__bridge_ready',
			'worktree-file.load',
		]);
	});

	test('emits active viewer mode notifications with monotonic sequence across mode switches', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});

		render(
			<BridgeAppProtocolRouter
				fileViewerProps={{
					worktreeFileSurfaceTransport: {
						loadInitialSurface: loadActiveViewerModeTestSurface,
					},
				}}
				protocol="worktree-file"
			/>,
		);

		expect(
			await pollWithinActUntilTruthy(() =>
				activeViewerModeUpdates(commandDetails).some(hasWorktreeFileActiveSource),
			),
		).toBe(true);
		await actClick(requireActiveContextButton('review'));
		expect(
			await pollWithinActUntilTruthy(() =>
				activeViewerModeUpdates(commandDetails).some((detail) => detail.params.mode === 'review'),
			),
		).toBe(true);
		await actClick(requireActiveContextButton('file'));
		expect(
			await pollWithinAct({
				getValue: () =>
					activeViewerModeUpdates(commandDetails).filter((detail) => detail.params.mode === 'file')
						.length,
				isSatisfied: (count): boolean => count >= 2,
			}),
		).toBeGreaterThanOrEqual(2);

		const updates = activeViewerModeUpdates(commandDetails);
		expect(updates.map((detail) => detail.params.sequence)).toEqual(
			updates.map((detail) => detail.params.sequence).toSorted((left, right) => left - right),
		);
		expect(new Set(updates.map((detail) => detail.params.sessionId)).size).toBe(1);
	});

	test('continues active viewer mode notifications for late sources after bridge-ready error', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		registerDisposer(
			installBridgeReadyHandshake({
				pushNonce: 'push-ready-error',
				readyErrorMessage: 'ready acknowledgement failed',
			}).dispose,
		);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});

		render(
			<BridgeAppProtocolRouter
				fileViewerProps={{
					worktreeFileSurfaceTransport: {
						loadInitialSurface: loadActiveViewerModeTestSurface,
					},
				}}
				protocol="worktree-file"
			/>,
		);

		expect(
			await pollWithinActUntilTruthy(() =>
				activeViewerModeUpdates(commandDetails).some(hasWorktreeFileActiveSource),
			),
		).toBe(true);
	});

	test('active viewer mode notifications match the committed mode through rapid transitions', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		const mismatchedUpdates: ActiveViewerModeUpdateDetail[] = [];
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			const response = recordBridgeSchemeRPCFetch(input, init, commandDetails);
			if (response === null) {
				return new Response('unexpected request', { status: 404 });
			}
			const detail = commandDetails.at(-1);
			if (!isActiveViewerModeUpdate(detail)) {
				return response;
			}
			const committedMode = activeViewerMode();
			if (committedMode !== null && committedMode !== detail.params.mode) {
				mismatchedUpdates.push(detail);
			}
			return response;
		});

		render(
			<BridgeAppProtocolRouter
				fileViewerProps={{
					worktreeFileSurfaceTransport: {
						loadInitialSurface: loadActiveViewerModeTestSurface,
					},
				}}
				protocol="review"
			/>,
		);
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');

		await actClick(requireActiveContextButton('file'));
		await actClick(requireActiveContextButton('review'));
		await actClick(requireActiveContextButton('file'));
		expect(await pollWithinActUntilEqual(activeViewerMode, 'file')).toBe('file');
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));

		expect(mismatchedUpdates).toEqual([]);
	});

	test('review active mode waits for current review source and dedupes source identity', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		const streamId = 'review:bridge-app-test-pane';
		const reviewPackage = makeBridgeReviewPackage();
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sourceIdentity: 'bridge-app-test-source',
			streamId,
			sequence: 0,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds,
		});
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-review-source' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});

		render(<BridgeAppProtocolRouter protocol="review" projectionWorkerClient={null} />);
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		expect(activeViewerModeUpdates(commandDetails)).toHaveLength(0);

		await dispatchIntakeFrame({
			generation: snapshotFrame.generation,
			kind: 'snapshot',
			nonce: 'push-review-source',
			payload: snapshotFrame,
			sequence: snapshotFrame.sequence,
			streamId,
		});
		expect(
			await pollWithinActUntilEqual(
				() => activeViewerModeUpdates(commandDetails).filter(hasReviewActiveSource).length,
				1,
			),
		).toBe(1);

		await dispatchIntakeFrame({
			generation: snapshotFrame.generation,
			kind: 'snapshot',
			nonce: 'push-review-source',
			payload: snapshotFrame,
			sequence: snapshotFrame.sequence + 1,
			streamId,
		});
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		expect(activeViewerModeUpdates(commandDetails).filter(hasReviewActiveSource)).toHaveLength(1);
	});

	test('dedupes file active source when a same-identity file surface open resolves', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		let loadCount = 0;
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadCount += 1;
			return await loadActiveViewerModeTestSurface();
		};

		const rendered = render(
			<BridgeApp
				fileViewerProps={{ worktreeFileSurfaceTransport: { loadInitialSurface } }}
				viewerMode="file"
			/>,
		);
		expect(
			await pollWithinActUntilEqual(
				() => activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource).length,
				1,
			),
		).toBe(1);

		const reloadSameSource = async (): Promise<WorktreeFileInitialSurface> => {
			loadCount += 1;
			return await loadActiveViewerModeTestSurface();
		};
		rendered.rerender(
			<BridgeApp
				fileViewerProps={{
					worktreeFileSurfaceTransport: { loadInitialSurface: reloadSameSource },
				}}
				viewerMode="file"
			/>,
		);

		expect(await pollWithinActUntilEqual(() => loadCount, 2)).toBe(2);
		expect(
			await pollWithinActUntilEqual(
				() => activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource).length,
				1,
			),
		).toBe(1);
	});

	test('parses document protocol metadata with Review as the fail-closed fallback', () => {
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'worktree-file');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('worktree-file');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'review-package');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
	});
});

function assertSharedResizableRailFallbackGeometry(props: {
	readonly contentPanelTestId: string;
	readonly frameTestId: string;
	readonly handleId: string;
	readonly railPanelTestId: string;
}): void {
	const frame = requireHTMLElement(document.querySelector(`[data-testid="${props.frameTestId}"]`));
	const layout = requireHTMLElement(frame.querySelector('[data-slot="resizable-panel-group"]'));
	const contentPanel = requireHTMLElement(
		frame.querySelector(`[data-testid="${props.contentPanelTestId}"]`),
	);
	const resizeHandle = requireHTMLElement(frame.querySelector(`#${props.handleId}`));
	const railPanel = requireHTMLElement(
		frame.querySelector(`[data-testid="${props.railPanelTestId}"]`),
	);
	const layoutBox = layout.getBoundingClientRect();
	const contentBox = contentPanel.getBoundingClientRect();
	const handleBox = resizeHandle.getBoundingClientRect();
	const railBox = railPanel.getBoundingClientRect();

	expect(layout.getAttribute('data-panel-group-direction')).toBe('horizontal');
	expect(contentPanel.id).toBe(props.contentPanelTestId);
	expect(railPanel.id).toBe(props.railPanelTestId);
	expect(layoutBox.width).toBeGreaterThan(700);
	expect(contentBox.width).toBeGreaterThan(railBox.width);
	expect(handleBox.width).toBeGreaterThanOrEqual(1);
	expect(railBox.width).toBeGreaterThanOrEqual(240);
	expect(railBox.height).toBeGreaterThan(200);
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected Bridge app browser test element to be an HTMLElement');
	}
	return element;
}

function requireActiveContextButton(mode: 'file' | 'review'): HTMLElement {
	return requireHTMLElement(
		document.querySelector(
			`[data-bridge-viewer-mode-active="true"] [data-testid="bridge-viewer-context-${mode}"]`,
		),
	);
}

async function loadActiveViewerModeTestSurface(): Promise<WorktreeFileInitialSurface> {
	return {
		frames: [makeSnapshotFrame({ generation: 7 })],
	};
}

function activeViewerModeUpdates(
	commandDetails: readonly BridgeRPCCommand[],
): ActiveViewerModeUpdateDetail[] {
	return commandDetails.filter(isActiveViewerModeUpdate);
}

function isActiveViewerModeUpdate(value: unknown): value is ActiveViewerModeUpdateDetail {
	return (
		isRecord(value) &&
		value['method'] === 'bridge.activeViewerMode.update' &&
		isRecord(value['params']) &&
		(value['params']['mode'] === 'file' || value['params']['mode'] === 'review') &&
		typeof value['params']['sequence'] === 'number' &&
		typeof value['params']['sessionId'] === 'string'
	);
}

function hasWorktreeFileActiveSource(detail: ActiveViewerModeUpdateDetail): boolean {
	return (
		detail.params.mode === 'file' &&
		isRecord(detail.params.activeSource) &&
		detail.params.activeSource['protocol'] === 'worktree-file' &&
		detail.params.activeSource['streamId'] === 'worktree-file:pane-1' &&
		detail.params.activeSource['generation'] === 7
	);
}

function hasReviewActiveSource(detail: ActiveViewerModeUpdateDetail): boolean {
	return (
		detail.params.mode === 'review' &&
		isRecord(detail.params.activeSource) &&
		detail.params.activeSource['protocol'] === 'review' &&
		detail.params.activeSource['streamId'] === 'review:bridge-app-test-pane' &&
		detail.params.activeSource['generation'] === 1
	);
}

function activeViewerMode(): string | null {
	return (
		document
			.querySelector('[data-testid="bridge-app-root"]')
			?.getAttribute('data-bridge-viewer-mode') ?? null
	);
}

async function dispatchIntakeFrame(
	frame: BridgeIntakeFrame & { readonly nonce: string },
): Promise<void> {
	await actUpdate((): void => {
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					nonce: frame.nonce,
					json: JSON.stringify(frame),
				},
			}),
		);
	});
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}
