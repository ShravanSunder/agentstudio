import { cleanup } from 'vitest-browser-react';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
export { installPierrePackagedWorkerFetchMock } from '../workers/pierre/bridge-pierre-dev-worker-factory.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../workers/pierre/bridge-pierre-worker-pool.js';
import {
	bridgeViewerCodeGeometry,
	bridgeViewerCodeTextContent,
	bridgeViewerRenderedTextContent,
	bridgeViewerVisibleCodeTextContent,
	waitForBridgeViewerAnimationFrame,
} from './bridge-viewer-browser-dom.js';
import type {
	BridgeViewerBrowserFixture,
	BridgeViewerMockedBackend,
} from './bridge-viewer-mocked-backend.js';

export * from './bridge-viewer-browser.integration.browser-test-support.js';

export function isBridgeCommandForItem(detail: unknown, method: string, itemId: string): boolean {
	if (!isRecord(detail)) {
		return false;
	}
	const params = detail['params'];
	return detail['method'] === method && isRecord(params) && params['fileId'] === itemId;
}

export async function waitForPendingProjectionResponseCount(
	backend: BridgeViewerMockedBackend,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.pendingProjectionResponses.length >= count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected ${count} pending projection responses`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForPendingProjectionResponseCount(backend, count, remainingAttempts - 1);
}

export async function waitForPendingProjectionResponseExactCount(
	backend: BridgeViewerMockedBackend,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.pendingProjectionResponses.length === count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected exactly ${count} pending projection responses`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForPendingProjectionResponseExactCount(backend, count, remainingAttempts - 1);
}

