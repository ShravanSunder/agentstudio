import { act } from 'react';
import { afterAll, afterEach, beforeEach, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Exercise the actual shell styling.
import '../app/bridge-app.css';
import { BridgeFileViewerBrowserHarnessApp } from './bridge-file-viewer-browser-test-app.js';
import { makeBrowserFileBatch } from './bridge-file-viewer-browser-test-batches.js';
import {
	installBridgeFileViewerNoopResizeObserver,
	waitForBridgeFileViewerWorkerMessageDrain,
} from './bridge-file-viewer-browser-test-harness.js';

const originalResizeObserver = globalThis.ResizeObserver;
beforeEach((): void => installBridgeFileViewerNoopResizeObserver());
afterAll((): void => {
	Object.assign(globalThis, { ResizeObserver: originalResizeObserver });
});

afterEach(async (): Promise<void> => {
	await act(async (): Promise<void> => {
		await waitForBridgeFileViewerWorkerMessageDrain();
	});
	await act(async (): Promise<void> => {
		await cleanup();
	});
});

test('certified zero-row inventory is Empty while no selection has different copy', async () => {
	await render(
		<BridgeFileViewerBrowserHarnessApp initialFileBatch={makeBrowserFileBatch({ rows: [] })} />,
	);
	await act(async (): Promise<void> => {
		await waitForBridgeFileViewerWorkerMessageDrain();
	});
	expect(
		document
			.querySelector('[data-bridge-region="file-tree"]')
			?.getAttribute('data-presentation-state'),
	).toBe('empty');
	expect(document.querySelector('[data-bridge-region="file-tree"]')?.textContent).toContain(
		'No files',
	);
	expect(document.querySelector('[data-bridge-region="file-content"]')?.textContent).toContain(
		'Select a file',
	);
	expect(document.querySelector('[data-slot="skeleton"], .animate-spin')).toBeNull();
	expect(document.body.textContent).not.toMatch(/loading|waiting|pending/i);
});

test('first loading member is Loading, never stale or certified Empty', async () => {
	await render(
		<BridgeFileViewerBrowserHarnessApp
			initialFileBatch={makeBrowserFileBatch({ rows: [], status: { status: 'loading' } })}
		/>,
	);
	await act(async (): Promise<void> => {
		await waitForBridgeFileViewerWorkerMessageDrain();
	});
	expect(
		document
			.querySelector('[data-testid="bridge-file-viewer-shell"]')
			?.getAttribute('data-file-display-status'),
	).toBe('loading');
	expect(
		document
			.querySelector('[data-bridge-region="file-tree"]')
			?.getAttribute('data-presentation-state'),
	).toBe('loading');
	expect(
		document.querySelector('[data-bridge-region="file-tree"] [data-slot="skeleton"]'),
	).not.toBeNull();
	expect(
		document.querySelector('[data-bridge-region="file-content"] [data-slot="skeleton"]'),
	).toBeNull();
});

test('failed member is Failed rather than a ready-empty fallback', async () => {
	await render(
		<BridgeFileViewerBrowserHarnessApp
			initialFileBatch={makeBrowserFileBatch({ rows: [], status: { status: 'failed' } })}
		/>,
	);
	await act(async (): Promise<void> => {
		await waitForBridgeFileViewerWorkerMessageDrain();
	});
	expect(
		document
			.querySelector('[data-bridge-region="file-tree"]')
			?.getAttribute('data-presentation-state'),
	).toBe('failed');
	expect(document.querySelector('[data-bridge-region="file-tree"] [role="alert"]')).not.toBeNull();
	expect(
		document.querySelector('[data-bridge-region="file-tree"] [data-slot="skeleton"]'),
	).toBeNull();
});

test('a source discovery failure before any subscription is Failed with a surface Retry', async () => {
	let subscriptionOpenCount = 0;
	const rendered = await render(
		<BridgeFileViewerBrowserHarnessApp
			fileProductSession={{
				currentSource: async (): Promise<never> => {
					throw new Error('Source discovery failed');
				},
				onMetadataSubscriptionOpen: (): void => {
					subscriptionOpenCount += 1;
				},
			}}
		/>,
	);
	await act(async (): Promise<void> => {
		await waitForBridgeFileViewerWorkerMessageDrain();
	});
	expect(subscriptionOpenCount).toBe(0);
	expect(
		document
			.querySelector('[data-bridge-region="file-tree"]')
			?.getAttribute('data-presentation-state'),
	).toBe('failed');
	await expect.element(rendered.getByRole('button', { name: 'Retry' }).first()).toBeVisible();
	expect(document.querySelector('[data-slot="skeleton"]')).toBeNull();
});

test('typed no-file-source-authority is quiet noSource Empty, not Loading or Failed', async () => {
	await render(
		<BridgeFileViewerBrowserHarnessApp
			fileProductSession={{
				currentSource: async () => ({ status: 'unavailable', reason: 'no-file-source-authority' }),
			}}
		/>,
	);
	await act(async (): Promise<void> => {
		await waitForBridgeFileViewerWorkerMessageDrain();
	});
	expect(
		document
			.querySelector('[data-bridge-region="file-tree"]')
			?.getAttribute('data-presentation-state'),
	).toBe('empty');
	expect(document.querySelector('[data-bridge-region="file-tree"]')?.textContent).toContain(
		'This pane has no worktree files.',
	);
	expect(
		document.querySelector('[data-slot="skeleton"], [role="alert"], button[aria-label="Retry"]'),
	).toBeNull();
	expect(document.body.textContent).not.toMatch(/loading|waiting|pending/i);
});
