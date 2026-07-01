import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	findBridgeViewerTreeScrollOwner,
	waitForBridgeViewerAnimationFrame,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type { PublishWorktreeFileFrames } from './bridge-file-viewer-browser-test-fixtures.js';

export function requireFramePublisher(
	publisher: PublishWorktreeFileFrames | null,
): PublishWorktreeFileFrames {
	if (publisher === null) {
		throw new Error('Frame subscription was not initialized.');
	}
	return publisher;
}

export function requireDeactivateFiles(deactivateFiles: (() => void) | null): () => void {
	if (deactivateFiles === null) {
		throw new Error('Controlled FileViewer did not publish its deactivate callback.');
	}
	return deactivateFiles;
}

export function requireActivateFiles(activateFiles: (() => void) | null): () => void {
	if (activateFiles === null) {
		throw new Error('Controlled FileViewer did not publish its activate callback.');
	}
	return activateFiles;
}

export function requireOpenSlowFile(openSlowFile: (() => void) | null): () => void {
	if (openSlowFile === null) {
		throw new Error('Controlled FileViewer did not publish its open callback.');
	}
	return openSlowFile;
}

export async function waitForOpenFileState(expectedState: string): Promise<void> {
	await waitForOpenFileStateAttempt({ attempt: 0, expectedState });
}

export async function waitForFileViewerActiveState(expectedState: string): Promise<void> {
	await waitForFileViewerActiveStateAttempt({ attempt: 0, expectedState });
}

export async function waitForRefreshButtonEnabled(): Promise<void> {
	await waitForRefreshButtonEnabledAttempt({ attempt: 0 });
}

export async function waitForDemandDispatchState(expectedState: string): Promise<void> {
	await waitForDemandDispatchStateAttempt({ attempt: 0, expectedState });
}

export async function waitForDemandDispatchLoadedCount(expectedLoadedCount: string): Promise<void> {
	await waitForDemandDispatchLoadedCountAttempt({ attempt: 0, expectedLoadedCount });
}

export async function waitForDemandDispatchFirstLane(expectedFirstLane: string): Promise<void> {
	await waitForDemandDispatchFirstLaneAttempt({ attempt: 0, expectedFirstLane });
}

export async function waitForRecordedFetchCount(props: {
	readonly expectedCount: number;
	readonly recordedFetches: readonly string[];
}): Promise<void> {
	await waitForRecordedFetchCountAttempt({
		attempt: 0,
		expectedCount: props.expectedCount,
		recordedFetches: props.recordedFetches,
	});
}

export async function waitForDescriptorRequestCount(props: {
	readonly expectedCount: number;
	readonly recordedRequests: readonly WorktreeFileDescriptorRequest[];
}): Promise<void> {
	await waitForDescriptorRequestCountAttempt({
		attempt: 0,
		expectedCount: props.expectedCount,
		recordedRequests: props.recordedRequests,
	});
}

export async function waitForMetadataTreeRowCount(expectedCount: number): Promise<void> {
	await waitForMetadataTreeRowCountAttempt({ attempt: 0, expectedCount });
}

export async function waitForSelectedDisplayPath(expectedPath: string): Promise<void> {
	await waitForSelectedDisplayPathAttempt({ attempt: 0, expectedPath });
}

export async function waitForInitialSurfaceState(expectedState: string): Promise<void> {
	await waitForInitialSurfaceStateAttempt({ attempt: 0, expectedState });
}

export async function waitForInitialSurfaceLoadCount(props: {
	readonly expectedCount: number;
	readonly getLoadCount: () => number;
}): Promise<void> {
	await waitForInitialSurfaceLoadCountAttempt({
		attempt: 0,
		expectedCount: props.expectedCount,
		getLoadCount: props.getLoadCount,
	});
}

export function makeTestTelemetryRecorder(
	samples: BridgeTelemetrySample[],
): BridgeTelemetryRecorder {
	return {
		isEnabled: (scope): boolean => scope === 'web',
		record: (sample): void => {
			samples.push(sample);
		},
		measure: (props): ReturnType<typeof props.operation> => props.operation(),
		flush: (): boolean => true,
	};
}

export async function waitForTelemetrySample(props: {
	readonly name: string;
	readonly samples: readonly BridgeTelemetrySample[];
}): Promise<BridgeTelemetrySample> {
	return waitForTelemetrySampleCount({
		count: 1,
		name: props.name,
		samples: props.samples,
	});
}