export async function waitForProjectionRequestCount(
	backend: BridgeViewerMockedBackend,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.projectionRequests.length >= count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected ${count} projection requests`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForProjectionRequestCount(backend, count, remainingAttempts - 1);
}

export async function waitForBridgeTelemetrySamples(
	backend: BridgeViewerMockedBackend,
	requiredNames: readonly string[],
	remainingAttempts = 180,
): Promise<readonly BridgeTelemetrySample[]> {
	const samples = telemetrySamplesFromBatches(backend.telemetryBatches);
	const presentNames = new Set(sampleNames(samples));
	if (requiredNames.every((name: string): boolean => presentNames.has(name))) {
		return samples;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			[
				`expected Bridge telemetry samples ${requiredNames.join(', ')}`,
				`actual=${sampleNames(samples).join(', ')}`,
			].join('; '),
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeTelemetrySamples(backend, requiredNames, remainingAttempts - 1);
}

export function telemetrySamplesFromCommands(
	commandDetails: readonly unknown[],
): readonly BridgeTelemetrySample[] {
	return commandDetails.flatMap((detail: unknown): readonly BridgeTelemetrySample[] => {
		if (!isBridgeTelemetryCommand(detail)) {
			return [];
		}
		return detail.params.samples;
	});
}

export function telemetrySamplesFromBatches(
	batches: readonly { readonly samples: readonly BridgeTelemetrySample[] }[],
): readonly BridgeTelemetrySample[] {
	return batches.flatMap((batch): readonly BridgeTelemetrySample[] => batch.samples);
}

export function sampleNames(samples: readonly BridgeTelemetrySample[]): readonly string[] {
	return samples.map((sample: BridgeTelemetrySample): string => sample.name);
}

export function isBridgeTelemetryCommand(value: unknown): value is {
	readonly method: 'system.bridgeTelemetry';
	readonly params: { readonly samples: readonly BridgeTelemetrySample[] };
} {
	return (
		typeof value === 'object' &&
		value !== null &&
		'method' in value &&
		value.method === 'system.bridgeTelemetry' &&
		'params' in value &&
		typeof value.params === 'object' &&
		value.params !== null &&
		'samples' in value.params &&
		Array.isArray(value.params.samples)
	);
}

export async function waitForBridgeViewerRenderedCodeGeometry(
	remainingAttempts = 180,
): Promise<void> {
	const geometry = bridgeViewerCodeGeometry();
	if (
		geometry.containerCount > 0 &&
		(geometry.lineCount > 0 || bridgeViewerCodeTextContent().trim().length > 0) &&
		geometry.firstContainerWidth > 0 &&
		geometry.firstContainerHeight > 0
	) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge CodeView geometry; geometry=${JSON.stringify(geometry)}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerRenderedCodeGeometry(remainingAttempts - 1);
}

export async function waitForBridgeCodeHeaderCollapseButtonForItemState(
	props: {
		readonly ariaExpanded: 'false' | 'true';
		readonly itemId: string;
	},
	remainingAttempts = 180,
): Promise<HTMLButtonElement> {
	const collapseButton = bridgeCodeHeaderCollapseButtons().find(
		(candidateButton: HTMLButtonElement): boolean =>
			candidateButton.dataset['bridgeCodeViewItemId'] === props.itemId &&
			candidateButton.getAttribute('aria-expanded') === props.ariaExpanded,
	);
	if (collapseButton !== undefined) {
		return collapseButton;
	}
	if (remainingAttempts <= 0) {
		const candidateStates = bridgeCodeHeaderCollapseButtons()
			.filter(
				(candidateButton: HTMLButtonElement): boolean =>
					candidateButton.dataset['bridgeCodeViewItemId'] === props.itemId,
			)
			.map((candidateButton: HTMLButtonElement): string | null =>
				candidateButton.getAttribute('aria-expanded'),
			);
		throw new Error(
			`expected Bridge CodeView header ${props.itemId} aria-expanded=${props.ariaExpanded}; states=${JSON.stringify(candidateStates)}`,
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeCodeHeaderCollapseButtonForItemState(props, remainingAttempts - 1);
}

export async function waitForBridgeCodeHeaderCollapseButtonForItemStateNearOffset(
	props: {
		readonly ariaExpanded: 'false' | 'true';
		readonly expectedOffset: number;
		readonly itemId: string;
		readonly maxDelta: number;
		readonly scrollOwner: HTMLElement;
	},
	remainingAttempts = 180,
): Promise<HTMLButtonElement> {
	const collapseButton = bridgeCodeHeaderCollapseButtons().find(
		(candidateButton: HTMLButtonElement): boolean =>
			candidateButton.dataset['bridgeCodeViewItemId'] === props.itemId &&
			candidateButton.getAttribute('aria-expanded') === props.ariaExpanded &&
			Math.abs(
				bridgeCodeHeaderOffsetFromScrollOwner({
					collapseButton: candidateButton,
					scrollOwner: props.scrollOwner,
				}) - props.expectedOffset,
			) <= props.maxDelta,
	);
	if (collapseButton !== undefined) {
		return collapseButton;
	}
	if (remainingAttempts <= 0) {
		const candidateOffsets = bridgeCodeHeaderCollapseButtons()
			.filter(
				(candidateButton: HTMLButtonElement): boolean =>
					candidateButton.dataset['bridgeCodeViewItemId'] === props.itemId,
			)
			.map(
				(
					candidateButton: HTMLButtonElement,
				): {
					readonly ariaExpanded: string | null;
					readonly offset: number;
				} => ({
					ariaExpanded: candidateButton.getAttribute('aria-expanded'),
					offset: bridgeCodeHeaderOffsetFromScrollOwner({
						collapseButton: candidateButton,
						scrollOwner: props.scrollOwner,
					}),
				}),
			);
		throw new Error(
			`expected Bridge CodeView header ${props.itemId} aria-expanded=${props.ariaExpanded} near ${props.expectedOffset}; candidates=${JSON.stringify(candidateOffsets)}`,
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeCodeHeaderCollapseButtonForItemStateNearOffset(
		props,
		remainingAttempts - 1,
	);
}

export function selectedBridgeViewerDisplayPath(): string | null {
	return (
		document
			.querySelector('[data-selected-display-path]')
			?.getAttribute('data-selected-display-path') ?? null
	);
}

export function bridgeViewerFetchInputUrl(input: RequestInfo | URL): string {
	if (typeof input === 'string') {
		return input;
	}
	if (input instanceof URL) {
		return input.toString();
	}
	return input.url;
}

export function selectedBridgeViewerContentState(): string | null {
	return (
		document
			.querySelector('[data-selected-content-state]')
			?.getAttribute('data-selected-content-state') ?? null
	);
}

export async function waitForSelectedBridgeViewerDisplayPath(
	displayPath: string,
	remainingAttempts = 180,
): Promise<void> {
	if (selectedBridgeViewerDisplayPath() === displayPath) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			[
				`expected selected Bridge viewer display path ${displayPath}, got ${selectedBridgeViewerDisplayPath() ?? 'null'}`,
				`reviewShell=${document.querySelector('[data-testid="review-viewer-shell"]') === null ? 'missing' : 'present'}`,
				`loadingShell=${document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]') === null ? 'missing' : 'present'}`,
				`failedShell=${document.querySelector('[data-testid="bridge-review-metadata-failed-shell"]') === null ? 'missing' : 'present'}`,
				`bodyText=${(document.body.textContent ?? '').slice(0, 240)}`,
			].join('\n'),
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForSelectedBridgeViewerDisplayPath(displayPath, remainingAttempts - 1);
}

