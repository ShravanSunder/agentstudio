import { afterEach, describe, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode renders the real app chrome.
import './bridge-app.css';
import type { BridgeWorkerRpcCommandInput } from '../core/comm-worker/bridge-worker-rpc-client.js';
import {
	actClick,
	actWait,
	pollWithinActUntilEqual,
	pollWithinActUntilTruthy,
} from './bridge-app-browser-test-actions.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

const paneRuntimeObservation = vi.hoisted(() => ({
	createCount: 0,
	disposeCount: 0,
	paneCommands: [] as BridgeWorkerRpcCommandInput[],
	surfaceRequests: [] as Array<'fileView' | 'review'>,
}));

vi.mock('../core/comm-worker/bridge-pane-runtime.js', async (importOriginal) => {
	const actual =
		await importOriginal<typeof import('../core/comm-worker/bridge-pane-runtime.js')>();
	const { createBridgeMainRenderSnapshotStore } =
		await import('../core/comm-worker/bridge-main-render-snapshot-store.js');
	const { createBridgeWorkerRpcLifecycleStore } =
		await import('../core/comm-worker/bridge-worker-rpc-lifecycle-store.js');
	return {
		...actual,
		createBridgePaneRuntime: (): unknown => {
			paneRuntimeObservation.createCount += 1;
			const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
			const surfaceClients = new Map(
				(['fileView', 'review'] as const).map((surface) => [
					surface,
					{
						lifecycle: {
							getServerSnapshot: lifecycleStore.getServerSnapshot,
							getSnapshot: lifecycleStore.getSnapshot,
							subscribe: lifecycleStore.subscribe,
						},
						renderStore: createBridgeMainRenderSnapshotStore(),
						send: vi.fn(),
						subscribeMessages: vi.fn((): (() => void) => (): void => undefined),
						surface,
					},
				]),
			);
			return {
				dispose: (): void => {
					paneRuntimeObservation.disposeCount += 1;
				},
				installNativeBootstrap: vi.fn(),
				installTelemetryProducer: vi.fn(),
				lifecycleStore,
				paneClient: {
					lifecycle: {
						getServerSnapshot: lifecycleStore.getServerSnapshot,
						getSnapshot: lifecycleStore.getSnapshot,
						subscribe: lifecycleStore.subscribe,
					},
					send: (command: BridgeWorkerRpcCommandInput): string => {
						paneRuntimeObservation.paneCommands.push(command);
						return `pane-command-${paneRuntimeObservation.paneCommands.length}`;
					},
					subscribeMessages: vi.fn((): (() => void) => (): void => undefined),
				},
				setNativeBootstrapRequester: vi.fn(),
				surfaceClient: (surface: 'fileView' | 'review') => {
					paneRuntimeObservation.surfaceRequests.push(surface);
					return surfaceClients.get(surface);
				},
			};
		},
	};
});

describe('BridgeApp pane runtime hard cut', () => {
	afterEach(async () => {
		await actWait(async (): Promise<void> => {
			cleanup();
			await new Promise<void>((resolve) => window.setTimeout(resolve, 0));
		});
		vi.restoreAllMocks();
		paneRuntimeObservation.createCount = 0;
		paneRuntimeObservation.disposeCount = 0;
		paneRuntimeObservation.paneCommands = [];
		paneRuntimeObservation.surfaceRequests = [];
		document.body.replaceChildren();
	});

	test('keeps one pane-owned runtime and stable surface clients across File to Review to File', async () => {
		// Arrange
		await actWait(async (): Promise<void> => {
			render(<BridgeAppProtocolRouter protocol="worktree-file" />);
			await new Promise<void>((resolve) => window.setTimeout(resolve, 0));
		});
		const appRoot = requireHTMLElement(document.querySelector('[data-testid="bridge-app-root"]'));
		expect(
			await pollWithinActUntilTruthy(() =>
				document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
			),
		).not.toBeNull();
		await actWait(
			() => new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve())),
		);

		// Act
		await actClick(requireActiveContextButton('review'));
		expect(
			await pollWithinActUntilEqual(
				() => appRoot.getAttribute('data-bridge-viewer-mode'),
				'review',
			),
		).toBe('review');
		await actWait(() => Promise.resolve());
		await actClick(requireActiveContextButton('file'));
		expect(
			await pollWithinActUntilEqual(() => appRoot.getAttribute('data-bridge-viewer-mode'), 'file'),
		).toBe('file');
		await actWait(
			() => new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve())),
		);

		// Assert
		expect(paneRuntimeObservation.createCount).toBe(1);
		expect(paneRuntimeObservation.surfaceRequests).toEqual(
			expect.arrayContaining(['fileView', 'review']),
		);
		expect(paneRuntimeObservation.disposeCount).toBe(0);
	});
});

function requireActiveContextButton(mode: 'file' | 'review'): HTMLElement {
	return requireHTMLElement(
		document.querySelector(
			`[data-bridge-viewer-mode-active="true"] [data-testid="bridge-viewer-context-${mode}"]`,
		),
	);
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected an HTML element.');
	return element;
}
