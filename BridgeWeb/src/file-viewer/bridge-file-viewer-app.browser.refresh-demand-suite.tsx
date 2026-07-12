import { useState, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import { requireBridgeViewerHTMLElement } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import type { FileMetadataInterestUpdate } from './bridge-file-viewer-browser-test-fixtures.js';
import { makeFileContent } from './bridge-file-viewer-browser-test-fixtures.js';
import {
	fileNavigationCommandForPath,
	makeFileDescriptor,
	makeDescriptorReadyMetadataEvents,
	makeFileMetadataEvents,
	makeSourceReplacementMetadataEvents,
	makeSourceSnapshotMetadataEvents,
	makeSourceIdentity,
	makeSourceResetMetadataEvents,
	type PublishFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	actUpdate,
	makeDeferredContent,
	makeGeneratedFileBody,
	metadataInterestPathsForLane,
	openFileBodyPreview,
	openFileState,
	requireActivateFiles,
	requireDeactivateFiles,
	settleBridgeFileViewerBrowserUpdates,
	waitForFileCodeViewScrollable,
	waitForFileCodeViewScrollOwner,
	requireMetadataPublisher,
	visibleCodeText,
	waitForFileViewerActiveState,
	waitForMetadataPublisher,
	waitForOpenFileBodyPreview,
	waitForOpenFileState,
	waitForOpenedContentCount,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp Browser Mode', () => {
	afterEach(async () => {
		await settleBridgeFileViewerBrowserUpdates();
		await actUpdate(cleanup);
		document.body.replaceChildren();
	});

	test('does not open unselected content after a worker source replacement', async () => {
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
		const openedDescriptorIds: string[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				initialMetadataEvents={makeFileMetadataEvents(oldFirstDescriptor, oldSecondDescriptor)}
				fileProductSession={{
					readContent: (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return Promise.resolve(makeFileContent('unexpected visible fetch\n'));
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

		expect(openedDescriptorIds).toEqual([]);
		const publishRequiredMetadataEvents = await waitForMetadataPublisher(
			(): PublishFileMetadataEvents | null => publishMetadataEvents,
		);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(
				makeSourceReplacementMetadataEvents(newFirstDescriptor, newSecondDescriptor),
			);
		});
		await actFrame();
		await actFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(openedDescriptorIds).toEqual([]);
		expect(shell.getAttribute('data-last-demand-dispatch-status')).toBeNull();
		expect(shell.getAttribute('data-last-demand-dispatch-origin')).toBeNull();
		expect(shell.getAttribute('data-last-demand-dispatch-intent-count')).toBeNull();
	});

	test('renders replacement file body after a worker source-update refreshes stale content', async () => {
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
		const openedDescriptorIds: string[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/refresh-target.ts')}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent(
							props.descriptor.descriptorId.includes('refresh-content-2')
								? 'export const refreshed = true;\n'
								: 'export const initial = true;\n',
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

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const initial = true;');
		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(makeSourceReplacementMetadataEvents(replacementDescriptor));
		});
		// The worker owns selected File View refresh after a source update:
		// wait on the refreshed content itself, since 'ready' also describes
		// the pre-reset state and the stale/loading states are transient.
		await waitForVisibleCodeText('export const refreshed = true;');
		await waitForOpenFileState('ready');
		expect(document.querySelector('[data-testid="worktree-file-refresh"]')).toBeNull();
		expect(openedDescriptorIds).toContain('refresh-content-2');
		expect(openFileBodyPreview()).toContain('export const refreshed = true;');
		await waitForVisibleCodeText('export const refreshed = true;');

		expect(visibleCodeText()).not.toContain('export const initial = true;');
	});

	test('renders replacement file body after an auto-open worker source refresh', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'auto-refresh-content-1',
			fileId: 'file-auto-refresh-target',
			path: 'src/auto-refresh-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'auto-refresh-content-2',
			fileId: 'file-auto-refresh-target',
			generation: 2,
			path: 'src/auto-refresh-target.ts',
			sourceIdentity: resetSourceIdentity,
		});
		const openedDescriptorIds: string[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent(
							props.descriptor.descriptorId.includes('auto-refresh-content-2')
								? 'export const autoRefreshed = true;\n'
								: 'export const autoInitial = true;\n',
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

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const autoInitial = true;');
		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(makeSourceReplacementMetadataEvents(replacementDescriptor));
		});
		await waitForVisibleCodeText('export const autoRefreshed = true;');
		await waitForOpenFileState('ready');

		expect(document.querySelector('[data-testid="worktree-file-refresh"]')).toBeNull();
		expect(openedDescriptorIds).toContain('auto-refresh-content-2');
		expect(openFileBodyPreview()).toContain('export const autoRefreshed = true;');
		expect(visibleCodeText()).not.toContain('export const autoInitial = true;');
	});

	test('restores File CodeView scroll position after a same-path worker source refresh', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'refresh-scroll-content-1',
			fileId: 'file-refresh-scroll-target',
			lineCount: 140,
			path: 'src/refresh-scroll-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'refresh-scroll-content-2',
			fileId: 'file-refresh-scroll-target',
			generation: 2,
			lineCount: 140,
			path: 'src/refresh-scroll-target.ts',
			sourceIdentity: resetSourceIdentity,
		});
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<div style={{ display: 'grid', height: '360px', overflow: 'hidden', width: '960px' }}>
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
					navigationCommand={fileNavigationCommandForPath('src/refresh-scroll-target.ts')}
					fileProductSession={{
						readContent: async (props) =>
							makeFileContent(
								props.descriptor.descriptorId.includes('refresh-scroll-content-2')
									? makeGeneratedFileBody('refreshedScroll', 140)
									: makeGeneratedFileBody('initialScroll', 140),
							),
						onMetadataSubscription: (handler): (() => void) => {
							publishMetadataEvents = handler;
							return (): void => {
								publishMetadataEvents = null;
							};
						},
					}}
				/>
			</div>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const initialScrollLine001 = true;');
		const scrollOwner = await waitForFileCodeViewScrollOwner();
		await waitForFileCodeViewScrollable(scrollOwner);
		await actUpdate((): void => {
			scrollOwner.scrollTop = 320;
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		});
		const scrollTopBeforeRefresh = scrollOwner.scrollTop;
		expect(scrollTopBeforeRefresh).toBeGreaterThan(0);
		await actFrame();
		const visibleInitialText = visibleCodeText();
		const visibleInitialLine = /initialScrollLine(\d{3})/u.exec(visibleInitialText)?.[1];
		if (visibleInitialLine === undefined) {
			throw new Error(`Expected a visible initial scroll line; actual=${visibleInitialText}`);
		}

		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(makeSourceReplacementMetadataEvents(replacementDescriptor));
		});
		await waitForOpenFileBodyPreview('export const refreshedScrollLine001 = true;');
		await waitForVisibleCodeText(`export const refreshedScrollLine${visibleInitialLine} = true;`);
		await waitForOpenFileState('ready');
		await actFrame();
		await actFrame();

		expect(openFileBodyPreview()).toContain('export const refreshedScrollLine001 = true;');
		expect(scrollOwner.scrollTop).toBeGreaterThanOrEqual(scrollTopBeforeRefresh - 1);
		expect(visibleCodeText()).not.toContain('export const initialScrollLine001 = true;');
	});

	test('does not repeat a failed replacement content open without explicit user intent', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'failed-refresh-content-1',
			fileId: 'file-failed-refresh-target',
			path: 'src/failed-refresh-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'failed-refresh-content-2',
			fileId: 'file-failed-refresh-target',
			generation: 2,
			path: 'src/failed-refresh-target.ts',
			sourceIdentity: resetSourceIdentity,
		});
		const openedDescriptorIds: string[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/failed-refresh-target.ts')}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						if (props.descriptor.descriptorId.includes('failed-refresh-content-2')) {
							throw new Error('failed refresh canary');
						}
						return makeFileContent('export const failedRefreshInitial = true;\n');
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
		await waitForVisibleCodeText('failedRefreshInitial');
		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(makeSourceReplacementMetadataEvents(replacementDescriptor));
		});
		await waitForOpenFileState('failed');
		await waitForOpenedContentCount({
			expectedCount: 2,
			openedDescriptorIds: openedDescriptorIds,
		});
		await actFrame();
		await actFrame();

		expect(openFileState()).toBe('failed');
		expect(visibleCodeText()).not.toContain('failedRefreshReplacement');
		expect(
			openedDescriptorIds.filter((url) => url.includes('failed-refresh-content-2')),
		).toHaveLength(1);
	});

	test('exits loading when selected File View worker health degrades', async () => {
		const targetDescriptor = makeFileDescriptor({
			contentHandle: 'degraded-worker-content',
			fileId: 'file-degraded-worker-target',
			path: 'src/degraded-worker-target.ts',
		});
		const deferredContent = makeDeferredContent();
		let publishWorkerMessages:
			| ((messages: readonly BridgeWorkerServerToMainMessage[]) => void)
			| null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(targetDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/degraded-worker-target.ts')}
				fileProductSession={{
					readContent: () => deferredContent.promise,
					onWorkerMessagesPublisher: (publisher) => {
						publishWorkerMessages = publisher;
					},
				}}
			/>,
		);

		await waitForOpenFileState('loading');
		await actUpdate((): void => {
			const publisher = publishWorkerMessages;
			if (publisher === null) throw new Error('Expected File worker message publisher.');
			publisher([
				{
					direction: 'serverWorkerToMain',
					kind: 'health',
					message: 'browser worker startup failed',
					requestId: 'browser-degraded-worker',
					status: 'degraded',
					transferDescriptors: [],
					wireVersion: 1,
				},
			]);
		});
		await waitForOpenFileState('failed');
		expect(visibleCodeText()).not.toContain('Loading');
	});

	test('retries a failed same-file navigation target after worker source replacement failure', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'failed-navigation-retry-content-1',
			fileId: 'file-failed-navigation-retry-target',
			path: 'src/failed-navigation-retry-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'failed-navigation-retry-content-2',
			fileId: 'file-failed-navigation-retry-target',
			generation: 2,
			path: 'src/failed-navigation-retry-target.ts',
			sourceIdentity: resetSourceIdentity,
		});
		const openedDescriptorIds: string[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;
		let retryNavigation: (() => void) | null = null;
		let replacementFetchAttemptCount = 0;

		function ControlledFileViewer(): ReactElement {
			const [navigationCommand, setNavigationCommand] = useState<BridgeViewerNavigationCommand>(
				fileNavigationCommandForPath('src/failed-navigation-retry-target.ts'),
			);
			retryNavigation = (): void => {
				setNavigationCommand({
					...fileNavigationCommandForPath('src/failed-navigation-retry-target.ts'),
					commandId: 'test:file:src/failed-navigation-retry-target.ts:retry',
					commandKind: 'activateTarget',
				});
			};
			return (
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
					navigationCommand={navigationCommand}
					fileProductSession={{
						readContent: async (props) => {
							openedDescriptorIds.push(props.descriptor.descriptorId);
							if (props.descriptor.descriptorId.includes('failed-navigation-retry-content-2')) {
								replacementFetchAttemptCount += 1;
								if (replacementFetchAttemptCount === 1) {
									throw new Error('failed navigation retry canary');
								}
								return makeFileContent('export const failedNavigationRetryReplacement = true;\n');
							}
							return makeFileContent('export const failedNavigationRetryInitial = true;\n');
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

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('failedNavigationRetryInitial');
		await actUpdate((): void => {
			requireMetadataPublisher(publishMetadataEvents)(
				makeSourceReplacementMetadataEvents(replacementDescriptor),
			);
		});
		await waitForOpenFileState('failed');
		await waitForOpenedContentCount({
			expectedCount: 2,
			openedDescriptorIds: openedDescriptorIds,
		});
		await waitForOpenFileState('failed');
		await actUpdate((): void => {
			const requiredRetryNavigation = retryNavigation;
			if (requiredRetryNavigation === null) {
				throw new Error('Expected retry navigation setter.');
			}
			requiredRetryNavigation();
		});

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('failedNavigationRetryReplacement');
		expect(
			openedDescriptorIds.filter((url) => url.includes('failed-navigation-retry-content-2')),
		).toHaveLength(2);
	});

	test('retries a failed same-file navigation target on a fresh command', async () => {
		const targetDescriptor = makeFileDescriptor({
			contentHandle: 'failed-open-retry-content',
			fileId: 'file-failed-open-retry-target',
			path: 'src/failed-open-retry-target.ts',
		});
		const openedDescriptorIds: string[] = [];
		let retryNavigation: (() => void) | null = null;
		let fetchAttemptCount = 0;

		function ControlledFileViewer(): ReactElement {
			const [navigationCommand, setNavigationCommand] = useState<BridgeViewerNavigationCommand>(
				fileNavigationCommandForPath('src/failed-open-retry-target.ts'),
			);
			retryNavigation = (): void => {
				setNavigationCommand({
					...fileNavigationCommandForPath('src/failed-open-retry-target.ts'),
					commandId: 'test:file:src/failed-open-retry-target.ts:retry',
					commandKind: 'activateTarget',
				});
			};
			return (
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					initialMetadataEvents={makeFileMetadataEvents(targetDescriptor)}
					navigationCommand={navigationCommand}
					fileProductSession={{
						readContent: async (props) => {
							openedDescriptorIds.push(props.descriptor.descriptorId);
							fetchAttemptCount += 1;
							if (fetchAttemptCount === 1) {
								throw new Error('failed open retry canary');
							}
							return makeFileContent('export const failedOpenRetryRecovered = true;\n');
						},
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);

		await waitForOpenFileState('failed');
		await actUpdate((): void => {
			const requiredRetryNavigation = retryNavigation;
			if (requiredRetryNavigation === null) {
				throw new Error('Expected retry navigation setter.');
			}
			requiredRetryNavigation();
		});

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('failedOpenRetryRecovered');
		expect(openedDescriptorIds).toEqual(['failed-open-retry-content', 'failed-open-retry-content']);
	});

	test('continues worker-owned replacement content completion while Files is inactive', async () => {
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
					initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
					isActive={isActive}
					navigationCommand={fileNavigationCommandForPath('src/inactive-refresh-target.ts')}
					fileProductSession={{
						readContent: (props) => {
							if (props.descriptor.descriptorId.includes('inactive-refresh-content-2')) {
								return deferredRefreshContent.promise;
							}
							return Promise.resolve(
								makeFileContent('export const inactiveRefreshInitial = true;\n'),
							);
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

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('inactiveRefreshInitial');
		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(makeSourceReplacementMetadataEvents(replacementDescriptor));
		});
		await waitForOpenFileState('loading');
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');

		await actUpdate((): void => {
			deferredRefreshContent.resolve(
				makeFileContent('export const inactiveRefreshReplacement = true;\n'),
			);
		});
		await actFrame();
		await actFrame();

		expect(openFileState()).toBe('ready');
		expect(visibleCodeText()).not.toContain('inactiveRefreshInitial');
		expect(visibleCodeText()).toContain('inactiveRefreshReplacement');
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-file-viewer-active')).toBe('false');
		expect(shell.getAttribute('data-last-refresh-commit-state')).toBeNull();

		await actUpdate(requireActivateFiles(activateFiles));
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
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/stable-target.ts')}
				fileProductSession={{
					readContent: async () => makeFileContent('export const stable = true;\n'),
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
		await waitForVisibleCodeText('export const stable = true;');
		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(makeSourceReplacementMetadataEvents(sameContentDescriptor));
		});

		await actFrame();
		await actFrame();
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const stable = true;');
		expect(openFileState()).toBe('ready');
	});

	test('clears selected content while a new source snapshot replaces the active stream', async () => {
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
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/source-less-reset-target.ts')}
				fileProductSession={{
					readContent: async (props) =>
						makeFileContent(
							props.descriptor.descriptorId.includes('source-snapshot-content-2')
								? 'export const sourceSnapshotFresh = true;\n'
								: 'export const sourceSnapshotInitial = true;\n',
						),
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
		await waitForVisibleCodeText('sourceSnapshotInitial');
		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(
				makeSourceSnapshotMetadataEvents({
					sequence: 1,
					sourceIdentity: replacementSourceIdentity,
				}),
			);
		});

		await waitForOpenFileState('loading');
		expect(visibleCodeText()).not.toContain('sourceSnapshotInitial');

		await actUpdate((): void => {
			publishRequiredMetadataEvents([
				...makeDescriptorReadyMetadataEvents(replacementDescriptor, { generation: 2, sequence: 2 }),
			]);
		});
		await waitForVisibleCodeText('sourceSnapshotFresh');
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
		const metadataInterestUpdates: FileMetadataInterestUpdate[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/source-less-reset-target.ts')}
				fileProductSession={{
					readContent: async (props) =>
						makeFileContent(
							props.descriptor.descriptorId.includes('source-less-reset-content-2')
								? 'export const sourceLessResetFresh = true;\n'
								: 'export const sourceLessResetInitial = true;\n',
						),
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
		await waitForVisibleCodeText('sourceLessResetInitial');
		const interestUpdateCountBeforeReset = metadataInterestUpdates.length;
		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(makeSourceResetMetadataEvents());
		});

		await waitForOpenFileState('loading');
		await actFrame();
		await actFrame();
		expect(document.querySelector('[data-testid="worktree-file-refresh"]')).toBeNull();
		expect(metadataInterestUpdates).toHaveLength(interestUpdateCountBeforeReset);
		expect(visibleCodeText()).not.toContain('sourceLessResetInitial');

		await actUpdate((): void => {
			publishRequiredMetadataEvents([
				...makeSourceSnapshotMetadataEvents({ sequence: 1, sourceIdentity: resetSourceIdentity }),
				...makeDescriptorReadyMetadataEvents(replacementDescriptor, { generation: 2, sequence: 2 }),
			]);
		});

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('sourceLessResetFresh');
	});

	test('requests a replacement descriptor after source reset snapshot metadata arrives without descriptors', async () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'source-snapshot-demand-content-1',
			fileId: 'file-source-less-reset-target',
			path: 'src/source-less-reset-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const metadataInterestUpdates: FileMetadataInterestUpdate[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/source-less-reset-target.ts')}
				fileProductSession={{
					readContent: async () =>
						makeFileContent('export const sourceSnapshotDemandInitial = true;\n'),
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
		await waitForVisibleCodeText('sourceSnapshotDemandInitial');
		const interestUpdateCountBeforeReset = metadataInterestUpdates.length;
		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(makeSourceResetMetadataEvents());
		});
		await waitForOpenFileState('loading');
		expect(metadataInterestUpdates).toHaveLength(interestUpdateCountBeforeReset);

		await actUpdate((): void => {
			publishRequiredMetadataEvents(
				makeSourceSnapshotMetadataEvents({ sequence: 1, sourceIdentity: resetSourceIdentity }),
			);
		});

		await actFrame();
		await actFrame();
		const finalInterestUpdate = metadataInterestUpdates.at(-1);
		if (finalInterestUpdate === undefined)
			throw new Error('Expected final File metadata interest.');
		expect(metadataInterestPathsForLane(finalInterestUpdate, 'foreground')).toEqual([
			'src/source-less-reset-target.ts',
		]);
		expect(finalInterestUpdate?.pathScope).toEqual([]);
	});
});
