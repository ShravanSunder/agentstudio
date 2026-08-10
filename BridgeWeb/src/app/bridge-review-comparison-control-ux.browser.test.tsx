import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production CSS.
import './bridge-app.css';
import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { BridgeReviewComparisonControl } from './bridge-review-comparison-control.js';

type ReviewComparisonPresentation = NonNullable<
	BridgeWorkerPanelChromePatchPayload['reviewComparison']
>;
type ReviewComparisonTargetCatalog = NonNullable<ReviewComparisonPresentation['targetCatalog']>;

describe('BridgeReviewComparisonControl UX Browser Mode', () => {
	test('separates a remote-tracking target from its resolved revision with an at sign', async () => {
		// Arrange
		const symbolicTarget = {
			branchName: 'journey-integration',
			kind: 'originDefaultBranch',
			remoteName: 'origin',
		} as const;
		const baseReviewPackage = makeBridgeReviewPackage();
		const reviewPackage: BridgeReviewPackage = {
			...baseReviewPackage,
			comparisonOrigin: {
				baseRole: 'contributionBase',
				comparedRole: 'capturedWorkingTree',
				contributionBaseOID: 'b'.repeat(40),
				kind: 'contribution',
				resolvedTargetOID: `51d3e39cffa1${'0'.repeat(28)}`,
				reviewedHeadOID: 'h'.repeat(40),
				symbolicTarget,
			},
			packageId: 'package-target-copy',
			revision: 5,
		};
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={{
					activeTarget: symbolicTarget,
					attempt: { reviewGeneration: 1, status: 'settled' },
					displayedSnapshot: {
						packageId: reviewPackage.packageId,
						reviewGeneration: reviewPackage.reviewGeneration,
						revision: reviewPackage.revision,
						status: 'current',
					},
					targetCatalog: null,
				}}
				displayedReviewPackage={reviewPackage}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect
			.element(rendered.getByText('origin/journey-integration @', { exact: true }))
			.toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-target-revision'))
			.toHaveTextContent('51d3e39cffa1');
	});

	test('focuses branch search when the comparison popover opens', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect.element(rendered.getByRole('combobox', { name: 'Search branches' })).toHaveFocus();
	});

	test('remembers commit mode when the comparison popover reopens', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();
		const trigger = rendered.getByTestId('bridge-review-comparison-trigger');
		await act(async (): Promise<void> => {
			await trigger.click();
			await rendered.getByRole('button', { name: 'Commit' }).click();
			await trigger.click();
		});

		// Act
		await act(async (): Promise<void> => {
			await trigger.click();
		});

		// Assert
		await expect
			.element(rendered.getByRole('button', { name: 'Commit', exact: true }))
			.toHaveAttribute('aria-pressed', 'true');
		await expect.element(rendered.getByRole('textbox', { name: 'Commit hash' })).toHaveFocus();
	});
});

async function renderComparisonTargetPicker(): ReturnType<typeof render> {
	return render(
		<BridgeReviewComparisonControl
			comparisonPresentation={{
				activeTarget: { branchName: 'main', kind: 'localDefaultBranch' },
				attempt: { reviewGeneration: 1, status: 'settled' },
				displayedSnapshot: { status: 'none' },
				targetCatalog: targetCatalog(),
			}}
			displayedReviewPackage={null}
			onApplyTarget={vi.fn()}
		/>,
	);
}

function targetCatalog(): ReviewComparisonTargetCatalog {
	return {
		branches: [
			{ branchName: 'main', kind: 'local', oid: 'a'.repeat(40) },
			{
				branchName: 'main',
				kind: 'remoteTracking',
				oid: 'b'.repeat(40),
				remoteName: 'origin',
			},
		],
		defaultTarget: {
			branchName: 'main',
			kind: 'remoteTracking',
			oid: 'b'.repeat(40),
			remoteName: 'origin',
		},
	};
}
