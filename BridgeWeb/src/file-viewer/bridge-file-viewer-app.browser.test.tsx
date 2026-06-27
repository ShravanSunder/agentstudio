import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceKind,
	BridgeResourceDescriptor,
} from '../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	worktreeFileDescriptorSchema,
	worktreeFileProtocolFrameSchema,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { BridgeFileViewerApp } from './bridge-file-viewer-app.js';

type PublishWorktreeFileFrames = (frames: readonly WorktreeFileProtocolFrame[]) => void;

describe('BridgeFileViewerApp Browser Mode', () => {
	test('uses the shared compact rail chrome before opening tree search', async () => {
		render(
			<BridgeFileViewerApp
				initialFrames={makeFrames(
					makeFileDescriptor({ path: 'src/app.ts' }),
					makeFileDescriptor({
						contentHandle: 'docs-content',
						fileId: 'file-docs',
						path: 'docs/readme.md',
					}),
				)}
			/>,
		);

		await waitForBridgeViewerAnimationFrame();

		const toolbar = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-rail-toolbar"]'),
		);
		expect(toolbar.getAttribute('data-bridge-shared-rail-toolbar')).toBe('true');
		expect(
			document.querySelector('[data-testid="bridge-file-viewer-rail-toolbar-leading"]'),
		).not.toBeNull();
		expect(
			document.querySelector('[data-testid="bridge-file-viewer-rail-toolbar-trailing"]'),
		).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-review-search-control"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-review-search-toggle"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-review-regex-toggle"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="worktree-file-filter-menu"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="worktree-file-search-input"]')).toBeNull();
		const searchToggle = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-search-toggle"]'),
		);
		const regexToggle = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-regex-toggle"]'),
		);
		expect(Math.round(searchToggle.getBoundingClientRect().height)).toBe(24);
		expect(Math.round(regexToggle.getBoundingClientRect().height)).toBe(24);
		expect(getComputedStyle(searchToggle).fontSize).toBe('11px');
		expect(getComputedStyle(regexToggle).fontSize).toBe('11px');
		const filterCount = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-filter-count"]'),
		);
		const sourceProvenance = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-provenance"]'),
		);
		expect(filterCount.getBoundingClientRect().width).toBeLessThanOrEqual(1);
		expect(filterCount.getBoundingClientRect().height).toBeLessThanOrEqual(1);
		expect(sourceProvenance.getBoundingClientRect().width).toBeLessThanOrEqual(1);
		expect(sourceProvenance.getBoundingClientRect().height).toBeLessThanOrEqual(1);

		searchToggle.click();
		await waitForBridgeViewerAnimationFrame();

		const searchInput = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-search-input"]'),
		);
		expect(Math.round(searchInput.getBoundingClientRect().height)).toBe(24);
		expect(getComputedStyle(searchInput).fontSize).toBe('11px');
		expect(searchInput.className).toContain('h-6');
		expect(searchInput.className).toContain('!text-[11px]');
		expect(searchInput.getBoundingClientRect().left).toBeGreaterThanOrEqual(
			toolbar.getBoundingClientRect().left,
		);
		expect(searchInput.getBoundingClientRect().right).toBeLessThanOrEqual(
			toolbar.getBoundingClientRect().right,
		);
	});

	test('opens a file navigation target in the browser without auto-opening the first descriptor', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'first-content',
			fileId: 'file-first',
			path: 'src/first.ts',
		});
		const targetDescriptor = makeFileDescriptor({
			contentHandle: 'target-content',
			fileId: 'file-target',
			path: 'docs/target.ts',
		});
		const fetchedResourceUrls: string[] = [];

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile={true}
				fetchResource={async (props): Promise<string> => {
					fetchedResourceUrls.push(props.resourceUrl);
					return props.resourceUrl.includes('target-content')
						? 'export const target = true;\n'
						: 'export const first = true;\n';
				}}
				initialFrames={makeFrames(firstDescriptor, targetDescriptor)}
				navigationCommand={fileNavigationCommandForPath('docs/target.ts')}
			/>,
		);

		await waitForOpenFileState('ready');

		expect(openFilePath()).toBe('docs/target.ts');
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-open-load-disposition')).toBe('cold-loaded');
		expect(shell.getAttribute('data-last-open-load-lane')).toBe('foreground');
		expect(shell.getAttribute('data-last-open-load-estimated-bytes')).toBe('64');
		expect(shell.getAttribute('data-last-open-load-scheduler-queued-bytes-after')).toBe('0');
		expect(shell.getAttribute('data-last-open-load-scheduler-queued-bytes-before')).toBe('0');
		expect(shell.getAttribute('data-last-open-load-scheduler-queued-after')).toBe('0');
		expect(shell.getAttribute('data-last-open-load-executor-in-flight-bytes-after')).toBe('0');
		expect(shell.getAttribute('data-last-open-load-executor-in-flight-bytes-before')).toBe('0');
		expect(shell.getAttribute('data-last-open-load-executor-in-flight-after')).toBe('0');
		expect(shell.getAttribute('data-last-open-load-executor-queued-bytes-after')).toBe('0');
		expect(shell.getAttribute('data-last-open-load-executor-queued-bytes-before')).toBe('0');
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/target-content?generation=1',
		);
	});

	test('preloads visible file tree demand without opening a file session', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'first-visible-content',
			fileId: 'file-first-visible',
			path: 'src/first-visible.ts',
		});
		const secondDescriptor = makeFileDescriptor({
			contentHandle: 'second-visible-content',
			fileId: 'file-second-visible',
			path: 'src/second-visible.ts',
		});
		const fetchedResourceUrls: string[] = [];

		render(
			<BridgeFileViewerApp
				fetchResource={async (props): Promise<string> => {
					fetchedResourceUrls.push(props.resourceUrl);
					return props.resourceUrl.includes('second-visible-content')
						? 'export const secondVisible = true;\n'
						: 'export const firstVisible = true;\n';
				}}
				initialFrames={makeFrames(firstDescriptor, secondDescriptor)}
			/>,
		);

		await waitForDemandDispatchState('settled');

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-stimulus-count')).toBe('1');
		expect(shell.getAttribute('data-last-demand-dispatch-loaded-count')).toBe('2');
		expect(shell.getAttribute('data-last-demand-dispatch-failed-count')).toBe('0');
		expect(shell.getAttribute('data-last-demand-dispatch-first-disposition')).toBe(
			'visible-preloaded',
		);
		expect(shell.getAttribute('data-last-demand-dispatch-first-lane')).toBe('visible');
		expect(openFileState()).toBeNull();
		expect(openFilePath()).toBeNull();
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/first-visible-content?generation=1',
			'agentstudio://resource/worktree-file/worktree.fileContent/second-visible-content?generation=1',
		]);
	});

	test('preloads only fetchable visible file tree demand', async () => {
		const textDescriptor = makeFileDescriptor({
			contentHandle: 'text-visible-content',
			fileId: 'file-text-visible',
			path: 'src/text-visible.ts',
		});
		const binaryDescriptor = makeFileDescriptor({
			contentHandle: 'binary-visible-content',
			fileId: 'file-binary-visible',
			isBinary: true,
			path: 'assets/logo.png',
		});
		const unavailableDescriptor = makeFileDescriptor({
			contentHandle: 'unavailable-visible-content',
			fileId: 'file-unavailable-visible',
			path: 'generated/huge.log',
			virtualizedExtentKind: 'unavailable',
		});
		const fetchedResourceUrls: string[] = [];

		render(
			<BridgeFileViewerApp
				fetchResource={async (props): Promise<string> => {
					fetchedResourceUrls.push(props.resourceUrl);
					return 'export const textVisible = true;\n';
				}}
				initialFrames={makeFrames(textDescriptor, binaryDescriptor, unavailableDescriptor)}
			/>,
		);

		await waitForDemandDispatchState('settled');

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-loaded-count')).toBe('1');
		expect(shell.getAttribute('data-last-demand-dispatch-failed-count')).toBe('0');
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/text-visible-content?generation=1',
		]);
	});

	test('preloads recently updated files from a provider event without opening the file', async () => {
		const visibleDescriptor = makeFileDescriptor({
			contentHandle: 'visible-content',
			fileId: 'file-visible',
			path: 'src/visible.ts',
		});
		const updatedDescriptor = makeFileDescriptor({
			contentHandle: 'recently-updated-content',
			fileId: 'file-recently-updated',
			path: 'src/recently-updated.ts',
		});
		const fetchedResourceUrls: string[] = [];

		render(
			<BridgeFileViewerApp
				fetchResource={async (props): Promise<string> => {
					fetchedResourceUrls.push(props.resourceUrl);
					return props.resourceUrl.includes('recently-updated-content')
						? 'export const recentlyUpdated = true;\n'
						: 'export const visible = true;\n';
				}}
				initialFrames={makeFrames(visibleDescriptor, updatedDescriptor)}
			/>,
		);

		await waitForDemandDispatchState('settled');
		window.dispatchEvent(
			new CustomEvent('bridge-worktree-file-recently-updated', {
				detail: {
					path: 'src/recently-updated.ts',
					proximity: 'nearby',
					sourceIdentity: 'dev-worktree-source',
				},
			}),
		);
		await waitForDemandDispatchFirstLane('nearby');

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-stimulus-count')).toBe('1');
		expect(shell.getAttribute('data-last-demand-dispatch-intent-count')).toBe('1');
		expect(shell.getAttribute('data-last-demand-dispatch-loaded-count')).toBe('1');
		expect(shell.getAttribute('data-last-demand-dispatch-failed-count')).toBe('0');
		expect(shell.getAttribute('data-last-demand-dispatch-first-lane')).toBe('nearby');
		expect(shell.getAttribute('data-last-demand-dispatch-first-dedupe-key')).toContain(
			'recently-updated-content',
		);
		expect(shell.getAttribute('data-last-demand-dispatch-first-freshness-key')).toContain(
			'recently-updated-content',
		);
		expect(openFileState()).toBeNull();
		expect(openFilePath()).toBeNull();
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/recently-updated-content?generation=1',
		);
	});

	test('ignores stale visible demand batch results after a newer source reset dispatch settles', async () => {
		const oldDescriptor = makeFileDescriptor({
			contentHandle: 'old-delayed-content',
			fileId: 'file-old-delayed',
			path: 'src/old-delayed.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const newFirstDescriptor = makeFileDescriptor({
			contentHandle: 'new-first-content',
			fileId: 'file-new-first',
			generation: 2,
			path: 'src/new-first.ts',
			sourceIdentity: resetSourceIdentity,
		});
		const newSecondDescriptor = makeFileDescriptor({
			contentHandle: 'new-second-content',
			fileId: 'file-new-second',
			generation: 2,
			path: 'src/new-second.ts',
			sourceIdentity: resetSourceIdentity,
		});
		const oldDeferredContent = makeDeferredContent();
		const newDeferredContent = makeDeferredContent();
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				fetchResource={(props): Promise<string> => {
					fetchedResourceUrls.push(props.resourceUrl);
					return props.resourceUrl.includes('old-delayed-content')
						? oldDeferredContent.promise
						: newDeferredContent.promise;
				}}
				initialFrames={makeFrames(oldDescriptor)}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForRecordedFetchCount({
			expectedCount: 1,
			recordedFetches: fetchedResourceUrls,
		});
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		publishRequiredFrames(makeResetFrames(newFirstDescriptor, newSecondDescriptor));
		await waitForRecordedFetchCount({
			expectedCount: 3,
			recordedFetches: fetchedResourceUrls,
		});
		newDeferredContent.resolve('export const fresh = true;\n');
		await waitForDemandDispatchLoadedCount('2');
		oldDeferredContent.resolve('export const old = true;\n');
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-intent-count')).toBe('2');
		expect(shell.getAttribute('data-last-demand-dispatch-loaded-count')).toBe('2');
		expect(shell.getAttribute('data-last-demand-dispatch-failed-count')).toBe('0');
	});
});

