import { useState, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import type { WorktreeFileInitialSurface } from '../worktree-file-surface/worktree-file-app.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { BridgeFileViewerApp } from './bridge-file-viewer-app.js';
import {
	fileNavigationCommandForPath,
	makeFileDescriptor,
	makeFileDescriptorFrame,
	makeFrames,
	makeResetFrames,
	makeSnapshotFrame,
	makeSourceIdentity,
	makeSourceLessResetFrames,
	makeTreeRowsOnlyFrames,
	type PublishWorktreeFileFrames,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	makeDeferredContent,
	makeTestTelemetryRecorder,
	openFileBodyPreview,
	openFilePath,
	openFileState,
	refreshButtonIsDisabled,
	renderedFilePath,
	requireActivateFiles,
	requireDeactivateFiles,
	requireFramePublisher,
	selectedDisplayPath,
	visibleCodeText,
	waitForDemandDispatchFirstFreshnessKeyContaining,
	waitForDemandDispatchFirstLane,
	waitForDemandDispatchLoadedCount,
	waitForDemandDispatchState,
	waitForDescriptorRequestCount,
	waitForFileViewerActiveState,
	waitForInitialSurfaceLoadCount,
	waitForOpenFileState,
	waitForRecordedFetchCount,
	waitForRefreshButtonEnabled,
	waitForSelectedDisplayPath,
	waitForTelemetrySample,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp Browser Mode', () => {
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

		await waitForOpenFileState('loading');
		await waitForRecordedFetchCount({
			expectedCount: 1,
			recordedFetches: fetchedResourceUrls,
		});
		requireDeactivateFiles(deactivateFiles)();
		await waitForFileViewerActiveState('false');
		firstDeferredContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const loadedWhileInactive = true;\n'),
		);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

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

		requireActivateFiles(activateFiles)();
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
		await waitForRecordedFetchCount({
			expectedCount: 1,
			recordedFetches: fetchedResourceUrls,
		});
		requireDeactivateFiles(deactivateFiles)();
		await waitForFileViewerActiveState('false');
		firstDeferredContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const shouldNotBlockVisible = true;\n'),
		);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		requireActivateFiles(activateFiles)();
		await waitForFileViewerActiveState('true');
		requireFramePublisher(publishFrames)(
			makeFileDescriptorFrame(replacementDescriptor, { sequence: 2 }),
		);

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

	test('ignores stale refresh completion after Files becomes inactive', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'inactive-refresh-content-1',
			fileId: 'file-inactive-refresh-target',
			path: 'src/inactive-refresh-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'inactive-refresh-content-2',
			fileId: 'file-inactive-refresh-target',
			generation: 2,
			path: 'src/inactive-refresh-target.ts',
			sourceIdentity: resetSourceIdentity,
		});
		const deferredRefreshContent = makeDeferredContent();
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
						if (props.resourceUrl.includes('inactive-refresh-content-2')) {
							return deferredRefreshContent.promise;
						}
						return Promise.resolve(
							makeWorktreeFileSurfaceRuntimeFetchedResource(
								'export const inactiveRefreshInitial = true;\n',
							),
						);
					}}
					initialFrames={makeFrames(initialDescriptor)}
					isActive={isActive}
					navigationCommand={fileNavigationCommandForPath('src/inactive-refresh-target.ts')}
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
		await waitForVisibleCodeText('inactiveRefreshInitial');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		publishRequiredFrames(makeResetFrames(replacementDescriptor));
		await waitForOpenFileState('stale');
		const refreshButton = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="worktree-file-refresh"]'),
		);
		refreshButton.click();
		await waitForOpenFileState('refreshing');
		requireDeactivateFiles(deactivateFiles)();
		await waitForFileViewerActiveState('false');

		deferredRefreshContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource(
				'export const inactiveRefreshReplacement = true;\n',
			),
		);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(openFileState()).toBe('stale');
		expect(openFileBodyPreview()).toContain('inactiveRefreshInitial');
		expect(visibleCodeText()).toContain('inactiveRefreshInitial');
		expect(visibleCodeText()).not.toContain('inactiveRefreshReplacement');
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-file-viewer-active')).toBe('false');
		expect(shell.getAttribute('data-last-refresh-commit-state')).toBe('ignored');

		requireActivateFiles(activateFiles)();
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
