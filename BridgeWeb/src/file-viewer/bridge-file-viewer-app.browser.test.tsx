import { useState, type ReactElement } from 'react';
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
	WorktreeFileDescriptorRequest,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	worktreeFileDescriptorSchema,
	worktreeFileProtocolFrameSchema,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	findBridgeViewerTreeScrollOwner,
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { BridgeFileViewerApp } from './bridge-file-viewer-app.js';

type PublishWorktreeFileFrames = (frames: readonly WorktreeFileProtocolFrame[]) => void;

describe('BridgeFileViewerApp Browser Mode', () => {
	test('waits for bridge readiness before opening the native Worktree/File source', async () => {
		const descriptor = makeFileDescriptor({ path: 'src/app.ts' });
		let loadInitialSurfaceCount = 0;
		const bridgeReadyCallbackState: { callback: (() => void) | null } = { callback: null };
		const registerBridgeReadyCallback = (callback: () => void): (() => void) => {
			bridgeReadyCallbackState.callback = callback;
			return (): void => {
				bridgeReadyCallbackState.callback = null;
			};
		};

		render(
			<BridgeFileViewerApp
				loadInitialSurface={async (): Promise<WorktreeFileInitialSurface> => {
					loadInitialSurfaceCount += 1;
					return {
						frames: makeFrames(descriptor),
						provenance: {
							baseRef: 'native-current-worktree',
							scenarioName: 'current-worktree',
							worktreeRootToken: 'root-token',
						},
						source: makeSourceIdentity(),
					};
				}}
				waitForBridgeReady={registerBridgeReadyCallback}
			/>,
		);

		await waitForBridgeViewerAnimationFrame();
		expect(loadInitialSurfaceCount).toBe(0);
		expect(document.querySelector('[data-worktree-file-path="src/app.ts"]')).toBeNull();
		if (bridgeReadyCallbackState.callback === null) {
			throw new Error('Expected BridgeFileViewerApp to register a bridge-ready callback');
		}

		bridgeReadyCallbackState.callback();
		await waitForInitialSurfaceLoadCount({
			expectedCount: 1,
			getLoadCount: () => loadInitialSurfaceCount,
		});

		expect(loadInitialSurfaceCount).toBe(1);
	});

	test('records initial surface load failure instead of silently blanking FileView', async () => {
		render(
			<BridgeFileViewerApp
				loadInitialSurface={async (): Promise<WorktreeFileInitialSurface> => {
					throw new Error('native worktree stream failed');
				}}
			/>,
		);

		await waitForInitialSurfaceState('failed');

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-worktree-initial-surface-error')).toBe(
			'native worktree stream failed',
		);
		expect(shell.getAttribute('data-worktree-metadata-tree-row-count')).toBe('0');
		expect(shell.getAttribute('data-worktree-source-state')).toBeNull();
	});

	test('continues native metadata loading while the mounted FileView mode is inactive', async () => {
		const descriptor = makeFileDescriptor({ path: 'src/app.ts' });
		const initialSurface = makeDeferredInitialSurface();
		let loadInitialSurfaceCount = 0;
		const loadInitialSurface = (): Promise<WorktreeFileInitialSurface> => {
			loadInitialSurfaceCount += 1;
			return initialSurface.promise;
		};
		const { rerender } = render(
			<BridgeFileViewerApp isActive={true} loadInitialSurface={loadInitialSurface} />,
		);

		await waitForInitialSurfaceLoadCount({
			expectedCount: 1,
			getLoadCount: () => loadInitialSurfaceCount,
		});

		rerender(<BridgeFileViewerApp isActive={false} loadInitialSurface={loadInitialSurface} />);
		initialSurface.resolve({
			frames: makeFrames(descriptor),
			provenance: {
				baseRef: 'native-current-worktree',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'root-token',
			},
			source: makeSourceIdentity(),
		});

		await waitForInitialSurfaceState('ready');
		const treeItemButton = await waitForBridgeViewerTreeItemButton('src/app.ts');

		rerender(<BridgeFileViewerApp isActive={true} loadInitialSurface={loadInitialSurface} />);
		await waitForBridgeViewerAnimationFrame();

		expect(loadInitialSurfaceCount).toBe(1);
		expect(treeItemButton.getAttribute('data-item-path')).toBe('src/app.ts');
	});

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

	test('renders streamed metadata tree rows before file descriptors arrive', async () => {
		const fetchedResourceUrls: string[] = [];

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource('should not be requested\n');
				}}
				initialFrames={makeTreeRowsOnlyFrames()}
			/>,
		);

		await waitForBridgeViewerTreeItemButton('Sources/AgentStudio/App/AppDelegate.swift');

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		const tree = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-status')).toBe('idle');
		expect(tree.getAttribute('data-worktree-tree-total-size-source')).toBe('providerFacts');
		expect(fetchedResourceUrls).toEqual([]);
	});

	test('keeps metadata-only file rows visible under the text-file filter', async () => {
		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={makeTreeRowsOnlyFrames()}
			/>,
		);

		await waitForBridgeViewerTreeItemButton('Sources/AgentStudio/App/AppDelegate.swift');
		requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-filter-menu"]'),
		).click();
		await waitForBridgeViewerAnimationFrame();
		const textFilterOption = [
			...document.querySelectorAll('[data-testid="bridge-review-filter-option"]'),
		]
			.filter((option): option is HTMLElement => option instanceof HTMLElement)
			.find((option): boolean => option.textContent?.includes('Text files') ?? false);
		if (textFilterOption === undefined) {
			throw new Error('Expected Worktree/File Text files filter option.');
		}
		textFilterOption.click();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		await waitForBridgeViewerTreeItemButton('Sources/AgentStudio/App/AppDelegate.swift');
		expect(
			requireBridgeViewerHTMLElement(
				document.querySelector('[data-testid="worktree-file-filter-count"]'),
			).textContent,
		).not.toBe('0/0');
	});

	test('restores the last open file when a metadata-only descriptor request fails', async () => {
		const initiallyOpenDescriptor = makeFileDescriptor({
			contentHandle: 'initial-content',
			fileId: 'file-000',
			path: 'File-000.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				fetchResource={async () =>
					makeWorktreeFileSurfaceRuntimeFetchedResource('export const initiallyOpen = true;\n')
				}
				initialFrames={makeFrames(initiallyOpenDescriptor)}
				requestFileDescriptor={async (request) => {
					descriptorRequests.push(request);
					throw new Error('descriptor request failed');
				}}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('initiallyOpen');

		requireFramePublisher(publishFrames)([
			makeTreeWindowFrame({ rowCount: 1, sequence: 2, startIndex: 1, totalPathCount: 2 }),
		]);
		const clickedButton = await waitForBridgeViewerTreeItemButton('File-001.swift');
		clickedButton.click();

		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});
		await waitForSelectedDisplayPath('File-000.swift');
		expect(openFilePath()).toBe('File-000.swift');
		expect(renderedFilePath()).toBe('File-000.swift');
		expect(openFileBodyPreview()).toContain('initiallyOpen');
	});

	test('applies subscribed tree window metadata after the startup snapshot', async () => {
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={[makeTreeWindowedSnapshotFrame({ rowCount: 200, totalPathCount: 260 })]}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForMetadataTreeRowCount(200);
		await waitForTreeScrollHeightAtLeast(200 * 24);
		requireFramePublisher(publishFrames)([
			makeTreeWindowFrame({ rowCount: 60, sequence: 1, startIndex: 200, totalPathCount: 260 }),
		]);

		await waitForMetadataTreeRowCount(260);
		await waitForTreeScrollHeightAtLeast(260 * 24);
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		const tree = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]'),
		);
		expect(shell.getAttribute('data-worktree-metadata-file-row-count')).toBe('260');
		expect(tree.getAttribute('data-worktree-tree-total-size-source')).toBe('providerFacts');
	});

	test('opens content for a file discovered through a subscribed tree window', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'initial-window-content',
			fileId: 'file-000',
			path: 'File-000.swift',
		});
		const continuedDescriptor = makeFileDescriptor({
			contentHandle: 'continued-window-content',
			fileId: 'file-250',
			path: 'File-250.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						props.resourceUrl.includes('continued-window-content')
							? 'export const continuedWindowSelection = true;\n'
							: 'export const initialWindowSelection = true;\n',
					);
				}}
				initialFrames={[
					makeTreeWindowedSnapshotFrame({ rowCount: 200, totalPathCount: 260 }),
					...makeFileDescriptorFrame(initialDescriptor, { sequence: 1 }),
				]}
				requestFileDescriptor={(request) => {
					descriptorRequests.push(request);
				}}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('initialWindowSelection');
		requireFramePublisher(publishFrames)([
			makeTreeWindowFrame({ rowCount: 60, sequence: 2, startIndex: 200, totalPathCount: 260 }),
		]);
		await waitForMetadataTreeRowCount(260);
		await waitForTreeScrollHeightAtLeast(260 * 24);
		const treeScrollOwner = findBridgeViewerTreeScrollOwner();
		if (treeScrollOwner === null) {
			throw new Error('Expected FileView tree scroll owner for continued window click.');
		}
		treeScrollOwner.scrollTo({ top: 250 * 24 });
		treeScrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		const continuedButton = await waitForBridgeViewerTreeItemButton('File-250.swift');
		expect(document.querySelector('[data-worktree-file-path="ignored-output/log.txt"]')).toBeNull();
		continuedButton.click();

		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});
		expect(selectedDisplayPath()).toBe('File-000.swift');
		expect(openFilePath()).toBe('File-000.swift');
		expect(openFileBodyPreview()).toContain('initialWindowSelection');

		requireFramePublisher(publishFrames)(
			makeFileDescriptorFrame(continuedDescriptor, { sequence: 3 }),
		);
		await waitForOpenFileState('ready');
		await waitForSelectedDisplayPath('File-250.swift');
		await waitForVisibleCodeText('continuedWindowSelection');

		expect(descriptorRequests).toEqual([
			{
				fileId: 'file-250',
				path: 'File-250.swift',
				rowId: 'row:File-250.swift',
				sourceIdentity: makeSourceIdentity(),
				lane: 'foreground',
			},
		]);
		expect(openFilePath()).toBe('File-250.swift');
		expect(renderedFilePath()).toBe('File-250.swift');
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/continued-window-content?generation=1',
		);
	});

	test('removes a tree row when native invalidates a deleted file without a replacement descriptor', async () => {
		const keptDescriptor = makeFileDescriptor({
			contentHandle: 'kept-content',
			fileId: 'file-kept',
			path: 'src/kept.ts',
		});
		const deletedDescriptor = makeFileDescriptor({
			contentHandle: 'deleted-content',
			fileId: 'file-deleted',
			path: 'src/deleted.ts',
		});
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={makeFrames(keptDescriptor, deletedDescriptor)}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForMetadataTreeRowCount(2);
		requireFramePublisher(publishFrames)(
			makeFileInvalidatedFrames({
				fileId: 'file-deleted',
				path: 'src/deleted.ts',
				sequence: 1,
			}),
		);

		await waitForMetadataTreeRowCount(1);
		await waitForBridgeViewerTreeItemButton('src/kept.ts');
		expect(document.querySelector('[data-worktree-file-path="src/deleted.ts"]')).toBeNull();
	});

	test('requests and opens a descriptor when clicking a metadata-only file row', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'app-delegate-content',
			fileId: 'file-app-delegate',
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const appDelegateFixture = true;\n',
					);
				}}
				initialFrames={makeTreeRowsOnlyFrames()}
				requestFileDescriptor={(request) => {
					descriptorRequests.push(request);
					const publishRequiredFrames = requireFramePublisher(publishFrames);
					publishRequiredFrames(makeFileDescriptorFrame(descriptor, { sequence: 1 }));
				}}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		const fileButton = await waitForBridgeViewerTreeItemButton(
			'Sources/AgentStudio/App/AppDelegate.swift',
		);
		fileButton.click();

		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('appDelegateFixture');

		expect(descriptorRequests).toEqual([
			{
				fileId: 'file-app-delegate',
				path: 'Sources/AgentStudio/App/AppDelegate.swift',
				rowId: 'row:Sources/AgentStudio/App/AppDelegate.swift',
				sourceIdentity: makeSourceIdentity(),
				lane: 'foreground',
			},
		]);
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/app-delegate-content?generation=1',
		]);
		expect(openFilePath()).toBe('Sources/AgentStudio/App/AppDelegate.swift');
	});

	test('does not advance selected display path until a metadata-only descriptor converges', async () => {
		const initiallyOpenDescriptor = makeFileDescriptor({
			contentHandle: 'initial-content',
			fileId: 'file-000',
			path: 'File-000.swift',
		});
		const clickedDescriptor = makeFileDescriptor({
			contentHandle: 'clicked-content',
			fileId: 'file-001',
			path: 'File-001.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						props.resourceUrl.includes('clicked-content')
							? 'export const clickedSelection = true;\n'
							: 'export const initiallyOpen = true;\n',
					);
				}}
				initialFrames={makeFrames(initiallyOpenDescriptor)}
				requestFileDescriptor={(request) => {
					descriptorRequests.push(request);
				}}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('initiallyOpen');

		const publishRequiredFrames = requireFramePublisher(publishFrames);
		publishRequiredFrames([
			makeTreeWindowFrame({ rowCount: 1, sequence: 2, startIndex: 1, totalPathCount: 3 }),
		]);
		const clickedButton = await waitForBridgeViewerTreeItemButton('File-001.swift');
		clickedButton.click();
		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});

		publishRequiredFrames([
			makeTreeWindowFrame({ rowCount: 1, sequence: 3, startIndex: 2, totalPathCount: 3 }),
		]);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		expect(selectedDisplayPath()).toBe('File-000.swift');
		expect(openFilePath()).toBe('File-000.swift');
		expect(renderedFilePath()).toBe('File-000.swift');
		expect(openFileBodyPreview()).toContain('initiallyOpen');
		expect(visibleCodeText()).toContain('export const initiallyOpen = true;');

		publishRequiredFrames(makeFileDescriptorFrame(clickedDescriptor, { sequence: 4 }));
		await waitForOpenFileState('ready');
		await waitForSelectedDisplayPath('File-001.swift');
		await waitForVisibleCodeText('clickedSelection');

		expect(descriptorRequests).toEqual([
			{
				fileId: 'file-001',
				path: 'File-001.swift',
				rowId: 'row:File-001.swift',
				sourceIdentity: makeSourceIdentity(),
				lane: 'foreground',
			},
		]);
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/clicked-content?generation=1',
		);
	});

	test('retries a metadata-only descriptor request when the clicked file has not converged', async () => {
		const initiallyOpenDescriptor = makeFileDescriptor({
			contentHandle: 'initial-content',
			fileId: 'file-000',
			path: 'File-000.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				fetchResource={async () =>
					makeWorktreeFileSurfaceRuntimeFetchedResource('export const initiallyOpen = true;\n')
				}
				initialFrames={makeFrames(initiallyOpenDescriptor)}
				requestFileDescriptor={(request) => {
					descriptorRequests.push(request);
				}}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('initiallyOpen');
		requireFramePublisher(publishFrames)([
			makeTreeWindowFrame({ rowCount: 1, sequence: 2, startIndex: 1, totalPathCount: 2 }),
		]);

		const clickedButton = await waitForBridgeViewerTreeItemButton('File-001.swift');
		clickedButton.click();
		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});
		await waitForSelectedDisplayPath('File-000.swift');
		clickedButton.click();
		await waitForDescriptorRequestCount({
			expectedCount: 2,
			recordedRequests: descriptorRequests,
		});

		expect(descriptorRequests).toEqual([
			{
				fileId: 'file-001',
				path: 'File-001.swift',
				rowId: 'row:File-001.swift',
				sourceIdentity: makeSourceIdentity(),
				lane: 'foreground',
			},
			{
				fileId: 'file-001',
				path: 'File-001.swift',
				rowId: 'row:File-001.swift',
				sourceIdentity: makeSourceIdentity(),
				lane: 'foreground',
			},
		]);
	});

	test('auto-opens the first metadata-only file row by requesting its descriptor', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'app-delegate-content',
			fileId: 'file-app-delegate',
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const autoOpenedMetadataRow = true;\n',
					);
				}}
				initialFrames={makeTreeRowsOnlyFrames()}
				requestFileDescriptor={(request) => {
					descriptorRequests.push(request);
					const publishRequiredFrames = requireFramePublisher(publishFrames);
					publishRequiredFrames(makeFileDescriptorFrame(descriptor, { sequence: 1 }));
				}}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('autoOpenedMetadataRow');

		expect(descriptorRequests).toEqual([
			{
				fileId: 'file-app-delegate',
				path: 'Sources/AgentStudio/App/AppDelegate.swift',
				rowId: 'row:Sources/AgentStudio/App/AppDelegate.swift',
				sourceIdentity: makeSourceIdentity(),
				lane: 'foreground',
			},
		]);
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/app-delegate-content?generation=1',
		]);
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
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource({
						text: props.resourceUrl.includes('target-content')
							? 'export const target = true;\n'
							: 'export const first = true;\n',
						timing: {
							firstChunkWaitMilliseconds: 5,
							responseWaitMilliseconds: 3,
							streamReadMilliseconds: 7,
						},
					});
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
		expect(
			Number(shell.getAttribute('data-last-open-load-resource-body-registry-commit-ms')),
		).toBeGreaterThanOrEqual(0);
		expect(shell.getAttribute('data-last-open-load-resource-fetch-response-wait-ms')).toBe('3');
		expect(shell.getAttribute('data-last-open-load-resource-first-chunk-wait-ms')).toBe('5');
		expect(shell.getAttribute('data-last-open-load-resource-stream-read-ms')).toBe('7');
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/target-content?generation=1',
		);
	});

	test('requests a metadata-only navigation target descriptor on the foreground lane', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'app-delegate-navigation-content',
			fileId: 'file-app-delegate',
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile={true}
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const navigationTargetFromMetadata = true;\n',
					);
				}}
				initialFrames={makeTreeRowsOnlyFrames()}
				navigationCommand={fileNavigationCommandForPath(
					'Sources/AgentStudio/App/AppDelegate.swift',
				)}
				requestFileDescriptor={(request) => {
					descriptorRequests.push(request);
					requireFramePublisher(publishFrames)(
						makeFileDescriptorFrame(descriptor, { sequence: 1 }),
					);
				}}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('navigationTargetFromMetadata');

		expect(descriptorRequests).toEqual([
			{
				fileId: 'file-app-delegate',
				path: 'Sources/AgentStudio/App/AppDelegate.swift',
				rowId: 'row:Sources/AgentStudio/App/AppDelegate.swift',
				sourceIdentity: makeSourceIdentity(),
				lane: 'foreground',
			},
		]);
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/app-delegate-navigation-content?generation=1',
		]);
		expect(openFilePath()).toBe('Sources/AgentStudio/App/AppDelegate.swift');
	});

	test('auto-opens the first descriptor when native metadata streams after the initial snapshot', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'streamed-content',
			fileId: 'file-streamed',
			path: 'src/streamed.ts',
		});
		const frames = makeFrames(descriptor);
		const snapshotFrame = frames[0];
		const descriptorFrame = frames[1];
		if (snapshotFrame === undefined || descriptorFrame === undefined) {
			throw new Error('Expected snapshot and descriptor frames.');
		}
		let publishFrames: PublishWorktreeFileFrames | null = null;
		const fetchedResourceUrls: string[] = [];

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile={true}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource('export const streamed = true;\n');
				}}
				initialFrames={[snapshotFrame]}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForBridgeViewerAnimationFrame();
		requireFramePublisher(publishFrames)([descriptorFrame]);

		await waitForOpenFileState('ready');

		expect(openFilePath()).toBe('src/streamed.ts');
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/streamed-content?generation=1',
		]);
	});

	test('renders file body without Pierre file header chrome inside the File canvas', async () => {
		const targetDescriptor = makeFileDescriptor({
			contentHandle: 'plain-content',
			fileId: 'file-plain',
			path: 'src/plain.ts',
		});

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fetchResource={async () =>
					makeWorktreeFileSurfaceRuntimeFetchedResource('export const plain = true;\n')
				}
				initialFrames={makeFrames(targetDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/plain.ts')}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const plain = true;');

		expect(fileCanvasRenderedTextOffset('export const plain')).not.toBeNull();
		expect(fileCanvasRenderedTextOffset('export const plain')).toBeLessThanOrEqual(4);
	});

	test('keeps the File CodeView viewport mounted while selected file content loads', async () => {
		const targetDescriptor = makeFileDescriptor({
			contentHandle: 'slow-content',
			fileId: 'file-slow',
			path: 'src/slow.ts',
		});
		const deferredContent = makeDeferredContent();
		let openSlowFile: (() => void) | null = null;

		function ControlledFileViewer(): ReactElement {
			const [navigationCommand, setNavigationCommand] = useState<
				BridgeViewerNavigationCommand | undefined
			>();
			openSlowFile = (): void => {
				setNavigationCommand(fileNavigationCommandForPath('src/slow.ts'));
			};
			return (
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					fetchResource={() => deferredContent.promise}
					initialFrames={makeFrames(targetDescriptor)}
					{...(navigationCommand === undefined ? {} : { navigationCommand })}
				/>
			);
		}

		render(<ControlledFileViewer />);

		const idleViewport = await waitForFileCodeViewViewport();
		const openRequiredSlowFile = requireOpenSlowFile(openSlowFile);
		openRequiredSlowFile();
		await waitForOpenFileState('loading');
		expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBe(
			idleViewport,
		);

		deferredContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const slow = true;\n'),
		);
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const slow = true;');

		expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBe(
			idleViewport,
		);
	});

	test('reserves selected file scroll extent from line-count metadata while content loads', async () => {
		const targetDescriptor = makeFileDescriptor({
			contentHandle: 'large-loading-content',
			fileId: 'file-large-loading',
			lineCount: 160,
			path: 'src/large-loading.ts',
		});
		const deferredContent = makeDeferredContent();

		render(
			<div style={{ display: 'grid', height: '360px', overflow: 'hidden', width: '960px' }}>
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					fetchResource={() => deferredContent.promise}
					initialFrames={makeFrames(targetDescriptor)}
					navigationCommand={fileNavigationCommandForPath('src/large-loading.ts')}
				/>
			</div>,
		);

		await waitForOpenFileState('loading');
		const scrollOwner = await waitForFileCodeViewScrollOwner();

		expect(scrollOwner.scrollHeight).toBeGreaterThan(scrollOwner.clientHeight + 32);

		deferredContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const largeLoading = true;\n'),
		);
	});

	test('keeps the viewport mounted without rendering the previous file while the next file loads', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'first-retained-content',
			fileId: 'file-first-retained',
			path: 'src/first-retained.ts',
		});
		const secondDescriptor = makeFileDescriptor({
			contentHandle: 'second-slow-content',
			fileId: 'file-second-slow',
			path: 'src/second-slow.ts',
		});
		const deferredSecondContent = makeDeferredContent();
		let openSecondFile: (() => void) | null = null;

		function ControlledFileViewer(): ReactElement {
			const [navigationCommand, setNavigationCommand] = useState<BridgeViewerNavigationCommand>(
				fileNavigationCommandForPath('src/first-retained.ts'),
			);
			openSecondFile = (): void => {
				setNavigationCommand(fileNavigationCommandForPath('src/second-slow.ts'));
			};
			return (
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					fetchResource={(props) =>
						props.resourceUrl.includes('second-slow-content')
							? deferredSecondContent.promise
							: Promise.resolve(
									makeWorktreeFileSurfaceRuntimeFetchedResource(
										'export const firstRetained = true;\n',
									),
								)
					}
					initialFrames={makeFrames(firstDescriptor, secondDescriptor)}
					navigationCommand={navigationCommand}
				/>
			);
		}

		render(
			<div style={{ height: '360px', width: '960px' }}>
				<ControlledFileViewer />
			</div>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const firstRetained = true;');
		const readyViewport = await waitForFileCodeViewViewport();
		const openRequiredSecondFile = requireOpenSlowFile(openSecondFile);
		openRequiredSecondFile();

		await waitForOpenFileState('loading');

		expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBe(
			readyViewport,
		);
		expect(visibleCodeText()).not.toContain('export const firstRetained = true;');
		expect(openFileBodyPreview()).toBeNull();

		deferredSecondContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const secondSlow = true;\n'),
		);
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const secondSlow = true;');

		expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBe(
			readyViewport,
		);
		expect(visibleCodeText()).not.toContain('export const firstRetained = true;');
	});

	test('reserves selected file scroll extent without rendering retained previous content', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'first-retained-scroll-content',
			fileId: 'file-first-retained-scroll',
			lineCount: 8,
			path: 'src/first-retained-scroll.ts',
		});
		const secondDescriptor = makeFileDescriptor({
			contentHandle: 'second-large-retained-target-content',
			fileId: 'file-second-large-retained-target',
			lineCount: 575,
			path: 'src/second-large-retained-target.ts',
		});
		const deferredSecondContent = makeDeferredContent();
		let openSecondFile: (() => void) | null = null;

		function ControlledFileViewer(): ReactElement {
			const [navigationCommand, setNavigationCommand] = useState<BridgeViewerNavigationCommand>(
				fileNavigationCommandForPath('src/first-retained-scroll.ts'),
			);
			openSecondFile = (): void => {
				setNavigationCommand(fileNavigationCommandForPath('src/second-large-retained-target.ts'));
			};
			return (
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					fetchResource={(props) =>
						props.resourceUrl.includes('second-large-retained-target-content')
							? deferredSecondContent.promise
							: Promise.resolve(
									makeWorktreeFileSurfaceRuntimeFetchedResource(
										makeGeneratedFileBody('firstRetainedScroll', 8),
									),
								)
					}
					initialFrames={makeFrames(firstDescriptor, secondDescriptor)}
					navigationCommand={navigationCommand}
				/>
			);
		}

		render(
			<div style={{ display: 'grid', height: '360px', overflow: 'hidden', width: '960px' }}>
				<ControlledFileViewer />
			</div>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const firstRetainedScrollLine001 = true;');
		const scrollOwner = await waitForFileCodeViewScrollOwner();
		const openRequiredSecondFile = requireOpenSlowFile(openSecondFile);
		openRequiredSecondFile();

		await waitForOpenFileState('loading');

		expect(visibleCodeText()).not.toContain('export const firstRetainedScrollLine001 = true;');
		expect(scrollOwner.scrollHeight).toBeGreaterThan(scrollOwner.clientHeight + 32);
		const loadingScrollHeight = scrollOwner.scrollHeight;
		scrollOwner.scrollTop = Math.min(scrollOwner.scrollHeight - scrollOwner.clientHeight, 480);
		scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));

		deferredSecondContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource(
				makeGeneratedFileBody('secondLargeRetainedTarget', 575),
			),
		);
		await waitForOpenFileState('ready');
		await waitForOpenFileBodyPreview('export const secondLargeRetainedTargetLine001 = true;');
		await waitForBridgeViewerAnimationFrame();

		expect(Math.abs(scrollOwner.scrollHeight - loadingScrollHeight)).toBeLessThanOrEqual(1);
	});

	test('does not render retained file body while the next selected file content loads', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'first-scrolled-content',
			fileId: 'file-first-scrolled',
			path: 'src/first-scrolled.ts',
		});
		const secondDescriptor = makeFileDescriptor({
			contentHandle: 'second-scroll-target-content',
			fileId: 'file-second-scroll-target',
			path: 'src/second-scroll-target.ts',
		});
		const deferredSecondContent = makeDeferredContent();
		let openSecondFile: (() => void) | null = null;

		function ControlledFileViewer(): ReactElement {
			const [navigationCommand, setNavigationCommand] = useState<BridgeViewerNavigationCommand>(
				fileNavigationCommandForPath('src/first-scrolled.ts'),
			);
			openSecondFile = (): void => {
				setNavigationCommand(fileNavigationCommandForPath('src/second-scroll-target.ts'));
			};
			return (
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					fetchResource={(props) =>
						props.resourceUrl.includes('second-scroll-target-content')
							? deferredSecondContent.promise
							: Promise.resolve(
									makeWorktreeFileSurfaceRuntimeFetchedResource(
										makeGeneratedFileBody('firstScrolled', 120),
									),
								)
					}
					initialFrames={makeFrames(firstDescriptor, secondDescriptor)}
					navigationCommand={navigationCommand}
				/>
			);
		}

		render(
			<div style={{ display: 'grid', height: '360px', overflow: 'hidden', width: '960px' }}>
				<ControlledFileViewer />
			</div>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const firstScrolledLine001 = true;');
		const scrollOwner = await waitForFileCodeViewScrollOwner();
		await waitForFileCodeViewScrollable(scrollOwner);
		scrollOwner.scrollTop = 320;
		scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForBridgeViewerAnimationFrame();
		expect(scrollOwner.scrollTop).toBeGreaterThan(0);

		const openRequiredSecondFile = requireOpenSlowFile(openSecondFile);
		openRequiredSecondFile();
		await waitForOpenFileState('loading');
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(openFileBodyPreview()).toBeNull();

		deferredSecondContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const secondScrollTarget = true;\n'),
		);
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const secondScrollTarget = true;');
		await waitForBridgeViewerAnimationFrame();

		expect(scrollOwner.scrollTop).toBeLessThanOrEqual(1);
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
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						props.resourceUrl.includes('second-visible-content')
							? 'export const secondVisible = true;\n'
							: 'export const firstVisible = true;\n',
					);
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
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const textVisible = true;\n',
					);
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

	test('ignores visible demand results that settle after Files becomes inactive', async () => {
		const visibleDescriptor = makeFileDescriptor({
			contentHandle: 'inactive-visible-content',
			fileId: 'file-inactive-visible',
			path: 'src/inactive-visible.ts',
		});
		const deferredContent = makeDeferredContent();
		const fetchedResourceUrls: string[] = [];
		let deactivateFiles: (() => void) | null = null;

		function ControlledFileViewer(): ReactElement {
			const [isActive, setIsActive] = useState(true);
			deactivateFiles = (): void => {
				setIsActive(false);
			};
			return (
				<BridgeFileViewerApp
					fetchResource={(props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return deferredContent.promise;
					}}
					initialFrames={makeFrames(visibleDescriptor)}
					isActive={isActive}
				/>
			);
		}

		render(<ControlledFileViewer />);

		await waitForRecordedFetchCount({
			expectedCount: 1,
			recordedFetches: fetchedResourceUrls,
		});
		const deactivate = requireDeactivateFiles(deactivateFiles);
		deactivate();
		await waitForBridgeViewerAnimationFrame();
		deferredContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const inactiveVisible = true;\n'),
		);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-file-viewer-active')).toBe('false');
		expect(shell.getAttribute('data-last-demand-dispatch-status')).toBe('idle');
		expect(shell.getAttribute('data-last-demand-dispatch-first-lane')).toBeNull();
	});

	test('preserves the streamed surface when Files becomes active again', async () => {
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;
		let loadInitialSurfaceCount = 0;

		function ControlledFileViewer(): ReactElement {
			const [isActive, setIsActive] = useState(true);
			activateFiles = (): void => {
				setIsActive(true);
			};
			deactivateFiles = (): void => {
				setIsActive(false);
			};
			return (
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					isActive={isActive}
					loadInitialSurface={async (): Promise<WorktreeFileInitialSurface> => {
						loadInitialSurfaceCount += 1;
						return {
							frames: makeFrames(
								makeFileDescriptor({
									contentHandle: `content-${loadInitialSurfaceCount}`,
									fileId: `file-${loadInitialSurfaceCount}`,
									path: `src/file-${loadInitialSurfaceCount}.ts`,
								}),
							),
							provenance: {
								baseRef: 'native-current-worktree',
								scenarioName: 'current-worktree',
								worktreeRootToken: 'root-token',
							},
							source: makeSourceIdentity({ subscriptionGeneration: loadInitialSurfaceCount }),
						};
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);

		await waitForInitialSurfaceLoadCount({
			expectedCount: 1,
			getLoadCount: () => loadInitialSurfaceCount,
		});
		requireDeactivateFiles(deactivateFiles)();
		await waitForFileViewerActiveState('false');
		requireActivateFiles(activateFiles)();
		await waitForFileViewerActiveState('true');
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(loadInitialSurfaceCount).toBe(1);
		await waitForBridgeViewerTreeItemButton('src/file-1.ts');
	});

	test('opens clicked file content after Files reactivates with the preserved streamed surface', async () => {
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;
		let loadInitialSurfaceCount = 0;
		const fetchedResourceUrls: string[] = [];

		function ControlledFileViewer(): ReactElement {
			const [isActive, setIsActive] = useState(true);
			activateFiles = (): void => {
				setIsActive(true);
			};
			deactivateFiles = (): void => {
				setIsActive(false);
			};
			return (
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					fetchResource={async (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return makeWorktreeFileSurfaceRuntimeFetchedResource(
							props.resourceUrl.includes('content-1')
								? 'export const reactivatedPreservedFile = true;\n'
								: 'export const initialFile = true;\n',
						);
					}}
					isActive={isActive}
					loadInitialSurface={async (): Promise<WorktreeFileInitialSurface> => {
						loadInitialSurfaceCount += 1;
						return {
							frames: makeFrames(
								makeFileDescriptor({
									contentHandle: `content-${loadInitialSurfaceCount}`,
									fileId: `file-${loadInitialSurfaceCount}`,
									path: `src/file-${loadInitialSurfaceCount}.ts`,
								}),
							),
							provenance: {
								baseRef: 'native-current-worktree',
								scenarioName: 'current-worktree',
								worktreeRootToken: 'root-token',
							},
							source: makeSourceIdentity({ subscriptionGeneration: loadInitialSurfaceCount }),
						};
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);

		await waitForInitialSurfaceLoadCount({
			expectedCount: 1,
			getLoadCount: () => loadInitialSurfaceCount,
		});
		requireDeactivateFiles(deactivateFiles)();
		await waitForFileViewerActiveState('false');
		requireActivateFiles(activateFiles)();
		await waitForFileViewerActiveState('true');
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(loadInitialSurfaceCount).toBe(1);
		const reactivatedFileButton = await waitForBridgeViewerTreeItemButton('src/file-1.ts');
		reactivatedFileButton.click();

		await waitForOpenFileState('ready');
		await waitForSelectedDisplayPath('src/file-1.ts');
		await waitForVisibleCodeText('reactivatedPreservedFile');

		expect(selectedDisplayPath()).toBe('src/file-1.ts');
		expect(openFilePath()).toBe('src/file-1.ts');
		expect(renderedFilePath()).toBe('src/file-1.ts');
		expect(openFileBodyPreview()).toContain('reactivatedPreservedFile');
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/content-1?generation=1',
		);
	});

	test('preloads recently updated files from a provider event without changing the open file', async () => {
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
				autoOpenInitialFile={true}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						props.resourceUrl.includes('recently-updated-content')
							? 'export const recentlyUpdated = true;\n'
							: 'export const visible = true;\n',
					);
				}}
				initialFrames={makeFrames(visibleDescriptor, updatedDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/visible.ts')}
			/>,
		);

		await waitForOpenFileState('ready');
		expect(openFilePath()).toBe('src/visible.ts');
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
		expect(shell.getAttribute('data-last-demand-dispatch-open-file-path-before')).toBe(
			'src/visible.ts',
		);
		expect(shell.getAttribute('data-last-demand-dispatch-open-file-path-after')).toBe(
			'src/visible.ts',
		);
		expect(openFileState()).toBe('ready');
		expect(openFilePath()).toBe('src/visible.ts');
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/recently-updated-content?generation=1',
		);
	});

	test('requests a descriptor before preloading recently updated metadata-only rows', async () => {
		const updatedDescriptor = makeFileDescriptor({
			contentHandle: 'recently-updated-metadata-only-content',
			fileId: 'file-app-delegate',
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const recentlyUpdatedMetadataOnly = true;\n',
					);
				}}
				initialFrames={makeTreeRowsOnlyFrames()}
				requestFileDescriptor={(request) => {
					descriptorRequests.push(request);
					const publishRequiredFrames = requireFramePublisher(publishFrames);
					publishRequiredFrames(makeFileDescriptorFrame(updatedDescriptor, { sequence: 1 }));
				}}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForBridgeViewerTreeItemButton('Sources/AgentStudio/App/AppDelegate.swift');
		window.dispatchEvent(
			new CustomEvent('bridge-worktree-file-recently-updated', {
				detail: {
					path: 'Sources/AgentStudio/App/AppDelegate.swift',
					proximity: 'nearby',
					sourceIdentity: 'dev-worktree-source',
				},
			}),
		);
		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});
		await waitForDemandDispatchFirstLane('nearby');

		expect(descriptorRequests).toEqual([
			{
				fileId: 'file-app-delegate',
				lane: 'nearby',
				path: 'Sources/AgentStudio/App/AppDelegate.swift',
				rowId: 'row:Sources/AgentStudio/App/AppDelegate.swift',
				sourceIdentity: makeSourceIdentity(),
			},
		]);
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/recently-updated-metadata-only-content?generation=1',
		]);
		expect(openFileState()).toBeNull();
	});

	test('ignores stale visible demand batch results after a newer source reset dispatch settles', async () => {
		const oldFirstDescriptor = makeFileDescriptor({
			contentHandle: 'old-first-delayed-content',
			fileId: 'file-old-first-delayed',
			path: 'src/old-first-delayed.ts',
		});
		const oldSecondDescriptor = makeFileDescriptor({
			contentHandle: 'old-second-delayed-content',
			fileId: 'file-old-second-delayed',
			path: 'src/old-second-delayed.ts',
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
				fetchResource={(props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return props.resourceUrl.includes('old-')
						? oldDeferredContent.promise
						: newDeferredContent.promise;
				}}
				initialFrames={makeFrames(oldFirstDescriptor, oldSecondDescriptor)}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForRecordedFetchCount({
			expectedCount: 2,
			recordedFetches: fetchedResourceUrls,
		});
		oldDeferredContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const old = true;\n'),
		);
		await waitForDemandDispatchFirstFreshnessKeyContaining('old-first-delayed-content');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		publishRequiredFrames(makeResetFrames(newFirstDescriptor, newSecondDescriptor));
		await waitForRecordedFetchCount({
			expectedCount: 4,
			recordedFetches: fetchedResourceUrls,
		});
		newDeferredContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const fresh = true;\n'),
		);
		await waitForDemandDispatchLoadedCount('2');
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-intent-count')).toBe('2');
		expect(shell.getAttribute('data-last-demand-dispatch-loaded-count')).toBe('2');
		expect(shell.getAttribute('data-last-demand-dispatch-failed-count')).toBe('0');
		expect(shell.getAttribute('data-last-demand-dispatch-origin')).toBe('visibleViewport');
		expect(shell.getAttribute('data-last-demand-dispatch-expected-visible-file-count')).toBe('2');
		expect(shell.getAttribute('data-last-demand-dispatch-first-dedupe-key')).toContain(
			'new-first-content',
		);
		expect(shell.getAttribute('data-last-demand-dispatch-first-freshness-key')).toContain(
			'new-first-content',
		);
		expect(shell.getAttribute('data-last-demand-dispatch-first-dedupe-key')).not.toContain(
			'old-first-delayed-content',
		);
		expect(shell.getAttribute('data-last-demand-dispatch-first-freshness-key')).not.toContain(
			'old-first-delayed-content',
		);
	});

	test('renders replacement file body after an explicit stale refresh', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'refresh-content-1',
			fileId: 'file-refresh-target',
			path: 'src/refresh-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'refresh-content-2',
			fileId: 'file-refresh-target',
			generation: 2,
			path: 'src/refresh-target.ts',
			sourceIdentity: resetSourceIdentity,
		});
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						props.resourceUrl.includes('refresh-content-2')
							? 'export const refreshed = true;\n'
							: 'export const initial = true;\n',
					);
				}}
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/refresh-target.ts')}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const initial = true;');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		publishRequiredFrames(makeResetFrames(replacementDescriptor));
		await waitForOpenFileState('stale');
		const refreshButton = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-refresh"]'),
		);
		refreshButton.click();

		await waitForOpenFileState('ready');
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/refresh-content-2?generation=2',
		);
		expect(openFileBodyPreview()).toContain('export const refreshed = true;');
		await waitForVisibleCodeText('export const refreshed = true;');

		expect(visibleCodeText()).not.toContain('export const initial = true;');
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-refresh-result')).toBe('ok');
		expect(shell.getAttribute('data-last-refresh-commit-state')).toBe('committed');
		expect(shell.getAttribute('data-last-refresh-descriptor-id')).toBe('refresh-content-2');
	});

	test('keeps selected file ready when reset metadata carries the same content descriptor', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'stable-content',
			fileId: 'file-stable-target',
			path: 'src/stable-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const sameContentDescriptor = makeFileDescriptor({
			contentHandle: 'stable-content',
			fileId: 'file-stable-target',
			generation: 2,
			path: 'src/stable-target.ts',
			sourceIdentity: resetSourceIdentity,
		});
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fetchResource={async () =>
					makeWorktreeFileSurfaceRuntimeFetchedResource('export const stable = true;\n')
				}
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/stable-target.ts')}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const stable = true;');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		publishRequiredFrames(makeResetFrames(sameContentDescriptor));

		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const stable = true;');
		expect(openFileState()).toBe('ready');
	});

	test('marks the open file stale when a new source snapshot replaces the active stream', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'source-snapshot-content-1',
			fileId: 'file-source-less-reset-target',
			path: 'src/source-less-reset-target.ts',
		});
		const replacementSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'source-snapshot-content-2',
			fileId: 'file-source-less-reset-target',
			generation: 2,
			path: 'src/source-less-reset-target.ts',
			sourceIdentity: replacementSourceIdentity,
		});
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) =>
					makeWorktreeFileSurfaceRuntimeFetchedResource(
						props.resourceUrl.includes('source-snapshot-content-2')
							? 'export const sourceSnapshotFresh = true;\n'
							: 'export const sourceSnapshotInitial = true;\n',
					)
				}
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/source-less-reset-target.ts')}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('sourceSnapshotInitial');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		publishRequiredFrames([
			makeSnapshotFrame({ sequence: 1, sourceIdentity: replacementSourceIdentity }),
		]);

		await waitForOpenFileState('stale');
		expect(visibleCodeText()).toContain('sourceSnapshotInitial');

		publishRequiredFrames([
			...makeFileDescriptorFrame(replacementDescriptor, { generation: 2, sequence: 2 }),
		]);
		await waitForRefreshButtonEnabled();
		const refreshButton = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-refresh"]'),
		);
		refreshButton.click();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-refresh-result')).toBe('ok');
		expect(shell.getAttribute('data-last-refresh-commit-state')).toBe('committed');

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('sourceSnapshotFresh');
		expect(visibleCodeText()).not.toContain('sourceSnapshotInitial');
	});

	test('blocks descriptor demand between a source-less reset and the next source snapshot', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'source-less-reset-content-1',
			fileId: 'file-source-less-reset-target',
			path: 'src/source-less-reset-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'source-less-reset-content-2',
			fileId: 'file-source-less-reset-target',
			generation: 2,
			path: 'src/source-less-reset-target.ts',
			sourceIdentity: resetSourceIdentity,
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fetchResource={async (props) =>
					makeWorktreeFileSurfaceRuntimeFetchedResource(
						props.resourceUrl.includes('source-less-reset-content-2')
							? 'export const sourceLessResetFresh = true;\n'
							: 'export const sourceLessResetInitial = true;\n',
					)
				}
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/source-less-reset-target.ts')}
				requestFileDescriptor={(request) => {
					descriptorRequests.push(request);
				}}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('sourceLessResetInitial');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		publishRequiredFrames(makeSourceLessResetFrames());

		await waitForOpenFileState('stale');
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		expect(refreshButtonIsDisabled()).toBe(true);
		expect(descriptorRequests).toEqual([]);
		expect(visibleCodeText()).toContain('sourceLessResetInitial');

		publishRequiredFrames([
			makeSnapshotFrame({ sequence: 1, sourceIdentity: resetSourceIdentity }),
			...makeFileDescriptorFrame(replacementDescriptor, { generation: 2, sequence: 2 }),
		]);

		await waitForRefreshButtonEnabled();
		const refreshButtonAfterSnapshot = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-refresh"]'),
		);
		refreshButtonAfterSnapshot.click();

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('sourceLessResetFresh');
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
			treeRows: descriptors.map(makeTreeRowFromDescriptor),
			treeSizeFacts: {
				extentKind: 'exactPathCount',
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

function makeTreeRowFromDescriptor(descriptor: WorktreeFileDescriptor): WorktreeTreeRowMetadata {
	const pathParts = descriptor.path.split('/');
	const name = pathParts.at(-1) ?? descriptor.path;
	const parentPath =
		pathParts.length > 1 ? pathParts.slice(0, pathParts.length - 1).join('/') : null;
	return makeTreeRow({
		depth: Math.max(pathParts.length - 1, 0),
		fileId: descriptor.fileId,
		isDirectory: false,
		name,
		parentPath,
		path: descriptor.path,
		sizeBytes: descriptor.sizeBytes,
		...(descriptor.lineCount === undefined ? {} : { lineCount: descriptor.lineCount }),
	});
}

function makeTreeRowsOnlyFrames(): readonly WorktreeFileProtocolFrame[] {
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
			treeRows: [
				makeTreeRow({
					depth: 0,
					isDirectory: true,
					name: 'Sources',
					parentPath: null,
					path: 'Sources',
				}),
				makeTreeRow({
					depth: 1,
					isDirectory: true,
					name: 'AgentStudio',
					parentPath: 'Sources',
					path: 'Sources/AgentStudio',
				}),
				makeTreeRow({
					depth: 2,
					isDirectory: true,
					name: 'App',
					parentPath: 'Sources/AgentStudio',
					path: 'Sources/AgentStudio/App',
				}),
				makeTreeRow({
					depth: 3,
					fileId: 'file-app-delegate',
					isDirectory: false,
					lineCount: 42,
					name: 'AppDelegate.swift',
					parentPath: 'Sources/AgentStudio/App',
					path: 'Sources/AgentStudio/App/AppDelegate.swift',
				}),
				makeTreeRow({
					depth: 2,
					isDirectory: true,
					name: 'Features',
					parentPath: 'Sources/AgentStudio',
					path: 'Sources/AgentStudio/Features',
				}),
				makeTreeRow({
					depth: 3,
					isDirectory: true,
					name: 'Bridge',
					parentPath: 'Sources/AgentStudio/Features',
					path: 'Sources/AgentStudio/Features/Bridge',
				}),
			],
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 6,
				windowStartIndex: 0,
				windowRowCount: 6,
				rowHeightPixels: 24,
			},
		}),
	];
}

