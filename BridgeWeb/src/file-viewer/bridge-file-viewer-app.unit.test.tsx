// @vitest-environment jsdom

import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, test, vi } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
	BridgeResourceKind,
} from '../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { BridgeFileViewerApp } from './bridge-file-viewer-app.js';

vi.mock('@pierre/diffs/react', () => ({
	CodeView: (props: {
		readonly items: readonly { readonly file?: { readonly contents?: string } }[];
	}) => <pre>{props.items.map((item) => item.file?.contents ?? '').join('\n')}</pre>,
	WorkerPoolContextProvider: (props: { readonly children: ReactNode }) => <>{props.children}</>,
	useWorkerPool: () => undefined,
}));

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
Object.assign(globalThis, {
	ResizeObserver: class BridgeFileViewerTestResizeObserver {
		disconnect(): void {}
		observe(): void {}
		unobserve(): void {}
	},
});

describe('BridgeFileViewerApp', () => {
	let mountedRoot: Root | null = null;

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
	});

	test('keeps unavailable text descriptors metadata-only in auto-open and filters', async () => {
		const unavailableDescriptor = makeFileDescriptor({
			contentHandle: 'deleted-content',
			fileId: 'file-deleted',
			path: 'docs/deleted-plan.md',
			virtualizedExtentKind: 'unavailable',
		});
		const liveDescriptor = makeFileDescriptor({
			contentHandle: 'live-content',
			fileId: 'file-live',
			path: 'src/live.ts',
		});
		const fetches: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeFileViewerApp
					autoOpenInitialFile={true}
					fetchResource={async (props): Promise<string> => {
						fetches.push(props.resourceUrl);
						return 'export const live = true;\n';
					}}
					initialFrames={makeFrames(unavailableDescriptor, liveDescriptor)}
				/>,
			);
			await nextMicrotask();
		});

		expect(openFileState()).toBe('ready');
		expect(fetches).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/live-content?generation=1',
		]);
		expect(document.body.textContent).toContain('export const live = true');
		expect(filterCount()).toBe('2/2');

		await clickControl('worktree-file-filter-fetchable');
		expect(filterCount()).toBe('1/2');

		await clickControl('worktree-file-filter-unavailable');
		expect(filterCount()).toBe('1/2');

		await clickControl('worktree-file-filter-all');
		await setSearchText('live');
		expect(filterCount()).toBe('1/2');

		await clickControl('worktree-file-regex-toggle');
		await setSearchText('[');
		expect(filterCount()).toBe('Invalid regex');
		expect(fetches).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/live-content?generation=1',
		]);
	});

	test('keeps stale body visible and retryable when explicit refresh fails', async () => {
		const firstDescriptor = makeFileDescriptor({ contentHandle: 'file-content-1' });
		const latestDescriptor = makeFileDescriptor({
			contentHandle: 'file-content-2',
			fileId: firstDescriptor.fileId,
			path: firstDescriptor.path,
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);
		let latestContentFetchCount = 0;
		const fetchResource = async (props: { readonly resourceUrl: string }): Promise<string> => {
			if (props.resourceUrl.includes('file-content-2')) {
				latestContentFetchCount += 1;
				if (latestContentFetchCount === 1) {
					throw new Error('refresh failed');
				}
				return 'export const value = 2;\n';
			}
			return 'export const value = 1;\n';
		};

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeFileViewerApp
					autoOpenInitialFile={true}
					fetchResource={fetchResource}
					initialFrames={makeFrames(firstDescriptor)}
				/>,
			);
			await nextMicrotask();
		});

		expect(openFileState()).toBe('ready');
		expect(document.body.textContent).toContain('export const value = 1');

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeFileViewerApp
					autoOpenInitialFile={true}
					fetchResource={fetchResource}
					initialFrames={[makeInvalidationFrame(latestDescriptor)]}
				/>,
			);
			await nextMicrotask();
		});

		expect(openFileState()).toBe('stale');
		expect(document.body.textContent).toContain('Content changed');
		expect(document.body.textContent).toContain('export const value = 1');

		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-testid="worktree-file-refresh"]')?.click();
			await nextMicrotask();
		});

		expect(openFileState()).toBe('stale');
		expect(document.body.textContent).toContain('Content changed');
		expect(document.body.textContent).toContain('export const value = 1');
		expect(document.querySelector('[data-testid="worktree-file-refresh"]')).not.toBeNull();
		expect(latestContentFetchCount).toBe(1);

		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-testid="worktree-file-refresh"]')?.click();
			await nextMicrotask();
		});

		expect(openFileState()).toBe('ready');
		expect(document.body.textContent).not.toContain('Content changed');
		expect(document.body.textContent).toContain('export const value = 2');
		expect(latestContentFetchCount).toBe(2);
	});

	test('keeps reset-stale body visible across split replacement descriptor callbacks', async () => {
		const firstDescriptor = makeFileDescriptor({ contentHandle: 'file-content-1' });
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'file-content-2',
			fileId: firstDescriptor.fileId,
			path: firstDescriptor.path,
		});
		let frameSubscriber: ((frames: readonly WorktreeFileProtocolFrame[]) => void) | undefined;
		const fetchedResourceUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeFileViewerApp
					autoOpenInitialFile={true}
					fetchResource={async (props): Promise<string> => {
						fetchedResourceUrls.push(props.resourceUrl);
						return props.resourceUrl.includes('file-content-2')
							? 'export const value = 2;\n'
							: 'export const value = 1;\n';
					}}
					initialFrames={makeFrames(firstDescriptor)}
					subscribeFrames={(onFrames) => {
						frameSubscriber = onFrames;
						return () => {};
					}}
				/>,
			);
			await nextMicrotask();
		});

		expect(openFileState()).toBe('ready');
		expect(document.body.textContent).toContain('export const value = 1');

		await act(async (): Promise<void> => {
			frameSubscriber?.([makeResetFrame({ source: makeSourceIdentity() })]);
			await nextMicrotask();
		});

		expect(openFileState()).toBe('stale');
		expect(document.body.textContent).toContain('Content changed');
		expect(document.body.textContent).toContain('export const value = 1');
		expect(document.querySelector('[data-testid="worktree-file-refresh"]')).not.toBeNull();

		await act(async (): Promise<void> => {
			frameSubscriber?.([makeFileDescriptorFrame(replacementDescriptor)]);
			await nextMicrotask();
		});

		expect(openFileState()).toBe('stale');
		expect(document.body.textContent).toContain('export const value = 1');

		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-testid="worktree-file-refresh"]')?.click();
			await nextMicrotask();
		});

		expect(openFileState()).toBe('ready');
		expect(document.body.textContent).toContain('export const value = 2');
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-2?generation=1',
		]);
	});

	test('does not let unrelated split replacement descriptor unblock reset-stale content', async () => {
		const firstDescriptor = makeFileDescriptor({ contentHandle: 'file-content-1' });
		const unrelatedDescriptor = makeFileDescriptor({
			contentHandle: 'other-content-1',
			fileId: 'file-2',
			path: 'src/other.ts',
		});
		let frameSubscriber: ((frames: readonly WorktreeFileProtocolFrame[]) => void) | undefined;
		const fetchedResourceUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeFileViewerApp
					autoOpenInitialFile={true}
					fetchResource={async (props): Promise<string> => {
						fetchedResourceUrls.push(props.resourceUrl);
						return 'export const value = 1;\n';
					}}
					initialFrames={makeFrames(firstDescriptor)}
					subscribeFrames={(onFrames) => {
						frameSubscriber = onFrames;
						return () => {};
					}}
				/>,
			);
			await nextMicrotask();
		});

		await act(async (): Promise<void> => {
			frameSubscriber?.([makeResetFrame({ source: makeSourceIdentity() })]);
			await nextMicrotask();
		});
		await act(async (): Promise<void> => {
			frameSubscriber?.([makeFileDescriptorFrame(unrelatedDescriptor)]);
			await nextMicrotask();
		});

		expect(openFileState()).toBe('stale');
		expect(document.body.textContent).toContain('export const value = 1');

		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-testid="worktree-file-refresh"]')?.click();
			await nextMicrotask();
		});

		expect(openFileState()).toBe('stale');
		expect(document.body.textContent).toContain('export const value = 1');
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
		]);
	});
});

