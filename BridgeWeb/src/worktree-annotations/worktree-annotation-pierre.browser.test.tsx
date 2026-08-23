import {
	CodeView,
	parseDiffFromFile,
	type CodeViewItem,
	type CodeViewOptions,
} from '@pierre/diffs';
import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import type { BridgeMainCodeViewItem } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import { BridgeFileViewerCodePanel } from '../file-viewer/bridge-file-viewer-code-panel.js';
import type { BridgeFileViewerSelectedCodeViewItem } from '../file-viewer/bridge-file-viewer-code-view-items.js';
import {
	annotationBaseThreadId,
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import type { WorktreeAnnotationThreadContext } from './worktree-annotation-surface-client.js';
import { WorktreeAnnotationSurfaceProvider } from './worktree-annotation-surface-provider.js';
import { WorktreeAnnotationNewMessageComposer } from './worktree-annotation-thread.js';

const headMessageId = '00000000-0000-7000-8000-000000000021';
const baseMessageId = '00000000-0000-7000-8000-000000000022';
const headReplyMessageId = '00000000-0000-7000-8000-000000000023';

describe('worktree annotation Pierre integration', () => {
	test('opens the File root composer from Pierre selection with path and line origin', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const appliedOptions: CodeViewOptions<undefined>[] = [];
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetOptions = CodeView.prototype.setOptions;
		CodeView.prototype.setOptions = function captureOptions(
			options: CodeViewOptions<undefined> | undefined,
		): void {
			if (options !== undefined) appliedOptions.push(options);
			originalSetOptions.call(this, options);
		};
		const selectedCodeViewItem = makeFileItem();
		try {
			const rendered = await render(
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<BridgeFileViewerCodePanel
						codeViewWorkerPoolEnabled={false}
						openFileState={{
							displayItem: null,
							fileId: 'file-1',
							path: 'Sources/App/View.swift',
							status: 'ready',
						}}
						renderFulfillmentCoordinator={{
							observePostRender: (): void => {},
							reconcilePublication: (): void => {},
						}}
						selectedCodeViewItem={selectedCodeViewItem}
						totalHeightPixels={null}
					/>
				</WorktreeAnnotationSurfaceProvider>,
			);
			await settleBrowserCondition(
				(): boolean => appliedOptions.at(-1)?.onLineSelectionEnd !== undefined,
				'Expected File Pierre selection callback.',
			);
			await act(async (): Promise<void> => {
				invokeGutterAdmission(
					requireCodeViewOptions(appliedOptions.at(-1)),
					{ start: 4, end: 7 },
					selectedCodeViewItem,
				);
				await Promise.resolve();
			});
			const textbox = rendered.getByRole('textbox', { name: 'Write an annotation in Markdown' });
			await expect.element(textbox).toBeVisible();
			const textareaElement = textbox.element();
			const annotationContent = textareaElement
				.closest<HTMLElement>('[slot]')
				?.assignedSlot?.closest<HTMLElement>('[data-annotation-content]');
			const conversationFrame = textareaElement.closest<HTMLElement>(
				'[data-testid="worktree-annotation-conversation-frame"]',
			);
			if (
				annotationContent === null ||
				annotationContent === undefined ||
				conversationFrame === null
			) {
				throw new Error('Expected the shared annotation frame inside Pierre annotation content.');
			}
			const annotationBounds = annotationContent.getBoundingClientRect();
			const frameBounds = conversationFrame.getBoundingClientRect();
			const textareaBounds = textareaElement.getBoundingClientRect();
			expect(frameBounds.width).toBeLessThanOrEqual(768);
			expect(frameBounds.left - annotationBounds.left).toBeGreaterThanOrEqual(8);
			expect(textareaBounds.left - frameBounds.left).toBeGreaterThanOrEqual(12);
			await act(async (): Promise<void> => {
				await textbox.fill('File selection comment');
				await Promise.resolve();
			});
			await settleBrowserCondition(
				(): boolean => surface.sentOperations.some((operation) => operation.kind === 'root.create'),
				'Expected first File edit to issue root.create.',
			);
			const rootCreateOperation = surface.sentOperations.find(
				(operation) => operation.kind === 'root.create',
			);
			if (rootCreateOperation?.kind !== 'root.create') {
				throw new Error('Expected the File root.create operation.');
			}
			await act(async (): Promise<void> => {
				surface.publishProjection(1, 1);
				surface.publishThread({
					context: {
						diffSide: null,
						endLine: 7,
						path: 'Sources/App/View.swift',
						placement: 'exact',
						resolution: 'open',
						scope: 'located',
						sourceIdentity: 'descriptor-file-1',
						sourceRole: 'file',
						startLine: 4,
						threadId: annotationHeadThreadId,
					},
					message: {
						...annotationMessage({
							messageId: headMessageId,
							threadId: annotationHeadThreadId,
						}),
						draft: {
							activeEditToken: rootCreateOperation.editToken,
							body: 'File selection comment',
							revision: 1,
						},
						savedBody: null,
						savedRevision: null,
					},
				});
				await Promise.resolve();
			});
			await expect.element(textbox).toHaveValue('File selection comment');
			expect(
				document.querySelectorAll('[aria-label="Write an annotation in Markdown"]'),
			).toHaveLength(1);
			expect(
				surface.sentOperations.find((operation) => operation.kind === 'root.create'),
			).toMatchObject({
				origin: {
					endLine: 7,
					kind: 'located',
					path: 'Sources/App/View.swift',
					sourceIdentity: 'descriptor-file-1',
					sourceRole: 'file',
					startLine: 4,
				},
			});
			await act(async (): Promise<void> => {
				await userEvent.keyboard('{Escape}');
				await Promise.resolve();
			});
			await settleBrowserCondition(
				(): boolean =>
					surface.sentOperations.some((operation) => operation.kind === 'draft.edit.release'),
				'Expected collapsed File root draft to release its edit token.',
			);
			expect(
				surface.sentOperations.filter((operation) => operation.kind === 'draft.edit.release'),
			).toHaveLength(1);
		} finally {
			CodeView.prototype.setOptions = originalSetOptions;
		}
	});

	test('keeps the exact File reply editor mounted across atomic projection replacements', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rootMessage = annotationMessage({
			messageId: headMessageId,
			threadId: annotationHeadThreadId,
		});
		const context: WorktreeAnnotationThreadContext = {
			diffSide: null,
			endLine: 4,
			path: 'Sources/App/View.swift',
			placement: 'exact',
			resolution: 'open',
			scope: 'located',
			sourceIdentity: 'descriptor-file-1',
			sourceRole: 'file',
			startLine: 4,
			threadId: annotationHeadThreadId,
		};
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<BridgeFileViewerCodePanel
					codeViewWorkerPoolEnabled={false}
					openFileState={{
						displayItem: null,
						fileId: 'file-1',
						path: 'Sources/App/View.swift',
						status: 'ready',
					}}
					renderFulfillmentCoordinator={{
						observePostRender: (): void => {},
						reconcilePublication: (): void => {},
					}}
					selectedCodeViewItem={makeFileItem()}
					totalHeightPixels={null}
				/>
			</WorktreeAnnotationSurfaceProvider>,
		);

		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 1,
				revision: 1,
				sessions: [annotationSessionSummary({ revision: 1, sessionId: annotationSessionId })],
			});
			surface.publishThread({ context, message: rootMessage });
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean =>
				document.querySelectorAll('[data-testid="worktree-annotation-thread"]').length === 1,
			'Expected one saved thread in the actual Pierre annotation slot.',
		);
		const compactThread = document.querySelector<HTMLElement>(
			'[data-testid="worktree-annotation-thread"]',
		);
		const codeViewScrollOwner = document.querySelector<HTMLElement>(
			'.bridge-code-view-scroll-owner',
		);
		if (compactThread === null || codeViewScrollOwner === null) {
			throw new Error('Expected the slotted compact thread and CodeView scroll owner.');
		}
		await settleBrowserCondition(
			(): boolean => compactThread.getBoundingClientRect().height > 0,
			'Expected Pierre to finish measuring the compact annotation row.',
		);
		const rowBoundsBeforeExpansion = compactThread.getBoundingClientRect();
		const scrollTopBeforeExpansion = codeViewScrollOwner.scrollTop;

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Reply to thread' }).click();
		});
		expect(compactThread.isConnected).toBe(true);
		const replyComposer = rendered.getByRole('textbox', { name: 'Reply with Markdown' });
		const originalTextarea = replyComposer.element();
		if (!(originalTextarea instanceof HTMLTextAreaElement)) {
			throw new Error('Expected the Reply composer to use the owned Textarea.');
		}
		expect(compactThread.contains(originalTextarea)).toBe(true);
		const rowBoundsAfterExpansion = compactThread.getBoundingClientRect();
		expect(rowBoundsAfterExpansion.height).toBeGreaterThan(rowBoundsBeforeExpansion.height);
		expect(rowBoundsAfterExpansion.top).toBeCloseTo(rowBoundsBeforeExpansion.top, 1);
		expect(codeViewScrollOwner.scrollTop).toBe(scrollTopBeforeExpansion);
		await act(async (): Promise<void> => {
			await replyComposer.fill('h');
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'reply.create'),
			'Expected the first Reply character to issue reply.create.',
		);
		const replyCreate = surface.sentOperations.find(
			(operation) => operation.kind === 'reply.create',
		);
		if (replyCreate?.kind !== 'reply.create') throw new Error('Expected reply.create.');
		const durableReply = {
			...annotationMessage({
				messageId: baseMessageId,
				ordinal: 1,
				sessionRevision: 2,
				threadId: annotationHeadThreadId,
			}),
			draft: {
				activeEditToken: replyCreate.editToken,
				body: 'h',
				revision: 1,
			},
			savedBody: null,
			savedRevision: null,
		} as const;

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			await Promise.resolve();
		});
		expect(originalTextarea.isConnected).toBe(true);
		expect(document.activeElement).toBe(originalTextarea);
		expect(originalTextarea.value).toBe('h');
		expect(compactThread.getBoundingClientRect().height).toBeCloseTo(
			rowBoundsAfterExpansion.height,
			1,
		);
		expect(codeViewScrollOwner.scrollTop).toBe(scrollTopBeforeExpansion);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 1,
				revision: 2,
				sessions: [annotationSessionSummary({ revision: 2, sessionId: annotationSessionId })],
				subscriptionId: 'annotation-browser-subscription-2',
			});
			surface.publishThreadMessages({
				context,
				messages: [{ ...rootMessage, sessionRevision: 2 }, durableReply],
				subscriptionId: 'annotation-browser-subscription-2',
			});
			await Promise.resolve();
		});

		expect(originalTextarea.isConnected).toBe(true);
		expect(document.activeElement).toBe(originalTextarea);
		expect(originalTextarea.value).toBe('h');
		expect(document.querySelectorAll('[data-testid="worktree-annotation-thread"]')).toHaveLength(1);
		expect(document.querySelectorAll('[aria-label="Reply with Markdown"]')).toHaveLength(1);
		expect(
			surface.sentOperations.filter((operation) => operation.kind === 'reply.create'),
		).toHaveLength(1);
		expect(
			surface.sentOperations.filter((operation) => operation.kind === 'draft.edit.release'),
		).toHaveLength(0);
	});

	test('never rebinds a pending File composer across file or descriptor navigation', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const appliedOptions: CodeViewOptions<undefined>[] = [];
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetOptions = CodeView.prototype.setOptions;
		CodeView.prototype.setOptions = function captureOptions(
			options: CodeViewOptions<undefined> | undefined,
		): void {
			if (options !== undefined) appliedOptions.push(options);
			originalSetOptions.call(this, options);
		};
		const fileA = makeFileItem();
		const fileB = makeFileItem({
			displayPath: 'Sources/App/Other.swift',
			fileId: 'file-2',
			sourceDescriptorId: 'descriptor-file-2',
		});
		const fileCWithReusedPresentationIdentity = makeFileItem({
			sourceDescriptorId: 'descriptor-file-3',
		});
		const renderFilePanel = (
			selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem,
		): ReactElement => (
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<BridgeFileViewerCodePanel
					codeViewWorkerPoolEnabled={false}
					openFileState={{
						displayItem: null,
						fileId: selectedCodeViewItem.bridgeMetadata.itemId,
						path: selectedCodeViewItem.bridgeMetadata.displayPath,
						status: 'ready',
					}}
					renderFulfillmentCoordinator={{
						observePostRender: (): void => {},
						reconcilePublication: (): void => {},
					}}
					selectedCodeViewItem={selectedCodeViewItem}
					totalHeightPixels={null}
				/>
			</WorktreeAnnotationSurfaceProvider>
		);

		try {
			const rendered = await render(renderFilePanel(fileA));
			await settleBrowserCondition(
				(): boolean => appliedOptions.at(-1)?.onLineSelectionEnd !== undefined,
				'Expected File Pierre selection callback.',
			);
			await act(async (): Promise<void> => {
				invokeGutterAdmission(
					requireCodeViewOptions(appliedOptions.at(-1)),
					{ start: 4, end: 4 },
					fileA,
				);
				await Promise.resolve();
			});
			await expect
				.element(rendered.getByRole('textbox', { name: 'Write an annotation in Markdown' }))
				.toBeVisible();

			await act(async (): Promise<void> => {
				await rendered.rerender(renderFilePanel(fileB));
				await Promise.resolve();
			});
			expect(document.querySelector('[aria-label="Write an annotation in Markdown"]')).toBeNull();

			await act(async (): Promise<void> => {
				await rendered.rerender(renderFilePanel(fileCWithReusedPresentationIdentity));
				await Promise.resolve();
			});
			expect(document.querySelector('[aria-label="Write an annotation in Markdown"]')).toBeNull();

			await act(async (): Promise<void> => {
				await rendered.rerender(renderFilePanel(fileA));
				await Promise.resolve();
			});
			expect(document.querySelector('[aria-label="Write an annotation in Markdown"]')).toBeNull();
		} finally {
			CodeView.prototype.setOptions = originalSetOptions;
		}
	});

	test('keeps two File threads on one line in distinct Pierre annotation rows', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<BridgeFileViewerCodePanel
					codeViewWorkerPoolEnabled={false}
					openFileState={{
						displayItem: null,
						fileId: 'file-1',
						path: 'Sources/App/View.swift',
						status: 'ready',
					}}
					renderFulfillmentCoordinator={{
						observePostRender: (): void => {},
						reconcilePublication: (): void => {},
					}}
					selectedCodeViewItem={makeFileItem()}
					totalHeightPixels={null}
				/>
			</WorktreeAnnotationSurfaceProvider>,
		);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 2,
				revision: 4,
				sessions: [annotationSessionSummary({ revision: 4, sessionId: annotationSessionId })],
			});
			for (const [index, threadId] of [annotationHeadThreadId, annotationBaseThreadId].entries()) {
				const context = {
					diffSide: null,
					endLine: 4,
					path: 'Sources/App/View.swift',
					placement: 'exact',
					resolution: 'open',
					scope: 'located',
					sourceIdentity: 'descriptor-file-1',
					sourceRole: 'file',
					startLine: index === 0 ? 3 : 4,
					threadId,
				} satisfies WorktreeAnnotationThreadContext;
				const rootMessage = annotationMessage({
					messageId: index === 0 ? headMessageId : baseMessageId,
					sessionRevision: 4,
					threadId,
				});
				if (index === 0) {
					surface.publishThreadMessages({
						context,
						messages: [
							rootMessage,
							annotationMessage({
								messageId: headReplyMessageId,
								ordinal: 1,
								sessionRevision: 4,
								threadId,
							}),
						],
					});
				} else {
					surface.publishThread({ context, message: rootMessage });
				}
			}
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean =>
				document.querySelectorAll('[data-testid="worktree-annotation-thread"]').length === 2,
			'Expected two distinct File thread rows at the shared line.',
		);
		const threadFrames = Array.from(
			document.querySelectorAll<HTMLElement>('[data-testid="worktree-annotation-thread"]'),
		);
		expect(threadFrames).toHaveLength(2);
		for (const threadFrame of threadFrames) {
			expect(threadFrame.getBoundingClientRect().width).toBeLessThanOrEqual(768);
		}
		const firstThreadFrame = threadFrames.find(
			(frame): boolean => frame.dataset['annotationThreadId'] === annotationHeadThreadId,
		);
		if (firstThreadFrame === undefined) throw new Error('Expected the multi-message File thread.');
		expect(firstThreadFrame.textContent).toContain('2 messages');
		expect(firstThreadFrame.textContent).toContain('Comment 3');
		expect(firstThreadFrame.textContent).not.toContain('Comment 1');
		await act(async (): Promise<void> => {
			firstThreadFrame
				.querySelector<HTMLButtonElement>('[aria-label="Expand 2 messages"]')
				?.click();
			await Promise.resolve();
		});
		const chronology = document.querySelector<HTMLElement>(
			'[data-testid="worktree-annotation-thread-chronology"]',
		);
		expect(chronology?.textContent).toContain('Comment 1');
		expect(chronology?.textContent).toContain('Comment 3');
		const firstBounds = threadFrames[0]?.getBoundingClientRect();
		const secondBounds = threadFrames[1]?.getBoundingClientRect();
		if (firstBounds === undefined || secondBounds === undefined) {
			throw new Error('Expected both File annotation frame bounds.');
		}
		expect(firstBounds.bottom <= secondBounds.top || secondBounds.bottom <= firstBounds.top).toBe(
			true,
		);
	});

	test('retains unsent composer text when native rejects the draft with a conflict', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review', {
			failRootCreateWithConflict: true,
		});
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<WorktreeAnnotationNewMessageComposer
					createOperation={(body, editToken) => ({
						admission: { kind: 'implicitOrSingle' },
						body,
						editToken,
						kind: 'root.create',
						origin: {
							diffSide: null,
							endLine: 7,
							kind: 'located',
							path: 'Sources/App/View.swift',
							sourceIdentity: 'descriptor-file-1',
							sourceRole: 'file',
							startLine: 7,
						},
					})}
					onCancel={(): void => {}}
					onSaved={(): void => {}}
					placeholder="Conflict composer"
				/>
			</WorktreeAnnotationSurfaceProvider>,
		);
		const textbox = rendered.getByRole('textbox', { name: 'Conflict composer' });
		await act(async (): Promise<void> => {
			await textbox.fill('Unsent reviewer text');
			textbox.element().blur();
			await Promise.resolve();
			await Promise.resolve();
		});
		await expect.element(rendered.getByRole('alert')).toHaveTextContent('conflict');
		await expect.element(textbox).toHaveValue('Unsent reviewer text');
	});
});

