import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production CSS.
import './bridge-app.css';
import type { BridgeProductReviewComparisonTargetCatalog } from '../core/comm-worker/bridge-product-review-comparison-contracts.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { BridgeReviewComparisonControl } from './bridge-review-comparison-control.js';

type ReviewComparisonTargetCatalog = BridgeProductReviewComparisonTargetCatalog;

describe('BridgeReviewComparisonControl UX Browser Mode', () => {
	test('presents the current branch and one effective comparison commit as a compact hierarchy', async () => {
		// Arrange
		const symbolicTarget = {
			basis: 'commonCommit',
			kind: 'ref',
			name: 'origin/journey-integration',
		} as const;
		const baseReviewPackage = makeBridgeReviewPackage();
		const reviewPackage: BridgeReviewPackage = {
			...baseReviewPackage,
			comparisonOrigin: {
				baseOID: 'b'.repeat(40),
				baseRole: 'commonCommit',
				comparedRole: 'capturedWorkingTree',
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
					repositoryDefaultTarget: { branchName: 'journey-integration', remoteName: 'origin' },
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
		const baseBranchLegend = rendered.getByText('Base branch', { exact: true });
		await expect.element(baseBranchLegend).toBeVisible();
		expect(getComputedStyle(baseBranchLegend.element()).textTransform).toBe('uppercase');
		await expect
			.element(rendered.getByText('origin/journey-integration', { exact: true }))
			.toBeVisible();
		await expect.element(rendered.getByText('Default', { exact: true })).toBeVisible();
		await expect.element(rendered.getByText('Comparing from', { exact: true })).toBeVisible();
		await expect.element(rendered.getByText('Common commit @', { exact: true })).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-effective-revision'))
			.toHaveTextContent('bbbbbbbbbbbb');
		const currentState = rendered.getByTestId('bridge-review-comparison-current-state');
		const selectionState = rendered.getByTestId('bridge-review-comparison-target-selection');
		const sectionDivider = rendered.getByTestId('bridge-review-comparison-section-divider');
		const currentStateBounds = currentState.element().getBoundingClientRect();
		const dividerBounds = sectionDivider.element().getBoundingClientRect();
		const selectionStateBounds = selectionState.element().getBoundingClientRect();
		expect(getComputedStyle(currentState.element()).borderTopWidth).toBe('0px');
		expect(getComputedStyle(sectionDivider.element()).height).toBe('1px');
		expect(dividerBounds.top - currentStateBounds.bottom).toBeGreaterThanOrEqual(10);
		expect(selectionStateBounds.top - dividerBounds.bottom).toBeGreaterThanOrEqual(10);
		const popupText =
			rendered.getByTestId('bridge-review-comparison-content').element().textContent ?? '';
		expect(popupText).not.toContain('Current comparison');
		expect(popupText).not.toContain('Review starts from');
		expect(popupText).not.toContain('Latest commit shared with');
		expect(popupText).not.toContain('Comparison refreshed');
	});

	test('selects direct branch-tip comparison through the owned radio menu', async () => {
		// Arrange
		const applyTarget = vi.fn();
		const symbolicTarget = {
			basis: 'commonCommit',
			kind: 'branch',
			name: 'journey-stack-base',
		} as const;
		const baseReviewPackage = makeBridgeReviewPackage();
		const reviewPackage: BridgeReviewPackage = {
			...baseReviewPackage,
			comparisonOrigin: {
				baseOID: 'a'.repeat(40),
				baseRole: 'commonCommit',
				comparedRole: 'capturedWorkingTree',
				kind: 'contribution',
				resolvedTargetOID: 'b'.repeat(40),
				reviewedHeadOID: 'c'.repeat(40),
				symbolicTarget,
			},
			packageId: 'package-custom-branch',
			revision: 8,
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
					repositoryDefaultTarget: null,
				}}
				displayedReviewPackage={reviewPackage}
				onApplyTarget={applyTarget}
			/>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
			await rendered.getByTestId('bridge-review-comparison-basis-trigger').click();
		});

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('menuitemradio', { name: 'Branch tip' }).click();
		});

		// Assert
		expect(applyTarget).toHaveBeenCalledExactlyOnceWith({
			basis: 'branchTip',
			kind: 'branch',
			name: 'journey-stack-base',
		});
		await expect.element(rendered.getByText('journey-stack-base', { exact: true })).toBeVisible();
		expect(
			(
				rendered.getByTestId('bridge-review-comparison-content').element().textContent ?? ''
			).includes('Default'),
		).toBe(false);
	});

	test('shows an exact commit as one direct base without a basis selector', async () => {
		// Arrange
		const commitOID = 'd'.repeat(40);
		const baseReviewPackage = makeBridgeReviewPackage();
		const reviewPackage: BridgeReviewPackage = {
			...baseReviewPackage,
			comparisonOrigin: {
				baseOID: commitOID,
				baseRole: 'selectedTarget',
				comparedRole: 'capturedWorkingTree',
				kind: 'contribution',
				resolvedTargetOID: commitOID,
				reviewedHeadOID: 'e'.repeat(40),
				symbolicTarget: { kind: 'commit', oid: commitOID },
			},
			packageId: 'package-exact-commit',
			revision: 9,
		};
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={{
					activeTarget: { kind: 'commit', oid: commitOID },
					attempt: { reviewGeneration: 1, status: 'settled' },
					displayedSnapshot: {
						packageId: reviewPackage.packageId,
						reviewGeneration: reviewPackage.reviewGeneration,
						revision: reviewPackage.revision,
						status: 'current',
					},
					repositoryDefaultTarget: null,
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
		await expect.element(rendered.getByText('Base commit', { exact: true })).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-effective-revision'))
			.toHaveTextContent('dddddddddddd');
		expect(
			document.querySelector('[data-testid="bridge-review-comparison-basis-trigger"]'),
		).toBeNull();
	});

	test('keeps stale predecessor target labeled during an unavailable request', async () => {
		// Arrange
		const baseReviewPackage = makeBridgeReviewPackage();
		const stalePackage: BridgeReviewPackage = {
			...baseReviewPackage,
			comparisonOrigin: {
				baseOID: 'a'.repeat(40),
				baseRole: 'commonCommit',
				comparedRole: 'capturedWorkingTree',
				kind: 'contribution',
				resolvedTargetOID: '1'.repeat(40),
				reviewedHeadOID: 'h'.repeat(40),
				symbolicTarget: {
					basis: 'commonCommit',
					branchName: 'master',
					kind: 'localDefaultBranch',
				},
			},
			packageId: 'package-unavailable-predecessor',
			revision: 5,
		};
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={{
					activeTarget: { basis: 'commonCommit', kind: 'branch', name: 'release/next' },
					attempt: {
						failureKind: 'targetNotFound',
						retryable: true,
						status: 'unavailable',
					},
					displayedSnapshot: {
						packageId: stalePackage.packageId,
						reviewGeneration: stalePackage.reviewGeneration,
						revision: stalePackage.revision,
						status: 'stale',
					},
					repositoryDefaultTarget: null,
				}}
				displayedReviewPackage={stalePackage}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-trigger'))
			.toHaveTextContent('Compare: master · Unavailable');
		await expect.element(rendered.getByText('Comparison unavailable')).toBeVisible();
		await expect
			.element(
				rendered.getByText(
					'The selected target could not be refreshed. The previous comparison remains visible.',
				),
			)
			.toBeVisible();
		await expect.element(rendered.getByText('Base branch', { exact: true })).toBeVisible();
		await expect.element(rendered.getByText('master', { exact: true })).toBeVisible();
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

	test('presents branch search and choices inside one bounded selector surface', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		const selectorSurface = rendered.getByTestId('bridge-review-comparison-branch-selector');
		await expect.element(selectorSurface).toBeVisible();
		expect(getComputedStyle(selectorSurface.element()).borderTopWidth).toBe('1px');
		expect(selectorSurface.element().querySelector('[data-slot="combobox-input"]')).not.toBeNull();
		expect(
			rendered
				.getByTestId('bridge-review-comparison-content')
				.element()
				.querySelector('[data-slot="toggle-group"]'),
		).not.toBeNull();
	});

	test('uses the product small-caps treatment for the popup title', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		const title = rendered.getByRole('heading', { name: 'Compare Worktree' });
		expect(getComputedStyle(title.element()).textTransform).toBe('uppercase');
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

	test('focuses the active text field when the comparison target kind changes', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Commit' }).click();
		});

		// Assert
		await expect.element(rendered.getByRole('textbox', { name: 'Commit hash' })).toHaveFocus();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Branch' }).click();
		});

		// Assert
		await expect.element(rendered.getByRole('combobox', { name: 'Search branches' })).toHaveFocus();
	});

	test('uses the neutral themed action for an explicit commit comparison', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
			await rendered.getByRole('button', { name: 'Commit' }).click();
		});

		// Assert
		const compareButton = rendered.getByRole('button', { name: 'Compare to this commit' });
		expect(getComputedStyle(compareButton.element()).backgroundColor).toBe('rgb(49, 50, 68)');
	});
});

async function renderComparisonTargetPicker(): ReturnType<typeof render> {
	return render(
		<BridgeReviewComparisonControl
			comparisonPresentation={{
				activeTarget: {
					basis: 'commonCommit',
					branchName: 'main',
					kind: 'localDefaultBranch',
				},
				attempt: { reviewGeneration: 1, status: 'settled' },
				displayedSnapshot: { status: 'none' },
				repositoryDefaultTarget: { branchName: 'main', remoteName: 'origin' },
			}}
			displayedReviewPackage={null}
			onApplyTarget={vi.fn()}
			targetQueryState={{ catalog: targetCatalog(), message: null, status: 'ready' }}
		/>,
	);
}

function targetCatalog(): ReviewComparisonTargetCatalog {
	return {
		capturedAtUnixMilliseconds: 1_700_000_000_000,
		cutoffUnixMilliseconds: 1_699_000_000_000,
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
		currentTarget: null,
		isTruncated: false,
	};
}