export async function waitForSelectedBridgeViewerContentState(
	contentState: string,
	remainingAttempts = 180,
): Promise<void> {
	if (selectedBridgeViewerContentState() === contentState) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected selected Bridge viewer content state ${contentState}, got ${selectedBridgeViewerContentState() ?? 'null'}`,
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForSelectedBridgeViewerContentState(contentState, remainingAttempts - 1);
}

export async function waitForScrolledBridgeViewerFileTreeItemButton(props: {
	readonly scrollOwner: HTMLElement;
	readonly remainingAttempts?: number;
}): Promise<HTMLButtonElement> {
	const remainingAttempts = props.remainingAttempts ?? 180;
	const maxScrollTop = Math.max(0, props.scrollOwner.scrollHeight - props.scrollOwner.clientHeight);
	const attemptIndex = 180 - remainingAttempts;
	props.scrollOwner.scrollTop = maxScrollTop * ((attemptIndex % 181) / 180);
	props.scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
	await waitForBridgeViewerAnimationFrame();

	const viewport = props.scrollOwner.getBoundingClientRect();
	const fileTreeContainer = document.querySelector('file-tree-container');
	const shadowRoot = fileTreeContainer?.shadowRoot;
	const button =
		shadowRoot === undefined || shadowRoot === null
			? null
			: ([...shadowRoot.querySelectorAll('button[data-item-path][data-item-type="file"]')].find(
					(candidate): candidate is HTMLButtonElement => {
						if (!(candidate instanceof HTMLButtonElement)) {
							return false;
						}
						const candidateBox = candidate.getBoundingClientRect();
						return candidateBox.bottom >= viewport.top && candidateBox.top <= viewport.bottom;
					},
				) ?? null);
	if (button !== null) {
		return button;
	}
	if (remainingAttempts <= 0) {
		throw new Error('expected scrolled Bridge viewer tree file button');
	}
	return await waitForScrolledBridgeViewerFileTreeItemButton({
		remainingAttempts: remainingAttempts - 1,
		scrollOwner: props.scrollOwner,
	});
}

export async function waitForBridgeViewerTextWithDiagnostics(
	text: string,
	remainingAttempts = 180,
): Promise<void> {
	if (bridgeViewerRenderedTextContent().includes(text)) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			[
				`expected rendered Bridge viewer text to contain ${text}`,
				`selectedItemId=${selectedBridgeViewerPanelAttribute('data-selected-item-id') ?? 'null'}`,
				`selectedDisplayPath=${selectedBridgeViewerDisplayPath() ?? 'null'}`,
				`selectedContentState=${selectedBridgeViewerContentState() ?? 'null'}`,
				`materializedUpdate=${selectedBridgeViewerPanelAttribute('data-selected-materialized-update-result') ?? 'null'}`,
				`materializedType=${selectedBridgeViewerPanelAttribute('data-selected-materialized-item-type') ?? 'null'}`,
				`materializedModelState=${selectedBridgeViewerPanelAttribute('data-selected-materialized-model-content-state') ?? 'null'}`,
				`selectedPresentationKind=${selectedBridgeViewerPanelAttribute('data-selected-presentation-kind') ?? 'null'}`,
				`selectedPresentationVersion=${selectedBridgeViewerPanelAttribute('data-selected-presentation-version') ?? 'null'}`,
				`materializedModelVersion=${selectedBridgeViewerPanelAttribute('data-selected-materialized-model-item-version') ?? 'null'}`,
				`materializedAdditions=${selectedBridgeViewerPanelAttribute('data-selected-materialized-addition-line-count') ?? 'null'}`,
				`materializedDeletions=${selectedBridgeViewerPanelAttribute('data-selected-materialized-deletion-line-count') ?? 'null'}`,
				`materializedFileLines=${selectedBridgeViewerPanelAttribute('data-selected-materialized-file-line-count') ?? 'null'}`,
				`selectionScrollDidScroll=${selectedBridgeViewerPanelAttribute('data-selection-scroll-did-scroll') ?? 'null'}`,
				`selectionScrollItem=${selectedBridgeViewerPanelAttribute('data-selection-scroll-item-id') ?? 'null'}`,
				`selectionScrollItemTop=${selectedBridgeViewerPanelAttribute('data-selection-scroll-item-top') ?? 'null'}`,
				`selectionScrollReason=${selectedBridgeViewerPanelAttribute('data-selection-scroll-reason') ?? 'null'}`,
				`selectionScrollRemainingFrameBudget=${selectedBridgeViewerPanelAttribute('data-selection-scroll-remaining-frame-budget') ?? 'null'}`,
				`workerPool=${JSON.stringify(bridgeViewerWorkerPoolSnapshot())}`,
				`codeGeometry=${JSON.stringify(bridgeViewerCodeGeometry())}`,
				`codeScroll=${JSON.stringify(bridgeViewerCodeScrollSnapshot())}`,
				`controlProbe=${JSON.stringify(window.bridgeReviewControlProbe ?? null)}`,
				`diffContainers=${JSON.stringify(bridgeViewerDiffContainerSnapshots())}`,
				`rendered=${bridgeViewerRenderedTextContent().slice(0, 800)}`,
			].join('; '),
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerTextWithDiagnostics(text, remainingAttempts - 1);
}

export function selectedBridgeViewerPanelAttribute(attributeName: string): string | null {
	return (
		document.querySelector('[data-testid="bridge-code-view-panel"]')?.getAttribute(attributeName) ??
		null
	);
}

export function bridgeViewerWorkerPoolSnapshot(): Record<string, string> {
	const dataset = document.documentElement.dataset;
	return {
		activeTasks: dataset['bridgePierreWorkerPoolActiveTasks'] ?? 'missing',
		busyWorkers: dataset['bridgePierreWorkerPoolBusyWorkers'] ?? 'missing',
		diffCacheSize: dataset['bridgePierreWorkerPoolDiffCacheSize'] ?? 'missing',
		fileCacheSize: dataset['bridgePierreWorkerPoolFileCacheSize'] ?? 'missing',
		managerState: dataset['bridgePierreWorkerPoolManagerState'] ?? 'missing',
		queuedTasks: dataset['bridgePierreWorkerPoolQueuedTasks'] ?? 'missing',
		state: dataset['bridgePierreWorkerPoolState'] ?? 'missing',
		totalWorkers: dataset['bridgePierreWorkerPoolTotalWorkers'] ?? 'missing',
		workersFailed: dataset['bridgePierreWorkerPoolWorkersFailed'] ?? 'missing',
	};
}

export function bridgeViewerCodeScrollSnapshot(): Record<string, number | string> {
	const scrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
	if (!(scrollOwner instanceof HTMLElement)) {
		return { state: 'missing' };
	}
	return {
		clientHeight: Math.round(scrollOwner.clientHeight),
		scrollHeight: Math.round(scrollOwner.scrollHeight),
		scrollTop: Math.round(scrollOwner.scrollTop),
	};
}

export function bridgeViewerDiffContainerSnapshots(): readonly Record<string, number | string>[] {
	return [...document.querySelectorAll('diffs-container')].map(
		(element: Element, index: number): Record<string, number | string> => {
			const box = element.getBoundingClientRect();
			const shadowRoot = element.shadowRoot;
			const lineElements = [...(shadowRoot?.querySelectorAll('[data-line-index]') ?? [])];
			return {
				height: Math.round(box.height),
				index,
				lineCount: lineElements.length,
				lineText: lineElements
					.slice(0, 5)
					.map((lineElement: Element): string => lineElement.textContent ?? '')
					.join('\\n')
					.slice(0, 240),
				text: (shadowRoot?.textContent ?? '').slice(0, 240),
				top: Math.round(box.top),
			};
		},
	);
}

export async function waitForBridgeViewerVisibleCodeTextWithDiagnostics(
	scrollOwner: HTMLElement,
	text: string,
	remainingAttempts = 180,
): Promise<void> {
	const visibleText = bridgeViewerVisibleCodeTextContent(scrollOwner);
	if (visibleText.includes(text)) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			[
				`expected visible Bridge viewer CodeView text to contain ${text}`,
				`selectedDisplayPath=${selectedBridgeViewerDisplayPath() ?? 'null'}`,
				`selectedContentState=${selectedBridgeViewerContentState() ?? 'null'}`,
				`materializedUpdate=${selectedBridgeViewerPanelAttribute('data-selected-materialized-update-result') ?? 'null'}`,
				`materializedType=${selectedBridgeViewerPanelAttribute('data-selected-materialized-item-type') ?? 'null'}`,
				`materializedFileLines=${selectedBridgeViewerPanelAttribute('data-selected-materialized-file-line-count') ?? 'null'}`,
				`visible=${visibleText.slice(0, 800)}`,
			].join('; '),
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerVisibleCodeTextWithDiagnostics(scrollOwner, text, remainingAttempts - 1);
}

export async function waitForStableBridgeViewerVisibleCodeTextWithDiagnostics(
	scrollOwner: HTMLElement,
	text: string,
	stableFrameCount = 8,
): Promise<void> {
	await waitForBridgeViewerVisibleCodeTextWithDiagnostics(scrollOwner, text);
	for (let frameIndex = 0; frameIndex < stableFrameCount; frameIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Stable visible text proof must observe sequential animation frames.
		await waitForBridgeViewerAnimationFrame();
		// oxlint-disable-next-line no-await-in-loop -- Stable visible text proof must re-check each observed frame.
		await waitForBridgeViewerVisibleCodeTextWithDiagnostics(scrollOwner, text);
	}
}

export async function waitForProjectionAbortCount(
	backend: BridgeViewerMockedBackend,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.projectionAbortKeys.length >= count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected ${count} projection aborts`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForProjectionAbortCount(backend, count, remainingAttempts - 1);
}

