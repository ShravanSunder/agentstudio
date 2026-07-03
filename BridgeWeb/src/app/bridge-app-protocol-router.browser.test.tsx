import { afterEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode geometry assertions need app CSS.
import './bridge-app.css';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import { makeSnapshotFrame } from './bridge-app-native-worktree-file.browser.test-support.js';
import {
	BridgeAppProtocolRouter,
	resolveBridgeAppProtocolFromElement,
} from './bridge-app-protocol-router.js';

interface ActiveViewerModeUpdateDetail {
	readonly method: 'bridge.activeViewerMode.update';
	readonly params: {
		readonly activeSource: unknown;
		readonly mode: 'file' | 'review';
		readonly sequence: number;
		readonly sessionId: string;
	};
}

describe('BridgeAppProtocolRouter', () => {
	afterEach(() => {
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
		document.documentElement.removeAttribute('data-bridge-nonce');
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
		requireActiveContextButton('review').click();
		await expect.poll(() => appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('review');
		expect(document.querySelectorAll('[data-slot="resizable-panel-group"]')).toHaveLength(1);
		assertSharedResizableRailFallbackGeometry({
			contentPanelTestId: 'bridge-review-content-panel',
			frameTestId: 'bridge-review-fallback-frame',
			handleId: 'bridge-review-rail-resize-handle',
			railPanelTestId: 'bridge-review-resizable-rail',
		});
		requireActiveContextButton('file').click();
		await expect.poll(() => appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('file');
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
			(): void => {
				eventNames.push('__bridge_ready');
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
			<BridgeAppProtocolRouter fileViewerProps={{ loadInitialSurface }} protocol="worktree-file" />,
		);

		await expect.poll(() => eventNames.includes('worktree-file.load')).toBe(true);
		expect(eventNames).toEqual([
			'__bridge_handshake_request',
			'__bridge_ready',
			'worktree-file.load',
		]);
	});

	test('emits active viewer mode notifications with monotonic sequence across mode switches', async () => {
		const commandDetails: unknown[] = [];
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.addEventListener('__bridge_handshake_request', (): void => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
			);
		});
		document.addEventListener('__bridge_command', (event: Event): void => {
			const detail = extractEventDetail(event);
			commandDetails.push(detail);
			if (isBridgeReadyCommand(detail)) {
				document.dispatchEvent(
					new CustomEvent('__bridge_response', {
						detail: { id: detail.id, result: {}, nonce: 'push-1' },
					}),
				);
			}
		});

		render(
			<BridgeAppProtocolRouter
				fileViewerProps={{ loadInitialSurface: loadActiveViewerModeTestSurface }}
				protocol="worktree-file"
			/>,
		);

		await expect
			.poll(() => activeViewerModeUpdates(commandDetails).some(hasWorktreeFileActiveSource))
			.toBe(true);
		requireActiveContextButton('review').click();
		await expect
			.poll(() =>
				activeViewerModeUpdates(commandDetails).some((detail) => detail.params.mode === 'review'),
			)
			.toBe(true);
		requireActiveContextButton('file').click();
		await expect
			.poll(
				() =>
					activeViewerModeUpdates(commandDetails).filter((detail) => detail.params.mode === 'file')
						.length,
			)
			.toBeGreaterThanOrEqual(2);

		const updates = activeViewerModeUpdates(commandDetails);
		expect(updates.map((detail) => detail.params.sequence)).toEqual(
			updates.map((detail) => detail.params.sequence).toSorted((left, right) => left - right),
		);
		expect(new Set(updates.map((detail) => detail.params.sessionId)).size).toBe(1);
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
	commandDetails: readonly unknown[],
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

function isBridgeReadyCommand(
	value: unknown,
): value is { readonly id: string; readonly method: 'bridge.ready' } {
	return isRecord(value) && value['method'] === 'bridge.ready' && typeof value['id'] === 'string';
}

function extractEventDetail(event: Event): unknown {
	return event instanceof CustomEvent ? event.detail : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}
