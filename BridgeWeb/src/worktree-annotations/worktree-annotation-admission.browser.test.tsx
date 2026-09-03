import { act, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';
import { page } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import { WorktreeAnnotationSurfaceProvider } from './worktree-annotation-surface-provider.js';
import { WorktreeAnnotationNewMessageComposer } from './worktree-annotation-thread.js';

const secondSessionId = '00000000-0000-7000-8000-000000000019';

describe('worktree annotation transient admission decision', () => {
	afterEach(async (): Promise<void> => {
		await cleanup();
	});

	test('does not draw a timeline continuation for an initial root composer', async () => {
		// Arrange
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(<AdmissionFixture surface={surface} />);

		// Act
		const composerMessage = rendered.getByTestId('worktree-annotation-message').element();

		// Assert
		expect(composerMessage.querySelector('.h-full.w-px.bg-comment-border')).toBeNull();
		await page.screenshot({
			path: '../../../tmp/bridgeweb-initial-composer-without-connector.png',
		});
	});

	test('demands the sole applicable session discovered after reload', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<div>Review content</div>
			</WorktreeAnnotationSurfaceProvider>,
		);

		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 0,
				revision: 3,
				sessions: [annotationSessionSummary({ revision: 3, sessionId: annotationSessionId })],
			});
			await settleInteraction();
		});

		await waitForOperationKind(surface, 'demand.acquire');
		expect(surface.sentOperations).toContainEqual({
			kind: 'demand.acquire',
			sessionId: annotationSessionId,
		});
	});

	test('resumes the original inline intent with the explicitly selected applicable session', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(<AdmissionFixture surface={surface} />);
		await publishSessions(surface, 'applicable');

		await act(async (): Promise<void> => {
			await rendered
				.getByRole('textbox', { name: 'Write an annotation in Markdown' })
				.fill('Intent');
			await settleInteraction();
		});
		await waitForOperationCount(surface, 1);
		await act(async (): Promise<void> => {
			surface.settleMostRecentAdmissionRequired({
				candidateSessionIds: [annotationSessionId, secondSessionId],
				reason: 'applicable_session_choice',
			});
			await settleInteraction();
		});

		await expect.element(rendered.getByText('Choose a review session')).toBeVisible();
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Continue session 2' }).click();
			await settleInteraction();
		});
		await waitForOperationCount(surface, 2);
		expect(surface.sentOperations.at(-1)).toMatchObject({
			admission: { kind: 'selected', sessionId: secondSessionId },
			body: 'Intent',
			kind: 'root.create',
		});
	});

	test('offers Continue, Leave Paused, and Start Another for uncertain continuity', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<AdmissionFixture surface={surface} />);
		await publishSessions(surface, 'uncertain');

		await act(async (): Promise<void> => {
			await rendered
				.getByRole('textbox', { name: 'Write an annotation in Markdown' })
				.fill('Intent');
			await settleInteraction();
		});
		await waitForOperationCount(surface, 1);
		await act(async (): Promise<void> => {
			surface.settleMostRecentAdmissionRequired({
				candidateSessionIds: [annotationSessionId],
				reason: 'uncertain_continuity_choice',
			});
			await settleInteraction();
		});

		await expect.element(rendered.getByRole('button', { name: 'Continue' })).toBeVisible();
		await expect.element(rendered.getByRole('button', { name: 'Leave Paused' })).toBeVisible();
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Start Another' }).click();
			await settleInteraction();
		});
		await waitForOperationCount(surface, 2);
		expect(surface.sentOperations.at(-1)).toMatchObject({
			admission: { kind: 'newSession' },
			body: 'Intent',
			kind: 'root.create',
		});
	});
});

function AdmissionFixture(props: {
	readonly surface: RecordingAnnotationBrowserSurface;
}): ReactElement {
	return (
		<WorktreeAnnotationSurfaceProvider surfaceClient={props.surface.client}>
			<WorktreeAnnotationNewMessageComposer
				createOperation={(body, editToken, admission) => ({
					admission: admission ?? { kind: 'implicitOrSingle' },
					body,
					editToken,
					kind: 'root.create',
					origin: {
						diffSide: null,
						endLine: 12,
						kind: 'located',
						path: 'Sources/App/View.swift',
						sourceIdentity: 'source-file-1',
						sourceRole: 'file',
						startLine: 12,
					},
				})}
				onCancel={() => {}}
				onSaved={() => {}}
				placeholder="Write an annotation in Markdown"
			/>
		</WorktreeAnnotationSurfaceProvider>
	);
}

async function publishSessions(
	surface: RecordingAnnotationBrowserSurface,
	sourceRelationship: 'applicable' | 'uncertain',
): Promise<void> {
	await act(async (): Promise<void> => {
		surface.publishProjectionState({
			expectedThreadCount: 0,
			revision: 3,
			sessions: [
				annotationSessionSummary({
					revision: 3,
					sessionId: annotationSessionId,
					sourceRelationship,
				}),
				annotationSessionSummary({
					revision: 3,
					sessionId: secondSessionId,
					sourceRelationship,
				}),
			],
		});
		await Promise.resolve();
	});
}

async function waitForOperationCount(
	surface: RecordingAnnotationBrowserSurface,
	expectedCount: number,
): Promise<void> {
	for (let attempt = 0; attempt < 50; attempt += 1) {
		if (surface.sentOperations.length >= expectedCount) return;
		// eslint-disable-next-line no-await-in-loop -- Browser state must settle between bounded observation attempts.
		await act(async (): Promise<void> => settleInteraction());
	}
	throw new Error(`Expected ${expectedCount} annotation operations.`);
}

async function waitForOperationKind(
	surface: RecordingAnnotationBrowserSurface,
	kind: 'demand.acquire',
): Promise<void> {
	for (let attempt = 0; attempt < 50; attempt += 1) {
		if (surface.sentOperations.some((operation) => operation.kind === kind)) return;
		// eslint-disable-next-line no-await-in-loop -- Browser state must settle between bounded observation attempts.
		await act(async (): Promise<void> => settleInteraction());
	}
	throw new Error(`Expected annotation operation ${kind}.`);
}

async function settleInteraction(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	await Promise.resolve();
}