export async function waitForPendingContentResponseCount(
	backend: BridgeViewerMockedBackend,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.pendingContentResponses.length >= count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected ${count} pending content responses`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForPendingContentResponseCount(backend, count, remainingAttempts - 1);
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

export function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}

export interface WaitForVisibleBridgeCodeHeaderCollapseButtonInOffsetRangeProps {
	readonly maxOffset: number;
	readonly minOffset: number;
	readonly scrollOwner: HTMLElement;
}

export async function waitForVisibleBridgeCodeHeaderCollapseButtonInOffsetRange(
	props: WaitForVisibleBridgeCodeHeaderCollapseButtonInOffsetRangeProps,
	remainingAttempts = 180,
): Promise<HTMLButtonElement> {
	for (const collapseButton of bridgeCodeHeaderCollapseButtons()) {
		const offset = bridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton,
			scrollOwner: props.scrollOwner,
		});
		if (offset >= props.minOffset && offset <= props.maxOffset) {
			return collapseButton;
		}
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected visible Bridge CodeView header collapse button between ${props.minOffset} and ${props.maxOffset}`,
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForVisibleBridgeCodeHeaderCollapseButtonInOffsetRange(
		props,
		remainingAttempts - 1,
	);
}

export function bridgeCodeHeaderCollapseButtons(): readonly HTMLButtonElement[] {
	const lightDomButtons = [
		...document.querySelectorAll('[data-testid="bridge-code-view-header-collapse-button"]'),
	].filter((button): button is HTMLButtonElement => button instanceof HTMLButtonElement);
	const shadowButtons = [...document.querySelectorAll('diffs-container')].flatMap(
		(container: Element): readonly HTMLButtonElement[] =>
			[
				...(container.shadowRoot?.querySelectorAll(
					'[data-testid="bridge-code-view-header-collapse-button"]',
				) ?? []),
			].filter((button): button is HTMLButtonElement => button instanceof HTMLButtonElement),
	);
	return [...lightDomButtons, ...shadowButtons];
}

