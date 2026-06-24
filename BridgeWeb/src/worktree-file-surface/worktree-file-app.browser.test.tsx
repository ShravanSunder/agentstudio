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

describe('WorktreeFileApp Browser Mode', () => {
	test('reserves tree and file extents before descriptor-backed content hydrates', async () => {
		const descriptor = makeFileDescriptor();
		const deferredContent = makeDeferred<string>();
		const fetchedResourceUrls: string[] = [];

		render(
			<WorktreeFileApp
				fetchResource={async ({ resourceUrl }) => {
					fetchedResourceUrls.push(resourceUrl);
					return await deferredContent.promise;
				}}
				initialFrames={makeFrames(descriptor)}
			/>,
		);

		await waitForBridgeViewerAnimationFrame();
		const treePanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-tree"]'),
		);
		expect(treePanel.getAttribute('data-worktree-tree-total-size')).toBe('480');
		expect(Math.abs(treePanel.scrollHeight - 480)).toBeLessThanOrEqual(1);

		requireBridgeViewerHTMLElement(
			document.querySelector('[data-worktree-file-path="src/app.ts"]'),
		).click();

		await waitForWorktreeFileState('loading');
		const contentPanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-content"]'),
		);
		const contentScrollHeightBefore = contentPanel.scrollHeight;
		expect(contentPanel.getAttribute('data-worktree-open-file-total-size')).toBe('80');
		expect(contentScrollHeightBefore).toBeGreaterThanOrEqual(80);
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/file-content-1?generation=1',
		]);

		deferredContent.resolve('export const value = 2;\nexport const other = 3;\n');
		await waitForWorktreeFileState('ready');
		await waitForBridgeViewerAnimationFrame();

		const contentScrollHeightAfter = contentPanel.scrollHeight;
		expect(Math.abs(contentScrollHeightAfter - contentScrollHeightBefore)).toBeLessThanOrEqual(20);
		expect(document.body.textContent).toContain('export const value = 2;');
		expect(document.body.innerHTML).not.toContain('agentstudio://resource');
	});

	test('renders binary unavailable descriptors without fetching content in the browser', async () => {
		const descriptor = makeFileDescriptor({
			isBinary: true,
			virtualizedExtentKind: 'unavailable',
		});
		let fetchCount = 0;

		render(
			<WorktreeFileApp
				fetchResource={async () => {
					fetchCount += 1;
					return 'must-not-fetch';
				}}
				initialFrames={makeFrames(descriptor)}
			/>,
		);

		await waitForBridgeViewerAnimationFrame();
		requireBridgeViewerHTMLElement(
			document.querySelector('[data-worktree-file-path="src/app.ts"]'),
		).click();

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

interface MakeFileDescriptorProps {
	readonly isBinary?: boolean;
	readonly virtualizedExtentKind?: WorktreeFileDescriptor['virtualizedExtentKind'];
}

function makeFileDescriptor(props: MakeFileDescriptorProps = {}): WorktreeFileDescriptor {
	const virtualizedExtentKind = props.virtualizedExtentKind ?? 'exactLineCount';
	return {
		path: 'src/app.ts',
		fileId: 'file-1',
		contentHandle: 'file-content-1',
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: 'file-content-1',
			resourceKind: 'worktree.fileContent',
		}),
		sourceIdentity: makeSourceIdentity(),
		sizeBytes: 64,
		virtualizedExtentKind,
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: 4 } : {}),
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
	status: 'loading' | 'ready' | 'unavailable',
	remainingAttempts = 120,
): Promise<void> {
	const contentPanel = document.querySelector('[data-testid="worktree-file-content"]');
	if (contentPanel?.getAttribute('data-worktree-open-file-state') === status) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`Expected Worktree/File open file state ${status}`);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForWorktreeFileState(status, remainingAttempts - 1);
}
