import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import './bridge-app.css';
import { BridgeReviewComparisonStatusBanner } from './bridge-review-comparison-status-banner.js';

describe('BridgeReviewComparisonStatusBanner', () => {
	test('announces pending comparison accessibly without presenting a visible layout row', async () => {
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
		expect(rendered.getByTestId('bridge-review-comparison-loading-spinner').query()).toBeNull();
		expect(rendered.getByRole('progressbar').query()).toBeNull();
		expect(rendered.getByTestId('bridge-review-comparison-status-region').query()).toBeNull();
		expect(getComputedStyle(rendered.getByRole('status').element()).position).toBe('absolute');
		expect(rendered.getByRole('button', { name: 'Retry' }).query()).toBeNull();
	});

	test('removes the accessible loading status when the comparison settles', async () => {
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

		expect(rendered.getByRole('status').query()).toBeNull();
		expect(rendered.getByTestId('bridge-review-comparison-status-region').query()).toBeNull();
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