function makeTreeWindowedSnapshotFrame(props: {
	readonly rowCount: number;
	readonly totalPathCount: number;
}): WorktreeFileProtocolFrame {
	return parseWorktreeFileProtocolFrame({
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
		treeRows: makeFlatFileTreeRows({ count: props.rowCount, startIndex: 0 }),
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: props.totalPathCount,
			windowStartIndex: 0,
			windowRowCount: props.rowCount,
			rowHeightPixels: 24,
		},
	});
}

function makeTreeWindowFrame(props: {
	readonly rowCount: number;
	readonly sequence: number;
	readonly startIndex: number;
	readonly totalPathCount: number;
}): WorktreeFileProtocolFrame {
	return parseWorktreeFileProtocolFrame({
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: props.sequence,
		frameKind: 'worktree.treeWindow',
		projectionIdentity: {
			source: makeSourceIdentity(),
			pathScope: [],
			sortKey: 'path',
			groupKey: 'none',
			filterKey: 'all',
			treeWindowKey: `tree-window-${props.startIndex}`,
		},
		windowDescriptor: makeAttachedDescriptor({
			descriptorId: `tree-window-${props.startIndex}`,
			resourceKind: 'worktree.treeWindow',
		}),
		rows: makeFlatFileTreeRows({ count: props.rowCount, startIndex: props.startIndex }),
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: props.totalPathCount,
			windowStartIndex: props.startIndex,
			windowRowCount: props.rowCount,
			rowHeightPixels: 24,
		},
	});
}

