import { expect } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

import { BridgeApp } from '../../app/bridge-app.js';
import { parseBridgeCoreResourceUrl } from '../../core/resources/bridge-resource-url.js';
import type { BridgeMarkdownRenderWorkerClient } from '../workers/markdown/bridge-markdown-render-worker-client.js';
export { installPierrePackagedWorkerFetchMock } from '../workers/pierre/bridge-pierre-dev-worker-factory.js';
import { waitForBridgeViewerAnimationFrame } from './bridge-viewer-browser-dom.js';
import type {
	BridgeViewerBrowserFixture,
	BridgeViewerMockedBackend,
	BridgeViewerMockedBackendDeliveryMode,
} from './bridge-viewer-mocked-backend.js';

interface BridgeViewerBrowserPerformanceSample {
	readonly durationMilliseconds: number;
	readonly fixture: BridgeViewerBrowserFixture;
	readonly backend: BridgeViewerMockedBackend;
	readonly deliveryMode?: BridgeViewerMockedBackendDeliveryMode;
	readonly codeViewWorkerPoolEnabled?: boolean;
}

export function renderBridgeApp(props: {
	readonly backend: BridgeViewerMockedBackend;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly markdownWorkerClient?: BridgeMarkdownRenderWorkerClient | null;
}): void {
	render(
		<BridgeApp
			codeViewWorkerPoolEnabled={props.codeViewWorkerPoolEnabled ?? false}
			fetchContent={props.backend.fetchContent}
			markdownWorkerClient={props.markdownWorkerClient ?? null}
			projectionWorkerClient={props.backend.projectionWorkerClient}
		/>,
	);
}

export async function finishPerformanceSample(props: {
	readonly durationMilliseconds: number;
	readonly fixture: BridgeViewerBrowserFixture;
	readonly backend: BridgeViewerMockedBackend;
	readonly deliveryMode?: BridgeViewerMockedBackendDeliveryMode;
	readonly codeViewWorkerPoolEnabled?: boolean;
}): Promise<BridgeViewerBrowserPerformanceSample> {
	expect(props.durationMilliseconds).toBeGreaterThan(0);
	expect(props.backend.projectionRequests.length).toBeGreaterThan(0);
	props.backend.dispose();
	cleanup();
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	document.body.replaceChildren();
	document.documentElement.removeAttribute('data-bridge-nonce');
	delete window.bridgeReviewControlProbe;
	return {
		durationMilliseconds: props.durationMilliseconds,
		fixture: props.fixture,
		backend: props.backend,
		...(props.deliveryMode === undefined ? {} : { deliveryMode: props.deliveryMode }),
		...(props.codeViewWorkerPoolEnabled === undefined
			? {}
			: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled }),
	};
}

export function percentile(values: readonly number[], percentileValue: number): number {
	if (values.length === 0) {
		throw new Error('expected at least one performance sample');
	}
	const sortedValues = [...values];
	// oxlint-disable-next-line unicorn/no-array-sort -- Sorting a local copy preserves the readonly input and supports current WebKit targets.
	sortedValues.sort((left, right): number => left - right);
	const index = Math.min(
		sortedValues.length - 1,
		Math.max(0, Math.ceil(sortedValues.length * percentileValue) - 1),
	);
	const value = sortedValues[index];
	if (value === undefined) {
		throw new Error('expected percentile sample');
	}
	return value;
}

export function isBridgeCommandForItem(detail: unknown, method: string, itemId: string): boolean {
	if (!isRecord(detail)) {
		return false;
	}
	const params = detail['params'];
	return detail['method'] === method && isRecord(params) && params['fileId'] === itemId;
}

export interface BackendLedgerCounts {
	readonly requestedUrlCount: number;
	readonly commandCount: number;
}

export function snapshotBackendLedgerCounts(
	backend: BridgeViewerMockedBackend,
): BackendLedgerCounts {
	return {
		requestedUrlCount: backend.requestedUrls.length,
		commandCount: backend.commandDetails.length,
	};
}

export function requestedContentUrlCount(
	backend: BridgeViewerMockedBackend,
	handleId: string,
): number {
	return backend.requestedUrls.filter((url: string): boolean => url.includes(handleId)).length;
}

export async function waitForRequestedContentUrlCountGreaterThan(
	backend: BridgeViewerMockedBackend,
	handleId: string,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (requestedContentUrlCount(backend, handleId) > count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected Bridge viewer content request count for ${handleId} to exceed ${count}; requested=${backend.requestedUrls.join(',')}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForRequestedContentUrlCountGreaterThan(backend, handleId, count, remainingAttempts - 1);
}

export async function waitForBridgeViewerSelectorAbsent(
	selector: string,
	remainingAttempts = 180,
): Promise<void> {
	if (document.querySelector(selector) === null) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge viewer selector to be absent: ${selector}`);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerSelectorAbsent(selector, remainingAttempts - 1);
}

export async function waitForBridgeViewerSelectedContentState(
	state: string,
	remainingAttempts = 180,
): Promise<void> {
	const shell = document.querySelector('[data-testid="review-viewer-shell"]');
	const currentState = shell?.getAttribute('data-selected-content-state') ?? 'missing';
	if (currentState === state) {
		return;
	}
	if (remainingAttempts <= 0) {
		const panel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		throw new Error(
			`expected selected content state ${state}; current=${currentState}; panel=${panel?.getAttribute('data-selected-content-state') ?? 'missing'}; text=${(document.body.textContent ?? '').slice(0, 300)}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerSelectedContentState(state, remainingAttempts - 1);
}

export function expectBackendCommandLedgerDelta(
	backend: BridgeViewerMockedBackend,
	beforeAction: BackendLedgerCounts,
	commandItemId: string,
): void {
	const actionCommands = backend.commandDetails.slice(beforeAction.commandCount);
	expect(
		actionCommands.some((detail: unknown): boolean =>
			isBridgeCommandForItem(detail, 'review.markFileViewed', commandItemId),
		),
	).toBe(true);
}

export function isBridgeContentResourceUrl(url: string): boolean {
	const parsedUrl = parseBridgeCoreResourceUrl(url, {
		allowedResourceKindsByProtocol: { review: new Set(['content']) },
	});
	return parsedUrl?.protocol === 'review' && parsedUrl.resourceKind === 'content';
}

export function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}
