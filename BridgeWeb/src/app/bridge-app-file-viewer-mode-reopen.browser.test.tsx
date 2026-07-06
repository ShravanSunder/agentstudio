import { afterEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode renders need app CSS.
import './bridge-app.css';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import {
	actClick,
	actUpdate,
	actWait,
	pollWithinActUntilEqual,
} from './bridge-app-native-review-error.browser.test-support.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

describe('Bridge file viewer mode re-open on switch', () => {
	afterEach(() => {
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
	});

	test('defers initial file surface load until a Review-first route activates Files', async () => {
		let loadCount = 0;
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadCount += 1;
			return { frames: [] };
		};
		installHandshake('push-reopen-1');

		render(
			<BridgeAppProtocolRouter
				fileViewerProps={{ worktreeFileSurfaceTransport: { loadInitialSurface } }}
				protocol="review"
			/>,
		);
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		expect(loadCount).toBe(0);

		await clickContext('file');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'file')).toBe('file');
		expect(await pollWithinActUntilEqual(() => loadCount, 1)).toBe(1);
	});

	test('reuses a live healthy stream — no re-open spam on healthy re-activations', async () => {
		let loadCount = 0;
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadCount += 1;
			return { frames: [] };
		};
		installHandshake('push-reopen-healthy');

		render(
			<BridgeAppProtocolRouter
				fileViewerProps={{ worktreeFileSurfaceTransport: { loadInitialSurface } }}
				protocol="worktree-file"
			/>,
		);
		expect(await pollWithinActUntilEqual(() => loadCount, 1)).toBe(1);

		await clickContext('review');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');
		await clickContext('file');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'file')).toBe('file');
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

		render(
			<BridgeAppProtocolRouter
				fileViewerProps={{ worktreeFileSurfaceTransport: { loadInitialSurface } }}
				protocol="worktree-file"
			/>,
		);
		expect(await pollWithinActUntilEqual(() => loadCount, 1)).toBe(1);

		await clickContext('review');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');

		// Switch back to file: the wedged surface never resolved, so the re-open fires
		// and recovers with a fresh open (which resolves).
		await clickContext('file');
		expect(await pollWithinActUntilEqual(() => loadCount, 2)).toBe(2);
		expect(await pollWithinActUntilEqual(activeViewerMode, 'file')).toBe('file');
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
					worktreeFileSurfaceTransport: {
						loadInitialSurface,
						registerSurfaceStreamResetRequiredCallback: (callback): (() => void) => {
							onSurfaceStreamResetRequired = callback;
							return (): void => {
								if (onSurfaceStreamResetRequired === callback) {
									onSurfaceStreamResetRequired = undefined;
								}
							};
						},
					},
				}}
				protocol="worktree-file"
			/>,
		);
		expect(await pollWithinActUntilEqual(() => loadCount, 1)).toBe(1);
		await clickContext('review');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');

		await actUpdate((): void => {
			onSurfaceStreamResetRequired?.();
		});
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		expect(loadCount).toBe(1);

		await clickContext('file');
		expect(await pollWithinActUntilEqual(() => loadCount, 2)).toBe(2);
		expect(await pollWithinActUntilEqual(activeViewerMode, 'file')).toBe('file');
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

async function clickContext(context: 'file' | 'review'): Promise<void> {
	const button = document.querySelector<HTMLElement>(
		`[data-testid="bridge-viewer-context-${context}"]`,
	);
	if (button === null) {
		throw new Error(`Missing bridge-viewer-context-${context} button`);
	}
	await actClick(button);
}
