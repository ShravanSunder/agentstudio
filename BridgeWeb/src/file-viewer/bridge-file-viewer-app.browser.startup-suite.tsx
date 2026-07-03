import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { worktreeFileProtocolFrameSchema } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import {
	findBridgeViewerTreeScrollOwner,
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerElement,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { BridgeFileViewerApp } from './bridge-file-viewer-app.js';
import {
	makeFileDescriptor,
	makeFileDescriptorFrame,
	makeFileInvalidatedFrames,
	makeFrames,
	makeSourceIdentity,
	makeTreeRow,
	makeTreeRowsOnlyFrames,
	makeTreeWindowedSnapshotFrame,
	makeTreeWindowFrame,
	type PublishWorktreeFileFrames,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	makeDeferredInitialSurface,
	makeTestTelemetryRecorder,
	openFileBodyPreview,
	openFilePath,
	renderedFilePath,
	requireFramePublisher,
	selectedDisplayPath,
	waitForDescriptorRequestCount,
	waitForInitialSurfaceLoadCount,
	waitForInitialSurfaceState,
	waitForMetadataTreeRowCount,
	waitForOpenFileState,
	waitForSelectedDisplayPath,
	waitForTelemetrySample,
	waitForTelemetrySampleCount,
	waitForTreeScrollHeightAtLeast,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

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

	test('traces the initial FileView pending surface before metadata resolves', async () => {
		const descriptor = makeFileDescriptor({ path: 'src/app.ts' });
		const initialSurface = makeDeferredInitialSurface();
		let loadInitialSurfaceCount = 0;

		render(
			<BridgeFileViewerApp
				loadInitialSurface={(): Promise<WorktreeFileInitialSurface> => {
					loadInitialSurfaceCount += 1;
					return initialSurface.promise;
				}}
			/>,
		);
		const stopTracing = startFileViewerUiTrace();

		await waitForInitialSurfaceLoadCount({
			expectedCount: 1,
			getLoadCount: () => loadInitialSurfaceCount,
		});
		await waitForFileViewerTrace((entries) =>
			entries.some(
				(entry) =>
					entry.initialSurfaceState === 'loading' &&
					entry.visibleText.includes('Source pending') &&
					fileViewerPendingCanvasIsVisible(entry.visibleText),
			),
		);
		const pendingEntries = fileViewerUiTraceEntries();
		const pendingEntry = pendingEntries.find(
			(entry) =>
				entry.initialSurfaceState === 'loading' &&
				entry.visibleText.includes('Source pending') &&
				fileViewerPendingCanvasIsVisible(entry.visibleText),
		);
		expect(pendingEntry).toEqual(
			expect.objectContaining({
				hasShell: true,
				initialSurfaceState: 'loading',
				metadataTreeRowCount: '0',
			}),
		);

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
		await waitForBridgeViewerTreeItemButton('src/app.ts');
		stopTracing();

		const traceEntries = fileViewerUiTraceEntries();
		expect(traceEntries.some((entry) => entry.initialSurfaceState === 'loading')).toBe(true);
		expect(traceEntries.some((entry) => entry.initialSurfaceState === 'ready')).toBe(true);
		expect(traceEntries.at(-1)).toEqual(
			expect.objectContaining({
				hasShell: true,
				initialSurfaceState: 'ready',
				metadataTreeRowCount: '1',
			}),
		);
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
		expect(document.querySelector('[data-testid="worktree-file-search-control"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="worktree-file-search-toggle"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="worktree-file-regex-toggle"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="worktree-file-filter-menu"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="worktree-file-search-input"]')).toBeNull();
		const searchToggle = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-search-toggle"]'),
		);
		const regexToggle = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-regex-toggle"]'),
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

	test('renders FileView rail in the shared resizable panel layout with stable geometry', async () => {
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

		await waitForInitialSurfaceState('ready');
		await waitForBridgeViewerElement('[data-slot="resizable-panel-group"]');

		const layout = requireBridgeViewerHTMLElement(
			document.querySelector('[data-slot="resizable-panel-group"]'),
		);
		const contentPanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-content-panel"]'),
		);
		const resizeHandle = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-rail-resize-handle"]'),
		);
		const railPanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-resizable-rail"]'),
		);
		const treePanel = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]'),
		);

		const layoutBox = layout.getBoundingClientRect();
		const contentBox = contentPanel.getBoundingClientRect();
		const handleBox = resizeHandle.getBoundingClientRect();
		const railBox = railPanel.getBoundingClientRect();
		const treeBox = treePanel.getBoundingClientRect();
		const railWidthRatio = railBox.width / layoutBox.width;
		const appButton = await waitForBridgeViewerTreeItemButton('src/app.ts');
		const readmeButton = await waitForBridgeViewerTreeItemButton('docs/readme.md');

		expect(layout.getAttribute('data-panel-group-direction')).toBe('horizontal');
		expect(layoutBox.width).toBeGreaterThan(900);
		expect(contentBox.width).toBeGreaterThan(railBox.width);
		expect(handleBox.width).toBeGreaterThanOrEqual(1);
		expect(railBox.width).toBeGreaterThanOrEqual(240);
		expect(railBox.height).toBeGreaterThan(200);
		expect(treeBox.width).toBeGreaterThan(200);
		expect(treeBox.height).toBeGreaterThan(150);
		expect(appButton.getAttribute('data-item-path')).toBe('src/app.ts');
		expect(readmeButton.getAttribute('data-item-path')).toBe('docs/readme.md');
		expect(railWidthRatio).toBeGreaterThan(0.24);
		expect(railWidthRatio).toBeLessThan(0.32);
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
			...document.querySelectorAll('[data-testid="worktree-file-filter-menu-option"]'),
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

	test('applies subscribed tree delta updates to the visible FileView tree', async () => {
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={makeTreeRowsOnlyFrames()}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
				}}
			/>,
		);

		await waitForMetadataTreeRowCount(6);
		await waitForBridgeViewerTreeItemButton('Sources/AgentStudio/App/AppDelegate.swift');
		requireFramePublisher(publishFrames)([
			worktreeFileProtocolFrameSchema.parse({
				kind: 'delta',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: 1,
				frameKind: 'worktree.treeDelta',
				operations: [
					{
						op: 'removeRows',
						rowIds: ['row:Sources/AgentStudio/App/AppDelegate.swift'],
						paths: ['Sources/AgentStudio/App/AppDelegate.swift'],
					},
					{
						op: 'upsertRows',
						rows: [
							makeTreeRow({
								depth: 4,
								fileId: 'file-bridge-runtime',
								isDirectory: false,
								lineCount: 64,
								name: 'BridgeRuntime.swift',
								parentPath: 'Sources/AgentStudio/Features/Bridge',
								path: 'Sources/AgentStudio/Features/Bridge/BridgeRuntime.swift',
							}),
						],
					},
				],
			}),
		]);

		await waitForMetadataTreeRowCount(5);
		await waitForBridgeViewerTreeItemButton(
			'Sources/AgentStudio/Features/Bridge/BridgeRuntime.swift',
		);
		expect(
			document.querySelector(
				'[data-worktree-file-path="Sources/AgentStudio/App/AppDelegate.swift"]',
			),
		).toBeNull();
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

	test('records file open ready telemetry from user click to rendered body commit', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'file-open-ready-content',
			fileId: 'file-open-ready',
			path: 'src/file-open-ready.ts',
		});
		const telemetrySamples: BridgeTelemetrySample[] = [];

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fetchResource={async () =>
					makeWorktreeFileSurfaceRuntimeFetchedResource('export const fileOpenReady = true;\n')
				}
				initialFrames={makeFrames(descriptor)}
				telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
			/>,
		);

		const fileButton = await waitForBridgeViewerTreeItemButton('src/file-open-ready.ts');
		fileButton.click();

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('fileOpenReady');
		const sample = await waitForTelemetrySample({
			name: 'performance.bridge.web.file_open_ready',
			samples: telemetrySamples,
		});

		expect(sample.durationMilliseconds).not.toBeNull();
		expect(sample.durationMilliseconds ?? -1).toBeGreaterThanOrEqual(0);
		expect(sample.stringAttributes).toMatchObject({
			'agentstudio.bridge.content.role': 'file',
			'agentstudio.bridge.phase': 'file_open_ready',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.result_reason': 'none',
			'agentstudio.bridge.slice': 'content_fetch',
			'agentstudio.bridge.viewer': 'file',
		});
		expect(sample.stringAttributes['agentstudio.bridge.demand.lane']).toBeTruthy();
		expect(sample.stringAttributes['agentstudio.bridge.demand.disposition']).toBeTruthy();
		expect(sample.numericAttributes['agentstudio.bridge.demand.request.sequence']).toBeGreaterThan(
			0,
		);
		expect(sample.numericAttributes['agentstudio.bridge.source.generation']).toBe(1);
		expect(
			sample.numericAttributes['agentstudio.bridge.demand.scheduler_queue_wait_ms'],
		).toBeGreaterThanOrEqual(0);
		expect(
			sample.numericAttributes['agentstudio.bridge.demand.executor_pending_wait_ms'],
		).toBeGreaterThanOrEqual(0);
		expect(
			sample.numericAttributes['agentstudio.bridge.demand.executor_in_flight_ms'],
		).toBeGreaterThanOrEqual(0);
	});

	test('records visible demand telemetry when the File tree scroll path settles demand', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'scroll-visible-demand-content',
			fileId: 'file-scroll-visible-demand',
			path: 'src/scroll-visible-demand.ts',
		});
		const telemetrySamples: BridgeTelemetrySample[] = [];

		render(
			<BridgeFileViewerApp
				fetchResource={async () =>
					makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const scrollVisibleDemand = true;\n',
					)
				}
				initialFrames={makeFrames(descriptor)}
				telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
			/>,
		);

		await waitForBridgeViewerTreeItemButton('src/scroll-visible-demand.ts');
		const initialSampleCount = telemetrySamples.filter(
			(sample): boolean => sample.name === 'performance.bridge.trees.scroll_visible_demand',
		).length;
		const treeScrollOwner = findBridgeViewerTreeScrollOwner();
		if (treeScrollOwner === null) {
			throw new Error('Expected FileView tree scroll owner for visible demand telemetry.');
		}
		treeScrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));

		const sample = await waitForTelemetrySampleCount({
			count: initialSampleCount + 1,
			name: 'performance.bridge.trees.scroll_visible_demand',
			samples: telemetrySamples,
		});

		expect(sample.durationMilliseconds).not.toBeNull();
		expect(sample.durationMilliseconds ?? -1).toBeGreaterThanOrEqual(0);
		expect(sample.stringAttributes).toMatchObject({
			'agentstudio.bridge.demand.disposition': 'published',
			'agentstudio.bridge.demand.lane': 'visible',
			'agentstudio.bridge.phase': 'scroll_visible_demand',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.result_reason': 'none',
			'agentstudio.bridge.slice': 'tree_prepare_input',
			'agentstudio.bridge.viewer': 'file',
		});
		expect(sample.numericAttributes['agentstudio.bridge.visible_item.count']).toBeGreaterThan(0);
		const settledSample = await waitForTelemetrySample({
			name: 'performance.bridge.web.visible_demand_settled',
			samples: telemetrySamples,
		});
		expect(settledSample.durationMilliseconds).not.toBeNull();
		expect(settledSample.durationMilliseconds ?? -1).toBeGreaterThanOrEqual(0);
		expect(settledSample.stringAttributes).toMatchObject({
			'agentstudio.bridge.content.role': 'file',
			'agentstudio.bridge.demand.lane': 'visible',
			'agentstudio.bridge.phase': 'visible_demand_settled',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.result_reason': 'none',
			'agentstudio.bridge.slice': 'content_fetch',
			'agentstudio.bridge.viewer': 'file',
		});
		expect(
			settledSample.numericAttributes['agentstudio.bridge.demand.enqueue_accepted.count'],
		).toBeGreaterThan(0);
		expect(settledSample.numericAttributes['agentstudio.bridge.demand.failed.count']).toBe(0);
		expect(
			settledSample.numericAttributes['agentstudio.bridge.demand.loaded.count'],
		).toBeGreaterThan(0);
		expect(
			settledSample.numericAttributes['agentstudio.bridge.demand.request.sequence'],
		).toBeGreaterThan(0);
		expect(
			settledSample.numericAttributes['agentstudio.bridge.demand.scheduler_queue_wait_ms'],
		).toBeGreaterThanOrEqual(0);
	});
});

