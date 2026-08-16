import { expect } from 'vitest';
import { render } from 'vitest-browser-react';

import type { BridgeWorkerRpcCommandInput } from '../core/comm-worker/bridge-worker-rpc-client.js';
import {
	actClick,
	actWait,
	installBridgeReadyHandshake,
	pollWithinActUntilEqual,
	pollWithinActUntilTruthy,
} from './bridge-app-browser-test-actions.js';
import {
	requestNativeSurface,
	requireActiveContextButton,
	requireHTMLElement,
} from './bridge-app-pane-runtime-control-test-support.js';
import {
	assertSurfacePositionRetained,
	establishSemanticSurfacePosition,
	waitForScrollableSurfaceOwners,
} from './bridge-app-pane-runtime-position-test-support.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

export async function runBridgeAppFileCornerSwitchJourney(props: {
	readonly activeViewerModeUpdateForNativeRequest: (
		nativeSelectionRequestId: string,
	) => BridgeWorkerRpcCommandInput | undefined;
	readonly installPositionFixtures: () => void;
	readonly publishNativeSurfaceSelectionRequest: (requestProps: {
		readonly bindingRevision: number;
		readonly nativeSelectionRequestId: string;
		readonly surface: 'file' | 'review';
	}) => Promise<void>;
	readonly runtimeCreateCount: () => number;
	readonly runtimeDisposeCount: () => number;
}): Promise<void> {
	const handshake = installBridgeReadyHandshake();
	await actWait(async (): Promise<void> => {
		await render(
			<div style={{ height: '860px', overflow: 'hidden', width: '1,440px' }}>
				<BridgeAppProtocolRouter
					codeViewWorkerPoolEnabled={false}
					fileViewerProps={{ autoOpenInitialFile: true }}
					protocol="worktree-file"
				/>
			</div>,
		);
		await Promise.resolve();
	});
	const appRoot = requireHTMLElement(document.querySelector('[data-testid="bridge-app-root"]'));
	const retainedFileHost = requireHTMLElement(
		document.querySelector('[data-testid="bridge-viewer-mode-host-file"]'),
	);
	const retainedReviewHost = requireHTMLElement(
		document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
	);
	await actWait(async (): Promise<void> => {
		props.installPositionFixtures();
		await Promise.resolve();
	});
	await requestNativeSurface({
		activeViewerModeUpdateForNativeRequest: props.activeViewerModeUpdateForNativeRequest,
		appRoot,
		bindingRevision: 1,
		nativeSelectionRequestId: 'native-selection-review-file-corner',
		publishNativeSurfaceSelectionRequest: props.publishNativeSurfaceSelectionRequest,
		surface: 'review',
	});
	const reviewOwners = await waitForScrollableSurfaceOwners({
		host: retainedReviewHost,
		surface: 'review',
	});
	const reviewPosition = await establishSemanticSurfacePosition(reviewOwners);
	const openFileButton = requireHTMLElement(
		await pollWithinActUntilTruthy(() =>
			viewportOpenFileButton(retainedReviewHost, reviewOwners.codeScrollOwner),
		),
	);
	const openedFilePath = openFileButton.getAttribute('data-bridge-code-view-file-path');
	if (openedFilePath === null) throw new Error('Missing file-corner command path.');
	await actClick(openFileButton);

	expect(await pollWithinActUntilEqual(() => appRoot.dataset['bridgeViewerMode'], 'file')).toBe(
		'file',
	);
	expect(
		await pollWithinActUntilEqual(
			() =>
				retainedFileHost
					.querySelector('[data-testid="bridge-file-viewer-shell"]')
					?.getAttribute('data-selected-display-path') ?? null,
			openedFilePath,
		),
	).toBe(openedFilePath);
	expect(document.querySelector('[data-testid="bridge-viewer-mode-host-file"]')).toBe(
		retainedFileHost,
	);
	expect(document.querySelector('[data-testid="bridge-viewer-mode-host-review"]')).toBe(
		retainedReviewHost,
	);

	await actClick(requireActiveContextButton('review'));

	expect(await pollWithinActUntilEqual(() => appRoot.dataset['bridgeViewerMode'], 'review')).toBe(
		'review',
	);
	await assertSurfacePositionRetained({
		expected: reviewPosition,
		owners: reviewOwners,
		surface: 'review',
	});
	expect(props.runtimeCreateCount()).toBe(1);
	expect(props.runtimeDisposeCount()).toBe(0);
	handshake.dispose();
}

function viewportOpenFileButton(host: HTMLElement, scrollOwner: HTMLElement): HTMLElement | null {
	const viewportBounds = scrollOwner.getBoundingClientRect();
	return (
		[
			...host.querySelectorAll<HTMLElement>('[data-testid="bridge-code-view-open-file-button"]'),
		].find((button): boolean => {
			const buttonBounds = button.getBoundingClientRect();
			return buttonBounds.bottom > viewportBounds.top && buttonBounds.top < viewportBounds.bottom;
		}) ?? null
	);
}
