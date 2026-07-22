import { afterAll, afterEach, beforeEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode renders need app CSS.
import './bridge-app.css';
import { createBridgePaneRuntime } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeProductCallResult } from '../core/comm-worker/bridge-product-call-contracts.js';
import type { BridgeProductSubscriptionOptions } from '../core/comm-worker/bridge-product-subscription-contracts.js';
import type { BridgeFileViewerBrowserTestProductSession } from '../file-viewer/bridge-file-viewer-browser-test-app.js';
import { makeTreeRowsOnlyMetadataEvents } from '../file-viewer/bridge-file-viewer-browser-test-fixtures.js';
import {
	createBridgeFileViewerBrowserTestPaneSessionFactory,
	installBridgeFileViewerNoopResizeObserver,
	settleBridgeFileViewerBrowserUpdates,
} from '../file-viewer/bridge-file-viewer-browser-test-harness.js';
import {
	actClick,
	actUpdate,
	actWait,
	installBridgeReadyHandshake,
	pollWithinActUntilEqual,
} from './bridge-app-browser-test-actions.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

const originalBridgeFileViewerModeResizeObserver = globalThis.ResizeObserver;

describe('Bridge file viewer mode re-open on switch', () => {
	beforeEach(() => {
		installBridgeFileViewerNoopResizeObserver();
	});

	afterAll(() => {
		Object.assign(globalThis, { ResizeObserver: originalBridgeFileViewerModeResizeObserver });
	});

	afterEach(async () => {
		await settleBridgeFileViewerBrowserUpdates();
		await actUpdate(cleanup);
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
	});

	test('reuses the pane-owned File source warmed by a Review-first route', async () => {
		let sourceDiscoveryCount = 0;
		let metadataSubscriptionOpenCount = 0;
		const productSession: BridgeFileViewerBrowserTestProductSession = {
			currentSource: (): BridgeProductCallResult<'file.source.current'> => {
				sourceDiscoveryCount += 1;
				return availableFileSource();
			},
			initialMetadataEvents: makeTreeRowsOnlyMetadataEvents(),
			onMetadataSubscriptionOpen: (
				_options: BridgeProductSubscriptionOptions<'file.metadata'>,
			): void => {
				metadataSubscriptionOpenCount += 1;
			},
		};
		const handshake = installBridgeReadyHandshake();

		await renderFileProductApp('review', productSession);
		expect(await pollWithinActUntilEqual(() => sourceDiscoveryCount, 1)).toBe(1);
		expect(await pollWithinActUntilEqual(() => metadataSubscriptionOpenCount, 1)).toBe(1);

		await clickContext('file');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'file')).toBe('file');
		await settleBridgeFileViewerBrowserUpdates();
		expect(sourceDiscoveryCount).toBe(1);
		expect(metadataSubscriptionOpenCount).toBe(1);
		handshake.dispose();
	});

	test('reuses a live healthy stream — no re-open spam on healthy re-activations', async () => {
		let sourceDiscoveryCount = 0;
		let metadataSubscriptionOpenCount = 0;
		const productSession: BridgeFileViewerBrowserTestProductSession = {
			currentSource: (): BridgeProductCallResult<'file.source.current'> => {
				sourceDiscoveryCount += 1;
				return availableFileSource();
			},
			initialMetadataEvents: makeTreeRowsOnlyMetadataEvents(),
			onMetadataSubscriptionOpen: (): void => {
				metadataSubscriptionOpenCount += 1;
			},
		};
		const handshake = installBridgeReadyHandshake();

		await renderFileProductApp('worktree-file', productSession);
		expect(await pollWithinActUntilEqual(() => sourceDiscoveryCount, 1)).toBe(1);
		expect(await pollWithinActUntilEqual(() => metadataSubscriptionOpenCount, 1)).toBe(1);

		await clickContext('review');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');
		await settleViewerFrames();
		await clickContext('file');
		expect(await pollWithinActUntilEqual(activeViewerMode, 'file')).toBe('file');
		await settleBridgeFileViewerBrowserUpdates();
		await settleViewerFrames();
		expect(sourceDiscoveryCount).toBe(1);
		expect(metadataSubscriptionOpenCount).toBe(1);
		handshake.dispose();
	});
});

async function renderFileProductApp(
	protocol: 'review' | 'worktree-file',
	productSession: BridgeFileViewerBrowserTestProductSession,
): Promise<Awaited<ReturnType<typeof render>>> {
	const paneSessionFactory = createBridgeFileViewerBrowserTestPaneSessionFactory({
		productSessionRef: { current: productSession },
	});
	return await render(
		<BridgeAppProtocolRouter
			codeViewWorkerPoolEnabled={false}
			paneRuntimeFactory={() => createBridgePaneRuntime({ sessionFactory: paneSessionFactory })}
			protocol={protocol}
		/>,
	);
}

function availableFileSource(): BridgeProductCallResult<'file.source.current'> {
	return {
		status: 'available',
		source: {
			cwdScope: null,
			freshness: 'live',
			includeStatuses: true,
			repoId: '00000000-0000-4000-8000-000000000001',
			rootPathToken: 'browser-test-root',
			worktreeId: '00000000-0000-4000-8000-000000000002',
		},
	};
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

async function settleViewerFrames(): Promise<void> {
	await actWait(
		() =>
			new Promise<void>((resolve): void => {
				requestAnimationFrame((): void => {
					requestAnimationFrame((): void => resolve());
				});
			}),
	);
}
