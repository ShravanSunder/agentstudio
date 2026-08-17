import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { page } from 'vitest/browser';

import { Toaster } from '@/components/ui/sonner.js';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import { WorktreeAnnotationOutputControls } from './worktree-annotation-output-controls.js';
import type {
	WorktreeAnnotationCommandOutcome,
	WorktreeAnnotationOutputHistorySummary,
	WorktreeAnnotationThreadContext,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationProjection,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';

type WorktreeAnnotationOutputResultSummary = Extract<
	Extract<WorktreeAnnotationCommandOutcome['status'], { readonly kind: 'output' }>['outcome'],
	{ readonly kind: 'succeeded' }
>['summary'];

describe('worktree annotation output controls', () => {
	test('prepares only the saved messages selected by the reviewer', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<TestOutputComposition />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				revision: 3,
				sessions: [
					annotationSessionSummary({
						revision: 3,
						sessionId: annotationSessionId,
					}),
				],
			});
			for (const [index, threadId] of [
				annotationHeadThreadId,
				'00000000-0000-7000-8000-000000000022',
			].entries()) {
				surface.publishThread({
					context: annotationOutputThreadContext(threadId, index + 8),
					message: annotationMessage({
						messageId: `00000000-0000-7000-8000-00000000003${index + 1}`,
						ordinal: index,
						sessionRevision: 3,
						threadId,
					}),
				});
			}
			await Promise.resolve();
		});

		await openReviewOutput(rendered);
		const savedMessageCheckboxes = rendered.getByRole('checkbox');
		await expect.element(savedMessageCheckboxes).toHaveLength(2);
		await expect
			.element(rendered.getByText('Thread 1 · Root comment · Saved revision 1'))
			.toBeVisible();
		expect(outputPopoverElement()?.textContent).not.toContain('00000099');
		const popover = outputPopoverElement();
		if (!(popover instanceof HTMLElement)) throw new Error('Expected output popover geometry.');
		const popoverBounds = popover.getBoundingClientRect();
		const triggerBounds = rendered
			.getByRole('button', { name: 'Review output' })
			.element()
			.getBoundingClientRect();
		const checkboxBounds = savedMessageCheckboxes.nth(0).element().getBoundingClientRect();
		expect(popoverBounds.width).toBeGreaterThanOrEqual(360);
		expect(popoverBounds.width).toBeLessThanOrEqual(400);
		expect(popoverBounds.height).toBeLessThan(window.innerHeight);
		expect(triggerBounds.height).toBe(20);
		expect(getComputedStyle(savedMessageCheckboxes.nth(0).element()).width).toBe('14px');
		expect(getComputedStyle(savedMessageCheckboxes.nth(0).element()).height).toBe('14px');
		expect(checkboxBounds.width).toBeGreaterThan(13);
		expect(checkboxBounds.height).toBeGreaterThan(13);
		await page.screenshot({
			element: popover,
			path: '../../../tmp/bridgeweb-worktree-annotation-output-controls.png',
		});
		await performBrowserAction(() => savedMessageCheckboxes.nth(0).click());
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Copy 1 comment' }).click(),
		);

		expect(surface.sentOperations.find((operation) => operation.kind === 'output.prepare')).toEqual(
			{
				kind: 'output.prepare',
				outputKind: 'clipboardMarkdown',
				selection: {
					kind: 'explicit',
					messageIds: ['00000000-0000-7000-8000-000000000031'],
				},
				sessionId: annotationSessionId,
			},
		);
		await performBrowserAction(async (): Promise<void> => {
			surface.settleMostRecentOutput({ kind: 'destination_cancelled' });
		});
	});

	test('shows the Copy toast, closes only output UI, and does not resolve the saved comment', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(
			<>
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<TestOutputComposition />
				</WorktreeAnnotationSurfaceProvider>
				<Toaster />
			</>,
		);
		await publishOutputFixture(surface);

		await openReviewOutput(rendered);
		await performBrowserAction(() => rendered.getByRole('button', { name: 'Select all' }).click());
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Copy 1 comment' }).click(),
		);
		await settleBrowserCondition(
			(): boolean =>
				surface.sentOperations.some(
					(operation): boolean =>
						operation.kind === 'output.prepare' && operation.outputKind === 'clipboardMarkdown',
				),
			'Expected a clipboard output preparation command.',
		);
		await performBrowserAction(async (): Promise<void> => {
			surface.settleMostRecentOutput({
				kind: 'succeeded',
				summary: outputResultSummary({
					messageCount: 1,
					outputKind: 'clipboard_markdown',
				}),
			});
		});
		await settleBrowserCondition(
			(): boolean =>
				(document.body.textContent?.includes('Copied 1 comment') ?? false) &&
				outputPopoverElement() === null,
			'Expected the Copy toast and closed output popover.',
		);

		expect(document.body.textContent).toContain('Copied 1 comment');
		expect(document.querySelector('[data-close-button]')).not.toBeNull();
		expect(
			surface.sentOperations.some((operation) => operation.kind === 'thread.resolution.set'),
		).toBe(false);
	});

	test('derives Select all state from current saved revisions after a revision changes', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<TestOutputComposition />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await publishOutputFixture(surface);
		await openReviewOutput(rendered);
		await performBrowserAction(() => rendered.getByRole('checkbox').click());
		await expect.element(rendered.getByRole('button', { name: 'Clear' })).toBeVisible();

		await act(async (): Promise<void> => {
			surface.publishThread({
				context: annotationSessionThreadContext(annotationHeadThreadId),
				message: {
					...annotationMessage({
						messageId: '00000000-0000-7000-8000-000000000031',
						sessionRevision: 3,
						threadId: annotationHeadThreadId,
					}),
					savedRevision: 2,
				},
			});
			await Promise.resolve();
		});
		await expect.element(rendered.getByRole('button', { name: 'Clear' })).toBeVisible();
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Copy 1 comment' }).click(),
		);
		expect(
			surface.sentOperations.findLast((operation) => operation.kind === 'output.prepare'),
		).toEqual({
			kind: 'output.prepare',
			outputKind: 'clipboardMarkdown',
			selection: {
				kind: 'explicit',
				messageIds: ['00000000-0000-7000-8000-000000000031'],
			},
			sessionId: annotationSessionId,
		});
		await performBrowserAction(async (): Promise<void> => {
			surface.settleMostRecentOutput({ kind: 'destination_cancelled' });
		});
	});

	test('inspects exact saved bytes and repeats history without selecting current messages', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const attemptId = '00000000-0000-7000-8000-000000000071';
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<TestOutputComposition />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				outputHistory: [outputHistorySummary({ attemptId, state: 'unknown' })],
				revision: 4,
				sessions: [
					annotationSessionSummary({
						revision: 4,
						sessionId: annotationSessionId,
					}),
				],
			});
			await Promise.resolve();
		});

		await openReviewOutput(rendered);
		await expect
			.element(
				rendered.getByText(
					'Unknown — exact bytes are saved, but whether the clipboard was changed is not proven.',
				),
			)
			.toBeVisible();
		await expect.element(rendered.getByText(/Output attempt 1 ·/)).toBeVisible();
		expect(outputPopoverElement()?.textContent).not.toContain('00000071');
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Inspect output attempt 1' }).click(),
		);
		expect(surface.sentOutputInspectionAttemptIds).toEqual([attemptId]);
		await performBrowserAction(async (): Promise<void> => {
			surface.settleMostRecentInspection({
				attemptId,
				content: '# Exact saved review\n\nRequest: keep this owner.',
				outputKind: 'clipboard_markdown',
			});
		});
		await expect
			.element(rendered.getByTestId('annotation-output-inspection'))
			.toHaveTextContent('Exact saved review');
		await expect
			.element(rendered.getByTestId('annotation-output-inspection'))
			.toHaveTextContent('47 bytes');

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Repeat output attempt 1' }).click(),
		);
		expect(
			surface.sentOperations.findLast((operation) => operation.kind === 'output.repeat'),
		).toEqual({
			attemptId,
			kind: 'output.repeat',
		});
		await performBrowserAction(async (): Promise<void> => {
			surface.settleMostRecentOutput({
				kind: 'unknown',
				summary: outputResultSummary({
					messageCount: 1,
					outputKind: 'clipboard_markdown',
				}),
			});
		});
	});

	test('states partial file success exactly and prevents repeating a merely prepared row', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const partialAttemptId = '00000000-0000-7000-8000-000000000072';
		const preparedAttemptId = '00000000-0000-7000-8000-000000000073';
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<TestOutputComposition />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				outputHistory: [
					outputHistorySummary({
						attemptId: partialAttemptId,
						outputKind: 'json_file',
						state: 'finalization_failed',
					}),
					outputHistorySummary({
						attemptId: preparedAttemptId,
						outputKind: 'json_file',
						state: 'prepared',
					}),
				],
				revision: 5,
				sessions: [
					annotationSessionSummary({
						revision: 5,
						sessionId: annotationSessionId,
					}),
				],
			});
			await Promise.resolve();
		});

		await openReviewOutput(rendered);
		await expect
			.element(
				rendered.getByText(
					'Partial success — the file was written, but durable history was not recorded.',
				),
			)
			.toBeVisible();
		await expect
			.element(rendered.getByRole('button', { name: 'Repeat output attempt 2' }))
			.toBeDisabled();
	});

	test('keeps export cancellation quiet', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<TestOutputComposition />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await publishOutputFixture(surface);
		await openReviewOutput(rendered);
		await performBrowserAction(() => rendered.getByRole('button', { name: 'Select all' }).click());

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Export 1 comment' }).click(),
		);
		await performBrowserAction(async (): Promise<void> => {
			surface.settleMostRecentOutput({ kind: 'destination_cancelled' });
		});
		expect(outputPopoverElement()).not.toBeNull();
		expect(document.body.textContent).not.toContain('Exported 1 comment');
	});

	test('reports the selected export filename after projection replacement', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(
			<>
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<ProjectionReplacingOutputComposition />
				</WorktreeAnnotationSurfaceProvider>
				<Toaster />
			</>,
		);
		await publishOutputFixture(surface);
		await openReviewOutput(rendered);
		await performBrowserAction(() => rendered.getByRole('button', { name: 'Select all' }).click());

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Export 1 comment' }).click(),
		);
		await performBrowserAction(async (): Promise<void> => {
			surface.settleMostRecentOutput({
				kind: 'succeeded',
				summary: outputResultSummary({
					destinationFilename: 'review-comments.json',
					messageCount: 1,
					outputKind: 'json_file',
				}),
			});
		});
		await settleBrowserCondition(
			(): boolean =>
				document.body.textContent?.includes('Exported 1 comment to review-comments.json.') ?? false,
			'Expected export success feedback to survive projection replacement.',
		);
		await expect
			.element(rendered.getByText('Exported 1 comment to review-comments.json.'))
			.toBeVisible();
	});
});

