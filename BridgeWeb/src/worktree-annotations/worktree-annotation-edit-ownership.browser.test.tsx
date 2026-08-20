import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import type { WorktreeAnnotationMessageEntry } from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationProjection,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';
import { WorktreeAnnotationThread } from './worktree-annotation-thread.js';

describe('worktree annotation browser edit ownership', () => {
	test('keeps one saved-message edit token across a Pierre portal replacement', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<ProjectedThread portalGeneration={0} />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await publishMessage(
			surface,
			draftMessage({ activeEditToken: 'persisted-token', revision: 1 }),
		);

		await act(async (): Promise<void> => {
			await rendered.getByText('Durable draft').click();
			await settleInteraction();
		});
		await waitForOperationKind(surface, 'draft.edit.acquire');
		const firstAcquire = surface.sentOperations.find(
			(operation) => operation.kind === 'draft.edit.acquire',
		);
		if (firstAcquire?.kind !== 'draft.edit.acquire') {
			throw new Error('Expected the initial saved-message edit-token acquire.');
		}

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			surface.publishThread({
				context: locatedContext,
				message: draftMessage({ activeEditToken: firstAcquire.editToken, revision: 2 }),
			});
			await settleInteraction();
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Annotation Markdown' }))
			.toBeEnabled();

		await rendered.rerender(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<ProjectedThread portalGeneration={1} />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await act(async (): Promise<void> => settleInteraction());

		expect(
			surface.sentOperations.flatMap((operation): readonly string[] =>
				operation.kind === 'draft.edit.acquire' ? [operation.editToken] : [],
			),
		).toEqual([firstAcquire.editToken]);
		expect(
			surface.sentOperations.filter((operation) => operation.kind === 'draft.edit.release'),
		).toHaveLength(0);
	});

	test('acquires an existing draft with a new token, flushes, then releases', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<ProjectedThread />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await publishMessage(
			surface,
			draftMessage({ activeEditToken: 'persisted-token', revision: 1 }),
		);

		await act(async (): Promise<void> => {
			await rendered.getByText('Durable draft').click();
			await settleInteraction();
		});
		await waitForOperationKind(surface, 'draft.edit.acquire');
		const acquire = surface.sentOperations.find(
			(operation) => operation.kind === 'draft.edit.acquire',
		);
		if (acquire?.kind !== 'draft.edit.acquire') throw new Error('Expected draft.edit.acquire.');
		expect(acquire.editToken).not.toBe('persisted-token');

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			surface.publishThread({
				context: locatedContext,
				message: draftMessage({ activeEditToken: acquire.editToken, revision: 2 }),
			});
			await settleInteraction();
		});
		const editor = rendered.getByRole('textbox', { name: 'Annotation Markdown' });
		await expect.element(editor).toBeEnabled();
		await act(async (): Promise<void> => {
			await editor.fill('Changed durable draft');
			editor.element().blur();
			await settleInteraction();
		});
		await waitForOperationKind(surface, 'draft.flush');
		const flush = surface.sentOperations.find((operation) => operation.kind === 'draft.flush');
		if (flush?.kind !== 'draft.flush') throw new Error('Expected draft.flush.');

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			surface.publishThread({
				context: locatedContext,
				message: {
					...draftMessage({ activeEditToken: acquire.editToken, revision: 3 }),
					draft: {
						activeEditToken: acquire.editToken,
						body: 'Changed durable draft',
						revision: 3,
					},
				},
			});
			await settleInteraction();
		});
		await waitForOperationKind(surface, 'draft.edit.release');
		expect(
			surface.sentOperations
				.map((operation) => operation.kind)
				.filter((kind) => kind.startsWith('draft.')),
		).toEqual(['draft.edit.acquire', 'draft.flush', 'draft.edit.release']);
	});
});

function ProjectedThread(props: { readonly portalGeneration?: number }): ReactElement | null {
	const projection = useWorktreeAnnotationProjection();
	return projection.threads[0] === undefined ? null : (
		<WorktreeAnnotationThread key={props.portalGeneration} thread={projection.threads[0]} />
	);
}

const locatedContext = {
	diffSide: null,
	endLine: 8,
	path: 'Sources/App/View.swift',
	placement: 'exact',
	resolution: 'open',
	scope: 'located',
	sourceIdentity: 'descriptor-file-1',
	sourceRole: 'file',
	startLine: 8,
	threadId: annotationHeadThreadId,
} as const;

function draftMessage(props: {
	readonly activeEditToken: string | null;
	readonly revision: number;
}): WorktreeAnnotationMessageEntry {
	return {
		...annotationMessage({
			messageId: '00000000-0000-7000-8000-000000000031',
			sessionRevision: props.revision + 2,
			threadId: annotationHeadThreadId,
		}),
		draft: {
			activeEditToken: props.activeEditToken,
			body: 'Durable draft',
			revision: props.revision,
		},
	};
}

async function publishMessage(
	surface: RecordingAnnotationBrowserSurface,
	message: WorktreeAnnotationMessageEntry,
): Promise<void> {
	await act(async (): Promise<void> => {
		surface.publishProjectionState({
			expectedThreadCount: 1,
			revision: 3,
			sessions: [annotationSessionSummary({ revision: 3, sessionId: annotationSessionId })],
		});
		surface.publishThread({ context: locatedContext, message });
		await settleInteraction();
	});
}

async function waitForOperationKind(
	surface: RecordingAnnotationBrowserSurface,
	kind: 'draft.edit.acquire' | 'draft.edit.release' | 'draft.flush',
): Promise<void> {
	for (let attempt = 0; attempt < 60; attempt += 1) {
		if (surface.sentOperations.some((operation) => operation.kind === kind)) return;
		// eslint-disable-next-line no-await-in-loop -- Browser state must settle between bounded observation attempts.
		await act(async (): Promise<void> => settleInteraction());
	}
	throw new Error(`Expected ${kind} annotation operation.`);
}

async function settleInteraction(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	await Promise.resolve();
}
