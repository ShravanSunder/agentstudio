import { act } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode renders need app CSS.
import './bridge-app.css';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { buildReviewMetadataSnapshotFrame } from '../features/review/protocol/review-metadata-frame-builder.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import { waitForBridgeViewerAnimationFrame } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

describe('Bridge review intake re-announce on activation', () => {
	afterEach(() => {
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
		document.documentElement.removeAttribute('data-bridge-nonce');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
	});

	test('initial review metadata snapshot publishes a ready package and leaves metadata loading', async () => {
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
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		installHandshake('push-initial-snapshot');

		render(<BridgeAppProtocolRouter protocol="review" projectionWorkerClient={null} />);
		expect(
			await pollWithinActUntilPresent(() =>
				document.querySelector('[data-testid="bridge-review-empty-shell"]'),
			),
		).not.toBeNull();

		await dispatchIntakeFrame({
			generation: snapshotFrame.generation,
			kind: 'snapshot',
			nonce: 'push-initial-snapshot',
			payload: snapshotFrame,
			sequence: snapshotFrame.sequence,
			streamId,
		});

		await act(async (): Promise<void> => {
			await waitForBridgeViewerAnimationFrame();
		});
		expect(
			await pollWithinActUntilAbsent(() =>
				document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]'),
			),
		).toBeNull();
		expect(
			await pollWithinActUntilPresent(() =>
				document.querySelector('[data-testid="review-viewer-shell"]'),
			),
		).not.toBeNull();
	});

	test('a sequence gap on the live review stream re-announces intake-ready to unwedge resetRequired', async () => {
		const reviewIntakeReadyCount = installReviewIntakeReadyCounter();
		const streamId = 'review:bridge-app-test-pane';
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		installHandshake('push-reannounce-gap');

		render(<BridgeAppProtocolRouter protocol="review" />);
		expect(await pollWithinActUntilEqual(() => reviewIntakeReadyCount.value, 1)).toBe(1);

		// A frame dropped mid-stream opens a sequence gap; the receiver locks
		// into resetRequired and rejects every further same-generation frame —
		// the surface silently goes stale. Only a higher-generation reset can
		// re-key it, so the gap must trigger a re-announce.
		await dispatchBareDeltaIntakeFrame({ streamId, generation: 1, sequence: 0 });
		await dispatchBareDeltaIntakeFrame({ streamId, generation: 1, sequence: 7 });
		expect(await pollWithinActUntilEqual(() => reviewIntakeReadyCount.value, 2)).toBe(2);
	});

	test('re-activating a review surface with no applied package re-announces intake-ready', async () => {
		const reviewIntakeReadyCount = installReviewIntakeReadyCounter();
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		installHandshake('push-reannounce-1');

		// Mount in file mode: the review intake controller announces once at
		// mount, but no review package ever arrives (dropped while inactive,
		// failed first load — the wedge classes).
		render(<BridgeAppProtocolRouter protocol="worktree-file" />);
		expect(await pollWithinActUntilEqual(() => reviewIntakeReadyCount.value, 1)).toBe(1);

		// Switching INTO review with no applied package must re-announce so
		// native re-delivers the package; a silent switch leaves the surface
		// blank forever.
		await clickContext('review');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');
		expect(await pollWithinActUntilEqual(() => reviewIntakeReadyCount.value, 2)).toBe(2);

		// Still no package: every re-activation keeps asking until content
		// lands — the ask is the browser's only recovery lever.
		await clickContext('file');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'file')).toBe('file');
		await clickContext('review');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');
		expect(await pollWithinActUntilEqual(() => reviewIntakeReadyCount.value, 3)).toBe(3);
	});
});

// This router mounts real resizable-panel chrome (ResizeObserver-driven layout
// settling) and drives review intake through native-shaped CustomEvents rather
// than direct prop/state calls, so React updates land continuously across the
// whole test — on mount, after every dispatched frame, and from background
// layout settling in between. `expect.poll(...)` alone re-checks the DOM on a
// real-timer interval without ever opening a `act()` scope, so every one of
// those updates fires outside of `act()`. Poll from inside a real-timer act()
// loop instead, so whichever update lands during the wait is captured.
async function pollWithinAct<TValue>(props: {
	readonly getValue: () => TValue;
	readonly isSatisfied: (value: TValue) => boolean;
	readonly pollIntervalMilliseconds?: number;
	readonly timeoutMilliseconds?: number;
}): Promise<TValue> {
	const timeoutMilliseconds = props.timeoutMilliseconds ?? 5000;
	const pollIntervalMilliseconds = props.pollIntervalMilliseconds ?? 20;
	const deadlineMilliseconds = Date.now() + timeoutMilliseconds;
	// oxlint-disable-next-line no-unreachable-loop -- Bounded poll loop with an early return per iteration.
	for (;;) {
		const value = props.getValue();
		if (props.isSatisfied(value) || Date.now() >= deadlineMilliseconds) {
			return value;
		}
		// oxlint-disable-next-line no-await-in-loop -- Real-time settling (ResizeObserver, rAF, intake round trips) must drain sequentially inside act().
		await act(async (): Promise<void> => {
			await new Promise<void>((resolve): void => {
				setTimeout(resolve, pollIntervalMilliseconds);
			});
		});
	}
}

function pollWithinActUntilPresent(getValue: () => Element | null): Promise<Element | null> {
	return pollWithinAct({ getValue, isSatisfied: (value): boolean => value !== null });
}

function pollWithinActUntilAbsent(getValue: () => Element | null): Promise<Element | null> {
	return pollWithinAct({ getValue, isSatisfied: (value): boolean => value === null });
}

function pollWithinActUntilEqual<TValue>(
	getValue: () => TValue,
	expectedValue: TValue,
): Promise<TValue> {
	return pollWithinAct({ getValue, isSatisfied: (value): boolean => value === expectedValue });
}

async function dispatchBareDeltaIntakeFrame(frame: {
	readonly streamId: string;
	readonly generation: number;
	readonly sequence: number;
}): Promise<void> {
	await act(async (): Promise<void> => {
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					nonce: 'push-reannounce-gap',
					json: JSON.stringify({ kind: 'delta', payload: {}, ...frame }),
				},
			}),
		);
		await Promise.resolve();
	});
}

async function dispatchIntakeFrame(
	frame: BridgeIntakeFrame & { readonly nonce: string },
): Promise<void> {
	await act(async (): Promise<void> => {
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					nonce: frame.nonce,
					json: JSON.stringify(frame),
				},
			}),
		);
		await Promise.resolve();
	});
}

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

async function clickContext(context: 'file' | 'review'): Promise<void> {
	const button = document.querySelector<HTMLElement>(
		`[data-testid="bridge-viewer-context-${context}"]`,
	);
	if (button === null) {
		throw new Error(`Missing bridge-viewer-context-${context} button`);
	}
	await act(async (): Promise<void> => {
		button.click();
		await Promise.resolve();
	});
}