type BrowserRenderResult = Awaited<ReturnType<typeof render>>;

function TestOutputComposition(): ReactElement {
	return <WorktreeAnnotationOutputControls activeSessionId={annotationSessionId} />;
}

function ProjectionReplacingOutputComposition(): ReactElement {
	const projection = useWorktreeAnnotationProjection();
	return (
		<WorktreeAnnotationOutputControls
			activeSessionId={annotationSessionId}
			key={projection.revision}
		/>
	);
}

async function openReviewOutput(rendered: BrowserRenderResult): Promise<void> {
	await performBrowserAction(() => rendered.getByRole('button', { name: 'Review output' }).click());
	await settleBrowserCondition(
		(): boolean => outputPopoverElement() !== null,
		'Expected the output popover to open.',
	);
}

function outputPopoverElement(): HTMLElement | null {
	return (
		Array.from(document.querySelectorAll<HTMLElement>('[data-slot="popover-content"]')).find(
			(popover): boolean =>
				popover.querySelector('[data-slot="popover-title"]')?.textContent === 'Review output',
		) ?? null
	);
}

function annotationOutputThreadContext(
	threadId: string,
	line: number,
): WorktreeAnnotationThreadContext {
	return {
		diffSide: null,
		endLine: line,
		path: 'Sources/App/View.swift',
		placement: 'exact',
		resolution: 'open',
		scope: 'located',
		sourceIdentity: 'descriptor-file-1',
		sourceRole: 'file',
		startLine: line,
		threadId,
	};
}

