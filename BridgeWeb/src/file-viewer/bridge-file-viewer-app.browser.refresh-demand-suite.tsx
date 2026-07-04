import { useState, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { requireBridgeViewerHTMLElement } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
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
	type PublishWorktreeFileFrames,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	actUpdate,
	makeDeferredContent,
	openFileBodyPreview,
	openFileState,
	requireActivateFiles,
	requireDeactivateFiles,
	requireFramePublisher,
	visibleCodeText,
	waitForDemandDispatchFirstFreshnessKeyContaining,
	waitForDemandDispatchLoadedCount,
	waitForFileViewerActiveState,
	waitForOpenFileState,
	waitForRecordedFetchCount,
	waitForRefreshDebugState,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp Browser Mode', () => {
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
		await actUpdate((): void => {
			oldDeferredContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource('export const old = true;\n'),
			);
		});
		await waitForDemandDispatchFirstFreshnessKeyContaining('old-first-delayed-content');
		const publishRequiredFrames = requireFramePublisher(publishFrames);
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(newFirstDescriptor, newSecondDescriptor));
		});
		await waitForRecordedFetchCount({
			expectedCount: 4,
			recordedFetches: fetchedResourceUrls,
		});
		await actUpdate((): void => {
			newDeferredContent.resolve(
				makeWorktreeFileSurfaceRuntimeFetchedResource('export const fresh = true;\n'),
			);
		});
		await waitForDemandDispatchLoadedCount('2');
		await actFrame();
		await actFrame();

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

	test('renders replacement file body after a silent auto refresh of stale content', async () => {
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
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(replacementDescriptor));
		});
		// Stale open files auto-refresh silently (no comment drafts exist yet):
		// wait on the refreshed content itself, since 'ready' also describes
		// the pre-reset state and the stale/refreshing states are transient.
		await waitForVisibleCodeText('export const refreshed = true;');
		await waitForOpenFileState('ready');
		expect(document.querySelector('[data-testid="worktree-file-refresh"]')).toBeNull();
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

	test('does not repeat silent auto refresh for the same stale descriptor after failure', async () => {
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
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					if (props.resourceUrl.includes('failed-refresh-content-2')) {
						throw new Error('failed refresh canary');
					}
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const failedRefreshInitial = true;\n',
					);
				}}
				initialFrames={makeFrames(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/failed-refresh-target.ts')}
				subscribeFrames={(handler): (() => void) => {
					publishFrames = handler;
					return (): void => {
						publishFrames = null;
					};
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
		await waitForRefreshDebugState({
			commitState: 'skipped',
			result: 'duplicate_stale_auto_refresh_failure',
		});

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-refresh-result')).toBe(
			'duplicate_stale_auto_refresh_failure',
		);
		expect(shell.getAttribute('data-last-refresh-commit-state')).toBe('skipped');
		expect(shell.getAttribute('data-last-refresh-descriptor-id')).toBe('failed-refresh-content-2');
		expect(shell.getAttribute('data-last-refresh-current-request-id')).toBe(
			shell.getAttribute('data-last-refresh-request-id'),
		);
		expect(openFileState()).toBe('stale');
		expect(visibleCodeText()).toContain('failedRefreshInitial');
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
		await actUpdate((): void => {
			publishRequiredFrames(makeResetFrames(replacementDescriptor));
		});
		// The stale state auto-refreshes silently; the deferred fetch holds it
		// in 'refreshing' so deactivation can race the completion.
		await waitForOpenFileState('refreshing');
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
		expect(openFileBodyPreview()).toContain('inactiveRefreshInitial');
		expect(visibleCodeText()).toContain('inactiveRefreshInitial');
		expect(visibleCodeText()).not.toContain('inactiveRefreshReplacement');
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-file-viewer-active')).toBe('false');
		expect(shell.getAttribute('data-last-refresh-commit-state')).toBe('ignored');

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
				fetchResource={async () =>
					makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const sourceSnapshotDemandInitial = true;\n',
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