function makeFrames(
	...descriptors: readonly WorktreeFileDescriptor[]
): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: makeSourceIdentity(),
			treeDescriptor: makeAttachedDescriptor({
				descriptorId: 'tree-window-1',
				resourceKind: 'worktree.treeWindow',
			}),
			treeSizeFacts: {
				pathCount: descriptors.length,
				windowStartIndex: 0,
				windowRowCount: descriptors.length,
				rowHeightPixels: 24,
			},
		}),
		...descriptors.map(
			(descriptor, descriptorIndex): WorktreeFileProtocolFrame =>
				parseWorktreeFileProtocolFrame({
					kind: 'delta',
					streamId: 'worktree-file:pane-1',
					generation: 1,
					sequence: descriptorIndex + 1,
					frameKind: 'worktree.fileDescriptor',
					descriptor,
				}),
		),
	];
}

function makeResetFrames(
	...replacementDescriptors: readonly WorktreeFileDescriptor[]
): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'reset',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 0,
			frameKind: 'worktree.reset',
			source: makeSourceIdentity({ subscriptionGeneration: 2, sourceCursor: 'cursor-2' }),
			reason: 'sourceChanged',
		}),
		...replacementDescriptors.map(
			(descriptor, descriptorIndex): WorktreeFileProtocolFrame =>
				parseWorktreeFileProtocolFrame({
					kind: 'delta',
					streamId: 'worktree-file:pane-1',
					generation: 2,
					sequence: descriptorIndex + 1,
					frameKind: 'worktree.fileDescriptor',
					descriptor,
				}),
		),
	];
}

