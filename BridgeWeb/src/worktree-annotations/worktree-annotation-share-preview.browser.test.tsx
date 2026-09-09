import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { page } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	WorktreeAnnotationSharePreview,
	type WorktreeAnnotationSharePreviewReadiness,
} from './worktree-annotation-share-preview.js';
import type { WorktreeAnnotationThreadProjection } from './worktree-annotation-surface-client.js';

describe('worktree annotation Share preview', () => {
	test('renders every supplied saved message with literal body, context, author, and no interactions', async () => {
		const markdownLookingBody =
			'# Not a heading\n[not a link](https://example.com)\n' + 'x'.repeat(600);
		const rendered = await render(
			<div className="w-[320px] p-2">
				<WorktreeAnnotationSharePreview
					inlineThreads={[
						threadFixture({
							endLine: 14,
							messages: [
								messageFixture('human-inline', 'First line\nSecond line', 'human'),
								messageFixture('agent-inline', markdownLookingBody, 'agent'),
							],
							path: 'Sources/Feature/Inline.swift',
							placement: 'relocated',
							resolution: 'resolved',
							startLine: 12,
							threadId: 'thread-inline',
						}),
					]}
					otherThreads={[
						threadFixture({
							endLine: 7,
							messages: [messageFixture('agent-other', 'Unavailable source body', 'agent')],
							path: 'Sources/Feature/Original.swift',
							placement: 'unavailable',
							resolution: 'open',
							startLine: 7,
							threadId: 'thread-other',
						}),
					]}
					readiness="current"
				/>
			</div>,
		);

		const preview = rendered.getByRole('region', { name: 'Comments to share' }).element();
		const threadCards = preview.querySelectorAll<HTMLElement>('[data-slot="card"]');
		expect(threadCards).toHaveLength(2);
		const inlineThread = preview.querySelector<HTMLElement>('[data-thread-id="thread-inline"]');
		if (inlineThread === null) throw new Error('Expected the inline thread preview.');
		const inlinePath = inlineThread.querySelector<HTMLElement>('[data-thread-path]');
		const inlineCard = inlineThread.querySelector<HTMLElement>('[data-slot="card"]');
		if (inlinePath === null || inlineCard === null) {
			throw new Error('Expected a path heading followed by one thread card.');
		}
		expect(inlineCard.contains(inlinePath)).toBe(false);
		expect(inlinePath.textContent).toContain('Sources/Feature/Inline.swift');
		expect(inlineCard.querySelectorAll('[data-message-id]')).toHaveLength(2);
		expect(inlineCard.textContent).toContain('You');
		expect(inlineCard.textContent).toContain('Agent');
		expect(inlineCard.textContent).toContain('Lines 12–14');
		expect(inlineCard.querySelector('[data-slot="avatar-fallback"]')?.textContent).toBe('Y');
		expect(getComputedStyle(inlineCard).backgroundColor).toBe('rgb(39, 44, 52)');
		expect(getComputedStyle(inlineCard).borderStyle).toBe('solid');
		expect(getComputedStyle(inlineCard).borderRadius).toBe('8px');
		expect(preview.querySelectorAll('[data-message-id]')).toHaveLength(3);
		expect(preview.querySelector('[data-message-id="human-inline"]')?.textContent).toContain(
			'First line\nSecond line',
		);
		expect(preview.querySelector('[data-message-id="agent-inline"]')?.textContent).toContain(
			markdownLookingBody,
		);
		expect(preview.querySelector('[data-message-id="agent-other"]')?.textContent).toContain(
			'Unavailable source body',
		);
		expect(preview.textContent).toContain('Sources/Feature/Inline.swift');
		expect(preview.textContent).toContain('Lines 12–14');
		expect(preview.textContent).toContain('Sources/Feature/Original.swift');
		expect(preview.textContent).toContain('Line 7');
		expect(preview.textContent).toContain('Relocated');
		expect(preview.textContent).toContain('Source unavailable');
		expect(preview.textContent).toContain('Resolved');
		expect(preview.textContent).toContain('You');
		expect(preview.textContent).toContain('Agent');
		expect(preview.querySelector('a, button, input, textarea, [role="checkbox"]')).toBeNull();
		const humanBody = preview.querySelector<HTMLElement>(
			'[data-message-id="human-inline"] .whitespace-pre-wrap',
		);
		if (humanBody === null) throw new Error('Expected the complete human body.');
		expect(getComputedStyle(humanBody).whiteSpace).toBe('pre-wrap');
		expect(getComputedStyle(humanBody).fontSize).toBe('12px');
		const longBody = preview.querySelector<HTMLElement>('[data-message-id="agent-inline"] p');
		if (longBody === null) throw new Error('Expected the complete long body.');
		expect(longBody.scrollWidth).toBeLessThanOrEqual(longBody.clientWidth);
		expect(preview.getBoundingClientRect().right).toBeLessThanOrEqual(
			preview.parentElement?.getBoundingClientRect().right ?? 0,
		);
		await page.screenshot({
			element: preview,
			path: '../../../tmp/bridgeweb-worktree-annotation-share-preview.png',
		});
	});

	test.each([
		['current', 'No comments to share.'],
		['unknown', 'Loading comments…'],
		['unconfirmed', 'Comments are still being confirmed.'],
	] satisfies readonly (readonly [WorktreeAnnotationSharePreviewReadiness, string])[])(
		'renders the %s empty/readiness state without interactive descendants',
		async (readiness, expectedText) => {
			const rendered = await render(
				<WorktreeAnnotationSharePreview
					inlineThreads={[]}
					otherThreads={[]}
					readiness={readiness}
				/>,
			);
			const state = rendered.getByText(expectedText).element();
			expect(state.querySelector('a, button, input, textarea, [role="checkbox"]')).toBeNull();
		},
	);

	test('labels supplied last-known content as unconfirmed', async () => {
		const rendered = await render(
			<WorktreeAnnotationSharePreview
				inlineThreads={[
					threadFixture({
						endLine: 3,
						messages: [messageFixture('unconfirmed-message', 'Last known saved body', 'human')],
						path: 'Sources/Unconfirmed.swift',
						placement: 'exact',
						resolution: 'open',
						startLine: 3,
						threadId: 'thread-unconfirmed',
					}),
				]}
				otherThreads={[]}
				readiness="unconfirmed"
			/>,
		);

		await expect.element(rendered.getByText('Last known comments')).toBeVisible();
		await expect.element(rendered.getByText('Last known saved body')).toBeVisible();
	});
});

