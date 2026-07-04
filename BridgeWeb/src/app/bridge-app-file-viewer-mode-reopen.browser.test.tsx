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

	test('reuses a live healthy stream — no re-open spam on healthy re-activations', async () => {
		let loadCount = 0;
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadCount += 1;
			return { frames: [] };
		};
		installHandshake('push-reopen-1');

		// Start in review mode: the frame controller opens the surface once at
		// mount and it resolves (a healthy, live stream).
		render(<BridgeAppProtocolRouter fileViewerProps={{ loadInitialSurface }} protocol="review" />);
		await expect.poll(() => loadCount).toBe(1);

		// Toggle file↔review repeatedly. A healthy stream is reused, so no
		// re-open fires — the idempotence guard prevents re-open spam.
		clickContext('file');
		await expect.poll(activeViewerMode).toBe('file');
		clickContext('review');
		await expect.poll(activeViewerMode).toBe('review');
		clickContext('file');
		await expect.poll(activeViewerMode).toBe('file');
		expect(loadCount).toBe(1);
	});

	test('recovers a wedged (never-resolved) surface by re-opening on re-activation', async () => {
		let loadCount = 0;
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadCount += 1;
			// Wedge the mount-time open so the surface never resolves — mirrors a
			// native open that raced/hung. Its liveness signal never fires, so the
			// switch must re-open to recover.
			if (loadCount === 1) {
				return await new Promise<WorktreeFileInitialSurface>(() => {});
			}
			return { frames: [] };
		};
		installHandshake('push-reopen-2');

		render(<BridgeAppProtocolRouter fileViewerProps={{ loadInitialSurface }} protocol="review" />);
		await expect.poll(() => loadCount).toBe(1);

		// Switch to file: the wedged surface never resolved, so the re-open fires
		// and recovers with a fresh open (which resolves).
		clickContext('file');
		await expect.poll(() => loadCount).toBe(2);
		await expect.poll(activeViewerMode).toBe('file');
	});

	test('defers a hidden resolved file surface stream reset until file mode re-activates', async () => {
		let loadCount = 0;
		let onSurfaceStreamResetRequired: (() => void) | undefined;
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadCount += 1;
			return { frames: [] };
		};
		installHandshake('push-reopen-gap');

		render(
			<BridgeAppProtocolRouter
				fileViewerProps={{
					loadInitialSurface,
					registerSurfaceStreamResetRequiredCallback: (callback): (() => void) => {
						onSurfaceStreamResetRequired = callback;
						return (): void => {
							if (onSurfaceStreamResetRequired === callback) {
								onSurfaceStreamResetRequired = undefined;
							}
						};
					},
				}}
				protocol="review"
			/>,
		);
		await expect.poll(() => loadCount).toBe(1);
		clickContext('file');
		await expect.poll(activeViewerMode).toBe('file');
		clickContext('review');
		await expect.poll(activeViewerMode).toBe('review');

		onSurfaceStreamResetRequired?.();
		await new Promise((resolve) => window.setTimeout(resolve, 0));
		expect(loadCount).toBe(1);

		clickContext('file');
		await expect.poll(() => loadCount).toBe(2);
		await expect.poll(activeViewerMode).toBe('file');
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
