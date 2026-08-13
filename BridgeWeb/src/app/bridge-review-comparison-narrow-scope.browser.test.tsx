import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production CSS.
import './bridge-app.css';
import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { BridgeReviewComparisonControl } from './bridge-review-comparison-control.js';

const narrowComparisonScenarios = [
	{
		description: 'Shows changes added to the staging area.',
		label: 'Staged only',
		reviewPackage: stagedOnlyPackage(),
	},
	{
		description: 'Shows tracked working tree changes that have not been staged.',
		label: 'Unstaged only',
		reviewPackage: unstagedOnlyPackage(),
	},
] as const;

describe('BridgeReviewComparisonControl narrow comparison scope', () => {
	test.each(narrowComparisonScenarios)(
		'hides the retained contribution target for $label comparisons',
		async (scenario) => {
			// Arrange
			const rendered = await render(
				<BridgeReviewComparisonControl
					comparisonPresentation={currentPresentationForPackage(scenario.reviewPackage)}
					displayedReviewPackage={scenario.reviewPackage}
					onApplyTarget={vi.fn()}
				/>,
			);

			// Assert
			const trigger = rendered.getByTestId('bridge-review-comparison-trigger');
			await expect.element(trigger).toHaveTextContent(scenario.label);
			expect(trigger.element().textContent).not.toContain('master');
		},
	);

	test.each(narrowComparisonScenarios)(
		'does not offer a selectable target for a $label narrow comparison',
		async (scenario) => {
			// Arrange
			const rendered = await render(
				<BridgeReviewComparisonControl
					comparisonPresentation={currentPresentationForPackage(scenario.reviewPackage)}
					displayedReviewPackage={scenario.reviewPackage}
					onApplyTarget={vi.fn()}
				/>,
			);
			const trigger = rendered.getByTestId('bridge-review-comparison-trigger');
			const descriptionId = trigger.element().getAttribute('aria-describedby');

			// Assert
			expect(trigger.element().textContent).toContain(scenario.label);
			expect(descriptionId).not.toBeNull();
			expect(document.getElementById(descriptionId ?? '')?.textContent).toBe(scenario.description);
			expect(trigger.element().getAttribute('aria-haspopup')).toBeNull();
			expect(document.querySelector('[data-testid="bridge-review-comparison-content"]')).toBeNull();
			expect(document.querySelector('[role="combobox"]')).toBeNull();
			expect(document.querySelector('[role="button"][aria-label="Commit"]')).toBeNull();
		},
	);
});

function currentPresentationForPackage(
	reviewPackage: BridgeReviewPackage,
): NonNullable<BridgeWorkerPanelChromePatchPayload['reviewComparison']> {
	return {
		activeTarget: { basis: 'commonCommit', branchName: 'master', kind: 'localDefaultBranch' },
		attempt: { reviewGeneration: 1, status: 'settled' },
		displayedSnapshot: {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
			status: 'current',
		},
		repositoryDefaultTarget: null,
	};
}

function stagedOnlyPackage(): BridgeReviewPackage {
	const reviewPackage = makeBridgeReviewPackage();
	return {
		...reviewPackage,
		baseEndpoint: { ...reviewPackage.baseEndpoint, kind: 'gitRef' },
		comparisonOrigin: null,
		headEndpoint: { ...reviewPackage.headEndpoint, kind: 'index' },
		packageId: 'package-staged-only',
		query: { ...reviewPackage.query, comparisonSemantics: 'indexDelta' },
	};
}

function unstagedOnlyPackage(): BridgeReviewPackage {
	const reviewPackage = makeBridgeReviewPackage();
	return {
		...reviewPackage,
		baseEndpoint: { ...reviewPackage.baseEndpoint, kind: 'index' },
		comparisonOrigin: null,
		headEndpoint: { ...reviewPackage.headEndpoint, kind: 'workingTree' },
		packageId: 'package-unstaged-only',
		query: { ...reviewPackage.query, comparisonSemantics: 'workingTreeDelta' },
	};
}