function annotationContext(
	props:
		| {
				readonly diffSide: 'deletions';
				readonly endLine: number;
				readonly sourceRole: 'review_base';
				readonly threadId: string;
		  }
		| {
				readonly diffSide: 'additions';
				readonly endLine: number;
				readonly sourceRole: 'review_head';
				readonly threadId: string;
		  },
): WorktreeAnnotationThreadContext {
	const commonContext = {
		endLine: props.endLine,
		path: 'Sources/App/View.swift',
		placement: 'exact',
		resolution: 'open',
		scope: 'located',
		sourceIdentity:
			props.sourceRole === 'review_base' ? 'handle-item-source-base' : 'handle-item-source-head',
		startLine: props.endLine,
		threadId: props.threadId,
	} as const;
	return props.sourceRole === 'review_base'
		? { ...commonContext, diffSide: props.diffSide, sourceRole: 'review_base' }
		: { ...commonContext, diffSide: props.diffSide, sourceRole: 'review_head' };
}

function makeReviewCodeViewItem(): BridgeMainCodeViewItem {
	const baseContents = ['let stable = 1', 'let reviewed = "before"', 'let tail = 3'].join('\n');
	const headContents = ['let stable = 1', 'let reviewed = "after"', 'let tail = 3'].join('\n');
	return {
		bridgeMetadata: {
			cacheKey: 'review-base|review-head',
			contentRoles: ['base', 'head'],
			contentState: 'hydrated',
			displayPath: 'Sources/App/View.swift',
			itemId: 'item-source',
			lineCount: 3,
			sourceDescriptorIdsByRole: {
				base: 'handle-item-source-base',
				diff: null,
				file: null,
				head: 'handle-item-source-head',
			},
		},
		fileDiff: parseDiffFromFile(
			{
				cacheKey: 'review-base',
				contents: baseContents,
				name: 'Sources/App/View.swift',
			},
			{
				cacheKey: 'review-head',
				contents: headContents,
				name: 'Sources/App/View.swift',
			},
		),
		id: 'item-source',
		type: 'diff',
		version: 1,
	};
}

