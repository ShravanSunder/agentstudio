import { afterEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode renders need app CSS.
import './bridge-app.css';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

describe('Bridge review intake re-announce on activation', () => {
	afterEach(() => {
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
		document.documentElement.removeAttribute('data-bridge-nonce');
	});

	test('re-activating a review surface with no applied package re-announces intake-ready', async () => {
		const reviewIntakeReadyCount = installReviewIntakeReadyCounter();
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		installHandshake('push-reannounce-1');

		// Mount in file mode: the review intake controller announces once at
		// mount, but no review package ever arrives (dropped while inactive,
		// failed first load — the wedge classes).
		render(<BridgeAppProtocolRouter protocol="worktree-file" />);
		await expect.poll(() => reviewIntakeReadyCount.value).toBe(1);

		// Switching INTO review with no applied package must re-announce so
		// native re-delivers the package; a silent switch leaves the surface
		// blank forever.
		clickContext('review');
		await expect.poll(activeViewerMode).toBe('review');
		await expect.poll(() => reviewIntakeReadyCount.value).toBe(2);

		// Still no package: every re-activation keeps asking until content
		// lands — the ask is the browser's only recovery lever.
		clickContext('file');
		await expect.poll(activeViewerMode).toBe('file');
		clickContext('review');
		await expect.poll(activeViewerMode).toBe('review');
		await expect.poll(() => reviewIntakeReadyCount.value).toBe(3);
	});
});

function installReviewIntakeReadyCounter(): { readonly value: number } {
	const counter = { value: 0 };
	document.addEventListener('__bridge_command', (event): void => {
		if (!(event instanceof CustomEvent)) {
			return;
		}
		const detail: unknown = event.detail;
		if (
			typeof detail === 'object' &&
			detail !== null &&
			'method' in detail &&
			detail.method === 'bridge.intakeReady' &&
			'params' in detail &&
			typeof detail.params === 'object' &&
			detail.params !== null &&
			'protocolId' in detail.params &&
			detail.params.protocolId === 'review'
		) {
			counter.value += 1;
		}
	});
	return counter;
}

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
