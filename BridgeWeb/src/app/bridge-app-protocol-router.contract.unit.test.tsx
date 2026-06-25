// @vitest-environment jsdom

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, test, vi } from 'vitest';

import type { BridgeViewerNavigationCommand } from './bridge-viewer-navigation-models.js';

const bridgeAppRouterContractMock = vi.hoisted(() => ({
	calls: [] as Array<{
		readonly viewerMode: 'file' | 'review' | undefined;
	}>,
}));

vi.mock('./bridge-app.js', () => ({
	BridgeApp: (props: { readonly viewerMode?: 'file' | 'review' }) => {
		bridgeAppRouterContractMock.calls.push({ viewerMode: props.viewerMode });
		return <div data-testid="bridge-app-contract-mock" data-viewer-mode={props.viewerMode} />;
	},
}));

import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('BridgeAppProtocolRouter contract', () => {
	let mountedRoot: Root | null = null;

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		bridgeAppRouterContractMock.calls.length = 0;
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
	});

	test('routes Worktree/File protocol by entering BridgeApp file mode', async () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeAppProtocolRouter protocol="worktree-file" />);
		});

		expect(bridgeAppRouterContractMock.calls).toEqual([{ viewerMode: 'file' }]);
		expect(
			document
				.querySelector('[data-testid="bridge-app-contract-mock"]')
				?.getAttribute('data-viewer-mode'),
		).toBe('file');
	});

	test('routes Review protocol by entering BridgeApp review mode', async () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeAppProtocolRouter protocol="review" />);
		});

		expect(bridgeAppRouterContractMock.calls).toEqual([{ viewerMode: 'review' }]);
		expect(
			document
				.querySelector('[data-testid="bridge-app-contract-mock"]')
				?.getAttribute('data-viewer-mode'),
		).toBe('review');
	});

	test('routes Files navigation commands by entering BridgeApp file mode', async () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);
		const navigationCommand = {
			commandId: 'dev:worktree:files',
			commandKind: 'initialize',
			context: 'files',
			restoreMemory: true,
			source: {
				sourceId: 'dev-worktree-source',
				sourceKind: 'worktree',
			},
		} satisfies BridgeViewerNavigationCommand;

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeAppProtocolRouter navigationCommand={navigationCommand} />);
		});

		expect(bridgeAppRouterContractMock.calls).toEqual([{ viewerMode: 'file' }]);
	});

	test('routes Review navigation commands by entering BridgeApp review mode', async () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);
		const navigationCommand = {
			commandId: 'dev:worktree:review',
			commandKind: 'initialize',
			context: 'review',
			restoreMemory: true,
			source: {
				comparisonId: 'dev-current-worktree-comparison',
				sourceId: 'dev-current-worktree-review',
				sourceKind: 'reviewComparison',
			},
		} satisfies BridgeViewerNavigationCommand;

		await act(async (): Promise<void> => {
			mountedRoot?.render(<BridgeAppProtocolRouter navigationCommand={navigationCommand} />);
		});

		expect(bridgeAppRouterContractMock.calls).toEqual([{ viewerMode: 'review' }]);
	});
});