function makeFrames(
	...descriptors: readonly WorktreeFileDescriptor[]
): readonly WorktreeFileProtocolFrame[] {
	return [
		{
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
				estimatedTotalHeightPixels: Math.max(1, descriptors.length) * 24,
				rowHeightPixels: 24,
				windowRowCount: descriptors.length,
				windowStartIndex: 0,
			},
		},
		...descriptors.map(
			(descriptor, descriptorIndex): WorktreeFileProtocolFrame => ({
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

function makeFileDescriptorFrame(descriptor: WorktreeFileDescriptor): WorktreeFileProtocolFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 2,
		sequence: 3,
		frameKind: 'worktree.fileDescriptor',
		descriptor,
	};
}

function makeResetFrame(props: {
	readonly source?: WorktreeFileSurfaceSourceIdentity;
}): WorktreeFileProtocolFrame {
	return {
		kind: 'reset',
		streamId: 'worktree-file:pane-1',
		generation: 2,
		sequence: 2,
		frameKind: 'worktree.reset',
		reason: 'sourceChanged',
		...(props.source === undefined ? {} : { source: props.source }),
	};
}

function makeFileDescriptor(props: {
	readonly contentHandle: string;
	readonly fileId?: string;
	readonly path?: string;
	readonly isBinary?: boolean;
	readonly virtualizedExtentKind?: WorktreeFileDescriptor['virtualizedExtentKind'];
}): WorktreeFileDescriptor {
	const virtualizedExtentKind = props.virtualizedExtentKind ?? 'exactLineCount';
	return {
		path: props.path ?? 'src/app.ts',
		fileId: props.fileId ?? 'file-1',
		contentHandle: props.contentHandle,
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: props.contentHandle,
			resourceKind: 'worktree.fileContent',
		}),
		sourceIdentity: makeSourceIdentity(),
		sizeBytes: 24,
		virtualizedExtentKind,
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: 1 } : {}),
		isBinary: props.isBinary ?? false,
		language: 'typescript',
		fileExtension: 'ts',
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
	readonly resourceKind: BridgeResourceKind;
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

