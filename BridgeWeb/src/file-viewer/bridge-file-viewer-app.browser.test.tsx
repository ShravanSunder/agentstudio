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
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { BridgeFileViewerApp } from './bridge-file-viewer-app.js';

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
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/target-content?generation=1',
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
				windowStartIndex: 0,
				windowRowCount: descriptors.length,
				rowHeightPixels: 24,
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

interface MakeFileDescriptorProps {
	readonly contentHandle?: string;
	readonly fileId?: string;
	readonly path: string;
}

function makeFileDescriptor(props: MakeFileDescriptorProps): WorktreeFileDescriptor {
	const contentHandle = props.contentHandle ?? 'file-content-1';
	return {
		path: props.path,
		fileId: props.fileId ?? 'file-1',
		contentHandle,
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: contentHandle,
			resourceKind: 'worktree.fileContent',
		}),
		sourceIdentity: makeSourceIdentity(),
		sizeBytes: 64,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 2,
		isBinary: false,
		language: 'typescript',
		fileExtension: 'ts',
	};
}

function makeSourceIdentity(): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'dev-worktree-source',
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
		sourceId: 'dev-worktree-source',
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

async function waitForOpenFileState(expectedState: string): Promise<void> {
	await waitForOpenFileStateAttempt({ attempt: 0, expectedState });
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
