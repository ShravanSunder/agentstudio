import type { ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import './bridge-app.css';
import type { BridgeMainReviewRefreshPresentation } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import {
	BridgeReviewRefreshHeaderAction,
	bridgeReviewRefreshHeaderPresentation,
} from './bridge-review-refresh-header-chrome.js';
import { BridgeViewerContentHeader } from './bridge-viewer-content-header.js';

const activeIdentity = {
	generation: 1,
	packageId: 'package-a',
	publicationId: '00000000-0000-7000-8000-000000000001',
	revision: 1,
	sourceIdentity: 'source-a',
} as const;
const candidateIdentity = {
	...activeIdentity,
	publicationId: '00000000-0000-7000-8000-000000000002',
	revision: 2,
} as const;

describe('Bridge Review refresh header chrome', () => {
	test('keeps ordinary, replacement, and unaffected promoted candidates silent', async () => {
		for (const refreshPresentation of [
			candidatePresentation({
				startDisposition: {
					affectedStableFileIdentities: ['item-1'],
					kind: 'sameSource',
					presentationClass: { kind: 'ordinary' },
				},
			}),
			candidatePresentation({ startDisposition: { kind: 'replacement' } }),
			candidatePresentation({
				startDisposition: {
					affectedStableFileIdentities: ['item-2'],
					kind: 'sameSource',
					presentationClass: { kind: 'promoted', reason: 'files' },
				},
			}),
		]) {
			// oxlint-disable-next-line no-await-in-loop -- Each case owns and unmounts one isolated browser document tree before the next case.
			const rendered = await renderRefreshHeader(refreshPresentation, ['item-1']);
			expect(rendered.getByTestId('bridge-viewer-content-status').query()).toBeNull();
			expect(rendered.getByRole('button', { name: 'Apply now' }).query()).toBeNull();
			// oxlint-disable-next-line no-await-in-loop -- Sequential cleanup prevents duplicate global role matches between case trees.
			await rendered.unmount();
		}
	});

	test('treats symbolic unknown as affected only while Review owns attention', async () => {
		const refreshPresentation = candidatePresentation({
			startDisposition: {
				affectedStableFileIdentities: [],
				kind: 'sameSource',
				presentationClass: { kind: 'promoted', reason: 'unknown' },
			},
		});
		const rendered = await renderRefreshHeader(refreshPresentation, ['item-1']);
		await expect
			.element(rendered.getByTestId('bridge-viewer-content-status'))
			.toHaveTextContent('Updating…');

		await rendered.rerender(refreshHeader(refreshPresentation, []));
		expect(rendered.getByTestId('bridge-viewer-content-status').query()).toBeNull();
	});

	test('renders retryable promoted failure through the owned button and preserves focus', async () => {
		const onRetry = vi.fn();
		const refreshPresentation = failurePresentation(true);
		const headerPresentation = bridgeReviewRefreshHeaderPresentation({
			attentionItemIds: ['item-1'],
			canRetry: true,
			refreshPresentation,
		});
		const rendered = await render(
			<BridgeViewerContentHeader
				controls={
					<BridgeReviewRefreshHeaderAction
						action={headerPresentation.action}
						onApplyNow={vi.fn()}
						onRetry={onRetry}
					/>
				}
				mode="review"
				statusText={headerPresentation.statusText}
				title="Sources/First.swift"
			/>,
		);
		await expect
			.element(rendered.getByTestId('bridge-viewer-content-status'))
			.toHaveTextContent('Update unavailable');
		const retry = rendered.getByRole('button', { name: 'Retry' });
		retry.element().focus();
		await retry.click();
		expect(onRetry).toHaveBeenCalledOnce();
		expect(document.activeElement).toBe(retry.element());

		await rendered.rerender(refreshHeader(failurePresentation(false), ['item-1']));
		await expect
			.element(rendered.getByTestId('bridge-viewer-content-status'))
			.toHaveTextContent('Update unavailable');
		expect(rendered.getByRole('button', { name: 'Retry' }).query()).toBeNull();
	});
});

async function renderRefreshHeader(
	refreshPresentation: BridgeMainReviewRefreshPresentation,
	attentionItemIds: readonly string[],
): ReturnType<typeof render> extends Promise<infer TResult> ? Promise<TResult> : never {
	return render(refreshHeader(refreshPresentation, attentionItemIds));
}

function refreshHeader(
	refreshPresentation: BridgeMainReviewRefreshPresentation,
	attentionItemIds: readonly string[],
): ReactElement {
	const presentation = bridgeReviewRefreshHeaderPresentation({
		attentionItemIds,
		canRetry: true,
		refreshPresentation,
	});
	return (
		<BridgeViewerContentHeader
			controls={
				<BridgeReviewRefreshHeaderAction
					action={presentation.action}
					onApplyNow={vi.fn()}
					onRetry={vi.fn()}
				/>
			}
			mode="review"
			statusText={presentation.statusText}
			title="Sources/First.swift"
		/>
	);
}

function candidatePresentation(props: {
	readonly startDisposition: NonNullable<
		BridgeMainReviewRefreshPresentation['candidate']
	>['startDisposition'];
}): BridgeMainReviewRefreshPresentation {
	return {
		activeIdentity,
		candidate: {
			affectedStableFileIdentities:
				props.startDisposition.kind === 'sameSource'
					? props.startDisposition.affectedStableFileIdentities
					: [],
			identity: candidateIdentity,
			role: 'provisional',
			startDisposition: props.startDisposition,
		},
		failure: null,
	};
}

function failurePresentation(retryable: boolean): BridgeMainReviewRefreshPresentation {
	return {
		activeIdentity,
		candidate: null,
		failure: {
			affectedStableFileIdentities: ['item-1'],
			identity: candidateIdentity,
			presentationClass: { kind: 'promoted', reason: 'commits' },
			retryable,
		},
	};
}