interface FileViewerUiTraceEntry {
	readonly contentStateText: string | null;
	readonly hasLazyFrame: boolean;
	readonly hasShell: boolean;
	readonly initialSurfaceState: string | null;
	readonly metadataTreeRowCount: string | null;
	readonly timestampMilliseconds: number;
	readonly visibleText: string;
}

declare global {
	interface Window {
		bridgeFileViewerUiTrace?: FileViewerUiTraceEntry[];
	}
}

function startFileViewerUiTrace(): () => void {
	window.bridgeFileViewerUiTrace = [];
	const recordSnapshot = (): void => {
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		const contentState = document.querySelector('[data-testid="bridge-file-viewer-content-state"]');
		window.bridgeFileViewerUiTrace?.push({
			contentStateText: normalizedText(contentState?.textContent ?? null),
			hasLazyFrame:
				document.querySelector('[data-testid="bridge-file-viewer-lazy-loading-frame"]') !== null,
			hasShell: shell !== null,
			initialSurfaceState: shell?.getAttribute('data-worktree-initial-surface-state') ?? null,
			metadataTreeRowCount: shell?.getAttribute('data-worktree-metadata-tree-row-count') ?? null,
			timestampMilliseconds: performance.now(),
			visibleText: normalizedText(document.body.textContent ?? '') ?? '',
		});
	};
	recordSnapshot();
	const observer = new MutationObserver(recordSnapshot);
	observer.observe(document.body, {
		attributes: true,
		childList: true,
		characterData: true,
		subtree: true,
	});
	return (): void => {
		observer.disconnect();
		recordSnapshot();
	};
}

async function waitForFileViewerTrace(
	predicate: (entries: readonly FileViewerUiTraceEntry[]) => boolean,
	attempt = 0,
): Promise<void> {
	if (predicate(fileViewerUiTraceEntries())) {
		return;
	}
	if (attempt >= 60) {
		throw new Error(
			`Expected FileView UI trace predicate to pass; entries=${JSON.stringify(
				fileViewerUiTraceEntries().slice(-5),
			)}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	await waitForFileViewerTrace(predicate, attempt + 1);
}

function fileViewerUiTraceEntries(): readonly FileViewerUiTraceEntry[] {
	return window.bridgeFileViewerUiTrace ?? [];
}

function normalizedText(text: string | null): string | null {
	if (text === null) {
		return null;
	}
	return text.replace(/\s+/gu, ' ').trim();
}

function fileViewerPendingCanvasIsVisible(visibleText: string): boolean {
	return (
		visibleText.includes('Select a file') ||
		visibleText.includes('Preparing code viewer') ||
		visibleText.includes('Code highlighting worker unavailable')
	);
}