function makeFileItem(
	props: {
		readonly displayPath?: string;
		readonly fileId?: string;
		readonly sourceDescriptorId?: string;
	} = {},
): BridgeFileViewerSelectedCodeViewItem {
	const displayPath = props.displayPath ?? 'Sources/App/View.swift';
	const fileId = props.fileId ?? 'file-1';
	const sourceDescriptorId = props.sourceDescriptorId ?? 'descriptor-file-1';
	return {
		bridgeMetadata: {
			cacheKey: `file-cache-${fileId}`,
			contentRoles: ['file'],
			contentState: 'hydrated',
			displayPath,
			itemId: fileId,
			lineCount: 8,
			sourceDescriptorId,
		},
		file: {
			cacheKey: `file-cache-${fileId}`,
			contents: Array.from(
				{ length: 8 },
				(_, index): string => `let line${index + 1} = ${index + 1}`,
			).join('\n'),
			lang: 'swift',
			name: displayPath,
		},
		id: `file:${fileId}`,
		type: 'file',
		version: 1,
	};
}

function invokeLineSelection(
	options: CodeViewOptions<undefined>,
	range: {
		readonly end: number;
		readonly endSide?: 'additions' | 'deletions';
		readonly side?: 'additions' | 'deletions';
		readonly start: number;
	} | null,
	item: Readonly<{ id: string }>,
): void {
	const callback = options.onLineSelectionEnd;
	if (callback === undefined) throw new Error('Expected a Pierre line-selection callback.');
	Reflect.apply(callback, undefined, [range, { item }]);
}

