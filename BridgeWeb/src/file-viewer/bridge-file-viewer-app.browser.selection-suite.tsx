import { useState, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import type { FileMetadataInterestUpdate } from './bridge-file-viewer-browser-test-fixtures.js';
import { makeFileContent } from './bridge-file-viewer-browser-test-fixtures.js';
import {
	fileNavigationCommandForPath,
	makeFileDescriptor,
	makeDescriptorReadyMetadataEvents,
	makeFileMetadataEvents,
	makeTreeRowsOnlyMetadataEvents,
	makeTreeWindowMetadataEvent,
	type PublishFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actClick,
	actFrame,
	actUpdate,
	fileCanvasRenderedTextOffset,
	makeDeferredContent,
	makeGeneratedFileBody,
	metadataInterestPathsForLane,
	openFileBodyPreview,
	openFilePath,
	renderedFilePath,
	requireMetadataPublisher,
	requireOpenSlowFile,
	settleBridgeFileViewerBrowserInteraction,
	settleBridgeFileViewerBrowserUpdates,
	selectedDisplayPath,
	visibleCodeText,
	waitForMetadataInterestUpdateCount,
	waitForFileCodeViewScrollable,
	waitForFileCodeViewScrollOwner,
	waitForFileCodeViewViewport,
	waitForOpenFileBodyPreview,
	waitForOpenFileState,
	waitForOpenedContentCount,
	waitForSelectedDisplayPath,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp Browser Mode', () => {
	afterEach(async () => {
		await actUpdate((): void => {
			cleanup();
		});
		await settleBridgeFileViewerBrowserUpdates();
		await actFrame();
		document.body.replaceChildren();
		terminateBridgePierreWorkerPoolSingletonForTest();
	});

	test('advances selected path immediately while metadata-only content converges', async () => {
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
		const metadataInterestUpdates: FileMetadataInterestUpdate[] = [];
		const openedDescriptorIds: string[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initiallyOpenDescriptor)}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent(
							props.descriptor.descriptorId.includes('clicked-content')
								? 'export const clickedSelection = true;\n'
								: 'export const initiallyOpen = true;\n',
						);
					},
					onMetadataInterestUpdate: (request) => {
						metadataInterestUpdates.push(request);
					},
					onMetadataSubscription: (handler): (() => void) => {
						publishMetadataEvents = handler;
						return (): void => {
							publishMetadataEvents = null;
						};
					},
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('initiallyOpen');

		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents([
				makeTreeWindowMetadataEvent({ rowCount: 1, sequence: 2, startIndex: 1, totalPathCount: 3 }),
			]);
		});
		const clickedButton = await waitForBridgeViewerTreeItemButton('File-001.swift');
		await actClick(clickedButton);
		await waitForMetadataInterestUpdateCount({
			expectedCount: 1,
			metadataInterestUpdates: metadataInterestUpdates,
		});

		await actUpdate((): void => {
			publishRequiredMetadataEvents([
				makeTreeWindowMetadataEvent({ rowCount: 1, sequence: 3, startIndex: 2, totalPathCount: 3 }),
			]);
		});
		await actFrame();
		await actFrame();
		expect(selectedDisplayPath()).toBe('File-001.swift');
		expect(openFilePath()).toBe('File-001.swift');
		expect(renderedFilePath()).toBeNull();
		expect(openFileBodyPreview()).toBeNull();
		expect(visibleCodeText()).not.toContain('export const initiallyOpen = true;');

		await actUpdate((): void => {
			publishRequiredMetadataEvents(
				makeDescriptorReadyMetadataEvents(clickedDescriptor, { sequence: 4 }),
			);
		});
		await waitForOpenFileState('ready');
		await waitForSelectedDisplayPath('File-001.swift');
		await waitForVisibleCodeText('clickedSelection');

		const finalInterestUpdate = metadataInterestUpdates.at(-1);
		if (finalInterestUpdate === undefined)
			throw new Error('Expected final File metadata interest.');
		expect(metadataInterestPathsForLane(finalInterestUpdate, 'foreground')).toEqual([
			'File-001.swift',
		]);
		expect(finalInterestUpdate?.pathScope).toEqual([]);
		expect(openedDescriptorIds).toContain('clicked-content');
	});

	test('keeps one foreground interest for a selected metadata-only descriptor until it converges', async () => {
		const initiallyOpenDescriptor = makeFileDescriptor({
			contentHandle: 'initial-content',
			fileId: 'file-000',
			path: 'File-000.swift',
		});
		const metadataInterestUpdates: FileMetadataInterestUpdate[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initiallyOpenDescriptor)}
				fileProductSession={{
					readContent: async () => makeFileContent('export const initiallyOpen = true;\n'),
					onMetadataInterestUpdate: (request) => {
						metadataInterestUpdates.push(request);
					},
					onMetadataSubscription: (handler): (() => void) => {
						publishMetadataEvents = handler;
						return (): void => {
							publishMetadataEvents = null;
						};
					},
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('initiallyOpen');
		await actUpdate((): void => {
			requireMetadataPublisher(publishMetadataEvents)([
				makeTreeWindowMetadataEvent({ rowCount: 1, sequence: 2, startIndex: 1, totalPathCount: 2 }),
			]);
		});

		const clickedButton = await waitForBridgeViewerTreeItemButton('File-001.swift');
		const updateCountBeforeClick = metadataInterestUpdates.length;
		await actClick(clickedButton);
		await waitForMetadataInterestUpdateCount({
			expectedCount: updateCountBeforeClick + 1,
			metadataInterestUpdates: metadataInterestUpdates,
		});
		await waitForSelectedDisplayPath('File-001.swift');
		await settleBridgeFileViewerBrowserInteraction();
		const settledUpdateCountAfterFirstSelection = metadataInterestUpdates.length;
		await actClick(clickedButton);
		await settleBridgeFileViewerBrowserInteraction();

		expect(metadataInterestUpdates).toHaveLength(settledUpdateCountAfterFirstSelection);
		const selectedInterestUpdate = metadataInterestUpdates.at(-1);
		if (selectedInterestUpdate === undefined) {
			throw new Error('Expected selected File metadata interest.');
		}
		expect(metadataInterestPathsForLane(selectedInterestUpdate, 'foreground')).toEqual([
			'File-001.swift',
		]);
		expect(selectedInterestUpdate?.pathScope).toEqual([]);
	});

	test('auto-opens the first metadata-only file row by requesting its descriptor', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'app-delegate-content',
			fileId: 'file-app-delegate',
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
		});
		const metadataInterestUpdates: FileMetadataInterestUpdate[] = [];
		const openedDescriptorIds: string[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent('export const autoOpenedMetadataRow = true;\n');
					},
					onMetadataInterestUpdate: (request) => {
						metadataInterestUpdates.push(request);
						const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
						publishRequiredMetadataEvents(
							makeDescriptorReadyMetadataEvents(descriptor, { sequence: 1 }),
						);
					},
					onMetadataSubscription: (handler): (() => void) => {
						publishMetadataEvents = handler;
						return (): void => {
							publishMetadataEvents = null;
						};
					},
				}}
			/>,
		);

		await waitForMetadataInterestUpdateCount({
			expectedCount: 1,
			metadataInterestUpdates: metadataInterestUpdates,
		});
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('autoOpenedMetadataRow');

		expect(metadataInterestUpdates.at(-1)).toEqual({
			interests: [{ lane: 'foreground', paths: ['Sources/AgentStudio/App/AppDelegate.swift'] }],
			pathScope: [],
		});
		expect(openedDescriptorIds).toEqual(['app-delegate-content']);
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
		const openedDescriptorIds: string[] = [];

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile={true}
				initialMetadataEvents={makeFileMetadataEvents(firstDescriptor, targetDescriptor)}
				navigationCommand={fileNavigationCommandForPath('docs/target.ts')}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent(
							props.descriptor.descriptorId.includes('target-content')
								? 'export const target = true;\n'
								: 'export const first = true;\n',
						);
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
		expect(openedDescriptorIds).toEqual(['target-content']);
	});

	test('requests a metadata-only navigation target descriptor on the foreground lane', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'app-delegate-navigation-content',
			fileId: 'file-app-delegate',
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
		});
		const metadataInterestUpdates: FileMetadataInterestUpdate[] = [];
		const openedDescriptorIds: string[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile={true}
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
				navigationCommand={fileNavigationCommandForPath(
					'Sources/AgentStudio/App/AppDelegate.swift',
				)}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent('export const navigationTargetFromMetadata = true;\n');
					},
					onMetadataInterestUpdate: (request) => {
						metadataInterestUpdates.push(request);
						requireMetadataPublisher(publishMetadataEvents)(
							makeDescriptorReadyMetadataEvents(descriptor, { sequence: 1 }),
						);
					},
					onMetadataSubscription: (handler): (() => void) => {
						publishMetadataEvents = handler;
						return (): void => {
							publishMetadataEvents = null;
						};
					},
				}}
			/>,
		);

		await waitForMetadataInterestUpdateCount({
			expectedCount: 1,
			metadataInterestUpdates: metadataInterestUpdates,
		});
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('navigationTargetFromMetadata');

		expect(metadataInterestUpdates.at(-1)).toEqual({
			interests: [{ lane: 'foreground', paths: ['Sources/AgentStudio/App/AppDelegate.swift'] }],
			pathScope: [],
		});
		expect(openedDescriptorIds).toEqual(['app-delegate-navigation-content']);
		expect(openFilePath()).toBe('Sources/AgentStudio/App/AppDelegate.swift');
	});

	test('auto-opens the first descriptor when native metadata streams after the initial snapshot', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'streamed-content',
			fileId: 'file-streamed',
			path: 'src/streamed.ts',
		});
		const metadataEvents = makeFileMetadataEvents(descriptor);
		const sourceAcceptedEvent = metadataEvents[0];
		const remainingMetadataEvents = metadataEvents.slice(1);
		if (sourceAcceptedEvent === undefined || remainingMetadataEvents.length === 0) {
			throw new Error('Expected source acceptance and subsequent File metadata events.');
		}
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;
		const openedDescriptorIds: string[] = [];

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile={true}
				initialMetadataEvents={[sourceAcceptedEvent]}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent('export const streamed = true;\n');
					},
					onMetadataSubscription: (handler): (() => void) => {
						publishMetadataEvents = handler;
						return (): void => {
							publishMetadataEvents = null;
						};
					},
				}}
			/>,
		);

		await actFrame();
		await actUpdate((): void => {
			requireMetadataPublisher(publishMetadataEvents)(remainingMetadataEvents);
		});

		await waitForOpenFileState('ready');

		expect(openFilePath()).toBe('src/streamed.ts');
		expect(openedDescriptorIds).toEqual(['streamed-content']);
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
				initialMetadataEvents={makeFileMetadataEvents(targetDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/plain.ts')}
				fileProductSession={{
					readContent: async () => makeFileContent('export const plain = true;\n'),
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const plain = true;');

		expect(fileCanvasRenderedTextOffset('export const plain')).not.toBeNull();
		expect(fileCanvasRenderedTextOffset('export const plain')).toBeLessThanOrEqual(4);
	});

	test('keeps the File CodeView viewport mounted after a warmed shell while selected file content loads', async () => {
		const warmDescriptor = makeFileDescriptor({
			contentHandle: 'warm-content',
			fileId: 'file-warm',
			path: 'src/warm.ts',
		});
		render(
			<BridgeFileViewerApp
				initialMetadataEvents={makeFileMetadataEvents(warmDescriptor)}
				fileProductSession={{
					readContent: async () => makeFileContent('export const warm = true;\n'),
				}}
			/>,
		);
		await waitForFileCodeViewViewport();
		await actUpdate((): void => {
			cleanup();
		});
		await actFrame();

		const targetDescriptor = makeFileDescriptor({
			contentHandle: 'slow-content',
			fileId: 'file-slow',
			path: 'src/slow.ts',
		});
		const deferredContent = makeDeferredContent();
		const openedDescriptorIds: string[] = [];
		let currentSourceSettled = false;
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
					initialMetadataEvents={makeFileMetadataEvents(targetDescriptor)}
					{...(navigationCommand === undefined ? {} : { navigationCommand })}
					fileProductSession={{
						currentSource: async () => {
							await waitForBridgeViewerAnimationFrame();
							currentSourceSettled = true;
							return {
								status: 'available',
								source: {
									cwdScope: null,
									freshness: 'live',
									includeStatuses: true,
									repoId: '00000000-0000-4000-8000-000000000001',
									rootPathToken: 'browser-test-root',
									worktreeId: '00000000-0000-4000-8000-000000000002',
								},
							};
						},
						readContent: (props) => {
							openedDescriptorIds.push(props.descriptor.descriptorId);
							return deferredContent.promise;
						},
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);

		const idleViewport = await waitForFileCodeViewViewport();
		expect(currentSourceSettled).toBe(true);
		const openRequiredSlowFile = requireOpenSlowFile(openSlowFile);
		await actUpdate(openRequiredSlowFile);
		await waitForOpenFileState('loading');
		await waitForOpenedContentCount({
			expectedCount: 1,
			openedDescriptorIds: openedDescriptorIds,
		});
		expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBe(
			idleViewport,
		);
		expect(openedDescriptorIds).toContain('slow-content');
		expect(document.querySelector('[data-testid="bridge-file-viewer-content-state"]')).toBeNull();
		expect(document.body.textContent ?? '').not.toContain('Loading file');

		await actUpdate((): void => {
			deferredContent.resolve(makeFileContent('export const slow = true;\n'));
		});
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
					initialMetadataEvents={makeFileMetadataEvents(targetDescriptor)}
					navigationCommand={fileNavigationCommandForPath('src/large-loading.ts')}
					fileProductSession={{
						readContent: () => deferredContent.promise,
					}}
				/>
			</div>,
		);

		await waitForOpenFileState('loading');
		const scrollOwner = await waitForFileCodeViewScrollOwner();
		await waitForFileCodeViewScrollable(scrollOwner);

		expect(scrollOwner.scrollHeight).toBeGreaterThan(scrollOwner.clientHeight + 32);

		await actUpdate((): void => {
			deferredContent.resolve(makeFileContent('export const largeLoading = true;\n'));
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
					initialMetadataEvents={makeFileMetadataEvents(firstDescriptor, secondDescriptor)}
					navigationCommand={navigationCommand}
					fileProductSession={{
						readContent: (props) =>
							props.descriptor.descriptorId.includes('second-slow-content')
								? deferredSecondContent.promise
								: Promise.resolve(makeFileContent('export const firstRetained = true;\n')),
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
			deferredSecondContent.resolve(makeFileContent('export const secondSlow = true;\n'));
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
					initialMetadataEvents={makeFileMetadataEvents(firstDescriptor, secondDescriptor)}
					navigationCommand={navigationCommand}
					fileProductSession={{
						readContent: (props) =>
							props.descriptor.descriptorId.includes('second-large-retained-target-content')
								? deferredSecondContent.promise
								: Promise.resolve(makeFileContent(makeGeneratedFileBody('firstRetainedScroll', 8))),
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
				makeFileContent(makeGeneratedFileBody('secondLargeRetainedTarget', 575)),
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
					initialMetadataEvents={makeFileMetadataEvents(firstDescriptor, secondDescriptor)}
					navigationCommand={navigationCommand}
					fileProductSession={{
						readContent: (props) =>
							props.descriptor.descriptorId.includes('second-scroll-target-content')
								? deferredSecondContent.promise
								: Promise.resolve(makeFileContent(makeGeneratedFileBody('firstScrolled', 120))),
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
			deferredSecondContent.resolve(makeFileContent('export const secondScrollTarget = true;\n'));
		});
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const secondScrollTarget = true;');
		await actFrame();

		expect(scrollOwner.scrollTop).toBeLessThanOrEqual(1);
	});
});
