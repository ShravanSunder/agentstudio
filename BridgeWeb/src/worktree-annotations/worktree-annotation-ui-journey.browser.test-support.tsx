import { act, type ReactElement } from 'react';
import { render } from 'vitest-browser-react';

import { Toaster } from '@/components/ui/sonner.js';

import { BridgeViewerContentHeader } from '../app/bridge-viewer-content-header.js';
import {
	BridgeViewerContextPanelProvider,
	BridgeViewerContextPanelViewport,
} from '../app/bridge-viewer-context-panel-host.js';
import {
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import { WorktreeAnnotationShareHeaderControl } from './worktree-annotation-output-controls.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationThreadContext,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationProjection,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';
import { WorktreeAnnotationThread } from './worktree-annotation-thread.js';

export const journeyRootMessageId = '00000000-0000-7000-8000-000000000201';
export const journeyReplyMessageId = '00000000-0000-7000-8000-000000000202';
export const journeyOutputAttemptId = '00000000-0000-7000-8000-000000000203';

export const journeyOpenContext: WorktreeAnnotationThreadContext = {
	diffSide: 'additions',
	endLine: 18,
	path: 'Sources/AgentStudio/Features/Bridge/ReviewPane.swift',
	placement: 'exact',
	resolution: 'open',
	scope: 'located',
	sourceIdentity: 'journey-review-file',
	sourceRole: 'review_head',
	startLine: 14,
	threadId: annotationHeadThreadId,
};

export const journeyResolvedContext: WorktreeAnnotationThreadContext = {
	...journeyOpenContext,
	resolution: 'resolved',
};

export function makeJourneyRootDraft(
	activeEditToken: string | null,
	revision: number,
): WorktreeAnnotationMessageEntry {
	return {
		...annotationMessage({
			messageId: journeyRootMessageId,
			sessionRevision: revision + 2,
			threadId: annotationHeadThreadId,
		}),
		createdAt: 807_667_200,
		draft: {
			activeEditToken,
			body: 'Clarify the reconnect state before presenting Review.',
			revision,
		},
		handled: true,
		savedBody: 'Clarify the reconnect state.',
		savedRevision: 1,
	};
}

export function makeJourneySavedRoot(sessionRevision: number): WorktreeAnnotationMessageEntry {
	return {
		...annotationMessage({
			messageId: journeyRootMessageId,
			sessionRevision,
			threadId: annotationHeadThreadId,
			threadRevision: 2,
		}),
		createdAt: 807_667_200,
		draft: null,
		handled: true,
		messageRevision: 3,
		savedBody: 'Clarify the reconnect state before enabling Share.',
		savedRevision: 2,
	};
}

export function makeJourneyReplyDraft(
	activeEditToken: string,
	sessionRevision: number,
): WorktreeAnnotationMessageEntry {
	return {
		...annotationMessage({
			messageId: journeyReplyMessageId,
			ordinal: 1,
			sessionRevision,
			threadId: annotationHeadThreadId,
			threadRevision: 3,
		}),
		createdAt: 807_667_260,
		draft: {
			activeEditToken,
			body: 'Added the readiness guard and recovery coverage.',
			revision: 0,
		},
		savedBody: null,
		savedRevision: null,
	};
}

export function makeJourneySavedReply(sessionRevision: number): WorktreeAnnotationMessageEntry {
	return {
		...annotationMessage({
			messageId: journeyReplyMessageId,
			ordinal: 1,
			sessionRevision,
			threadId: annotationHeadThreadId,
			threadRevision: 3,
		}),
		createdAt: 807_667_260,
		draft: null,
		handled: false,
		messageRevision: 2,
		savedBody: 'Added the readiness guard and recovery coverage.',
		savedRevision: 1,
	};
}

export async function renderWorktreeAnnotationUiJourney(
	surface: RecordingAnnotationBrowserSurface,
): Promise<Awaited<ReturnType<typeof render>>> {
	return await render(<WorktreeAnnotationUiJourneyFixture surface={surface} />);
}

export async function publishJourneyThread(props: {
	readonly context: WorktreeAnnotationThreadContext;
	readonly messages: readonly WorktreeAnnotationMessageEntry[];
	readonly revision: number;
	readonly surface: RecordingAnnotationBrowserSurface;
}): Promise<void> {
	const eligibleMessageCount = props.messages.filter(
		(message) => message.savedBody !== null && message.draft === null,
	).length;
	await act(async (): Promise<void> => {
		props.surface.publishProjectionState({
			expectedThreadCount: 1,
			revision: props.revision,
			sessions: [
				annotationSessionSummary({
					eligibleMessageCount,
					revision: props.revision,
					sessionId: annotationSessionId,
				}),
			],
		});
		props.surface.publishThreadMessages({ context: props.context, messages: props.messages });
		await settleJourneyInteraction();
	});
}

export async function settleJourneyInteraction(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve): void => {
		requestAnimationFrame((): void => resolve());
	});
	await Promise.resolve();
}

export async function waitForJourneyCondition(
	predicate: () => boolean,
	failureMessage: string,
	remainingFrames = 60,
): Promise<void> {
	await act(async (): Promise<void> => settleJourneyInteraction());
	if (predicate()) return;
	if (remainingFrames <= 0) throw new Error(failureMessage);
	await waitForJourneyCondition(predicate, failureMessage, remainingFrames - 1);
}

export async function finishJourneyMotion(element: HTMLElement): Promise<void> {
	await waitForJourneyCondition(
		() => !element.hasAttribute('data-starting-style'),
		'Expected the journey surface opening motion to settle.',
	);
	await act(async (): Promise<void> => {
		await Promise.all(
			element
				.getAnimations({ subtree: true })
				.map((animation) => animation.finished.catch((): void => {})),
		);
		await settleJourneyInteraction();
	});
}

function WorktreeAnnotationUiJourneyFixture(props: {
	readonly surface: RecordingAnnotationBrowserSurface;
}): ReactElement {
	return (
		<WorktreeAnnotationSurfaceProvider surfaceClient={props.surface.client}>
			<Toaster duration={Number.POSITIVE_INFINITY} />
			<BridgeViewerContextPanelProvider>
				<div
					className="grid h-[620px] w-[760px] grid-rows-[auto_minmax(0,1fr)] bg-background"
					data-testid="worktree-annotation-ui-journey"
				>
					<BridgeViewerContentHeader
						controls={<WorktreeAnnotationShareHeaderControl />}
						mode="review"
						statusText="Review ready"
						title="ReviewPane.swift"
					/>
					<BridgeViewerContextPanelViewport testId="worktree-annotation-ui-journey-viewport">
						<div className="grid min-h-0 grid-cols-[minmax(0,1fr)_22rem] gap-4 p-4">
							{/* Fixture-only focus boundary; this journey does not claim full shell or Pierre proof. */}
							<button className="self-start" type="button">
								Review code canvas
							</button>
							<JourneyThreadProjection />
						</div>
					</BridgeViewerContextPanelViewport>
				</div>
			</BridgeViewerContextPanelProvider>
		</WorktreeAnnotationSurfaceProvider>
	);
}

function JourneyThreadProjection(): ReactElement | null {
	const projection = useWorktreeAnnotationProjection();
	const thread = projection.threads[0];
	return thread === undefined ? null : (
		<div className="min-w-0" data-testid="worktree-annotation-ui-journey-thread-host">
			<WorktreeAnnotationThread
				rangeIdentity={{ itemId: 'journey-review-file', range: { end: 18, start: 14 } }}
				thread={thread}
			/>
		</div>
	);
}