export function requireBridgeCodeHeaderCollapseButtonItemId(
	collapseButton: HTMLButtonElement,
): string {
	const itemId = collapseButton.dataset['bridgeCodeViewItemId'];
	if (itemId === undefined || itemId.length === 0) {
		throw new Error('expected Bridge CodeView header collapse button item id');
	}
	return itemId;
}

export function bridgeCodeHeaderOffsetFromScrollOwner(props: {
	readonly collapseButton: HTMLElement;
	readonly scrollOwner: HTMLElement;
}): number {
	const headerElement = bridgeCodeHeaderElementForCollapseButton(props.collapseButton);
	return (
		(headerElement ?? props.collapseButton).getBoundingClientRect().top -
		props.scrollOwner.getBoundingClientRect().top
	);
}

export function bridgeCodeHeaderElementForCollapseButton(
	collapseButton: HTMLElement,
): HTMLElement | null {
	const lightDomHeader = collapseButton.closest<HTMLElement>('[data-diffs-header]');
	if (lightDomHeader !== null) {
		return lightDomHeader;
	}
	const rootHostElement = bridgeViewerShadowRootHostElement(collapseButton.getRootNode());
	if (rootHostElement !== null) {
		return rootHostElement.closest<HTMLElement>('[data-diffs-header]') ?? rootHostElement;
	}
	return null;
}

