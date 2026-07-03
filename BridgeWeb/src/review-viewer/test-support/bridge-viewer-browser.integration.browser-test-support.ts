import { createElement } from 'react';
import { render } from 'vitest-browser-react';

import { BridgeApp, type BridgeAppProps } from '../../app/bridge-app.js';
import { waitForBridgeViewerAnimationFrame } from './bridge-viewer-browser-dom.js';
import type { BridgeViewerMockedBackend } from './bridge-viewer-mocked-backend.js';

export function renderBridgeViewerAppWithMockedBackend(props: {
	readonly backend: BridgeViewerMockedBackend;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly fetchContent?: BridgeViewerMockedBackend['fetchContent'];
}): void {
	render(
		createElement<BridgeAppProps>(BridgeApp, {
			codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled ?? false,
			...(props.codeViewWorkerFactory === undefined
				? {}
				: { codeViewWorkerFactory: props.codeViewWorkerFactory }),
			fetchContent: props.fetchContent ?? props.backend.fetchContent,
			markdownWorkerClient: null,
			projectionWorkerClient: props.backend.projectionWorkerClient,
		}),
	);
}

export async function waitForBridgeCodeViewHeaderForPath(
	path: string,
	remainingAttempts = 180,
): Promise<HTMLElement> {
	const header = findBridgeCodeViewHeaderForPath(path);
	if (header !== null) {
		return header;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge CodeView header for path ${path}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeCodeViewHeaderForPath(path, remainingAttempts - 1);
}

function findBridgeCodeViewHeaderForPath(path: string): HTMLElement | null {
	for (const container of document.querySelectorAll('diffs-container')) {
		const shadowRoot = container.shadowRoot;
		if (shadowRoot === null) {
			continue;
		}
		const header = [...shadowRoot.querySelectorAll('[data-diffs-header]')].find(
			(candidate: Element): candidate is HTMLElement =>
				candidate instanceof HTMLElement && (candidate.textContent ?? '').includes(path),
		);
		if (header !== undefined) {
			return header;
		}
	}
	return null;
}
