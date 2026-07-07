import { useState, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { requireBridgeViewerHTMLElement } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import {
	fileNavigationCommandForPath,
	makeFileDescriptor,
	makeFileDescriptorFrame,
	makeFrames,
	makeResetFrames,
	makeSnapshotFrame,
	makeSourceIdentity,
	makeSourceLessResetFrames,
	type PublishWorktreeFileFrames,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	actUpdate,
	makeDeferredContent,
	makeGeneratedFileBody,
	openFileBodyPreview,
	openFileState,
	requireActivateFiles,
	requireDeactivateFiles,
	waitForFileCodeViewScrollable,
	waitForFileCodeViewScrollOwner,
	requireFramePublisher,
	visibleCodeText,
	waitForDemandDispatchState,
	waitForFileViewerActiveState,
	waitForOpenFileState,
	waitForRecordedFetchCount,
	waitForRefreshDebugState,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';
import type { BridgeFileViewerRuntimeTransportFactory } from './bridge-file-viewer-render-snapshot-controller.js';

describe('BridgeFileViewerApp Browser Mode', () => {
	test('does not revive visible main-thread demand after a source reset', async () => {
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
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				initialFrames={makeFrames(oldFirstDescriptor, oldSecondDescriptor)}
				worktreeFileSurfaceTransport={{
					fetchResource: (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return Promise.resolve(
							makeWorktreeFileSurfaceRuntimeFetchedResource('unexpected visible fetch\n'),
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

		await waitForDemandDispatchState('idle');
		expect(fetchedResourceUrls).toEqual([]);
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(newFirstDescriptor, newSecondDescriptor));
		});
		await actFrame();
		await actFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(fetchedResourceUrls).toEqual([]);
		expect(shell.getAttribute('data-last-demand-dispatch-status')).toBe('idle');
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
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/refresh-target.ts')}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return makeWorktreeFileSurfaceRuntimeFetchedResource(
							props.resourceUrl.includes('refresh-content-2')
								? 'export const refreshed = true;\n'
								: 'export const initial = true;\n',
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

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const initial = true;');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(replacementDescriptor));
		});
		// The worker owns selected File View refresh after a source update:
		// wait on the refreshed content itself, since 'ready' also describes
		// the pre-reset state and the stale/loading states are transient.
		await waitForVisibleCodeText('export const refreshed = true;');
		await waitForOpenFileState('ready');
		expect(document.querySelector('[data-testid="worktree-file-refresh"]')).toBeNull();
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/refresh-content-2?cursor=cursor-2&generation=2',
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
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				initialFrames={makeFrames(initialDescriptor)}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return makeWorktreeFileSurfaceRuntimeFetchedResource(
							props.resourceUrl.includes('auto-refresh-content-2')
								? 'export const autoRefreshed = true;\n'
								: 'export const autoInitial = true;\n',
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

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('export const autoInitial = true;');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(replacementDescriptor));
		});
		await waitForVisibleCodeText('export const autoRefreshed = true;');
		await waitForOpenFileState('ready');

		expect(document.querySelector('[data-testid="worktree-file-refresh"]')).toBeNull();
		expect(fetchedResourceUrls).toContain(
			'agentstudio://resource/worktree-file/worktree.fileContent/auto-refresh-content-2?cursor=cursor-2&generation=2',
		);
		expect(openFileBodyPreview()).toContain('export const autoRefreshed = true;');
		expect(visibleCodeText()).not.toContain('export const autoInitial = true;');
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-refresh-result')).toBe('ok');
		expect(shell.getAttribute('data-last-refresh-commit-state')).toBe('committed');
		expect(shell.getAttribute('data-last-refresh-descriptor-id')).toBe('auto-refresh-content-2');
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
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<div style={{ display: 'grid', height: '360px', overflow: 'hidden', width: '960px' }}>
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					initialFrames={makeFrames(initialDescriptor)}
					navigationCommand={fileNavigationCommandForPath('src/refresh-scroll-target.ts')}
					worktreeFileSurfaceTransport={{
						fetchResource: async (props) =>
							makeWorktreeFileSurfaceRuntimeFetchedResource(
								props.resourceUrl.includes('refresh-scroll-content-2')
									? makeGeneratedFileBody('refreshedScroll', 140)
									: makeGeneratedFileBody('initialScroll', 140),
							),
						subscribeFrames: (handler): (() => void) => {
							publishFrames = handler;
							return (): void => {
								publishFrames = null;
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

		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(replacementDescriptor));
		});
		await waitForOpenFileState('ready');
		await waitForRefreshDebugState({
			commitState: 'committed',
			result: 'ok',
		});
		await waitForOpenFileState('ready');
		await actFrame();
		await actFrame();

		expect(openFileBodyPreview()).toContain('export const refreshedScrollLine001 = true;');
		expect(scrollOwner.scrollTop).toBeGreaterThanOrEqual(scrollTopBeforeRefresh - 1);
		expect(visibleCodeText()).not.toContain('export const initialScrollLine001 = true;');
	});

	test('does not repeat a failed worker source-update refresh without explicit user intent', async () => {
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
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/failed-refresh-target.ts')}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						if (props.resourceUrl.includes('failed-refresh-content-2')) {
							throw new Error('failed refresh canary');
						}
						return makeWorktreeFileSurfaceRuntimeFetchedResource(
							'export const failedRefreshInitial = true;\n',
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

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('failedRefreshInitial');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(replacementDescriptor));
		});
		await waitForOpenFileState('stale');
		await waitForRecordedFetchCount({
			expectedCount: 2,
			recordedFetches: fetchedResourceUrls,
		});
		await actFrame();
		await actFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-refresh-result')).toBeNull();
		expect(shell.getAttribute('data-last-refresh-commit-state')).toBeNull();
		expect(openFileState()).toBe('stale');
		expect(visibleCodeText()).not.toContain('failedRefreshReplacement');
		expect(
			fetchedResourceUrls.filter((url) => url.includes('failed-refresh-content-2')),
		).toHaveLength(1);
	});

	test('exits loading when selected File View worker health degrades', async () => {
		const targetDescriptor = makeFileDescriptor({
			contentHandle: 'degraded-worker-content',
			fileId: 'file-degraded-worker-target',
			path: 'src/degraded-worker-target.ts',
		});
		const degradedTransportFactory: BridgeFileViewerRuntimeTransportFactory = ({
			publishWorkerMessages,
		}) => ({
			dispatch: (): void => {
				publishWorkerMessages([
					{
						wireVersion: 1,
						direction: 'serverWorkerToMain',
						transferDescriptors: [],
						kind: 'health',
						requestId: 'browser-degraded-worker',
						status: 'degraded',
						message: 'browser worker startup failed',
					},
				]);
			},
			dispose: (): void => {},
		});

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				fileViewCommWorkerTransportFactory={degradedTransportFactory}
				initialFrames={makeFrames(targetDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/degraded-worker-target.ts')}
			/>,
		);

		await waitForOpenFileState('failed');
		expect(visibleCodeText()).not.toContain('Loading');
	});

	test('retries a stale same-file navigation target after worker source refresh failure', async () => {
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
		const fetchedResourceUrls: string[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;
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
					initialFrames={makeFrames(initialDescriptor)}
					navigationCommand={navigationCommand}
					worktreeFileSurfaceTransport={{
						fetchResource: async (props) => {
							fetchedResourceUrls.push(props.resourceUrl);
							if (props.resourceUrl.includes('failed-navigation-retry-content-2')) {
								replacementFetchAttemptCount += 1;
								if (replacementFetchAttemptCount === 1) {
									throw new Error('failed navigation retry canary');
								}
								return makeWorktreeFileSurfaceRuntimeFetchedResource(
									'export const failedNavigationRetryReplacement = true;\n',
								);
							}
							return makeWorktreeFileSurfaceRuntimeFetchedResource(
								'export const failedNavigationRetryInitial = true;\n',
							);
						},
						subscribeFrames: (handler): (() => void) => {
							publishFrames = handler;
							return (): void => {
								publishFrames = null;
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
			requireFramePublisher(publishFrames)(makeResetFrames(replacementDescriptor));
		});
		await waitForOpenFileState('stale');
		await waitForRecordedFetchCount({
			expectedCount: 2,
			recordedFetches: fetchedResourceUrls,
		});
		await waitForOpenFileState('stale');
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
			fetchedResourceUrls.filter((url) => url.includes('failed-navigation-retry-content-2')),
		).toHaveLength(2);
	});

	test('retries a failed same-file navigation target on a fresh command', async () => {
		const targetDescriptor = makeFileDescriptor({
			contentHandle: 'failed-open-retry-content',
			fileId: 'file-failed-open-retry-target',
			path: 'src/failed-open-retry-target.ts',
		});
		const fetchedResourceUrls: string[] = [];
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
					initialFrames={makeFrames(targetDescriptor)}
					navigationCommand={navigationCommand}
					worktreeFileSurfaceTransport={{
						fetchResource: async (props) => {
							fetchedResourceUrls.push(props.resourceUrl);
							fetchAttemptCount += 1;
							if (fetchAttemptCount === 1) {
								throw new Error('failed open retry canary');
							}
							return makeWorktreeFileSurfaceRuntimeFetchedResource(
								'export const failedOpenRetryRecovered = true;\n',
							);
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
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/failed-open-retry-content?cursor=cursor-1&generation=1',
			'agentstudio://resource/worktree-file/worktree.fileContent/failed-open-retry-content?cursor=cursor-1&generation=1',
		]);
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
					initialFrames={makeFrames(initialDescriptor)}
					isActive={isActive}
					navigationCommand={fileNavigationCommandForPath('src/inactive-refresh-target.ts')}
					worktreeFileSurfaceTransport={{
						fetchResource: (props) => {
							if (props.resourceUrl.includes('inactive-refresh-content-2')) {
								return deferredRefreshContent.promise;
							}
							return Promise.resolve(
								makeWorktreeFileSurfaceRuntimeFetchedResource(
									'export const inactiveRefreshInitial = true;\n',
								),
							);
						},
						subscribeFrames: (handler): (() => void) => {
							publishFrames = handler;
							return (): void => {
								publishFrames = null;
							};
						},
					}}
				/>
			);
		}

		render(<ControlledFileViewer />);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('inactiveRefreshInitial');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(replacementDescriptor));
		});
		// The worker source-update refresh is in flight while the visible
		// state remains stale, so deactivation can race the completion.
		await waitForOpenFileState('stale');
		await actUpdate(requireDeactivateFiles(deactivateFiles));
		await waitForFileViewerActiveState('false');

		await actUpdate((): void => {
			deferredRefreshContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource(
					'export const inactiveRefreshReplacement = true;\n',
				),
			);
		});
		await actFrame();
		await actFrame();

		expect(openFileState()).toBe('stale');
		expect(visibleCodeText()).toContain('inactiveRefreshInitial');
		expect(visibleCodeText()).not.toContain('inactiveRefreshReplacement');
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
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/stable-target.ts')}
				worktreeFileSurfaceTransport={{
					fetchResource: async () =>
						makeWorktreeFileSurfaceRuntimeFetchedResource('export const stable = true;\n'),
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
		await waitForVisibleCodeText('export const stable = true;');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(sameContentDescriptor));
		});

		await actFrame();
		await actFrame();
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
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/source-less-reset-target.ts')}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) =>
						makeWorktreeFileSurfaceRuntimeFetchedResource(
							props.resourceUrl.includes('source-snapshot-content-2')
								? 'export const sourceSnapshotFresh = true;\n'
								: 'export const sourceSnapshotInitial = true;\n',
						),
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
		await waitForVisibleCodeText('sourceSnapshotInitial');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames([
				makeSnapshotFrame({ sequence: 1, sourceIdentity: replacementSourceIdentity }),
			]);
		});

		await waitForOpenFileState('stale');
		expect(visibleCodeText()).toContain('sourceSnapshotInitial');

		await actUpdate((): void => {
			publishRequiredFrames([
				...makeFileDescriptorFrame(replacementDescriptor, { generation: 2, sequence: 2 }),
			]);
		});
		await waitForVisibleCodeText('sourceSnapshotFresh');
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
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/source-less-reset-target.ts')}
				worktreeFileSurfaceTransport={{
					fetchResource: async (props) =>
						makeWorktreeFileSurfaceRuntimeFetchedResource(
							props.resourceUrl.includes('source-less-reset-content-2')
								? 'export const sourceLessResetFresh = true;\n'
								: 'export const sourceLessResetInitial = true;\n',
						),
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
		await waitForVisibleCodeText('sourceLessResetInitial');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeSourceLessResetFrames());
		});

		await waitForOpenFileState('stale');
		await actFrame();
		await actFrame();
		expect(document.querySelector('[data-testid="worktree-file-refresh"]')).toBeNull();
		expect(descriptorRequests).toEqual([]);
		expect(visibleCodeText()).toContain('sourceLessResetInitial');

		await actUpdate((): void => {
			publishRequiredFrames([
				makeSnapshotFrame({ sequence: 1, sourceIdentity: resetSourceIdentity }),
				...makeFileDescriptorFrame(replacementDescriptor, { generation: 2, sequence: 2 }),
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
		const descriptorRequests: WorktreeFileDescriptorRequest[] = [];
		let publishFrames: PublishWorktreeFileFrames | null = null;

		render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/source-less-reset-target.ts')}
				worktreeFileSurfaceTransport={{
					fetchResource: async () =>
						makeWorktreeFileSurfaceRuntimeFetchedResource(
							'export const sourceSnapshotDemandInitial = true;\n',
						),
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
		await waitForVisibleCodeText('sourceSnapshotDemandInitial');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeSourceLessResetFrames());
		});
		await waitForOpenFileState('stale');
		expect(descriptorRequests).toEqual([]);

		await actUpdate((): void => {
			publishRequiredFrames([
				makeSnapshotFrame({ sequence: 1, sourceIdentity: resetSourceIdentity }),
			]);
		});

		await actFrame();
		await actFrame();
		expect(descriptorRequests).toEqual([
			expect.objectContaining({
				fileId: 'file-source-less-reset-target',
				lane: 'foreground',
				path: 'src/source-less-reset-target.ts',
				sourceIdentity: resetSourceIdentity,
			}),
		]);
	});
});
