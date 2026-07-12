import { act, useState, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import {
	findBridgeViewerTreeItemButton,
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import type { FileMetadataInterestUpdate } from './bridge-file-viewer-browser-test-fixtures.js';
import { makeFileContent } from './bridge-file-viewer-browser-test-fixtures.js';
import {
	fileNavigationCommandForPath,
	makeFileDescriptor,
	makeDescriptorReadyMetadataEvents,
	makeFileMetadataEvents,
	makeSourceIdentity,
	makeTreeRow,
	makeTreeRowsOnlyMetadataEvents,
	parseFileMetadataEvent,
	type PublishFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actClick,
	actFrame,
	actUpdate,
	makeDeferredContent,
	openFileBodyPreview,
	openFilePath,
	openFileState,
	renderedFilePath,
	requireActivateFiles,
	requireDeactivateFiles,
	requireMetadataPublisher,
	selectedDisplayPath,
	visibleCodeText,
	waitForMetadataInterestUpdateCount,
	waitForFileViewerActiveState,
	waitForMetadataSubscriptionOpenCount,
	waitForMetadataTreeRowCount,
	waitForBridgeFileViewerWorkerMessageDrain,
	waitForOpenFileState,
	waitForOpenedContentCount,
	waitForSelectedDisplayPath,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp Browser Mode', () => {
	afterEach(async () => {
		await waitForBridgeFileViewerWorkerMessageDrain();
	});

	test('recovers a slow foreground navigation open after Files reactivates', async () => {
		const slowDescriptor = makeFileDescriptor({
			contentHandle: 'inactive-open-content',
			fileId: 'file-inactive-open',
			path: 'src/inactive-open.ts',
		});
		const firstDeferredContent = makeDeferredContent();
		const openedDescriptorIds: string[] = [];
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
					initialMetadataEvents={makeFileMetadataEvents(slowDescriptor)}
					isActive={isActive}
					navigationCommand={fileNavigationCommandForPath('src/inactive-open.ts')}
					fileProductSession={{
						readContent: (props) => {
							openedDescriptorIds.push(props.descriptor.descriptorId);
							return firstDeferredContent.promise;
						},
					}}
				/>
			);
		}

		await act(async (): Promise<void> => {
			render(<ControlledFileViewer />);
			await import('./bridge-file-viewer-shell.js');
			await Promise.resolve();
		});
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		await waitForOpenFileState('loading');
		await waitForOpenedContentCount({
			expectedCount: 1,
			openedDescriptorIds: openedDescriptorIds,
		});
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate((): void => {
			firstDeferredContent.resolve(makeFileContent('export const loadedWhileInactive = true;\n'));
		});
		await actFrame();
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-file-viewer-active')).toBe('false');
		expect(openFileState()).toBe('ready');
		expect(openFileBodyPreview()).toContain('loadedWhileInactive');
		expect(visibleCodeText()).toContain('loadedWhileInactive');

		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('loadedWhileInactive');
		await waitForBridgeFileViewerWorkerMessageDrain();
		expect(openFilePath()).toBe('src/inactive-open.ts');
		expect(openFileBodyPreview()).toContain('loadedWhileInactive');
	});

	test('does not repeat an aborted initial content open without fresh user intent', async () => {
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
		const openedDescriptorIds: string[] = [];
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
					initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
					isActive={isActive}
					fileProductSession={{
						readContent: (props) => {
							openedDescriptorIds.push(props.descriptor.descriptorId);
							if (openedDescriptorIds.length === 1) {
								return firstFetchPromise;
							}
							return Promise.resolve(makeFileContent('export const autoOpenRetried = true;\n'));
						},
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		await waitForOpenFileState('loading');
		await waitForOpenedContentCount({
			expectedCount: 1,
			openedDescriptorIds: openedDescriptorIds,
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
		await waitForBridgeFileViewerWorkerMessageDrain();
		expect(openFileState()).toBe('failed');

		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await waitForBridgeViewerTreeItemButton('src/auto-open-aborted.ts');

		await actFrame();
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();
		expect(openedDescriptorIds).toHaveLength(1);
		expect(openFileState()).toBe('failed');
		expect(openFilePath()).toBe('src/auto-open-aborted.ts');
		expect(openFileBodyPreview()).toBeNull();
	});

	test('preserves the streamed surface when Files becomes active again', async () => {
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;
		let metadataSubscriptionOpenCount = 0;

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
					initialMetadataEvents={makeFileMetadataEvents(
						makeFileDescriptor({
							contentHandle: 'content-1',
							fileId: 'file-1',
							path: 'src/file-1.ts',
						}),
					)}
					isActive={isActive}
					fileProductSession={{
						onMetadataSubscriptionOpen: () => {
							metadataSubscriptionOpenCount += 1;
						},
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		await waitForMetadataSubscriptionOpenCount({
			expectedCount: 1,
			getLoadCount: () => metadataSubscriptionOpenCount,
		});
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await actFrame();
		await actFrame();
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		expect(metadataSubscriptionOpenCount).toBe(1);
		await waitForBridgeViewerTreeItemButton('src/file-1.ts');
		await waitForBridgeFileViewerWorkerMessageDrain();
	});

	test('applies a tree delta pushed while Files is hidden without reloading the surface', async () => {
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;
		let metadataSubscriptionOpenCount = 0;
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

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
					initialMetadataEvents={makeFileMetadataEvents(
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
					)}
					isActive={isActive}
					fileProductSession={{
						onMetadataSubscriptionOpen: () => {
							metadataSubscriptionOpenCount += 1;
						},
						onMetadataSubscription: (handler): (() => void) => {
							publishMetadataEvents = handler;
							return (): void => {
								publishMetadataEvents = null;
							};
						},
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		await waitForMetadataSubscriptionOpenCount({
			expectedCount: 1,
			getLoadCount: () => metadataSubscriptionOpenCount,
		});
		await waitForMetadataTreeRowCount(2);
		await waitForBridgeViewerTreeItemButton('src/existing.ts');
		await waitForBridgeViewerTreeItemButton('src/removed.ts');

		// Hide Files (switch to Review), then push a tree delta while hidden.
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate((): void => {
			requireMetadataPublisher(publishMetadataEvents)([
				parseFileMetadataEvent({
					eventKind: 'file.treeDelta',
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
							rowIds: ['row:src:removed.ts'],
							paths: ['src/removed.ts'],
						},
					],
					source: makeSourceIdentity(),
				}),
			]);
		});
		await waitForBridgeFileViewerWorkerMessageDrain();

		// Show Files again (switch back to Review -> Files).
		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await waitForBridgeViewerTreeItemButton('src/added.ts');
		await waitForBridgeFileViewerWorkerMessageDrain();

		expect(findBridgeViewerTreeItemButton('src/removed.ts')).toBeNull();
		expect(findBridgeViewerTreeItemButton('src/existing.ts')).not.toBeNull();
		expect(metadataSubscriptionOpenCount).toBe(1);
	});

	test('opens clicked file content after Files reactivates with the preserved streamed surface', async () => {
		let activateFiles: (() => void) | null = null;
		let deactivateFiles: (() => void) | null = null;
		let metadataSubscriptionOpenCount = 0;
		const openedDescriptorIds: string[] = [];
		const reactivatedContent = makeDeferredContent();

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
					initialMetadataEvents={makeFileMetadataEvents(
						makeFileDescriptor({
							contentHandle: 'content-1',
							fileId: 'file-1',
							path: 'src/file-1.ts',
						}),
					)}
					isActive={isActive}
					fileProductSession={{
						readContent: (props) => {
							openedDescriptorIds.push(props.descriptor.descriptorId);
							return reactivatedContent.promise;
						},
						onMetadataSubscriptionOpen: () => {
							metadataSubscriptionOpenCount += 1;
						},
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		await waitForMetadataSubscriptionOpenCount({
			expectedCount: 1,
			getLoadCount: () => metadataSubscriptionOpenCount,
		});
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate(requireActivateFiles(activateFiles));
		await waitForFileViewerActiveState('true');
		await actFrame();
		await actFrame();
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		expect(metadataSubscriptionOpenCount).toBe(1);
		const reactivatedFileButton = await waitForBridgeViewerTreeItemButton('src/file-1.ts');
		await actClick(reactivatedFileButton);
		await waitForOpenedContentCount({
			expectedCount: 1,
			openedDescriptorIds: openedDescriptorIds,
		});
		await actUpdate((): void => {
			reactivatedContent.resolve(
				makeFileContent('export const reactivatedPreservedFile = true;\n'),
			);
		});

		await waitForOpenFileState('ready');
		await waitForSelectedDisplayPath('src/file-1.ts');
		await waitForVisibleCodeText('reactivatedPreservedFile');
		await actFrame();
		await actFrame();
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		expect(selectedDisplayPath()).toBe('src/file-1.ts');
		expect(openFilePath()).toBe('src/file-1.ts');
		expect(renderedFilePath()).toBe('src/file-1.ts');
		expect(openFileBodyPreview()).toContain('reactivatedPreservedFile');
		expect(openedDescriptorIds).toContain('content-1');
	});

	test('opens the inactive metadata subscription without main-thread demand', async () => {
		let metadataSubscriptionOpenCount = 0;
		let subscriptionInterestCount: number | null = null;
		let subscriptionPathScopeCount: number | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
				isActive={false}
				fileProductSession={{
					onMetadataSubscriptionOpen: (options) => {
						metadataSubscriptionOpenCount += 1;
						subscriptionInterestCount = options.interests.length;
						subscriptionPathScopeCount = options.pathScope.length;
					},
				}}
			/>,
		);
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		expect(metadataSubscriptionOpenCount).toBe(1);
		expect(subscriptionInterestCount).toBe(0);
		expect(subscriptionPathScopeCount).toBe(0);
	});

	test('does not open unselected descriptors while Files is inactive', async () => {
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
		const openedDescriptorIds: string[] = [];

		render(
			<BridgeFileViewerApp
				initialMetadataEvents={makeFileMetadataEvents(visibleDescriptor, updatedDescriptor)}
				isActive={false}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent('unexpected page-level event content open\n');
					},
				}}
			/>,
		);
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();
		expect(openFileState()).toBeNull();
		expect(openedDescriptorIds).toEqual([]);
	});

	test('requests visible metadata-only descriptors without opening their content', async () => {
		const metadataInterestUpdates: FileMetadataInterestUpdate[] = [];
		const openedDescriptorIds: string[] = [];

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent('export const recentlyUpdatedMetadataOnly = true;\n');
					},
					onMetadataInterestUpdate: (request) => {
						metadataInterestUpdates.push(request);
					},
				}}
			/>,
		);
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		await waitForBridgeViewerTreeItemButton('Sources/AgentStudio/App/AppDelegate.swift');
		await waitForMetadataInterestUpdateCount({
			expectedCount: 1,
			metadataInterestUpdates: metadataInterestUpdates,
		});
		await actFrame();
		await actFrame();
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		expect(metadataInterestUpdates.at(-1)).toEqual({
			interests: [{ lane: 'visible', paths: ['Sources/AgentStudio/App/AppDelegate.swift'] }],
			pathScope: [],
		});
		expect(openedDescriptorIds).toEqual([]);
		expect(openFileState()).toBeNull();
	});

	test('keeps metadata-only fulfillment from opening content while Files is inactive', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'recently-updated-inactive-content',
			fileId: 'file-app-delegate',
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
		});
		const metadataInterestUpdates: FileMetadataInterestUpdate[] = [];
		const openedDescriptorIds: string[] = [];
		let deactivateFiles: (() => void) | null = null;
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		function ControlledFileViewer(): ReactElement {
			const [isActive, setIsActive] = useState(true);
			deactivateFiles = (): void => {
				setIsActive(false);
			};
			return (
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
					isActive={isActive}
					fileProductSession={{
						readContent: (props) => {
							openedDescriptorIds.push(props.descriptor.descriptorId);
							return Promise.resolve(
								makeFileContent('export const visibleAfterReactivate = true;\n'),
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
				/>
			);
		}

		render(<ControlledFileViewer />);
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

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
		await waitForBridgeFileViewerWorkerMessageDrain();
		await waitForMetadataInterestUpdateCount({
			expectedCount: 1,
			metadataInterestUpdates: metadataInterestUpdates,
		});
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');
		await actUpdate((): void => {
			requireMetadataPublisher(publishMetadataEvents)(
				makeDescriptorReadyMetadataEvents(firstDescriptor, { sequence: 1 }),
			);
		});
		await waitForBridgeFileViewerWorkerMessageDrain();

		await actFrame();
		await actFrame();
		await actFrame();
		await waitForBridgeFileViewerWorkerMessageDrain();

		expect(openedDescriptorIds).toEqual([]);
	});
});
