import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { WorktreeFileApp } from './worktree-file-app.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from './worktree-file-surface-runtime.js';

describe('WorktreeFileApp Browser Mode', () => {
	test('auto-opens the initial fetchable file when requested', async () => {
		const descriptor = makeFileDescriptor();
		const fetchedResourceUrls: string[] = [];

		await renderWorktreeFileApp(
			<WorktreeFileApp
				autoOpenInitialFile
				fetchResource={async ({ resourceUrl }) => {
					fetchedResourceUrls.push(resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const value = 2;\nexport const other = 3;\n',
					);
				}}
				initialFrames={makeFrames(descriptor)}
			/>,
		);

		await waitForWorktreeFileState('ready');
		await waitForWorktreeFileAnimationFrame();

		const contentPanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-content"]'),
		);
		expect(contentPanel.getAttribute('data-worktree-open-file-path')).toBe('src/app.ts');
		expect(contentPanel.getAttribute('data-worktree-open-file-total-size')).toBe('40');
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
		]);
		expect(document.body.textContent).toContain('export const value = 2;');
	});

	test('reserves tree and file extents before descriptor-backed content hydrates', async () => {
		const descriptor = makeFileDescriptor();
		const deferredContent =
			makeDeferred<ReturnType<typeof makeWorktreeFileSurfaceRuntimeFetchedResource>>();
		const fetchedResourceUrls: string[] = [];

		await renderWorktreeFileApp(
			<WorktreeFileApp
				fetchResource={async ({ resourceUrl }) => {
					fetchedResourceUrls.push(resourceUrl);
					return await deferredContent.promise;
				}}
				initialFrames={makeFrames(descriptor)}
			/>,
		);

		await waitForWorktreeFileAnimationFrame();
		const treePanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-tree"]'),
		);
		expect(treePanel.getAttribute('data-worktree-tree-total-size')).toBe('480');
		expect(Math.abs(treePanel.scrollHeight - 480)).toBeLessThanOrEqual(1);

		await clickWorktreeFileRow();

		await waitForWorktreeFileState('loading');
		const contentPanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-content"]'),
		);
		const contentExtent = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-content-extent"]'),
		);
		const contentExtentHeightBefore = contentExtent.getBoundingClientRect().height;
		expect(contentPanel.getAttribute('data-worktree-open-file-total-size')).toBe('40');
		expect(Math.abs(contentExtentHeightBefore - 40)).toBeLessThanOrEqual(1);
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
		]);

		await act(async (): Promise<void> => {
			deferredContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource(
					'export const value = 2;\nexport const other = 3;\n',
				),
			);
			await Promise.resolve();
		});
		await waitForWorktreeFileState('ready');
		await waitForWorktreeFileAnimationFrame();

		const contentExtentHeightAfter = contentExtent.getBoundingClientRect().height;
		expect(Math.abs(contentExtentHeightAfter - contentExtentHeightBefore)).toBeLessThanOrEqual(1);
		expect(document.body.textContent).toContain('export const value = 2;');
		expect(document.body.innerHTML).not.toContain('agentstudio://resource');
	});

	test('renders binary unavailable descriptors without fetching content in the browser', async () => {
		const descriptor = makeFileDescriptor({
			isBinary: true,
			virtualizedExtentKind: 'unavailable',
		});
		let fetchCount = 0;

		await renderWorktreeFileApp(
			<WorktreeFileApp
				fetchResource={async () => {
					fetchCount += 1;
					return makeWorktreeFileSurfaceRuntimeFetchedResource('must-not-fetch');
				}}
				initialFrames={makeFrames(descriptor)}
			/>,
		);

		await waitForWorktreeFileAnimationFrame();
		await clickWorktreeFileRow();

		await waitForWorktreeFileState('unavailable');

		const contentPanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-content"]'),
		);
		expect(fetchCount).toBe(0);
		expect(contentPanel.getAttribute('data-worktree-open-file-path')).toBe('src/app.ts');
		expect(contentPanel.getAttribute('data-worktree-open-file-total-size')).toBeNull();
		expect(document.body.textContent).toContain('Content unavailable');
		expect(document.body.textContent).not.toContain('must-not-fetch');
	});

	test('keeps stale content visible after invalidation without starting FE auto refresh', async () => {
		const descriptor = makeFileDescriptor({ lineCount: 1 });
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'file-content-2',
			lineCount: 2,
		});
		const fetchedResourceUrls: string[] = [];
		const { rerender } = await renderWorktreeFileApp(
			<WorktreeFileApp
				fetchResource={async ({ resourceUrl }) => {
					fetchedResourceUrls.push(resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						resourceUrl.includes('file-content-2')
							? 'export const value = 3;\nexport const other = 4;\n'
							: 'export const value = 2;\n',
					);
				}}
				initialFrames={makeFrames(descriptor)}
			/>,
		);

		await waitForWorktreeFileAnimationFrame();
		await clickWorktreeFileRow();
		await waitForWorktreeFileState('ready');
		expect(document.body.textContent).toContain('export const value = 2;');

		await act(async (): Promise<void> => {
			rerender(<WorktreeFileApp initialFrames={[makeInvalidationFrame(replacementDescriptor)]} />);
			await Promise.resolve();
		});
		await waitForWorktreeFileState('stale');
		await waitForWorktreeFileAnimationFrame();

		const contentPanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-content"]'),
		);
		expect(document.querySelector('[data-worktree-file-path="src/app.ts"]')).not.toBeNull();
		expect(contentPanel.getAttribute('data-worktree-open-file-total-size')).toBe('40');
		expect(document.body.textContent).toContain('Content changed');
		const refreshButton = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-refresh"]'),
		);

		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
		]);
		expect(document.body.textContent).not.toContain('export const value = 3;');
		expect(document.body.textContent).toContain('export const value = 2;');
		expect(document.body.innerHTML).not.toContain('agentstudio://resource');

		await act(async (): Promise<void> => {
			refreshButton.click();
			await Promise.resolve();
		});
		await waitForWorktreeFileState('ready');

		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-2?generation=1',
		]);
		expect(document.body.textContent).toContain('export const value = 3;');
		expect(document.body.textContent).not.toContain('Content changed');
	});

	test('a failed initial surface load surfaces a visible error instead of an unhandled rejection', async () => {
		await renderWorktreeFileApp(
			<WorktreeFileApp
				loadInitialSurface={() => Promise.reject(new Error('native open failed'))}
			/>,
		);

		await waitForWorktreeSourceState('failed');

		const provenance = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-provenance"]'),
		);
		expect(provenance.textContent).toBe('Source load failed');
	});
});