function openFileState(): string | null {
	return (
		document
			.querySelector('[data-worktree-open-file-state]')
			?.getAttribute('data-worktree-open-file-state') ?? null
	);
}

async function nextMicrotask(): Promise<void> {
	await Promise.resolve();
}

async function clickControl(testId: string): Promise<void> {
	await act(async (): Promise<void> => {
		document.querySelector<HTMLButtonElement>(`[data-testid="${testId}"]`)?.click();
		await nextMicrotask();
	});
}

async function setSearchText(value: string): Promise<void> {
	const input = document.querySelector<HTMLInputElement>(
		'[data-testid="worktree-file-search-input"]',
	);
	if (input === null) {
		throw new Error('Expected worktree file search input');
	}
	await act(async (): Promise<void> => {
		const valueDescriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
		if (valueDescriptor?.set === undefined) {
			throw new Error('Expected native input value setter');
		}
		// oxlint-disable-next-line typescript/unbound-method -- Test helper needs the native input setter with an explicit receiver.
		Reflect.apply(valueDescriptor.set, input, [value]);
		input.dispatchEvent(new Event('input', { bubbles: true }));
		input.dispatchEvent(new Event('change', { bubbles: true }));
		await nextMicrotask();
	});
}

function filterCount(): string | null {
	return document.querySelector('[data-testid="worktree-file-filter-count"]')?.textContent ?? null;
}