function makeFlatFileTreeRows(props: {
	readonly count: number;
	readonly startIndex: number;
}): readonly WorktreeTreeRowMetadata[] {
	return Array.from({ length: props.count }, (_value, index): WorktreeTreeRowMetadata => {
		const fileIndex = props.startIndex + index;
		const fileName = `File-${fileIndex.toString().padStart(3, '0')}.swift`;
		return makeTreeRow({
			depth: 0,
			fileId: `file-${fileIndex.toString().padStart(3, '0')}`,
			isDirectory: false,
			name: fileName,
			parentPath: null,
			path: fileName,
			sizeBytes: 24,
		});
	});
}

function makeFileDescriptorFrame(
	descriptor: WorktreeFileDescriptor,
	props: { readonly generation?: number; readonly sequence: number },
): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'delta',
			streamId: 'worktree-file:pane-1',
			generation: props.generation ?? 1,
			sequence: props.sequence,
			frameKind: 'worktree.fileDescriptor',
			descriptor,
		}),
	];
}

function makeSnapshotFrame(props: {
	readonly sequence: number;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}): WorktreeFileProtocolFrame {
	return parseWorktreeFileProtocolFrame({
		kind: 'snapshot',
		streamId: 'worktree-file:pane-1',
		generation: props.sourceIdentity.subscriptionGeneration,
		sequence: props.sequence,
		frameKind: 'worktree.snapshot',
		source: props.sourceIdentity,
		treeDescriptor: makeAttachedDescriptor({
			descriptorId: 'tree-window-source-less-reset',
			generation: props.sourceIdentity.subscriptionGeneration,
			resourceKind: 'worktree.treeWindow',
		}),
		treeRows: [
			makeTreeRow({
				depth: 0,
				fileId: 'file-source-less-reset-target',
				isDirectory: false,
				name: 'source-less-reset-target.ts',
				parentPath: null,
				path: 'src/source-less-reset-target.ts',
				sizeBytes: 64,
			}),
		],
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: 1,
			windowStartIndex: 0,
			windowRowCount: 1,
			rowHeightPixels: 24,
		},
	});
}