async function waitForWorktreeSourceState(
	sourceState: 'live' | 'failed',
	remainingAttempts = 120,
): Promise<void> {
	const appRoot = document.querySelector('[data-testid="worktree-file-app"]');
	if (appRoot?.getAttribute('data-worktree-source-state') === sourceState) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`Expected Worktree/File source state ${sourceState}`);
	}
	await waitForWorktreeFileAnimationFrame();
	await waitForWorktreeSourceState(sourceState, remainingAttempts - 1);
}

function makeFrames(descriptor: WorktreeFileDescriptor): readonly WorktreeFileProtocolFrame[] {
	return [
		{
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: makeSourceIdentity(),
			metadataLineage: {
				loadedBy: 'startup_window',
				lane: 'foreground',
			},
			treeRows: [
				{
					rowId: 'row-1',
					path: descriptor.path,
					name: 'View.swift',
					parentPath: 'Sources/App',
					depth: 2,
					isDirectory: false,
					fileId: descriptor.fileId,
				},
			],
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 20,
				windowStartIndex: 0,
				windowRowCount: 1,
				rowHeightPixels: 24,
			},
		},
		{
			kind: 'delta',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 1,
			frameKind: 'worktree.fileDescriptor',
			descriptor,
		},
	];
}

interface MakeFileDescriptorProps {
	readonly contentHandle?: string;
	readonly isBinary?: boolean;
	readonly lineCount?: number;
	readonly virtualizedExtentKind?: WorktreeFileDescriptor['virtualizedExtentKind'];
}

function makeFileDescriptor(props: MakeFileDescriptorProps = {}): WorktreeFileDescriptor {
	const virtualizedExtentKind = props.virtualizedExtentKind ?? 'exactLineCount';
	const contentHandle = props.contentHandle ?? 'file-content-1';
	return {
		path: 'src/app.ts',
		fileId: 'file-1',
		contentHandle,
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: contentHandle,
			resourceKind: 'worktree.fileContent',
		}),
		sourceIdentity: makeSourceIdentity(),
		sizeBytes: 64,
		virtualizedExtentKind,
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: props.lineCount ?? 2 } : {}),
		isBinary: props.isBinary ?? false,
		language: 'typescript',
		fileExtension: 'ts',
	};
}

function makeInvalidationFrame(descriptor: WorktreeFileDescriptor): WorktreeFileProtocolFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 2,
		sequence: 2,
		frameKind: 'worktree.fileInvalidated',
		invalidation: {
			path: descriptor.path,
			fileId: descriptor.fileId,
			reason: 'contentChanged',
			latestDescriptor: descriptor,
		},
	};
}

function makeSourceIdentity(): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-1',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		subscriptionGeneration: 1,
		sourceCursor: 'cursor-1',
	};
}

function makeAttachedDescriptor(props: {
	readonly descriptorId: string;
	readonly resourceKind: 'worktree.fileContent';
}): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'source-1',
		generation: 1,
		streamId: 'worktree-file:pane-1',
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'worktree-file',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/worktree-file/${props.resourceKind}/${props.descriptorId}?generation=1`,
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

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
}

function makeDeferred<TValue>(): Deferred<TValue> {
	let resolve: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((promiseResolve) => {
		resolve = promiseResolve;
	});
	if (resolve === null) {
		throw new Error('Deferred promise did not initialize');
	}
	return { promise, resolve };
}

async function waitForWorktreeFileState(
	status: 'loading' | 'ready' | 'stale' | 'unavailable',
	remainingAttempts = 120,
): Promise<void> {
	const contentPanel = document.querySelector('[data-testid="worktree-file-content"]');
	if (contentPanel?.getAttribute('data-worktree-open-file-state') === status) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`Expected Worktree/File open file state ${status}`);
	}
	await waitForWorktreeFileAnimationFrame();
	await waitForWorktreeFileState(status, remainingAttempts - 1);
}

async function renderWorktreeFileApp(element: ReactElement): Promise<ReturnType<typeof render>> {
	let renderResult: ReturnType<typeof render> | null = null;
	await act(async (): Promise<void> => {
		renderResult = render(element);
		await Promise.resolve();
	});
	if (renderResult === null) {
		throw new Error('Expected WorktreeFileApp render result.');
	}
	return renderResult;
}

async function clickWorktreeFileRow(): Promise<void> {
	const row = requireBridgeViewerHTMLElement(
		document.querySelector('[data-worktree-file-path="src/app.ts"]'),
	);
	await act(async (): Promise<void> => {
		row.click();
		await Promise.resolve();
	});
}

async function waitForWorktreeFileAnimationFrame(): Promise<void> {
	await act(async (): Promise<void> => {
		await waitForBridgeViewerAnimationFrame();
	});
}
