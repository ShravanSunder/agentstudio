// @vitest-environment jsdom

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, test } from 'vitest';

import {
	BridgeAppProtocolRouter,
	resolveBridgeAppProtocolFromElement,
} from './bridge-app-protocol-router.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('BridgeAppProtocolRouter', () => {
	let mountedRoot: Root | null = null;

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
	});

	test('defaults to Review when no app protocol is declared', async () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeAppProtocolRouter />);
		});

		const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
		const contextSwitcher = document.querySelector(
			'[data-testid="bridge-viewer-context-switcher"]',
		);
		const contentTopbar = document.querySelector('[data-testid="bridge-viewer-content-topbar"]');
		const fileContextButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
		const reviewContextButton = document.querySelector(
			'[data-testid="bridge-viewer-context-review"]',
		);
		expect(appRoot?.getAttribute('data-bridge-app-owner')).toBe('BridgeApp');
		expect(appRoot?.getAttribute('data-bridge-viewer-shell-owner')).toBe('BridgeViewerAppShell');
		expect(appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('review');
		expect(contentTopbar?.getAttribute('data-bridge-viewer-content-topbar')).toBe('true');
		expect(contextSwitcher?.parentElement).toBe(contentTopbar);
		expect(contextSwitcher).not.toBeNull();
		expect(fileContextButton?.getAttribute('data-slot')).toBe('button');
		expect(fileContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('false');
		expect(reviewContextButton?.getAttribute('data-slot')).toBe('button');
		expect(reviewContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('true');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="worktree-file-app"]')).toBeNull();
	});

	test('routes Worktree/File protocol through the shared Bridge app shell', async () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeAppProtocolRouter protocol="worktree-file" />);
		});

		expect(document.querySelector('[data-testid="worktree-file-app"]')).toBeNull();
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
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
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		const codeCanvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
		const treeSidebar = document.querySelector('[data-testid="bridge-file-viewer-sidebar"]');
		expect(appRoot?.getAttribute('data-bridge-app-owner')).toBe('BridgeApp');
		expect(appRoot?.getAttribute('data-bridge-viewer-shell-owner')).toBe('BridgeViewerAppShell');
		expect(appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('file');
		expect(contentTopbar?.getAttribute('data-bridge-viewer-content-topbar')).toBe('true');
		expect(contextSwitcher?.parentElement).toBe(contentTopbar);
		expect(contextSwitcher).not.toBeNull();
		expect(fileContextButton?.getAttribute('data-slot')).toBe('button');
		expect(fileContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('true');
		expect(reviewContextButton?.getAttribute('data-slot')).toBe('button');
		expect(reviewContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('false');
		expect(modeHost?.parentElement).toBe(appRoot);
		expect(modeHost?.getAttribute('data-bridge-viewer-mode-active')).toBe('true');
		expect(modeHost?.className).toContain('pt-9');
		expect(shell?.parentElement).toBe(modeHost);
		expect(shell?.getAttribute('data-file-viewer-owner')).toBe('BridgeViewerApp.FileViewer');
		expect(shell?.getAttribute('data-sidebar-position')).toBe('right');
		expect(codeCanvas?.getAttribute('data-pierre-code-view-owner')).toBe('CodeView.file');
		expect(treeSidebar?.getAttribute('data-pierre-file-tree-owner')).toBe('FileTree');
	});

	test('parses document protocol metadata with Review as the fail-closed fallback', () => {
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'worktree-file');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('worktree-file');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'review-package');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
	});
});