export function bridgeViewerShadowRootHostElement(root: Node): HTMLElement | null {
	if (!('host' in root) || !(root.host instanceof HTMLElement)) {
		return null;
	}
	return root.host;
}

export function bridgeViewerElementAncestorChain(element: HTMLElement): readonly string[] {
	const chain: string[] = [];
	let currentElement: HTMLElement | null = element;
	while (currentElement !== null && chain.length < 8) {
		const box = currentElement.getBoundingClientRect();
		chain.push(
			[
				currentElement.tagName.toLowerCase(),
				`top=${Math.round(box.top)}`,
				`bottom=${Math.round(box.bottom)}`,
				`height=${Math.round(box.height)}`,
				currentElement.getAttribute('data-diffs-header') === null
					? null
					: `data-diffs-header=${currentElement.getAttribute('data-diffs-header') ?? ''}`,
				currentElement.getAttribute('data-testid') === null
					? null
					: `testid=${currentElement.getAttribute('data-testid') ?? ''}`,
				typeof currentElement.className === 'string' && currentElement.className.length > 0
					? `class=${currentElement.className}`
					: null,
			]
				.filter((value): value is string => value !== null)
				.join(' '),
		);
		currentElement = currentElement.parentElement;
	}
	return chain;
}

export async function sampleBridgeCodeViewScrollMotion(props: {
	readonly action: () => void;
	readonly frameCount: number;
	readonly scrollOwner: HTMLElement;
}): Promise<readonly number[]> {
	const samples: number[] = [props.scrollOwner.scrollTop];
	props.action();
	for (let index = 0; index < props.frameCount; index += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Smooth-scroll proof must sample sequential animation frames.
		await waitForBridgeViewerAnimationFrame();
		samples.push(props.scrollOwner.scrollTop);
	}
	return samples;
}

export function isBridgeCodeViewSmoothMotionSample(samples: readonly number[]): boolean {
	if (samples.length < 4) {
		return false;
	}
	const motionSummary = summarizeBridgeCodeViewScrollMotion(samples);
	if (motionSummary.totalDistance < 64) {
		return false;
	}
	const uniqueRoundedSamples = new Set(samples.map((sample: number): number => Math.round(sample)));
	return (
		uniqueRoundedSamples.size >= 4 &&
		motionSummary.largestFrameDelta < motionSummary.totalDistance * 0.9
	);
}

export function isBridgeCodeViewIntentionalRevealMotionSample(samples: readonly number[]): boolean {
	if (isBridgeCodeViewSmoothMotionSample(samples)) {
		return true;
	}
	if (samples.length < 2) {
		return false;
	}
	const firstScrollTop = samples[0] ?? 0;
	const lastScrollTop = samples.at(-1) ?? firstScrollTop;
	const totalDistance = Math.abs(lastScrollTop - firstScrollTop);
	if (totalDistance < 64) {
		return false;
	}
	const largestFrameDelta = summarizeBridgeCodeViewScrollMotion(samples).largestFrameDelta;
	return largestFrameDelta >= totalDistance * 0.9;
}

export function expectBridgeCodeViewIntentionalRevealMotion(props: {
	readonly context: string;
	readonly samples: readonly number[];
}): void {
	if (isBridgeCodeViewIntentionalRevealMotionSample(props.samples)) {
		return;
	}
	throw new Error(
		`expected intentional Bridge CodeView reveal motion for ${props.context}; summary=${JSON.stringify(
			summarizeBridgeCodeViewScrollMotion(props.samples),
		)} samples=${JSON.stringify(props.samples.map((sample): number => Math.round(sample)))}`,
	);
}

export function summarizeBridgeCodeViewScrollMotion(samples: readonly number[]): {
	readonly largeFrameDeltaCount: number;
	readonly largestFrameDelta: number;
	readonly totalDistance: number;
} {
	const firstScrollTop = samples[0] ?? 0;
	const lastScrollTop = samples.at(-1) ?? firstScrollTop;
	const frameDeltas = samples.slice(1).map((sample: number, index: number): number => {
		const previousSample = samples[index] ?? sample;
		return Math.abs(sample - previousSample);
	});
	const largestFrameDelta = samples
		.slice(1)
		.reduce((largestDelta: number, sample: number, index: number): number => {
			const previousSample = samples[index] ?? sample;
			return Math.max(largestDelta, Math.abs(sample - previousSample));
		}, 0);
	return {
		largeFrameDeltaCount: frameDeltas.filter((frameDelta: number): boolean => frameDelta > 2000)
			.length,
		largestFrameDelta,
		totalDistance: Math.abs(lastScrollTop - firstScrollTop),
	};
}