interface MakeFileDescriptorProps {
	readonly contentHandle?: string;
	readonly fileId?: string;
	readonly generation?: number;
	readonly isBinary?: boolean;
	readonly path: string;
	readonly sourceIdentity?: WorktreeFileSurfaceSourceIdentity;
	readonly virtualizedExtentKind?: WorktreeFileDescriptor['virtualizedExtentKind'];
}

function makeFileDescriptor(props: MakeFileDescriptorProps): WorktreeFileDescriptor {
	const contentHandle = props.contentHandle ?? 'file-content-1';
	const generation = props.generation ?? 1;
	const sourceIdentity = props.sourceIdentity ?? makeSourceIdentity();
	const virtualizedExtentKind = props.virtualizedExtentKind ?? 'exactLineCount';
	return worktreeFileDescriptorSchema.parse({
		path: props.path,
		fileId: props.fileId ?? 'file-1',
		contentHandle,
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: contentHandle,
			generation,
			resourceKind: 'worktree.fileContent',
		}),
		sourceIdentity,
		sizeBytes: 64,
		virtualizedExtentKind,
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: 2 } : {}),
		isBinary: props.isBinary ?? false,
		language: 'typescript',
		fileExtension: 'ts',
	});
}

function makeSourceIdentity(
	props: {
		readonly sourceCursor?: string;
		readonly subscriptionGeneration?: number;
	} = {},
): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'dev-worktree-source',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		subscriptionGeneration: props.subscriptionGeneration ?? 1,
		sourceCursor: props.sourceCursor ?? 'cursor-1',
	};
}