function makeSourceLessResetFrames(): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'reset',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 0,
			frameKind: 'worktree.reset',
			reason: 'sourceChanged',
		}),
	];
}

function makeFileInvalidatedFrames(props: {
	readonly fileId: string;
	readonly path: string;
	readonly sequence: number;
}): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'delta',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: props.sequence,
			frameKind: 'worktree.fileInvalidated',
			invalidation: {
				path: props.path,
				fileId: props.fileId,
				reason: 'contentChanged',
			},
		}),
	];
}

function makeTreeRow(props: {
	readonly changeStatus?: string;
	readonly depth: number;
	readonly fileId?: string;
	readonly isDirectory: boolean;
	readonly lineCount?: number;
	readonly name: string;
	readonly parentPath: string | null;
	readonly path: string;
	readonly sizeBytes?: number;
}): WorktreeTreeRowMetadata {
	return {
		rowId: `row:${props.path}`,
		path: props.path,
		name: props.name,
		parentPath: props.parentPath,
		depth: props.depth,
		isDirectory: props.isDirectory,
		...(props.fileId === undefined ? {} : { fileId: props.fileId }),
		...(props.sizeBytes === undefined ? {} : { sizeBytes: props.sizeBytes }),
		...(props.lineCount === undefined ? {} : { lineCount: props.lineCount }),
		...(props.changeStatus === undefined ? {} : { changeStatus: props.changeStatus }),
	};
}

