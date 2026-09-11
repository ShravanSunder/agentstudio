import { CodeView, parseDiffFromFile } from '@pierre/diffs';
import { act, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../../app/bridge-app.css';
import { createBridgeMainRenderFulfillmentCoordinator } from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import {
	annotationBaseThreadId,
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from '../../worktree-annotations/worktree-annotation-browser-test-support.js';
import type { WorktreeAnnotationThreadContext } from '../../worktree-annotations/worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationInteraction,
	WorktreeAnnotationSurfaceProvider,
} from '../../worktree-annotations/worktree-annotation-surface-provider.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { BridgeCodeViewPanel } from './bridge-code-view-panel.js';
import { worktreeAnnotationMetadataForPierreAnnotation } from './worktree-annotation-pierre-adapter.js';

const handledHeadMessageId = '00000000-0000-7000-8000-000000000091';
const handledBaseMessageId = '00000000-0000-7000-8000-000000000092';

// oxlint-disable-next-line unbound-method -- Restored after every Browser witness.
const originalCodeViewSetup = CodeView.prototype.setup;

describe('Bridge CodeView worktree annotation membership', () => {
	afterEach(async (): Promise<void> => {
		CodeView.prototype.setup = originalCodeViewSetup;
		await act(async (): Promise<void> => {
			await cleanup();
		});
	});

	test('keeps actual Pierre annotations independent from the Share drawer scope', async () => {
		let mountedCodeView: CodeView | null = null;
		CodeView.prototype.setup = function captureMountedCodeView(root: HTMLElement): void {
			// oxlint-disable-next-line typescript/no-this-alias -- Browser witness captures the live Pierre instance and restores the prototype after the test.
			mountedCodeView = this;
			originalCodeViewSetup.call(this, root);
		};
		const surface = new RecordingAnnotationBrowserSurface('review');
		const reviewPackage = makeBridgeReviewPackage();
		const reviewProjection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const renderFulfillmentCoordinator = createBridgeMainRenderFulfillmentCoordinator({
			sendDisposition: (): void => {},
		});
		try {
			const rendered = await render(
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<ShareScopeTestControls />
					<BridgeCodeViewPanel
						presentationPositionKey="annotation-share-scope-membership"
						projection={reviewProjection}
						renderFulfillmentCoordinator={renderFulfillmentCoordinator}
						reviewPackage={reviewPackage}
						selectedCodeViewItem={makeReviewCodeViewItem()}
						selectedItemId="item-source"
						visibleCodeViewItems={[makeReviewCodeViewItem()]}
						workerPoolEnabled={false}
					/>
				</WorktreeAnnotationSurfaceProvider>,
			);
			await settleBrowserCondition(
				(): boolean => mountedCodeView !== null,
				'Expected a mounted Pierre CodeView.',
			);

			await act(async (): Promise<void> => {
				surface.publishProjectionState({
					expectedThreadCount: 2,
					revision: 1,
					sessions: [annotationSessionSummary({ revision: 1, sessionId: annotationSessionId })],
				});
				surface.publishThread({
					context: annotationContext({
						diffSide: 'additions',
						sourceRole: 'review_head',
						threadId: annotationHeadThreadId,
					}),
					message: {
						...annotationMessage({
							messageId: handledHeadMessageId,
							threadId: annotationHeadThreadId,
						}),
						handled: true,
					},
				});
				surface.publishThread({
					context: annotationContext({
						diffSide: 'deletions',
						sourceRole: 'review_base',
						threadId: annotationBaseThreadId,
					}),
					message: {
						...annotationMessage({
							messageId: handledBaseMessageId,
							threadId: annotationBaseThreadId,
						}),
						handled: true,
					},
				});
				await Promise.resolve();
			});

			await settleBrowserCondition(
				(): boolean => renderedPierreThreadCount() === 2,
				'Expected two initial Pierre annotation threads.',
			);
			expect(pierreThreadIds(requireMountedCodeView(mountedCodeView))).toEqual([
				annotationHeadThreadId,
				annotationBaseThreadId,
			]);

			await act(async (): Promise<void> => {
				await rendered.getByRole('button', { name: 'Open Share on Pending' }).click();
				await nextAnimationFrame();
			});
			await settleBrowserCondition(
				(): boolean => renderedPierreThreadCount() === 2,
				'Expected opening Share on Pending to preserve both Pierre annotation threads.',
			);
			expect(pierreThreadIds(requireMountedCodeView(mountedCodeView))).toEqual([
				annotationHeadThreadId,
				annotationBaseThreadId,
			]);

			await act(async (): Promise<void> => {
				await rendered.getByRole('button', { name: 'Show All in Share' }).click();
				await nextAnimationFrame();
			});
			await settleBrowserCondition(
				(): boolean => renderedPierreThreadCount() === 2,
				'Expected switching Share to All to preserve both Pierre annotation threads.',
			);
			expect(pierreThreadIds(requireMountedCodeView(mountedCodeView))).toEqual([
				annotationHeadThreadId,
				annotationBaseThreadId,
			]);

			await act(async (): Promise<void> => {
				await rendered.getByRole('button', { name: 'Show Pending in Share' }).click();
				await nextAnimationFrame();
			});
			await settleBrowserCondition(
				(): boolean => renderedPierreThreadCount() === 2,
				'Expected switching Share back to Pending to preserve both Pierre annotation threads.',
			);
			expect(pierreThreadIds(requireMountedCodeView(mountedCodeView))).toEqual([
				annotationHeadThreadId,
				annotationBaseThreadId,
			]);

			await act(async (): Promise<void> => {
				await rendered.getByRole('button', { name: 'Close Share' }).click();
				await nextAnimationFrame();
			});
			await settleBrowserCondition(
				(): boolean => renderedPierreThreadCount() === 2,
				'Expected closing Share to preserve both Pierre annotation threads.',
			);
			expect(pierreThreadIds(requireMountedCodeView(mountedCodeView))).toEqual([
				annotationHeadThreadId,
				annotationBaseThreadId,
			]);
		} finally {
			renderFulfillmentCoordinator.dispose();
		}
	});

	test('completes a requested annotation reveal only after the inline thread is mounted and visible', async () => {
		let mountedCodeView: CodeView | null = null;
		CodeView.prototype.setup = function captureMountedCodeView(root: HTMLElement): void {
			// oxlint-disable-next-line typescript/no-this-alias -- Browser witness captures the live Pierre instance and restores the prototype after the test.
			mountedCodeView = this;
			originalCodeViewSetup.call(this, root);
		};
		const surface = new RecordingAnnotationBrowserSurface('review');
		const reviewPackage = makeBridgeReviewPackage();
		const reviewProjection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const renderFulfillmentCoordinator = createBridgeMainRenderFulfillmentCoordinator({
			sendDisposition: (): void => {},
		});
		const completedRequests: number[] = [];
		const panel = (reveal: boolean): ReactElement => (
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<BridgeCodeViewPanel
					{...(reveal
						? {
								annotationReveal: {
									itemId: 'item-source',
									range: { end: 2, side: 'additions' as const, start: 2 },
									requestId: 17,
									threadId: annotationHeadThreadId,
								},
								onAnnotationRevealComplete: (requestId: number): void => {
									completedRequests.push(requestId);
								},
							}
						: {})}
					presentationPositionKey="annotation-reveal"
					projection={reviewProjection}
					renderFulfillmentCoordinator={renderFulfillmentCoordinator}
					reviewPackage={reviewPackage}
					selectedCodeViewItem={makeReviewCodeViewItem()}
					selectedItemId="item-source"
					visibleCodeViewItems={[makeReviewCodeViewItem()]}
					workerPoolEnabled={false}
				/>
			</WorktreeAnnotationSurfaceProvider>
		);
		try {
			const rendered = await render(panel(false));
			await settleBrowserCondition(
				(): boolean => mountedCodeView !== null,
				'Expected a mounted Pierre CodeView.',
			);
			await act(async (): Promise<void> => {
				surface.publishProjectionState({
					expectedThreadCount: 1,
					revision: 1,
					sessions: [annotationSessionSummary({ revision: 1, sessionId: annotationSessionId })],
				});
				surface.publishThread({
					context: annotationContext({
						diffSide: 'additions',
						sourceRole: 'review_head',
						threadId: annotationHeadThreadId,
					}),
					message: annotationMessage({
						messageId: handledHeadMessageId,
						threadId: annotationHeadThreadId,
					}),
				});
				await Promise.resolve();
			});
			await settleBrowserCondition(
				(): boolean => renderedPierreThreadCount() === 1,
				'Expected the destination inline thread before requesting its reveal.',
			);

			await rendered.rerender(panel(true));
			await settleBrowserCondition(
				(): boolean => completedRequests.includes(17),
				'Expected completion only after the inline annotation thread became visible.',
			);
			const scrollOwner = document.querySelector<HTMLElement>('.bridge-code-view-scroll-owner');
			const thread = document.querySelector<HTMLElement>(
				`[data-annotation-thread-id="${annotationHeadThreadId}"]`,
			);
			if (scrollOwner === null || thread === null)
				throw new Error('Missing revealed thread geometry.');
			const viewportBounds = scrollOwner.getBoundingClientRect();
			const threadBounds = thread.getBoundingClientRect();
			expect(threadBounds.bottom).toBeGreaterThan(viewportBounds.top);
			expect(threadBounds.top).toBeLessThan(viewportBounds.bottom);
			expect(completedRequests).toEqual([17]);
		} finally {
			renderFulfillmentCoordinator.dispose();
		}
	});
});

function ShareScopeTestControls(): ReactElement {
	const interaction = useWorktreeAnnotationInteraction();
	return (
		<div>
			<button type="button" onClick={interaction.openShareMode}>
				Open Share on Pending
			</button>
			<button type="button" onClick={() => interaction.setShareScope('all')}>
				Show All in Share
			</button>
			<button type="button" onClick={() => interaction.setShareScope('pending')}>
				Show Pending in Share
			</button>
			<button type="button" onClick={interaction.closeShareMode}>
				Close Share
			</button>
		</div>
	);
}

function annotationContext(
	props:
		| {
				readonly diffSide: 'deletions';
				readonly sourceRole: 'review_base';
				readonly threadId: string;
		  }
		| {
				readonly diffSide: 'additions';
				readonly sourceRole: 'review_head';
				readonly threadId: string;
		  },
): WorktreeAnnotationThreadContext {
	const commonContext = {
		endLine: 2,
		path: 'Sources/App/View.swift',
		placement: 'exact',
		resolution: 'open',
		scope: 'located',
		sourceIdentity:
			props.sourceRole === 'review_base' ? 'handle-item-source-base' : 'handle-item-source-head',
		startLine: 2,
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
			{ cacheKey: 'review-base', contents: baseContents, name: 'Sources/App/View.swift' },
			{ cacheKey: 'review-head', contents: headContents, name: 'Sources/App/View.swift' },
		),
		id: 'item-source',
		type: 'diff',
		version: 1,
	};
}

