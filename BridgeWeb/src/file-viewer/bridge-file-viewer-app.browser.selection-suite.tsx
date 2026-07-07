import { useState, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import {
	fileNavigationCommandForPath,
	makeFileDescriptor,
	makeFileDescriptorFrame,
	makeFrames,
	makeSourceIdentity,
	makeTreeRowsOnlyFrames,
	makeTreeWindowFrame,
	type PublishWorktreeFileFrames,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actClick,
	actFrame,
	actUpdate,
	createBridgeFileViewerBrowserTestCommWorkerTransportFactory,
	fileCanvasRenderedTextOffset,
	makeDeferredContent,
	makeGeneratedFileBody,
	makeTestTelemetryRecorder,
	openFileBodyPreview,
	openFilePath,
	renderedFilePath,
	requireFramePublisher,
	requireOpenSlowFile,
	selectedDisplayPath,
	visibleCodeText,
	waitForDescriptorRequestCount,
	waitForFileCodeViewScrollable,
	waitForFileCodeViewScrollOwner,
	waitForFileCodeViewViewport,
	waitForOpenFileBodyPreview,
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
				initialFrames={makeFrames(initiallyOpenDescriptor)}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return makeWorktreeFileSurfaceRuntimeFetchedResource(
							props.resourceUrl.includes('clicked-content')
								? 'export const clickedSelection = true;\n'
								: 'export const initiallyOpen = true;\n',
						);
					},
					requestFileDescriptor: (request) => {
						descriptorRequests.push(request);
					},
					subscribeFrames: (handler): (() => void) => {
						publishFrames = handler;
						return (): void => {
							publishFrames = null;
						};
					},
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('initiallyOpen');

		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames([
				makeTreeWindowFrame({ rowCount: 1, sequence: 2, startIndex: 1, totalPathCount: 3 }),
			]);
		});
		const clickedButton = await waitForBridgeViewerTreeItemButton('File-001.swift');
		await actClick(clickedButton);
		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});

		await actUpdate((): void => {
			publishRequiredFrames([
				makeTreeWindowFrame({ rowCount: 1, sequence: 3, startIndex: 2, totalPathCount: 3 }),
			]);
		});
		await actFrame();
		await actFrame();
		expect(selectedDisplayPath()).toBe('File-000.swift');
		expect(openFilePath()).toBe('File-000.swift');
		expect(renderedFilePath()).toBe('File-000.swift');
		expect(openFileBodyPreview()).toContain('initiallyOpen');
		expect(visibleCodeText()).toContain('export const initiallyOpen = true;');

		await actUpdate((): void => {
			publishRequiredFrames(makeFileDescriptorFrame(clickedDescriptor, { sequence: 4 }));
		});
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
			'agentstudio://resource/worktree-file/worktree.fileContent/clicked-content?cursor=cursor-1&generation=1',
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
				initialFrames={makeFrames(initiallyOpenDescriptor)}
				worktreeFileSurfaceTransport={{
					fetchResource: async () =>
						makeWorktreeFileSurfaceRuntimeFetchedResource('export const initiallyOpen = true;\n'),
					requestFileDescriptor: (request) => {
						descriptorRequests.push(request);
					},
					subscribeFrames: (handler): (() => void) => {
						publishFrames = handler;
						return (): void => {
							publishFrames = null;
						};
					},
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('initiallyOpen');
		await actUpdate((): void => {
			requireFramePublisher(publishFrames)([
				makeTreeWindowFrame({ rowCount: 1, sequence: 2, startIndex: 1, totalPathCount: 2 }),
			]);
		});

		const clickedButton = await waitForBridgeViewerTreeItemButton('File-001.swift');
		await actClick(clickedButton);
		await waitForDescriptorRequestCount({
			expectedCount: 1,
			recordedRequests: descriptorRequests,
		});
		await waitForSelectedDisplayPath('File-000.swift');
		await actClick(clickedButton);
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
				initialFrames={makeTreeRowsOnlyFrames()}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return makeWorktreeFileSurfaceRuntimeFetchedResource(
							'export const autoOpenedMetadataRow = true;\n',
						);
					},
					requestFileDescriptor: (request) => {
						descriptorRequests.push(request);
						const publishRequiredFrames = requireFramePublisher(publishFrames);
						publishRequiredFrames(makeFileDescriptorFrame(descriptor, { sequence: 1 }));
					},
					subscribeFrames: (handler): (() => void) => {
						publishFrames = handler;
						return (): void => {
							publishFrames = null;
						};
					},
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
			'agentstudio://resource/worktree-file/worktree.fileContent/app-delegate-content?cursor=cursor-1&generation=1',
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
		const telemetrySamples: BridgeTelemetrySample[] = [];

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile={true}
				initialFrames={makeFrames(firstDescriptor, targetDescriptor)}
				navigationCommand={fileNavigationCommandForPath('docs/target.ts')}
				telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) => {
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
					},
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('target = true');

		expect(openFilePath()).toBe('docs/target.ts');
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-open-load-disposition')).toBeNull();
		const fileOpenReadySample = await waitForTelemetrySample({
			name: 'performance.bridge.web.file_open_ready',
			samples: telemetrySamples,
		});
		expect(fileOpenReadySample.stringAttributes).toMatchObject({
			'agentstudio.bridge.demand.disposition': 'worker-selected',
			'agentstudio.bridge.demand.lane': 'foreground',
			'agentstudio.bridge.phase': 'file_open_ready',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.viewer': 'file',
		});
		expect(
			fileOpenReadySample.numericAttributes['agentstudio.bridge.demand.request.sequence'],
		).toBeGreaterThan(0);
		expect(fileOpenReadySample.numericAttributes['agentstudio.bridge.source.generation']).toBe(1);
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/target-content?cursor=cursor-1&generation=1',
		]);
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
				initialFrames={makeTreeRowsOnlyFrames()}
				navigationCommand={fileNavigationCommandForPath(
					'Sources/AgentStudio/App/AppDelegate.swift',
				)}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return makeWorktreeFileSurfaceRuntimeFetchedResource(
							'export const navigationTargetFromMetadata = true;\n',
						);
					},
					requestFileDescriptor: (request) => {
						descriptorRequests.push(request);
						requireFramePublisher(publishFrames)(
							makeFileDescriptorFrame(descriptor, { sequence: 1 }),
						);
					},
					subscribeFrames: (handler): (() => void) => {
						publishFrames = handler;
						return (): void => {
							publishFrames = null;
						};
					},
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
			'agentstudio://resource/worktree-file/worktree.fileContent/app-delegate-navigation-content?cursor=cursor-1&generation=1',
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
				initialFrames={[snapshotFrame]}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return makeWorktreeFileSurfaceRuntimeFetchedResource('export const streamed = true;\n');
					},
					subscribeFrames: (handler): (() => void) => {
						publishFrames = handler;
						return (): void => {
							publishFrames = null;
						};
					},
				}}
			/>,
		);

		await actFrame();
		await actUpdate((): void => {
			requireFramePublisher(publishFrames)([descriptorFrame]);
		});

		await waitForOpenFileState('ready');

		expect(openFilePath()).toBe('src/streamed.ts');
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/streamed-content?cursor=cursor-1&generation=1',
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
				fileViewCommWorkerTransportFactory={createBridgeFileViewerBrowserTestCommWorkerTransportFactory(
					{
						fetchResource: async () =>
							makeWorktreeFileSurfaceRuntimeFetchedResource('export const plain = true;\n'),
					},
				)}
				initialFrames={makeFrames(targetDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/plain.ts')}
				worktreeFileSurfaceTransport={{
					fetchResource: async () =>
						makeWorktreeFileSurfaceRuntimeFetchedResource('export const plain = true;\n'),
				}}
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
		const fetchedResourceUrls: string[] = [];
		const telemetrySamples: BridgeTelemetrySample[] = [];
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
					initialFrames={makeFrames(targetDescriptor)}
					{...(navigationCommand === undefined ? {} : { navigationCommand })}
					telemetryRecorder={makeTestTelemetryRecorder(telemetrySamples)}
					worktreeFileSurfaceTransport={{
						fetchResource: (props) => {
							fetchedResourceUrls.push(props.resourceUrl);
							return deferredContent.promise;
						},
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);

		const idleViewport = await waitForFileCodeViewViewport();
		const openRequiredSlowFile = requireOpenSlowFile(openSlowFile);
		await actUpdate(openRequiredSlowFile);
		await waitForOpenFileState('loading');
		await waitForRecordedFetchCount({
			expectedCount: 1,
			recordedFetches: fetchedResourceUrls,
		});
		expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBe(
			idleViewport,
		);
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/slow-content?cursor=cursor-1&generation=1',
		);
		expect(document.querySelector('[data-testid="bridge-file-viewer-content-state"]')).toBeNull();
		expect(document.body.textContent ?? '').not.toContain('Loading file');

		await actUpdate((): void => {
			deferredContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource('export const slow = true;\n'),
			);
		});
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const slow = true;');
		const fileOpenReadySample = await waitForTelemetrySample({
			name: 'performance.bridge.web.file_open_ready',
			samples: telemetrySamples,
		});

		expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBe(
			idleViewport,
		);
		expect(
			telemetrySamples.filter((sample) => sample.name === 'performance.bridge.web.content_fetch'),
		).toEqual([]);
		expect(fileOpenReadySample.stringAttributes).toMatchObject({
			'agentstudio.bridge.content.role': 'file',
			'agentstudio.bridge.demand.disposition': 'worker-selected',
			'agentstudio.bridge.demand.lane': 'foreground',
			'agentstudio.bridge.phase': 'file_open_ready',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.viewer': 'file',
		});
		expect(
			fileOpenReadySample.numericAttributes['agentstudio.bridge.demand.request.sequence'],
		).toBeGreaterThan(0);
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
					initialFrames={makeFrames(targetDescriptor)}
					navigationCommand={fileNavigationCommandForPath('src/large-loading.ts')}
					worktreeFileSurfaceTransport={{
						fetchResource: () => deferredContent.promise,
					}}
				/>
			</div>,
		);

		await waitForOpenFileState('loading');
		const scrollOwner = await waitForFileCodeViewScrollOwner();
		await waitForFileCodeViewScrollable(scrollOwner);

		expect(scrollOwner.scrollHeight).toBeGreaterThan(scrollOwner.clientHeight + 32);

		await actUpdate((): void => {
			deferredContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource('export const largeLoading = true;\n'),
			);
		});
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
					initialFrames={makeFrames(firstDescriptor, secondDescriptor)}
					navigationCommand={navigationCommand}
					worktreeFileSurfaceTransport={{
						fetchResource: (props) =>
							props.resourceUrl.includes('second-slow-content')
								? deferredSecondContent.promise
								: Promise.resolve(
										makeWorktreeFileSurfaceRuntimeFetchedResource(
											'export const firstRetained = true;\n',
										),
									),
					}}
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
		await actUpdate(openRequiredSecondFile);

		await waitForOpenFileState('loading');

		expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBe(
			readyViewport,
		);
		expect(visibleCodeText()).not.toContain('export const firstRetained = true;');
		expect(openFileBodyPreview()).toBeNull();

		await actUpdate((): void => {
			deferredSecondContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource('export const secondSlow = true;\n'),
			);
		});
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
					initialFrames={makeFrames(firstDescriptor, secondDescriptor)}
					navigationCommand={navigationCommand}
					worktreeFileSurfaceTransport={{
						fetchResource: (props) =>
							props.resourceUrl.includes('second-large-retained-target-content')
								? deferredSecondContent.promise
								: Promise.resolve(
										makeWorktreeFileSurfaceRuntimeFetchedResource(
											makeGeneratedFileBody('firstRetainedScroll', 8),
										),
									),
					}}
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
		await actUpdate(openRequiredSecondFile);

		await waitForOpenFileState('loading');

		expect(visibleCodeText()).not.toContain('export const firstRetainedScrollLine001 = true;');
		expect(scrollOwner.scrollHeight).toBeGreaterThan(scrollOwner.clientHeight + 32);
		const loadingScrollHeight = scrollOwner.scrollHeight;
		await actUpdate((): void => {
			scrollOwner.scrollTop = Math.min(scrollOwner.scrollHeight - scrollOwner.clientHeight, 480);
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		});

		await actUpdate((): void => {
			deferredSecondContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource(
					makeGeneratedFileBody('secondLargeRetainedTarget', 575),
				),
			);
		});
		await waitForOpenFileState('ready');
		await waitForOpenFileBodyPreview('export const secondLargeRetainedTargetLine001 = true;');
		await actFrame();

		expect(Math.abs(scrollOwner.scrollHeight - loadingScrollHeight)).toBeLessThanOrEqual(1);
	});

	test('does not render retained file body while the next selected file content loads', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'first-scrolled-content',
			fileId: 'file-first-scrolled',
			lineCount: 120,
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
					initialFrames={makeFrames(firstDescriptor, secondDescriptor)}
					navigationCommand={navigationCommand}
					worktreeFileSurfaceTransport={{
						fetchResource: (props) =>
							props.resourceUrl.includes('second-scroll-target-content')
								? deferredSecondContent.promise
								: Promise.resolve(
										makeWorktreeFileSurfaceRuntimeFetchedResource(
											makeGeneratedFileBody('firstScrolled', 120),
										),
									),
					}}
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
		await actUpdate((): void => {
			scrollOwner.scrollTop = 320;
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		});
		expect(scrollOwner.scrollTop).toBeGreaterThan(0);

		const openRequiredSecondFile = requireOpenSlowFile(openSecondFile);
		await actUpdate(openRequiredSecondFile);
		await waitForOpenFileState('loading');
		await actFrame();
		await actFrame();

		expect(openFileBodyPreview()).toBeNull();

		await actUpdate((): void => {
			deferredSecondContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource('export const secondScrollTarget = true;\n'),
			);
		});
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const secondScrollTarget = true;');
		await actFrame();

		expect(scrollOwner.scrollTop).toBeLessThanOrEqual(1);
	});
});
