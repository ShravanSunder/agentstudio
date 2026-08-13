import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import './bridge-app.css';
import { BridgeReviewComparisonStatusBanner } from './bridge-review-comparison-status-banner.js';

describe('BridgeReviewComparisonStatusBanner', () => {
	test('announces an indeterminate pending comparison without presenting retry', async () => {
		const rendered = await render(
			<BridgeReviewComparisonStatusBanner
				onRetry={vi.fn()}
				state={{
					displayedTargetLabel: 'origin/main',
					kind: 'loadingPrevious',
					requestedTargetLabel: 'feature/new-target',
				}}
			/>,
		);

		await expect
			.element(rendered.getByRole('status'))
			.toHaveTextContent('Loading comparison with feature/new-target');
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-loading-spinner'))
			.toBeVisible();
		expect(rendered.getByRole('progressbar').query()).toBeNull();
		const statusRegion = rendered.getByTestId('bridge-review-comparison-status-region').element();
		expect(statusRegion.dataset['motionState']).toBe('entering');
		expect(getComputedStyle(statusRegion).animationDuration).toBe('0.12s');
		expect(rendered.getByRole('button', { name: 'Retry' }).query()).toBeNull();
	});

	test('animates the loading region out before removing the settled comparison status', async () => {
		const rendered = await render(
			<BridgeReviewComparisonStatusBanner
				onRetry={vi.fn()}
				state={{
					displayedTargetLabel: 'origin/main',
					kind: 'loadingPrevious',
					requestedTargetLabel: 'feature/new-target',
				}}
			/>,
		);

		await rendered.rerender(
			<BridgeReviewComparisonStatusBanner onRetry={vi.fn()} state={{ kind: 'settled' }} />,
		);

		const statusRegion = rendered.getByTestId('bridge-review-comparison-status-region');
		await expect.element(statusRegion).toBeVisible();
		expect(statusRegion.element().dataset['motionState']).toBe('exiting');
		expect(getComputedStyle(statusRegion.element()).animationDuration).toBe('0.12s');

		await act(async (): Promise<void> => {
			statusRegion.element().dispatchEvent(new AnimationEvent('animationend', { bubbles: true }));
		});
		expect(
			rendered.getByTestId('bridge-review-comparison-status-region').element().dataset[
				'motionState'
			],
		).toBe('settled');
		expect(rendered.getByTestId('bridge-review-comparison-status-banner').query()).toBeNull();
	});

	test('keeps failure and retry inside the comparison pane banner', async () => {
		const retryTarget = {
			basis: 'commonCommit' as const,
			kind: 'ref' as const,
			name: 'feature/new-target',
		};
		const onRetry = vi.fn();
		const rendered = await render(
			<BridgeReviewComparisonStatusBanner
				onRetry={onRetry}
				state={{
					displayedTargetLabel: 'origin/main',
					kind: 'failedPrevious',
					requestedTargetLabel: 'feature/new-target',
					retryTarget,
				}}
			/>,
		);

		await expect
			.element(rendered.getByRole('alert'))
			.toHaveTextContent(
				'Couldn’t load feature/new-target. Showing the previous comparison with origin/main.',
			);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Retry' }).click();
		});
		expect(onRetry).toHaveBeenCalledExactlyOnceWith(retryTarget);
	});
});