function invokeGutterAdmission(
	options: CodeViewOptions<undefined>,
	range: {
		readonly end: number;
		readonly endSide?: 'additions' | 'deletions';
		readonly side?: 'additions' | 'deletions';
		readonly start: number;
	},
	item: Readonly<{ id: string }>,
): void {
	const gutterCallback = options.onGutterUtilityClick;
	const selectionEndCallback = options.onLineSelectionEnd;
	if (gutterCallback === undefined || selectionEndCallback === undefined) {
		throw new Error('Expected Pierre gutter and line-selection callbacks.');
	}
	Reflect.apply(gutterCallback, undefined, [range, { item }]);
	Reflect.apply(selectionEndCallback, undefined, [range, { item }]);
}

function requireCodeView(value: CodeView | undefined): CodeView {
	if (value === undefined) throw new Error('Expected mounted Pierre CodeView.');
	return value;
}

function requireCodeViewItem(value: CodeViewItem | undefined): CodeViewItem {
	if (value === undefined) throw new Error('Expected current Pierre item.');
	return value;
}

function requireCodeViewOptions(
	value: CodeViewOptions<undefined> | undefined,
): CodeViewOptions<undefined> {
	if (value === undefined) throw new Error('Expected current Pierre options.');
	return value;
}

async function settleBrowserCondition(
	predicate: () => boolean,
	failureMessage: string,
	remainingFrames = 60,
): Promise<void> {
	await act(async (): Promise<void> => {
		await Promise.resolve();
		await new Promise<void>((resolve): void => {
			requestAnimationFrame((): void => resolve());
		});
		await Promise.resolve();
	});
	if (predicate()) return;
	if (remainingFrames <= 0) throw new Error(failureMessage);
	await settleBrowserCondition(predicate, failureMessage, remainingFrames - 1);
}

void annotationContext;
void makeReviewCodeViewItem;
void invokeLineSelection;
void requireCodeView;
void requireCodeViewItem;