async function publishOutputFixture(surface: RecordingAnnotationBrowserSurface): Promise<void> {
	await act(async (): Promise<void> => {
		surface.publishProjectionState({
			revision: 3,
			sessions: [
				annotationSessionSummary({
					revision: 3,
					sessionId: annotationSessionId,
				}),
			],
		});
		surface.publishThread({
			context: annotationSessionThreadContext(annotationHeadThreadId),
			message: annotationMessage({
				messageId: '00000000-0000-7000-8000-000000000031',
				sessionRevision: 3,
				threadId: annotationHeadThreadId,
			}),
		});
		await Promise.resolve();
	});
}

function annotationSessionThreadContext(threadId: string): WorktreeAnnotationThreadContext {
	return annotationOutputThreadContext(threadId, 8);
}

function outputResultSummary(props: {
	readonly destinationFilename?: string | null;
	readonly messageCount: number;
	readonly outputKind: 'clipboard_markdown' | 'json_file';
}): WorktreeAnnotationOutputResultSummary {
	return {
		attemptId: '00000000-0000-7000-8000-000000000071',
		destinationFilename: props.destinationFilename ?? null,
		messageCount: props.messageCount,
		outputKind: props.outputKind,
		sessionId: annotationSessionId,
	} as const;
}

function outputHistorySummary(props: {
	readonly attemptId: string;
	readonly outputKind?: 'clipboard_markdown' | 'json_file';
	readonly state: 'finalization_failed' | 'prepared' | 'succeeded' | 'unknown';
}): WorktreeAnnotationOutputHistorySummary {
	return {
		attemptId: props.attemptId,
		createdAt: 10,
		messageCount: 1,
		outputKind: props.outputKind ?? 'clipboard_markdown',
		repeatedFromAttemptId: null,
		sessionId: annotationSessionId,
		state: props.state,
		updatedAt: 11,
	} as const;
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

async function performBrowserAction(action: () => Promise<void>): Promise<void> {
	await act(async (): Promise<void> => {
		await action();
		await Promise.resolve();
		await nextBrowserAnimationFrame();
		await nextBrowserAnimationFrame();
		await Promise.resolve();
	});
}

async function nextBrowserAnimationFrame(): Promise<void> {
	await new Promise<void>((resolve): void => {
		requestAnimationFrame((): void => resolve());
	});
}
