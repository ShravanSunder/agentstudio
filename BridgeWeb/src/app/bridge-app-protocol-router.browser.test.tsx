import { afterEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import {
	BridgeAppProtocolRouter,
	resolveBridgeAppProtocolFromElement,
} from './bridge-app-protocol-router.js';

describe('BridgeAppProtocolRouter', () => {
	afterEach(() => {
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
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
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		expect(lazyLoadingFrame?.parentElement).toBe(modeHost);
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

	test('parses document protocol metadata with Review as the fail-closed fallback', () => {
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'worktree-file');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('worktree-file');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'review-package');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
	});
});
