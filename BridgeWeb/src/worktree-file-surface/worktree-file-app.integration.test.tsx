// @vitest-environment jsdom

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, test } from 'vitest';

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
import { WorktreeFileApp } from './worktree-file-app.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('WorktreeFileApp', () => {
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

	test('applies Worktree/File frames and opens selected content through descriptor-backed fetch', async () => {
		const descriptor = makeFileDescriptor();
		const fetchedResourceUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<WorktreeFileApp
					fetchResource={async ({ resourceUrl }) => {
						fetchedResourceUrls.push(resourceUrl);
						return 'export const value = 2;\n';
					}}
					initialFrames={makeFrames(descriptor)}
				/>,
			);
		});

		expect(document.querySelector('[data-testid="worktree-file-app"]')).not.toBeNull();
		expect(
			document
				.querySelector('[data-worktree-tree-total-size]')
				?.getAttribute('data-worktree-tree-total-size'),
		).toBe('480');

		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-worktree-file-path="src/app.ts"]')?.click();
		});

		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
		]);
		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('ready');
		expect(
			document
				.querySelector('[data-worktree-open-file-path]')
				?.getAttribute('data-worktree-open-file-path'),
		).toBe('src/app.ts');
		expect(document.body.textContent).toContain('export const value = 2;');
		expect(container.innerHTML).not.toContain('agentstudio://resource');
	});

	test('renders binary unavailable descriptors as metadata-only without fetching body bytes', async () => {
		const descriptor = makeFileDescriptor({
			isBinary: true,
			virtualizedExtentKind: 'unavailable',
		});
		let fetchCount = 0;
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<WorktreeFileApp
					fetchResource={async () => {
						fetchCount += 1;
						return 'must-not-fetch';
					}}
					initialFrames={makeFrames(descriptor)}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-worktree-file-path="src/app.ts"]')?.click();
		});

		expect(fetchCount).toBe(0);
		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('unavailable');
		expect(
			document
				.querySelector('[data-worktree-open-file-path]')
				?.getAttribute('data-worktree-open-file-path'),
		).toBe('src/app.ts');
		expect(document.body.textContent).toContain('src/app.ts');
		expect(document.body.textContent).not.toContain('must-not-fetch');
	});

	test('keeps latest selection when an older content request resolves later', async () => {
		const slowDescriptor = makeFileDescriptor({
			contentHandle: 'slow-content',
			fileId: 'file-slow',
			path: 'src/slow.ts',
		});
		const unavailableDescriptor = makeFileDescriptor({
			contentHandle: 'binary-content',
			fileId: 'file-binary',
			isBinary: true,
			path: 'assets/logo.png',
			virtualizedExtentKind: 'unavailable',
		});
		const slowContent = makeDeferred<string>();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<WorktreeFileApp
					fetchResource={async ({ resourceUrl }) => {
						if (resourceUrl.includes('slow-content')) {
							return await slowContent.promise;
						}
						throw new Error(`Unexpected resource fetch ${resourceUrl}`);
					}}
					initialFrames={makeFrames(slowDescriptor, unavailableDescriptor)}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-worktree-file-path="src/slow.ts"]')?.click();
			await nextMicrotask();
		});
		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('loading');

		await act(async (): Promise<void> => {
			document
				.querySelector<HTMLButtonElement>('[data-worktree-file-path="assets/logo.png"]')
				?.click();
			await nextMicrotask();
		});
		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('unavailable');
		expect(
			document
				.querySelector('[data-worktree-open-file-path]')
				?.getAttribute('data-worktree-open-file-path'),
		).toBe('assets/logo.png');

		await act(async (): Promise<void> => {
			slowContent.resolve('slow content must stay stale\n');
			await slowContent.promise;
			await nextMicrotask();
		});

		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('unavailable');
		expect(
			document
				.querySelector('[data-worktree-open-file-path]')
				?.getAttribute('data-worktree-open-file-path'),
		).toBe('assets/logo.png');
		expect(document.body.textContent).not.toContain('slow content must stay stale');
	});

	test('marks an open file stale while preserving tree, visible body, and explicit refresh', async () => {
		const descriptor = makeFileDescriptor({ lineCount: 1 });
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'file-content-2',
			fileId: descriptor.fileId,
			lineCount: 7,
			path: descriptor.path,
		});
		const fetchedResourceUrls: string[] = [];
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<WorktreeFileApp
					fetchResource={async ({ resourceUrl }) => {
						fetchedResourceUrls.push(resourceUrl);
						return resourceUrl.includes('file-content-2')
							? 'export const value = 3;\n'
							: 'export const value = 2;\n';
					}}
					initialFrames={makeFrames(descriptor)}
				/>,
			);
		});
		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-worktree-file-path="src/app.ts"]')?.click();
			await nextMicrotask();
		});
		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('ready');
		expect(
			document
				.querySelector('[data-worktree-open-file-total-size]')
				?.getAttribute('data-worktree-open-file-total-size'),
		).toBe('20');

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<WorktreeFileApp initialFrames={[makeInvalidationFrame(replacementDescriptor)]} />,
			);
			await nextMicrotask();
		});

		expect(document.querySelector('[data-worktree-file-path="src/app.ts"]')).not.toBeNull();
		expect(
			document
				.querySelector('[data-worktree-tree-total-size]')
				?.getAttribute('data-worktree-tree-total-size'),
		).toBe('480');
		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('stale');
		expect(
			document
				.querySelector('[data-worktree-open-file-total-size]')
				?.getAttribute('data-worktree-open-file-total-size'),
		).toBe('140');
		expect(document.body.textContent).toContain('Content changed');
		expect(document.body.textContent).toContain('export const value = 2');

		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-testid="worktree-file-refresh"]')?.click();
			await nextMicrotask();
		});

		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-2?generation=1',
		]);
		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('ready');
		expect(document.body.textContent).toContain('export const value = 3');
		expect(document.body.textContent).not.toContain('export const value = 2;');
	});

	test('keeps an invalidated in-flight open stale after the old content resolves', async () => {
		const descriptor = makeFileDescriptor({ lineCount: 1 });
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'file-content-2',
			fileId: descriptor.fileId,
			lineCount: 7,
			path: descriptor.path,
		});
		const slowContent = makeDeferred<string>();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<WorktreeFileApp
					fetchResource={async () => await slowContent.promise}
					initialFrames={makeFrames(descriptor)}
				/>,
			);
		});
		await act(async (): Promise<void> => {
			document.querySelector<HTMLButtonElement>('[data-worktree-file-path="src/app.ts"]')?.click();
			await nextMicrotask();
		});
		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('loading');

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<WorktreeFileApp initialFrames={[makeInvalidationFrame(replacementDescriptor)]} />,
			);
			await nextMicrotask();
		});
		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('stale');
		expect(
			document
				.querySelector('[data-worktree-open-file-total-size]')
				?.getAttribute('data-worktree-open-file-total-size'),
		).toBe('140');

		await act(async (): Promise<void> => {
			slowContent.resolve('old content must not render\n');
			await slowContent.promise;
			await nextMicrotask();
		});

		expect(
			document
				.querySelector('[data-worktree-open-file-state]')
				?.getAttribute('data-worktree-open-file-state'),
		).toBe('stale');
		expect(document.body.textContent).not.toContain('old content must not render');
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
				pathCount: 20,
				windowStartIndex: 0,
				windowRowCount: 1,
				rowHeightPixels: 24,
			},
		},
		...descriptors.map(
			(descriptor): WorktreeFileProtocolFrame => ({
				kind: 'delta',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: 1,
				frameKind: 'worktree.fileDescriptor',
				descriptor,
			}),
		),
	];
}

interface MakeFileDescriptorProps {
	readonly contentHandle?: string;
	readonly fileId?: string;
	readonly isBinary?: boolean;
	readonly lineCount?: number;
	readonly path?: string;
	readonly virtualizedExtentKind?: WorktreeFileDescriptor['virtualizedExtentKind'];
}

function makeFileDescriptor(props: MakeFileDescriptorProps = {}): WorktreeFileDescriptor {
	const virtualizedExtentKind = props.virtualizedExtentKind ?? 'exactLineCount';
	const contentHandle = props.contentHandle ?? 'file-content-1';
	return {
		path: props.path ?? 'src/app.ts',
		fileId: props.fileId ?? 'file-1',
		contentHandle,
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: contentHandle,
			resourceKind: 'worktree.fileContent',
		}),
		sourceIdentity: makeSourceIdentity(),
		sizeBytes: 24,
		virtualizedExtentKind,
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: props.lineCount ?? 1 } : {}),
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
	readonly resourceKind: 'worktree.fileContent' | 'worktree.treeWindow';
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

async function nextMicrotask(): Promise<void> {
	await Promise.resolve();
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
