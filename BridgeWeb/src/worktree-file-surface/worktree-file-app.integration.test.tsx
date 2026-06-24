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

function makeFileDescriptor(): WorktreeFileDescriptor {
	return {
		path: 'src/app.ts',
		fileId: 'file-1',
		contentHandle: 'file-content-1',
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: 'file-content-1',
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