export async function waitForTelemetrySampleCount(props: {
	readonly count: number;
	readonly name: string;
	readonly samples: readonly BridgeTelemetrySample[];
	readonly attempt?: number;
}): Promise<BridgeTelemetrySample> {
	const matchingSamples = props.samples.filter((sample): boolean => sample.name === props.name);
	if (matchingSamples.length >= props.count) {
		const sample = matchingSamples.at(props.count - 1);
		if (sample === undefined) {
			throw new Error(`Expected telemetry sample at index ${props.count - 1}.`);
		}
		return sample;
	}
	const attempt = props.attempt ?? 0;
	if (attempt >= 60) {
		throw new Error(
			`Expected ${props.count} telemetry samples named ${props.name}; actual=${matchingSamples.length}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	return waitForTelemetrySampleCount({
		...props,
		attempt: attempt + 1,
	});
}

export async function waitForFileCodeViewViewport(): Promise<HTMLElement> {
	return waitForFileCodeViewViewportAttempt({ attempt: 0 });
}

export async function waitForFileCodeViewScrollOwner(): Promise<HTMLElement> {
	return waitForFileCodeViewScrollOwnerAttempt({ attempt: 0 });
}

export async function waitForFileCodeViewScrollable(scrollOwner: HTMLElement): Promise<void> {
	await waitForFileCodeViewScrollableAttempt({ attempt: 0, scrollOwner });
}

export async function waitForOpenFileStateAttempt(props: {
	readonly attempt: number;
	readonly expectedState: string;
}): Promise<void> {
	if (openFileState() === props.expectedState) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected open file state ${props.expectedState}; actual=${openFileState() ?? 'missing'}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForOpenFileStateAttempt({
		attempt: props.attempt + 1,
		expectedState: props.expectedState,
	});
}

export async function waitForRefreshButtonEnabledAttempt(props: {
	readonly attempt: number;
}): Promise<void> {
	if (!refreshButtonIsDisabled()) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error('Expected Worktree/File refresh button to become enabled.');
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForRefreshButtonEnabledAttempt({ attempt: props.attempt + 1 });
}

export async function waitForFileCodeViewViewportAttempt(props: {
	readonly attempt: number;
}): Promise<HTMLElement> {
	const viewport = document.querySelector('[data-testid="bridge-file-viewer-code-view"]');
	if (viewport instanceof HTMLElement) {
		return viewport;
	}
	if (props.attempt >= 60) {
		throw new Error('Expected File CodeView viewport to be mounted.');
	}
	await waitForBridgeViewerAnimationFrame();
	return waitForFileCodeViewViewportAttempt({ attempt: props.attempt + 1 });
}

export async function waitForFileCodeViewScrollOwnerAttempt(props: {
	readonly attempt: number;
}): Promise<HTMLElement> {
	const scrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
	if (scrollOwner instanceof HTMLElement) {
		return scrollOwner;
	}
	if (props.attempt >= 60) {
		throw new Error('Expected File CodeView scroll owner to be mounted.');
	}
	await waitForBridgeViewerAnimationFrame();
	return waitForFileCodeViewScrollOwnerAttempt({ attempt: props.attempt + 1 });
}

export async function waitForFileCodeViewScrollableAttempt(props: {
	readonly attempt: number;
	readonly scrollOwner: HTMLElement;
}): Promise<void> {
	if (props.scrollOwner.scrollHeight > props.scrollOwner.clientHeight + 32) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected File CodeView to be scrollable; scrollHeight=${props.scrollOwner.scrollHeight}; clientHeight=${props.scrollOwner.clientHeight}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForFileCodeViewScrollableAttempt({
		attempt: props.attempt + 1,
		scrollOwner: props.scrollOwner,
	});
}

export function openFileState(): string | null {
	return (
		document
			.querySelector('[data-worktree-open-file-state]')
			?.getAttribute('data-worktree-open-file-state') ?? null
	);
}

export function refreshButtonIsDisabled(): boolean {
	const refreshButton = document.querySelector('[data-testid="worktree-file-refresh"]');
	if (!(refreshButton instanceof HTMLButtonElement)) {
		throw new Error('Expected Worktree/File refresh button to be mounted.');
	}
	return refreshButton.disabled;
}

export function openFilePath(): string | null {
	return (
		document
			.querySelector('[data-worktree-open-file-path]')
			?.getAttribute('data-worktree-open-file-path') ?? null
	);
}

export function selectedDisplayPath(): string | null {
	return (
		document
			.querySelector('[data-testid="bridge-file-viewer-shell"]')
			?.getAttribute('data-selected-display-path') ?? null
	);
}

export function visibleCodeText(): string {
	const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
	if (!(canvas instanceof HTMLElement)) {
		return '';
	}
	const renderedText = Array.from(canvas.querySelectorAll('diffs-container'))
		.flatMap((container) =>
			Array.from(container.shadowRoot?.querySelectorAll('[data-content]') ?? []),
		)
		.map((contentBlock) => contentBlock.textContent ?? '')
		.join('\n');
	return renderedText.length > 0 ? renderedText : (canvas.textContent ?? '');
}

export function openFileBodyPreview(): string | null {
	return (
		document
			.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')
			?.getAttribute('data-worktree-open-file-body-preview') ?? null
	);
}

export function renderedFilePath(): string | null {
	return (
		document
			.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')
			?.getAttribute('data-worktree-rendered-file-path') ?? null
	);
}

export async function waitForOpenFileBodyPreview(expectedText: string): Promise<void> {
	await waitForOpenFileBodyPreviewAttempt({ attempt: 0, expectedText });
}

export async function waitForOpenFileBodyPreviewAttempt(props: {
	readonly attempt: number;
	readonly expectedText: string;
}): Promise<void> {
	const actualPreview = openFileBodyPreview();
	if (actualPreview?.includes(props.expectedText) === true) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected open file body preview ${props.expectedText}; actual=${actualPreview ?? 'missing'}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForOpenFileBodyPreviewAttempt({
		attempt: props.attempt + 1,
		expectedText: props.expectedText,
	});
}

export function fileCanvasRenderedTextOffset(text: string): number | null {
	const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
	if (!(canvas instanceof HTMLElement)) {
		return null;
	}
	return renderedTextOffsetWithinRoot({
		canvas,
		root: canvas,
		text,
		visitedRoots: new Set<ParentNode>(),
	});
}

export function renderedTextOffsetWithinRoot(props: {
	readonly canvas: HTMLElement;
	readonly root: ParentNode;
	readonly text: string;
	readonly visitedRoots: Set<ParentNode>;
}): number | null {
	if (props.visitedRoots.has(props.root)) {
		return null;
	}
	props.visitedRoots.add(props.root);
	const walker = document.createTreeWalker(props.root, NodeFilter.SHOW_TEXT);
	let currentNode = walker.nextNode();
	while (currentNode !== null) {
		if (currentNode.textContent?.includes(props.text)) {
			const parentElement = currentNode.parentElement;
			if (parentElement instanceof HTMLElement) {
				return parentElement.getBoundingClientRect().top - props.canvas.getBoundingClientRect().top;
			}
		}
		currentNode = walker.nextNode();
	}
	for (const candidate of props.root.querySelectorAll<HTMLElement>('[data-line-index]')) {
		if (candidate.textContent?.includes(props.text)) {
			return candidate.getBoundingClientRect().top - props.canvas.getBoundingClientRect().top;
		}
	}
	const shadowRootOffsets = Array.from(props.root.querySelectorAll('*')).flatMap(
		(element): readonly number[] => {
			const shadowRoot = element.shadowRoot;
			if (shadowRoot === null) {
				return [];
			}
			const offset = renderedTextOffsetWithinRoot({
				canvas: props.canvas,
				root: shadowRoot,
				text: props.text,
				visitedRoots: props.visitedRoots,
			});
			return offset === null ? [] : [offset];
		},
	);
	return shadowRootOffsets.length === 0 ? null : Math.min(...shadowRootOffsets);
}

export async function waitForVisibleCodeText(expectedText: string): Promise<void> {
	await waitForVisibleCodeTextAttempt({ attempt: 0, expectedText });
}

export function makeGeneratedFileBody(label: string, lineCount: number): string {
	return Array.from(
		{ length: lineCount },
		(_value, index): string =>
			`export const ${label}Line${String(index + 1).padStart(3, '0')} = true;`,
	).join('\n');
}

export async function waitForVisibleCodeTextAttempt(props: {
	readonly attempt: number;
	readonly expectedText: string;
}): Promise<void> {
	const actualText = visibleCodeText();
	if (actualText.includes(props.expectedText)) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected visible code text ${props.expectedText}; actual=${actualText.slice(0, 300)}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForVisibleCodeTextAttempt({
		attempt: props.attempt + 1,
		expectedText: props.expectedText,
	});
}

export async function waitForDemandDispatchStateAttempt(props: {
	readonly attempt: number;
	readonly expectedState: string;
}): Promise<void> {
	const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
	const actualState = shell?.getAttribute('data-last-demand-dispatch-status') ?? null;
	if (actualState === props.expectedState) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected demand dispatch state ${props.expectedState}; actual=${actualState ?? 'missing'}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForDemandDispatchStateAttempt({
		attempt: props.attempt + 1,
		expectedState: props.expectedState,
	});
}

export async function waitForFileViewerActiveStateAttempt(props: {
	readonly attempt: number;
	readonly expectedState: string;
}): Promise<void> {
	const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
	const actualState = shell?.getAttribute('data-file-viewer-active') ?? null;
	if (actualState === props.expectedState) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected FileViewer active state ${props.expectedState}; actual=${actualState ?? 'missing'}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForFileViewerActiveStateAttempt({
		attempt: props.attempt + 1,
		expectedState: props.expectedState,
	});
}

export async function waitForDemandDispatchLoadedCountAttempt(props: {
	readonly attempt: number;
	readonly expectedLoadedCount: string;
}): Promise<void> {
	const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
	const actualLoadedCount = shell?.getAttribute('data-last-demand-dispatch-loaded-count') ?? null;
	if (actualLoadedCount === props.expectedLoadedCount) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected demand dispatch loaded count ${props.expectedLoadedCount}; actual=${actualLoadedCount ?? 'missing'}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForDemandDispatchLoadedCountAttempt({
		attempt: props.attempt + 1,
		expectedLoadedCount: props.expectedLoadedCount,
	});
}

export async function waitForDemandDispatchFirstLaneAttempt(props: {
	readonly attempt: number;
	readonly expectedFirstLane: string;
}): Promise<void> {
	const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
	const actualFirstLane = shell?.getAttribute('data-last-demand-dispatch-first-lane') ?? null;
	if (actualFirstLane === props.expectedFirstLane) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected demand dispatch first lane ${props.expectedFirstLane}; actual=${actualFirstLane ?? 'missing'}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForDemandDispatchFirstLaneAttempt({
		attempt: props.attempt + 1,
		expectedFirstLane: props.expectedFirstLane,
	});
}

export async function waitForDemandDispatchFirstFreshnessKeyContaining(
	expectedContentHandle: string,
): Promise<void> {
	await waitForDemandDispatchFirstFreshnessKeyContainingAttempt({
		attempt: 0,
		expectedContentHandle,
	});
}

export async function waitForDemandDispatchFirstFreshnessKeyContainingAttempt(props: {
	readonly attempt: number;
	readonly expectedContentHandle: string;
}): Promise<void> {
	const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
	const actualFirstFreshnessKey =
		shell?.getAttribute('data-last-demand-dispatch-first-freshness-key') ?? null;
	if (actualFirstFreshnessKey?.includes(props.expectedContentHandle) === true) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected demand dispatch first freshness key to include ${
				props.expectedContentHandle
			}; actual=${actualFirstFreshnessKey ?? 'missing'}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForDemandDispatchFirstFreshnessKeyContainingAttempt({
		attempt: props.attempt + 1,
		expectedContentHandle: props.expectedContentHandle,
	});
}

export async function waitForRecordedFetchCountAttempt(props: {
	readonly attempt: number;
	readonly expectedCount: number;
	readonly recordedFetches: readonly string[];
}): Promise<void> {
	if (props.recordedFetches.length === props.expectedCount) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected ${props.expectedCount} fetches; actual=${props.recordedFetches.length}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForRecordedFetchCountAttempt({
		attempt: props.attempt + 1,
		expectedCount: props.expectedCount,
		recordedFetches: props.recordedFetches,
	});
}

export async function waitForDescriptorRequestCountAttempt(props: {
	readonly attempt: number;
	readonly expectedCount: number;
	readonly recordedRequests: readonly WorktreeFileDescriptorRequest[];
}): Promise<void> {
	if (props.recordedRequests.length === props.expectedCount) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected ${props.expectedCount} descriptor requests; actual=${props.recordedRequests.length}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForDescriptorRequestCountAttempt({
		attempt: props.attempt + 1,
		expectedCount: props.expectedCount,
		recordedRequests: props.recordedRequests,
	});
}

export async function waitForMetadataTreeRowCountAttempt(props: {
	readonly attempt: number;
	readonly expectedCount: number;
}): Promise<void> {
	const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
	const actualCount = Number(shell?.getAttribute('data-worktree-metadata-tree-row-count') ?? '0');
	if (actualCount === props.expectedCount) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected metadata tree row count ${props.expectedCount}; actual=${actualCount}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForMetadataTreeRowCountAttempt({
		attempt: props.attempt + 1,
		expectedCount: props.expectedCount,
	});
}

export async function waitForSelectedDisplayPathAttempt(props: {
	readonly attempt: number;
	readonly expectedPath: string;
}): Promise<void> {
	const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
	const actualPath = shell?.getAttribute('data-selected-display-path') ?? null;
	if (actualPath === props.expectedPath) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected selected display path ${props.expectedPath}; actual=${actualPath ?? 'missing'}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForSelectedDisplayPathAttempt({
		attempt: props.attempt + 1,
		expectedPath: props.expectedPath,
	});
}

export async function waitForInitialSurfaceStateAttempt(props: {
	readonly attempt: number;
	readonly expectedState: string;
}): Promise<void> {
	const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
	const actualState = shell?.getAttribute('data-worktree-initial-surface-state') ?? null;
	if (actualState === props.expectedState) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected initial surface state ${props.expectedState}; actual=${actualState ?? 'missing'}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForInitialSurfaceStateAttempt({
		attempt: props.attempt + 1,
		expectedState: props.expectedState,
	});
}

export async function waitForTreeScrollHeightAtLeast(
	minimumScrollHeight: number,
	attempt = 0,
): Promise<void> {
	const scrollOwner = findBridgeViewerTreeScrollOwner();
	const actualScrollHeight = scrollOwner?.scrollHeight ?? 0;
	if (actualScrollHeight >= minimumScrollHeight) {
		return;
	}
	if (attempt >= 60) {
		throw new Error(
			`Expected tree scrollHeight >= ${minimumScrollHeight}; actual=${actualScrollHeight}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForTreeScrollHeightAtLeast(minimumScrollHeight, attempt + 1);
}

export async function waitForInitialSurfaceLoadCountAttempt(props: {
	readonly attempt: number;
	readonly expectedCount: number;
	readonly getLoadCount: () => number;
}): Promise<void> {
	const currentLoadCount = props.getLoadCount();
	if (currentLoadCount === props.expectedCount) {
		return;
	}
	if (props.attempt >= 60) {
		throw new Error(
			`Expected ${props.expectedCount} initial surface loads; actual=${currentLoadCount}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForInitialSurfaceLoadCountAttempt({
		attempt: props.attempt + 1,
		expectedCount: props.expectedCount,
		getLoadCount: props.getLoadCount,
	});
}

export function makeDeferredContent(): {
	readonly promise: Promise<ReturnType<typeof makeWorktreeFileSurfaceRuntimeFetchedResource>>;
	readonly resolve: (
		value: ReturnType<typeof makeWorktreeFileSurfaceRuntimeFetchedResource>,
	) => void;
} {
	let resolveContent:
		| ((value: ReturnType<typeof makeWorktreeFileSurfaceRuntimeFetchedResource>) => void)
		| null = null;
	const promise = new Promise<ReturnType<typeof makeWorktreeFileSurfaceRuntimeFetchedResource>>(
		(resolve): void => {
			resolveContent = resolve;
		},
	);
	return {
		promise,
		resolve: (value): void => {
			if (resolveContent === null) {
				throw new Error('Deferred content resolver was not initialized.');
			}
			resolveContent(value);
		},
	};
}

export function makeDeferredInitialSurface(): {
	readonly promise: Promise<WorktreeFileInitialSurface>;
	readonly resolve: (value: WorktreeFileInitialSurface) => void;
} {
	let resolveInitialSurface: ((value: WorktreeFileInitialSurface) => void) | null = null;
	const promise = new Promise<WorktreeFileInitialSurface>((resolve): void => {
		resolveInitialSurface = resolve;
	});
	return {
		promise,
		resolve: (value): void => {
			if (resolveInitialSurface === null) {
				throw new Error('Deferred initial surface resolver was not initialized.');
			}
			resolveInitialSurface(value);
		},
	};
}
