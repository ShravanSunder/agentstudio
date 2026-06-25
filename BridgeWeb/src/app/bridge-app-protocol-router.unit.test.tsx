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
		expect(document.querySelector('[data-testid="bridge-app-root"]')).not.toBeNull();
	});

	test('parses document protocol metadata with Review as the fail-closed fallback', () => {
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'worktree-file');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('worktree-file');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'review-package');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
	});
});
