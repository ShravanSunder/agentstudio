import { act } from 'react';
import { beforeEach, describe, expect, test } from 'vitest';
import { page, userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import { RecordingAnnotationBrowserSurface } from './worktree-annotation-browser-test-support.js';
import {
	locatedContext,
	makeSavedMessage,
	publishThreadMessages,
	renderAnnotationProjection,
	replyMessageId,
	rootMessageId,
	secondRootMessageId,
} from './worktree-annotation-thread.browser.test-support.js';

describe('worktree annotation thread status presentation', () => {
	beforeEach(async (): Promise<void> => {
		await act(async (): Promise<void> => {
			await userEvent.unhover(document.body);
		});
	});

	test('summarizes hidden draft, locked, and relocated thread state', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(
			surface,
			[
				{
					...makeSavedMessage({ body: 'Earlier draft.', messageId: rootMessageId }),
					draft: { activeEditToken: null, body: 'Earlier draft changes.', revision: 2 },
				},
				{
					...makeSavedMessage({
						body: 'Locked reply.',
						messageId: replyMessageId,
						ordinal: 1,
					}),
					status: 'locked',
				},
				makeSavedMessage({
					body: 'Latest reply.',
					messageId: secondRootMessageId,
					ordinal: 2,
				}),
			],
			{ ...locatedContext, placement: 'relocated' },
		);

		await expect.element(rendered.getByText('Latest reply.')).toBeVisible();
		await expect.element(rendered.getByText('Draft')).toBeVisible();
		await expect
			.element(rendered.getByRole('img', { name: 'Contains copied or exported comments' }))
			.toBeVisible();
		expect(rendered.container.textContent).not.toContain('Contains locked output');
		await expect.element(rendered.getByText('Relocated')).toBeVisible();
		const lockedStatus = rendered
			.getByRole('img', { name: 'Contains copied or exported comments' })
			.element();
		expect(lockedStatus.getAttribute('tabindex')).toBe('0');
		await act(async (): Promise<void> => {
			lockedStatus.focus();
			await userEvent.keyboard('{Shift>}{Tab}{/Shift}{Tab}');
			await expect
				.element(page.getByText('Copied or exported comments cannot be edited.'))
				.toBeVisible();
		});
		expect(document.activeElement).toBe(lockedStatus);
		expect(
			page
				.getByText('Copied or exported comments cannot be edited.')
				.element()
				.getAttribute('data-slot'),
		).toBe('tooltip-content');
		await page.screenshot({ path: '../../../tmp/bridgeweb-annotation-lock-tooltip.png' });
	});

	test('distinguishes the neutral Draft cue from yellow Pending state', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Earlier message.', messageId: rootMessageId }),
			{
				...makeSavedMessage({
					body: 'Saved latest message.',
					messageId: replyMessageId,
					ordinal: 1,
				}),
				draft: {
					activeEditToken: null,
					body: 'Unsaved latest changes.',
					revision: 2,
				},
			},
		]);

		await expect.element(rendered.getByText('Unsaved latest changes.')).toBeVisible();
		await expect
			.element(rendered.getByTestId('worktree-annotation-message').getByText('Draft'))
			.toBeVisible();
		const draftCue = rendered.getByTestId('worktree-annotation-thread-summary').getByText('Draft');
		await expect.element(draftCue).toBeVisible();
		expect(draftCue.element().className).not.toContain('text-warning');
		expect(document.querySelector('[data-annotation-draft="present"] .bg-warning')).toBeNull();
	});

	test('keeps output inclusion controls out of the thread timeline', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Earlier included message.', messageId: rootMessageId }),
			makeSavedMessage({ body: 'Latest included message.', messageId: replyMessageId, ordinal: 1 }),
		]);
		expect(document.querySelector('[aria-label="Include latest comment"]')).toBeNull();
		expect(document.querySelector('[aria-label="Exclude latest comment"]')).toBeNull();
		expect(rendered.getByText('Mixed inclusion').all()).toHaveLength(0);
	});
});
