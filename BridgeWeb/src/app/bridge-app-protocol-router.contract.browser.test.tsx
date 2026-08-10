import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

const bridgeAppRouterContractMock = vi.hoisted(() => ({
	calls: [] as Array<{
		readonly viewerMode: 'file' | 'review' | undefined;
	}>,
}));

vi.mock('./bridge-app.js', () => ({
	BridgeApp: (props: { readonly viewerMode?: 'file' | 'review' }) => {
		bridgeAppRouterContractMock.calls.push({
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

		expect(bridgeAppRouterContractMock.calls).toEqual([{ viewerMode: 'file' }]);
		expect(
			document
				.querySelector('[data-testid="bridge-app-contract-mock"]')
				?.getAttribute('data-viewer-mode'),
		).toBe('file');
	});

	test('routes Review protocol by entering BridgeApp review mode', async () => {
		await render(<BridgeAppProtocolRouter protocol="review" />);

		expect(bridgeAppRouterContractMock.calls).toEqual([{ viewerMode: 'review' }]);
		expect(
			document
				.querySelector('[data-testid="bridge-app-contract-mock"]')
				?.getAttribute('data-viewer-mode'),
		).toBe('review');
	});
});