function makeResetFrames(
	...replacementDescriptors: readonly WorktreeFileDescriptor[]
): readonly WorktreeFileProtocolFrame[] {
	const resetSourceIdentity = makeSourceIdentity({
		subscriptionGeneration: 2,
		sourceCursor: 'cursor-2',
	});
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'reset',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 0,
			frameKind: 'worktree.reset',
			source: resetSourceIdentity,
			reason: 'sourceChanged',
		}),
		parseWorktreeFileProtocolFrame({
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 1,
			frameKind: 'worktree.snapshot',
			source: resetSourceIdentity,
			treeDescriptor: makeAttachedDescriptor({
				descriptorId: 'tree-window-reset',
				generation: 2,
				resourceKind: 'worktree.treeWindow',
			}),
			treeRows: replacementDescriptors.map(makeTreeRowFromDescriptor),
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: replacementDescriptors.length,
				windowStartIndex: 0,
				windowRowCount: replacementDescriptors.length,
				rowHeightPixels: 24,
			},
		}),
		...replacementDescriptors.map(
			(descriptor, descriptorIndex): WorktreeFileProtocolFrame =>
				parseWorktreeFileProtocolFrame({
					kind: 'delta',
					streamId: 'worktree-file:pane-1',
					generation: 2,
					sequence: descriptorIndex + 2,
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
	readonly lineCount?: number;
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
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: props.lineCount ?? 2 } : {}),
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

function requireDeactivateFiles(deactivateFiles: (() => void) | null): () => void {
	if (deactivateFiles === null) {
		throw new Error('Controlled FileViewer did not publish its deactivate callback.');
	}
	return deactivateFiles;
}

function requireActivateFiles(activateFiles: (() => void) | null): () => void {
	if (activateFiles === null) {
		throw new Error('Controlled FileViewer did not publish its activate callback.');
	}
	return activateFiles;
}

function requireOpenSlowFile(openSlowFile: (() => void) | null): () => void {
	if (openSlowFile === null) {
		throw new Error('Controlled FileViewer did not publish its open callback.');
	}
	return openSlowFile;
}

async function waitForOpenFileState(expectedState: string): Promise<void> {
	await waitForOpenFileStateAttempt({ attempt: 0, expectedState });
}

async function waitForFileViewerActiveState(expectedState: string): Promise<void> {
	await waitForFileViewerActiveStateAttempt({ attempt: 0, expectedState });
}

async function waitForRefreshButtonEnabled(): Promise<void> {
	await waitForRefreshButtonEnabledAttempt({ attempt: 0 });
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

async function waitForDescriptorRequestCount(props: {
	readonly expectedCount: number;
	readonly recordedRequests: readonly WorktreeFileDescriptorRequest[];
}): Promise<void> {
	await waitForDescriptorRequestCountAttempt({
		attempt: 0,
		expectedCount: props.expectedCount,
		recordedRequests: props.recordedRequests,
	});
}

async function waitForMetadataTreeRowCount(expectedCount: number): Promise<void> {
	await waitForMetadataTreeRowCountAttempt({ attempt: 0, expectedCount });
}

async function waitForSelectedDisplayPath(expectedPath: string): Promise<void> {
	await waitForSelectedDisplayPathAttempt({ attempt: 0, expectedPath });
}

async function waitForInitialSurfaceState(expectedState: string): Promise<void> {
	await waitForInitialSurfaceStateAttempt({ attempt: 0, expectedState });
}

async function waitForInitialSurfaceLoadCount(props: {
	readonly expectedCount: number;
	readonly getLoadCount: () => number;
}): Promise<void> {
	await waitForInitialSurfaceLoadCountAttempt({
		attempt: 0,
		expectedCount: props.expectedCount,
		getLoadCount: props.getLoadCount,
	});
}

async function waitForFileCodeViewViewport(): Promise<HTMLElement> {
	return waitForFileCodeViewViewportAttempt({ attempt: 0 });
}

async function waitForFileCodeViewScrollOwner(): Promise<HTMLElement> {
	return waitForFileCodeViewScrollOwnerAttempt({ attempt: 0 });
}

async function waitForFileCodeViewScrollable(scrollOwner: HTMLElement): Promise<void> {
	await waitForFileCodeViewScrollableAttempt({ attempt: 0, scrollOwner });
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

async function waitForRefreshButtonEnabledAttempt(props: {
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

async function waitForFileCodeViewViewportAttempt(props: {
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

async function waitForFileCodeViewScrollOwnerAttempt(props: {
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

async function waitForFileCodeViewScrollableAttempt(props: {
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

function openFileState(): string | null {
	return (
		document
			.querySelector('[data-worktree-open-file-state]')
			?.getAttribute('data-worktree-open-file-state') ?? null
	);
}

function refreshButtonIsDisabled(): boolean {
	const refreshButton = document.querySelector('[data-testid="worktree-file-refresh"]');
	if (!(refreshButton instanceof HTMLButtonElement)) {
		throw new Error('Expected Worktree/File refresh button to be mounted.');
	}
	return refreshButton.disabled;
}

function openFilePath(): string | null {
	return (
		document
			.querySelector('[data-worktree-open-file-path]')
			?.getAttribute('data-worktree-open-file-path') ?? null
	);
}

function selectedDisplayPath(): string | null {
	return (
		document
			.querySelector('[data-testid="bridge-file-viewer-shell"]')
			?.getAttribute('data-selected-display-path') ?? null
	);
}

function visibleCodeText(): string {
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

function openFileBodyPreview(): string | null {
	return (
		document
			.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')
			?.getAttribute('data-worktree-open-file-body-preview') ?? null
	);
}

function renderedFilePath(): string | null {
	return (
		document
			.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')
			?.getAttribute('data-worktree-rendered-file-path') ?? null
	);
}

async function waitForOpenFileBodyPreview(expectedText: string): Promise<void> {
	await waitForOpenFileBodyPreviewAttempt({ attempt: 0, expectedText });
}

async function waitForOpenFileBodyPreviewAttempt(props: {
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

function fileCanvasRenderedTextOffset(text: string): number | null {
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

function renderedTextOffsetWithinRoot(props: {
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

async function waitForVisibleCodeText(expectedText: string): Promise<void> {
	await waitForVisibleCodeTextAttempt({ attempt: 0, expectedText });
}

function makeGeneratedFileBody(label: string, lineCount: number): string {
	return Array.from(
		{ length: lineCount },
		(_value, index): string =>
			`export const ${label}Line${String(index + 1).padStart(3, '0')} = true;`,
	).join('\n');
}

async function waitForVisibleCodeTextAttempt(props: {
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

async function waitForFileViewerActiveStateAttempt(props: {
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

async function waitForDemandDispatchFirstFreshnessKeyContaining(
	expectedContentHandle: string,
): Promise<void> {
	await waitForDemandDispatchFirstFreshnessKeyContainingAttempt({
		attempt: 0,
		expectedContentHandle,
	});
}

async function waitForDemandDispatchFirstFreshnessKeyContainingAttempt(props: {
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

async function waitForDescriptorRequestCountAttempt(props: {
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

async function waitForMetadataTreeRowCountAttempt(props: {
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

async function waitForSelectedDisplayPathAttempt(props: {
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

async function waitForInitialSurfaceStateAttempt(props: {
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

async function waitForTreeScrollHeightAtLeast(
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

async function waitForInitialSurfaceLoadCountAttempt(props: {
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

function makeDeferredContent(): {
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

function makeDeferredInitialSurface(): {
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