function threadFixture(props: {
	readonly endLine: number;
	readonly messages: readonly WorktreeAnnotationThreadProjection['messages'][number][];
	readonly path: string;
	readonly placement: WorktreeAnnotationThreadProjection['context']['placement'];
	readonly resolution: WorktreeAnnotationThreadProjection['context']['resolution'];
	readonly startLine: number;
	readonly threadId: string;
}): WorktreeAnnotationThreadProjection {
	return {
		context: {
			diffSide: 'additions',
			endLine: props.endLine,
			path: props.path,
			placement: props.placement,
			resolution: props.resolution,
			scope: 'located',
			sourceIdentity: `source-${props.threadId}`,
			sourceRole: 'file',
			startLine: props.startLine,
			threadId: props.threadId,
		},
		messages: props.messages,
	};
}

function messageFixture(
	messageId: string,
	savedBody: string,
	authorKind: 'agent' | 'human',
): WorktreeAnnotationThreadProjection['messages'][number] {
	return {
		attentionState: authorKind === 'agent' ? 'new' : 'not_applicable',
		authorKind,
		createdAt: 1_786_124_400_000,
		draft: null,
		handled: false,
		messageId,
		messageRevision: 1,
		ordinal: 1,
		savedBody,
		savedRevision: 1,
		sessionId: 'session-preview',
		sessionRevision: 1,
		status: 'locked',
		threadId: 'fixture-thread',
		threadRevision: 1,
	};
}
