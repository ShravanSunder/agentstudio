import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import type { BridgeViewerNavigationCommand } from './bridge-viewer-navigation-models.js';

const bridgeAppRouterContractMock = vi.hoisted(() => ({
	calls: [] as Array<{
		readonly navigationCommand: BridgeViewerNavigationCommand | undefined;
		readonly viewerMode: 'file' | 'review' | undefined;
	}>,
}));

vi.mock('./bridge-app.js', () => ({
	BridgeApp: (props: {
		readonly navigationCommand?: BridgeViewerNavigationCommand;
		readonly viewerMode?: 'file' | 'review';
	}) => {
		bridgeAppRouterContractMock.calls.push({
			navigationCommand: props.navigationCommand,
			viewerMode: props.viewerMode,
		});
		return <div data-testid="bridge-app-contract-mock" data-viewer-mode={props.viewerMode} />;
	},
}));

import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

describe('BridgeAppProtocolRouter contract', () => {
	afterEach(() => {
		bridgeAppRouterContractMock.calls.length = 0;
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
	});

	test('routes Worktree/File protocol by entering BridgeApp file mode', async () => {
		await render(<BridgeAppProtocolRouter protocol="worktree-file" />);

		expect(bridgeAppRouterContractMock.calls).toEqual([
			{ navigationCommand: undefined, viewerMode: 'file' },
		]);
		expect(
			document
				.querySelector('[data-testid="bridge-app-contract-mock"]')
				?.getAttribute('data-viewer-mode'),
		).toBe('file');
	});

	test('routes Review protocol by entering BridgeApp review mode', async () => {
		await render(<BridgeAppProtocolRouter protocol="review" />);

		expect(bridgeAppRouterContractMock.calls).toEqual([
			{ navigationCommand: undefined, viewerMode: 'review' },
		]);
		expect(
			document
				.querySelector('[data-testid="bridge-app-contract-mock"]')
				?.getAttribute('data-viewer-mode'),
		).toBe('review');
	});

	test('routes Files navigation commands by entering BridgeApp file mode', async () => {
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

		await render(<BridgeAppProtocolRouter navigationCommand={navigationCommand} />);

		expect(bridgeAppRouterContractMock.calls).toEqual([{ navigationCommand, viewerMode: 'file' }]);
	});

	test('routes Review navigation commands by entering BridgeApp review mode', async () => {
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

		await render(<BridgeAppProtocolRouter navigationCommand={navigationCommand} />);

		expect(bridgeAppRouterContractMock.calls).toEqual([
			{ navigationCommand, viewerMode: 'review' },
		]);
	});
});
