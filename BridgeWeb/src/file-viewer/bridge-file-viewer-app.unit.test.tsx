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
});

function makeFrames(descriptor: WorktreeFileDescriptor): readonly WorktreeFileProtocolFrame[] {
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
				pathCount: 1,
				estimatedTotalHeightPixels: 24,
				rowHeightPixels: 24,
				windowRowCount: 1,
				windowStartIndex: 0,
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

function makeFileDescriptor(props: {
	readonly contentHandle: string;
	readonly fileId?: string;
	readonly path?: string;
}): WorktreeFileDescriptor {
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
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 1,
		isBinary: false,
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