function pierreThreadIds(codeView: CodeView): readonly string[] {
	return (codeView.getItem('item-source')?.annotations ?? [])
		.flatMap((annotation): readonly string[] => {
			const metadata = worktreeAnnotationMetadataForPierreAnnotation(annotation);
			return metadata?.kind === 'thread' ? [metadata.threadId] : [];
		})
		.toSorted();
}

function renderedPierreThreadCount(): number {
	return document.querySelectorAll('[data-testid="worktree-annotation-thread"]').length;
}

function requireMountedCodeView(codeView: CodeView | null): CodeView {
	if (codeView === null) throw new Error('Expected a mounted Pierre CodeView.');
	return codeView;
}

async function nextAnimationFrame(): Promise<void> {
	await new Promise<void>((resolve): void => {
		requestAnimationFrame((): void => resolve());
	});
}

async function settleBrowserCondition(
	predicate: () => boolean,
	failureMessage: string,
	remainingFrames = 60,
): Promise<void> {
	await act(async (): Promise<void> => {
		await Promise.resolve();
		await nextAnimationFrame();
		await Promise.resolve();
	});
	if (predicate()) return;
	if (remainingFrames <= 0) throw new Error(failureMessage);
	await settleBrowserCondition(predicate, failureMessage, remainingFrames - 1);
}