function makeAttachedDescriptor(props: {
	readonly descriptorId: string;
	readonly generation?: number;
	readonly resourceKind: BridgeResourceKind;
}): BridgeAttachedResourceDescriptor {
	const generation = props.generation ?? 1;
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'dev-worktree-source',
		generation,
		streamId: 'worktree-file:pane-1',
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'worktree-file',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/worktree-file/${props.resourceKind}/${props.descriptorId}?generation=${generation}`,
		identity,
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: 64,
			maxBytes: 1024,
		},
	} satisfies BridgeResourceDescriptor;
	return bridgeAttachedResourceDescriptorSchema.parse({
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: descriptor.identity,
		},
		descriptor,
	});
}

function parseWorktreeFileProtocolFrame(frame: unknown): WorktreeFileProtocolFrame {
	return worktreeFileProtocolFrameSchema.parse(frame);
}

function fileNavigationCommandForPath(path: string): BridgeViewerNavigationCommand {
	return {
		commandId: `test:file:${path}`,
		commandKind: 'initialize',
		context: 'files',
		restoreMemory: true,
		source: {
			sourceKind: 'worktree',
			sourceId: 'source-1',
		},
		target: {
			targetKind: 'file',
			fileRef: {
				sourceId: 'source-1',
				path,
			},
			version: 'current',
		},
	};
}

function requireFramePublisher(
	publisher: PublishWorktreeFileFrames | null,
): PublishWorktreeFileFrames {
	if (publisher === null) {
		throw new Error('Frame subscription was not initialized.');
	}
	return publisher;
}

async function waitForOpenFileState(expectedState: string): Promise<void> {
	await waitForOpenFileStateAttempt({ attempt: 0, expectedState });
}

async function waitForDemandDispatchState(expectedState: string): Promise<void> {
	await waitForDemandDispatchStateAttempt({ attempt: 0, expectedState });
}

async function waitForDemandDispatchLoadedCount(expectedLoadedCount: string): Promise<void> {
	await waitForDemandDispatchLoadedCountAttempt({ attempt: 0, expectedLoadedCount });
}

async function waitForDemandDispatchFirstLane(expectedFirstLane: string): Promise<void> {
	await waitForDemandDispatchFirstLaneAttempt({ attempt: 0, expectedFirstLane });
}

async function waitForRecordedFetchCount(props: {
	readonly expectedCount: number;
	readonly recordedFetches: readonly string[];
}): Promise<void> {
	await waitForRecordedFetchCountAttempt({
		attempt: 0,
		expectedCount: props.expectedCount,
		recordedFetches: props.recordedFetches,
	});
}

async function waitForOpenFileStateAttempt(props: {
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

function openFileState(): string | null {
	return (
		document
			.querySelector('[data-worktree-open-file-state]')
			?.getAttribute('data-worktree-open-file-state') ?? null
	);
}

function openFilePath(): string | null {
	return (
		document
			.querySelector('[data-worktree-open-file-path]')
			?.getAttribute('data-worktree-open-file-path') ?? null
	);
}

async function waitForDemandDispatchStateAttempt(props: {
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

async function waitForDemandDispatchLoadedCountAttempt(props: {
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

async function waitForDemandDispatchFirstLaneAttempt(props: {
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

async function waitForRecordedFetchCountAttempt(props: {
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

function makeDeferredContent(): {
	readonly promise: Promise<string>;
	readonly resolve: (value: string) => void;
} {
	let resolveContent: ((value: string) => void) | null = null;
	const promise = new Promise<string>((resolve): void => {
		resolveContent = resolve;
	});
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
