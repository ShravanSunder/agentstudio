import { useState, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import {
	findBridgeViewerTreeItemButton,
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { BridgeFileViewerApp } from './bridge-file-viewer-app.js';
import {
	fileNavigationCommandForPath,
	makeFileDescriptor,
	makeFileDescriptorFrame,
	makeFrames,
	makeSourceIdentity,
	makeTreeRow,
	makeTreeRowsOnlyFrames,
	makeTreeWindowFrame,
	parseWorktreeFileProtocolFrame,
	type PublishWorktreeFileFrames,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actClick,
	actFrame,
	actUpdate,
	makeDeferredContent,
	makeTestTelemetryRecorder,
	openFileBodyPreview,
	openFilePath,
	openFileState,
	renderedFilePath,
	requireActivateFiles,
	requireDeactivateFiles,
	requireFramePublisher,
	selectedDisplayPath,
	visibleCodeText,
	waitForDemandDispatchFirstFreshnessKeyContaining,
	waitForDemandDispatchFirstLane,
	waitForDemandDispatchState,
	waitForDescriptorRequestCount,
	waitForFileViewerActiveState,
	waitForInitialSurfaceLoadCount,
	waitForMetadataTreeRowCount,
	waitForOpenFileState,
	waitForRecordedFetchCount,
	waitForSelectedDisplayPath,
	waitForTelemetrySample,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp Browser Mode', () => {
	afterEach(async () => {
		cleanup();
		await actFrame();
		document.body.replaceChildren();
		terminateBridgePierreWorkerPoolSingletonForTest();
	});

	test('recovers a slow foreground navigation open after Files reactivates', async () => {
		const slowDescriptor = makeFileDescriptor({
			contentHandle: 'inactive-open-content',
			fileId: 'file-inactive-open',
			path: 'src/inactive-open.ts',
		});
		const firstDeferredContent = makeDeferredContent();
		const fetchedResourceUrls: string[] = [];
		const telemetrySamples: BridgeTelemetrySample[] = [];
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;

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
					fetchResource={(props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return firstDeferredContent.promise;
					}}
					initialFrames={makeFrames(slowDescriptor)}
					isActive={isActive}
					navigationCommand={fileNavigationCommandForPath('src/inactive-open.ts')}
					telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
				/>
			);
		}

		render(<ControlledFileViewer />);
		await actFrame();

		await waitForOpenFileState('loading');
		await waitForRecordedFetchCount({
			expectedCount: 1,
			recordedFetches: fetchedResourceUrls,
		});
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate((): void => {
			firstDeferredContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource('export const loadedWhileInactive = true;\n'),
			);
		});
		await actFrame();
		await actFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-file-viewer-active')).toBe('false');
		expect(openFileState()).toBeNull();
		expect(openFileBodyPreview()).toBeNull();
		expect(visibleCodeText()).not.toContain('loadedWhileInactive');
		expect(
			telemetrySamples.some((sample) => sample.name === 'performance.bridge.web.file_open_ready'),
		).toBe(false);

		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('loadedWhileInactive');
		const fileOpenSample = await waitForTelemetrySample({
			name: 'performance.bridge.web.file_open_ready',
			samples: telemetrySamples,
		});

		expect(openFilePath()).toBe('src/inactive-open.ts');
		expect(openFileBodyPreview()).toContain('loadedWhileInactive');
		expect(fileOpenSample.stringAttributes['agentstudio.bridge.demand.disposition']).toBe(
			'cache-hit',
		);
	});

	test('retries the initial auto-open when the first activation aborts during mode switch', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'auto-open-aborted-content',
			fileId: 'file-auto-open-aborted',
			path: 'src/auto-open-aborted.ts',
		});
		const firstFetchController: { reject: ((reason?: unknown) => void) | null } = {
			reject: null,
		};
		const firstFetchPromise = new Promise<never>((_resolve, reject): void => {
			firstFetchController.reject = reject;
		});
		const fetchedResourceUrls: string[] = [];
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;

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
					autoOpenInitialFile
					codeViewWorkerPoolEnabled={false}
					fetchResource={(props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						if (fetchedResourceUrls.length === 1) {
							return firstFetchPromise;
						}
						return Promise.resolve(
							makeWorktreeFileSurfaceRuntimeFetchedResource(
								'export const autoOpenRetried = true;\n',
							),
						);
					}}
					initialFrames={makeFrames(initialDescriptor)}
					isActive={isActive}
				/>
			);
		}

		render(<ControlledFileViewer />);
		await actFrame();

		await waitForOpenFileState('loading');
		await waitForRecordedFetchCount({
			expectedCount: 1,
			recordedFetches: fetchedResourceUrls,
		});
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		const rejectFirstFetch = firstFetchController.reject;
		if (rejectFirstFetch === null) {
			throw new Error('Expected first fetch reject callback to be registered.');
		}
		await actUpdate((): void => {
			rejectFirstFetch(new DOMException('Context switch aborted', 'AbortError'));
		});
		await actFrame();
		await actFrame();
		expect(openFileState()).toBeNull();

		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await waitForBridgeViewerTreeItemButton('src/auto-open-aborted.ts');

		await waitForRecordedFetchCount({
			expectedCount: 2,
			recordedFetches: fetchedResourceUrls,
		});
		await waitForOpenFileState('ready');
		await waitForSelectedDisplayPath('src/auto-open-aborted.ts');
		await waitForVisibleCodeText('autoOpenRetried');

		expect(openFilePath()).toBe('src/auto-open-aborted.ts');
		expect(openFileBodyPreview()).toContain('autoOpenRetried');
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
		await actFrame();

		await waitForInitialSurfaceLoadCount({
			expectedCount: 1,
			getLoadCount: () => loadInitialSurfaceCount,
		});
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await actFrame();
		await actFrame();

		expect(loadInitialSurfaceCount).toBe(1);
		await waitForBridgeViewerTreeItemButton('src/file-1.ts');
	});

	test('applies a tree delta pushed while Files is hidden without reloading the surface', async () => {
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;
		let loadInitialSurfaceCount = 0;
		let publishFrames: PublishWorktreeFileFrames | null = null;

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
									contentHandle: 'content-existing',
									fileId: 'file-existing',
									path: 'src/existing.ts',
								}),
								makeFileDescriptor({
									contentHandle: 'content-removed',
									fileId: 'file-removed',
									path: 'src/removed.ts',
								}),
							),
							provenance: {
								baseRef: 'native-current-worktree',
								scenarioName: 'current-worktree',
								worktreeRootToken: 'root-token',
							},
							source: makeSourceIdentity(),
						};
					}}
					subscribeFrames={(handler): (() => void) => {
						publishFrames = handler;
						return (): void => {
							publishFrames = null;
						};
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);
		await actFrame();

		await waitForInitialSurfaceLoadCount({
			expectedCount: 1,
			getLoadCount: () => loadInitialSurfaceCount,
		});
		await waitForMetadataTreeRowCount(2);
		await waitForBridgeViewerTreeItemButton('src/existing.ts');
		await waitForBridgeViewerTreeItemButton('src/removed.ts');

		// Hide Files (switch to Review), then push a tree delta while hidden.
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate((): void => {
			requireFramePublisher(publishFrames)([
				parseWorktreeFileProtocolFrame({
					kind: 'delta',
					streamId: 'worktree-file:pane-1',
					generation: 1,
					sequence: 3,
					frameKind: 'worktree.treeDelta',
					operations: [
						{
							op: 'upsertRows',
							rows: [
								makeTreeRow({
									depth: 1,
									fileId: 'file-added',
									isDirectory: false,
									lineCount: 12,
									name: 'added.ts',
									parentPath: 'src',
									path: 'src/added.ts',
								}),
							],
						},
						{
							op: 'removeRows',
							rowIds: ['row:src/removed.ts'],
							paths: ['src/removed.ts'],
						},
					],
				}),
			]);
		});

		// Show Files again (switch back to Review -> Files).
		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await waitForBridgeViewerTreeItemButton('src/added.ts');

		expect(findBridgeViewerTreeItemButton('src/removed.ts')).toBeNull();
		expect(findBridgeViewerTreeItemButton('src/existing.ts')).not.toBeNull();
		expect(loadInitialSurfaceCount).toBe(1);
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
		await actFrame();

		await waitForInitialSurfaceLoadCount({
			expectedCount: 1,
			getLoadCount: () => loadInitialSurfaceCount,
		});
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await actFrame();
		await actFrame();

		expect(loadInitialSurfaceCount).toBe(1);
		const reactivatedFileButton = await waitForBridgeViewerTreeItemButton('src/file-1.ts');
		await actClick(reactivatedFileButton);

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

	test('ignores a late metadata-only descriptor from before Files deactivated', async () => {
		const initiallyOpenDescriptor = makeFileDescriptor({
			contentHandle: 'initial-content',
			fileId: 'file-000',
			path: 'File-000.swift',
		});
		const lateDescriptor = makeFileDescriptor({
			contentHandle: 'late-clicked-content',
			fileId: 'file-001',
			path: 'File-001.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		const fetchedResourceUrls: string[] = [];
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;
		let publishFrames: PublishWorktreeFileFrames | null = null;

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
					autoOpenInitialFile
					codeViewWorkerPoolEnabled={false}
					fetchResource={async (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return makeWorktreeFileSurfaceRuntimeFetchedResource(
							props.resourceUrl.includes('late-clicked-content')
								? 'export const lateClickedSelection = true;\n'
								: 'export const initiallyOpen = true;\n',
						);
					}}
					initialFrames={makeFrames(initiallyOpenDescriptor)}
					isActive={isActive}
					requestFileDescriptor={(request) => {
						descriptorRequests.push(request);
					}}
					subscribeFrames={(handler): (() => void) => {
						publishFrames = handler;
						return (): void => {
							publishFrames = null;
						};
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('initiallyOpen');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames([
				makeTreeWindowFrame({ rowCount: 1, sequence: 2, startIndex: 1, totalPathCount: 2 }),
			]);
		});
		const clickedButton = await waitForBridgeViewerTreeItemButton('File-001.swift');
		await actClick(clickedButton);
		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});

		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await actUpdate((): void => {
			publishRequiredFrames(makeFileDescriptorFrame(lateDescriptor, { sequence: 3 }));
		});
		await actFrame();
		await actFrame();

		expect(openFilePath()).toBe('File-000.swift');
		expect(selectedDisplayPath()).toBe('File-000.swift');
		expect(renderedFilePath()).toBe('File-000.swift');
		expect(openFileBodyPreview()).toContain('initiallyOpen');
		expect(visibleCodeText()).not.toContain('lateClickedSelection');

		await actClick(clickedButton);
		await waitForOpenFileState('ready');
		await waitForSelectedDisplayPath('File-001.swift');
		await waitForVisibleCodeText('lateClickedSelection');

		expect(openFilePath()).toBe('File-001.swift');
		expect(descriptorRequests).toHaveLength(1);
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/late-clicked-content?generation=1',
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
		await actUpdate((): void => {
			window.dispatchEvent(
				new CustomEvent('bridge-worktree-file-recently-updated', {
					detail: {
						path: 'src/recently-updated.ts',
						proximity: 'nearby',
						sourceIdentity: 'dev-worktree-source',
					},
				}),
			);
		});
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
		await actFrame();

		await waitForBridgeViewerTreeItemButton('Sources/AgentStudio/App/AppDelegate.swift');
		await actUpdate((): void => {
			window.dispatchEvent(
				new CustomEvent('bridge-worktree-file-recently-updated', {
					detail: {
						path: 'Sources/AgentStudio/App/AppDelegate.swift',
						proximity: 'nearby',
						sourceIdentity: 'dev-worktree-source',
					},
				}),
			);
		});
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

	test('clears inactive recently updated demand so visible warming can settle after reactivation', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'recently-updated-inactive-content',
			fileId: 'file-app-delegate',
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'visible-after-reactivate-content',
			fileId: 'file-app-delegate',
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
		});
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		const fetchedResourceUrls: string[] = [];
		const firstDeferredContent = makeDeferredContent();
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;
		let publishFrames: PublishWorktreeFileFrames | null = null;

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
					fetchResource={(props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						if (props.resourceUrl.includes('recently-updated-inactive-content')) {
							return firstDeferredContent.promise;
						}
						return Promise.resolve(
							makeWorktreeFileSurfaceRuntimeFetchedResource(
								'export const visibleAfterReactivate = true;\n',
							),
						);
					}}
					initialFrames={makeTreeRowsOnlyFrames()}
					isActive={isActive}
					requestFileDescriptor={(request) => {
						descriptorRequests.push(request);
						const publishRequiredFrames = requireFramePublisher(publishFrames);
						publishRequiredFrames(makeFileDescriptorFrame(firstDescriptor, { sequence: 1 }));
					}}
					subscribeFrames={(handler): (() => void) => {
						publishFrames = handler;
						return (): void => {
							publishFrames = null;
						};
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);
		await actFrame();

		await waitForBridgeViewerTreeItemButton('Sources/AgentStudio/App/AppDelegate.swift');
		await actUpdate((): void => {
			window.dispatchEvent(
				new CustomEvent('bridge-worktree-file-recently-updated', {
					detail: {
						path: 'Sources/AgentStudio/App/AppDelegate.swift',
						proximity: 'nearby',
						sourceIdentity: 'dev-worktree-source',
					},
				}),
			);
		});
		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});
		await waitForRecordedFetchCount({
			expectedCount: 1,
			recordedFetches: fetchedResourceUrls,
		});
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate((): void => {
			firstDeferredContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource(
					'export const shouldNotBlockVisible = true;\n',
				),
			);
		});
		await actFrame();
		await actFrame();

		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await actUpdate((): void => {
			requireFramePublisher(publishFrames)(
				makeFileDescriptorFrame(replacementDescriptor, { sequence: 2 }),
			);
		});

		await waitForRecordedFetchCount({
			expectedCount: 2,
			recordedFetches: fetchedResourceUrls,
		});
		await waitForDemandDispatchFirstLane('visible');
		await waitForDemandDispatchFirstFreshnessKeyContaining('visible-after-reactivate-content');

		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/visible-after-reactivate-content?generation=1',
		);
	});
});
