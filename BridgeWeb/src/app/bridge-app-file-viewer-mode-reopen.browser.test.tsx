import { afterEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode renders need app CSS.
import './bridge-app.css';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

describe('Bridge file viewer mode re-open on switch', () => {
	afterEach(() => {
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
	});

	test('re-issues the worktree-file surface open when the file mode is re-activated', async () => {
		let loadCount = 0;
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadCount += 1;
			return { frames: [] };
		};
		installHandshake('push-reopen-1');

		// Start in review mode: the file shell is inactive but the frame
		// controller still opens its surface once at mount.
		render(<BridgeAppProtocolRouter fileViewerProps={{ loadInitialSurface }} protocol="review" />);
		await expect.poll(() => loadCount).toBe(1);

		// Switch to file: an in-place toggle (no WebView remount). Before the
		// re-open signal existed the surface never re-opened, so this stayed at 1.
		clickContext('file');
		await expect.poll(() => loadCount).toBe(2);
		await expect.poll(activeViewerMode).toBe('file');

		// Toggle away and back: each re-activation re-runs the open announce so a
		// wedged or stale-identity stream can always recover.
		clickContext('review');
		await expect.poll(activeViewerMode).toBe('review');
		clickContext('file');
		await expect.poll(() => loadCount).toBe(3);
	});

	test('recovers with a fresh open after a prior surface open wedged (never completed)', async () => {
		let loadCount = 0;
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadCount += 1;
			// Wedge the FIRST file-activation open so its stream never completes —
			// mirrors a native open that raced/hung. Recovery must not depend on
			// the wedged surface ever resolving.
			if (loadCount === 2) {
				return await new Promise<WorktreeFileInitialSurface>(() => {});
			}
			return { frames: [] };
		};
		installHandshake('push-reopen-2');

		render(<BridgeAppProtocolRouter fileViewerProps={{ loadInitialSurface }} protocol="review" />);
		await expect.poll(() => loadCount).toBe(1);

		// Switch to file: its open hangs forever (wedged surface).
		clickContext('file');
		await expect.poll(() => loadCount).toBe(2);
		await expect.poll(activeViewerMode).toBe('file');

		// Toggle away and back: the re-open announce must fire a fresh open even
		// though the prior open never completed, so the file view can recover.
		clickContext('review');
		await expect.poll(activeViewerMode).toBe('review');
		clickContext('file');
		await expect.poll(() => loadCount).toBe(3);
	});
});

function installHandshake(pushNonce: string): void {
	document.addEventListener(
		'__bridge_handshake_request',
		(): void => {
			document.dispatchEvent(new CustomEvent('__bridge_handshake', { detail: { pushNonce } }));
		},
		{ once: true },
	);
}

function activeViewerMode(): string | null {
	return (
		document
			.querySelector('[data-testid="bridge-app-root"]')
			?.getAttribute('data-bridge-viewer-mode') ?? null
	);
}

function clickContext(context: 'file' | 'review'): void {
	const button = document.querySelector<HTMLElement>(
		`[data-testid="bridge-viewer-context-${context}"]`,
	);
	if (button === null) {
		throw new Error(`Missing bridge-viewer-context-${context} button`);
	}
	button.click();
}
