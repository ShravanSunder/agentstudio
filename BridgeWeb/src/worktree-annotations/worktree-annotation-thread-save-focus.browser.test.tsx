import { act } from 'react';
import { describe, expect, test } from 'vitest';
import { userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	annotationSessionId,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import type { WorktreeAnnotationMessageEntry } from './worktree-annotation-surface-client.js';
import {
	locatedContext,
	makeSavedMessage,
	publishThreadMessages,
	renderAnnotationProjection,
	rootMessageId,
	settleBrowserCondition,
} from './worktree-annotation-thread.browser.test-support.js';

describe('worktree annotation Save focus', () => {
	test('saves a resumed durable draft and naturally returns keyboard ownership', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		const draftMessage = {
			...makeSavedMessage({ body: 'Saved body.', messageId: rootMessageId }),
			draft: {
				activeEditToken: 'annotation-edit-existing-draft',
				body: 'Reviewed body.',
				revision: 1,
			},
			savedRevision: 1,
		} satisfies WorktreeAnnotationMessageEntry;

		await publishThreadMessages(surface, [draftMessage]);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Edit annotation' }).click();
		});
		await settleBrowserCondition(
			(): boolean =>
				surface.sentOperations.some((operation) => operation.kind === 'draft.edit.acquire'),
			'Expected the resumed draft to acquire current-generation edit ownership.',
		);
		const acquireOperation = surface.sentOperations.find(
			(operation) => operation.kind === 'draft.edit.acquire',
		);
		if (acquireOperation?.kind !== 'draft.edit.acquire') {
			throw new Error('Expected draft.edit.acquire before Save.');
		}
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			surface.publishThread({
				context: locatedContext,
				message: {
					...draftMessage,
					draft: {
						activeEditToken: acquireOperation.editToken,
						body: 'Reviewed body.',
						revision: 2,
					},
					sessionRevision: 4,
				},
			});
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Save annotation' }).click();
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'draft.save'),
			'Expected the primary Save action to issue draft.save.',
		);
		expect(surface.sentOperations.at(-1)).toMatchObject({
			kind: 'draft.save',
			messageId: rootMessageId,
		});

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'draft.save');
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => document.querySelector('[aria-label="Annotation Markdown"]') === null,
			'Expected the exact committed Save receipt to close the editor before projection.',
		);
		const thread = rendered.getByTestId('worktree-annotation-thread').element();
		expect(thread.contains(document.activeElement)).toBe(true);
		expect(thread.getAttribute('data-annotation-expanded')).toBe('true');

		await act(async (): Promise<void> => {
			surface.publishThread({
				context: locatedContext,
				message: {
					...draftMessage,
					draft: null,
					savedBody: 'Reviewed body.',
					savedRevision: 2,
					sessionRevision: 5,
				},
			});
			await Promise.resolve();
		});
		await expect
			.element(rendered.getByTestId('worktree-annotation-thread').getByText('Reviewed body.'))
			.toBeVisible();
		expect(thread.contains(document.activeElement)).toBe(true);

		await act(async (): Promise<void> => {
			await userEvent.keyboard('r');
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Reply with Markdown' }))
			.toBeVisible();
		await act(async (): Promise<void> => {
			await userEvent.keyboard('{Escape}');
		});
		await settleBrowserCondition(
			(): boolean => document.querySelector('[aria-label="Reply with Markdown"]') === null,
			'Expected Escape to finish Reply before the Control-R transition.',
		);
		expect(thread.contains(document.activeElement)).toBe(true);

		await act(async (): Promise<void> => {
			await userEvent.keyboard('{Control>}r{/Control}');
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Reply with Markdown' }))
			.toBeVisible();
	});
});