export function bridgeReviewFixtureItemIdForPath(
	fixture: BridgeViewerBrowserFixture,
	path: string,
): string {
	for (const item of Object.values(fixture.reviewPackage.itemsById)) {
		if ((item.headPath ?? item.basePath) === path) {
			return item.itemId;
		}
	}
	throw new Error(`expected fixture item for path ${path}`);
}

export async function cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke(): Promise<void> {
	cleanup();
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	terminateBridgePierreWorkerPoolSingletonForTest();
	await waitForBridgePierreWorkerPoolDiagnosticsCleared();
}

export async function waitForBridgePierreWorkerPoolDiagnosticsCleared(
	remainingAttempts = 30,
): Promise<void> {
	if (bridgePierreWorkerPoolDiagnosticsAreCleared()) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected Bridge Pierre worker pool diagnostics to clear before worker revoke, got ${JSON.stringify(
				bridgeViewerWorkerPoolSnapshot(),
			)}`,
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgePierreWorkerPoolDiagnosticsCleared(remainingAttempts - 1);
}

export function bridgePierreWorkerPoolDiagnosticsAreCleared(): boolean {
	const dataset = document.documentElement.dataset;
	return (
		dataset['bridgePierreWorkerPoolActiveTasks'] === undefined &&
		dataset['bridgePierreWorkerPoolBusyWorkers'] === undefined &&
		dataset['bridgePierreWorkerPoolManagerState'] === undefined &&
		dataset['bridgePierreWorkerPoolQueuedTasks'] === undefined &&
		dataset['bridgePierreWorkerPoolState'] === undefined &&
		dataset['bridgePierreWorkerPoolWorkersFailed'] === undefined
	);
}

export async function waitForBridgeCodeHeaderCollapseButtonForItem(
	itemId: string,
	remainingAttempts = 180,
): Promise<HTMLButtonElement> {
	for (const collapseButton of bridgeCodeHeaderCollapseButtons()) {
		if (collapseButton.dataset['bridgeCodeViewItemId'] === itemId) {
			return collapseButton;
		}
	}
	if (remainingAttempts <= 0) {
		const renderedHeaderItemIds = bridgeCodeHeaderCollapseButtons().map(
			(collapseButton: HTMLButtonElement): string | undefined =>
				collapseButton.dataset['bridgeCodeViewItemId'],
		);
		const appRoot = document.querySelector<HTMLElement>('[data-testid="bridge-app-root"]');
		const codeViewRoot = document.querySelector<HTMLElement>(
			'[data-testid="bridge-code-view-panel"]',
		);
		throw new Error(
			`expected Bridge CodeView header collapse button for ${itemId}; diagnostics=${JSON.stringify({
				renderedHeaderItemIds,
				selectedDisplayPath:
					document.documentElement.dataset['bridgeViewerSelectedDisplayPath'] ?? null,
				selectedContentState:
					document.documentElement.dataset['bridgeViewerSelectedContentState'] ?? null,
				appTextPreview: appRoot?.textContent?.slice(0, 240) ?? null,
				codeViewDataset:
					codeViewRoot === null ? null : Object.fromEntries(Object.entries(codeViewRoot.dataset)),
			})}`,
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeCodeHeaderCollapseButtonForItem(itemId, remainingAttempts - 1);
}

export async function waitForBridgeCodeHeaderOffsetFromScrollOwner(props: {
	readonly collapseButton: HTMLButtonElement;
	readonly maxOffset: number;
	readonly scrollOwner: HTMLElement;
	readonly remainingAttempts?: number;
}): Promise<number> {
	const minimumHeaderOffset = -20;
	const offset = bridgeCodeHeaderOffsetFromScrollOwner({
		collapseButton: props.collapseButton,
		scrollOwner: props.scrollOwner,
	});
	if (offset >= minimumHeaderOffset && offset <= props.maxOffset) {
		return offset;
	}
	const remainingAttempts = props.remainingAttempts ?? 180;
	if (remainingAttempts <= 0) {
		const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		const headerElement = bridgeCodeHeaderElementForCollapseButton(props.collapseButton);
		const scrollOwnerBox = props.scrollOwner.getBoundingClientRect();
		const headerBox = headerElement?.getBoundingClientRect() ?? null;
		const collapseButtonBox = props.collapseButton.getBoundingClientRect();
		const collapseButtonRoot = props.collapseButton.getRootNode();
		throw new Error(
			`expected Bridge CodeView header near scroll top, got offset ${offset}; diagnostics=${JSON.stringify(
				{
					scrollTop: Math.round(props.scrollOwner.scrollTop),
					scrollHeight: Math.round(props.scrollOwner.scrollHeight),
					clientHeight: Math.round(props.scrollOwner.clientHeight),
					rootConstructorName: collapseButtonRoot.constructor.name,
					rootNodeType: collapseButtonRoot.nodeType,
					rootHasHost: 'host' in collapseButtonRoot,
					rootHostTagName:
						'host' in collapseButtonRoot && collapseButtonRoot.host instanceof HTMLElement
							? collapseButtonRoot.host.tagName
							: null,
					ancestorChain: bridgeViewerElementAncestorChain(props.collapseButton),
					scrollOwnerTop: Math.round(scrollOwnerBox.top),
					headerTop: headerBox === null ? null : Math.round(headerBox.top),
					headerBottom: headerBox === null ? null : Math.round(headerBox.bottom),
					headerHeight: headerBox === null ? null : Math.round(headerBox.height),
					collapseButtonTop: Math.round(collapseButtonBox.top),
					collapseButtonBottom: Math.round(collapseButtonBox.bottom),
					collapseButtonHeight: Math.round(collapseButtonBox.height),
					headerText: props.collapseButton.textContent?.slice(0, 120) ?? null,
					panelDataset:
						codeViewPanel instanceof HTMLElement
							? Object.fromEntries(Object.entries(codeViewPanel.dataset))
							: null,
				},
			)}`,
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeCodeHeaderOffsetFromScrollOwner({
		...props,
		remainingAttempts: remainingAttempts - 1,
	});
}

export async function waitForBridgeCodeHeaderItemOffsetFromScrollOwner(props: {
	readonly itemId: string;
	readonly maxOffset: number;
	readonly scrollOwner: HTMLElement;
	readonly remainingAttempts?: number;
}): Promise<number> {
	for (const collapseButton of bridgeCodeHeaderCollapseButtons()) {
		if (collapseButton.dataset['bridgeCodeViewItemId'] !== props.itemId) {
			continue;
		}
		const offset = bridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton,
			scrollOwner: props.scrollOwner,
		});
		if (offset >= -20 && offset <= props.maxOffset) {
			return offset;
		}
	}
	const remainingAttempts = props.remainingAttempts ?? 180;
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge CodeView header ${props.itemId} near scroll top`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeCodeHeaderItemOffsetFromScrollOwner({
		...props,
		remainingAttempts: remainingAttempts - 1,
	});
}

export async function waitForStableBridgeCodeHeaderOffsetFromScrollOwner(props: {
	readonly collapseButton: HTMLButtonElement;
	readonly maxOffset: number;
	readonly scrollOwner: HTMLElement;
}): Promise<number> {
	let stableOffset = await waitForBridgeCodeHeaderOffsetFromScrollOwner(props);
	for (let frameIndex = 0; frameIndex < 8; frameIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Sticky header proof must observe sequential animation frames.
		await waitForBridgeViewerAnimationFrame();
		// oxlint-disable-next-line no-await-in-loop -- Sticky header proof must re-check each observed frame.
		stableOffset = await waitForBridgeCodeHeaderOffsetFromScrollOwner(props);
	}
	return stableOffset;
}

export async function waitForStableBridgeCodeViewLayout(
	scrollOwner: HTMLElement,
	stableFrameCount = 6,
): Promise<void> {
	// Wait for the code-view layout to go quiet (item hydration stops changing total height)
	// before a test captures a baseline. Bounded and frame-based — never a wall-clock sleep.
	let previousScrollHeight = scrollOwner.scrollHeight;
	let stableFrames = 0;
	for (let frameIndex = 0; frameIndex < 180; frameIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Layout-quiet detection must observe sequential frames.
		await waitForBridgeViewerAnimationFrame();
		if (Math.abs(scrollOwner.scrollHeight - previousScrollHeight) <= 1) {
			stableFrames += 1;
			if (stableFrames >= stableFrameCount) {
				return;
			}
		} else {
			stableFrames = 0;
		}
		previousScrollHeight = scrollOwner.scrollHeight;
	}
}
