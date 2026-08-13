import { act } from 'react';
import { createRef, type ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production CSS.
import './bridge-app.css';
import type { BridgeProductReviewComparisonTargetCatalog } from '../core/comm-worker/bridge-product-review-comparison-contracts.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { BridgeReviewComparisonBranchSelector } from './bridge-review-comparison-branch-selector.js';
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
		await expect
			.element(rendered.getByRole('heading', { name: 'Current comparison' }))
			.toBeVisible();
		await expect
			.element(rendered.getByText('Branch: origin/journey-integration', { exact: true }))
			.toBeVisible();
		await expect.element(rendered.getByText('Default', { exact: true })).toBeVisible();
		await expect.element(rendered.getByText('Comparing from:', { exact: true })).toBeVisible();
		await expect.element(rendered.getByText('Common commit @', { exact: true })).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-effective-revision'))
			.toHaveTextContent('bbbbbbbbbbbb');
		const currentState = rendered.getByTestId('bridge-review-comparison-current-state');
		const currentTarget = rendered.getByTestId('bridge-review-comparison-current-target');
		const currentBasis = rendered.getByTestId('bridge-review-comparison-current-basis');
		expect(getComputedStyle(currentTarget.element()).fontSize).toBe(
			getComputedStyle(currentBasis.element()).fontSize,
		);
		expect(getComputedStyle(currentTarget.element()).fontWeight).toBe(
			getComputedStyle(currentBasis.element()).fontWeight,
		);
		expect(getComputedStyle(currentTarget.element()).color).toBe(
			getComputedStyle(currentBasis.element()).color,
		);
		expect(currentState.element().querySelector('button')).toBeNull();
		expect(
			currentState
				.element()
				.querySelector('[data-testid="bridge-review-comparison-basis-trigger"]'),
		).toBeNull();
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
		expect(popupText).toContain('Current comparison');
		expect(popupText).not.toContain('Review starts from');
		expect(popupText).not.toContain('Latest commit shared with');
		expect(popupText).not.toContain('Comparison refreshed');
		expect(popupText).not.toContain('Base branch');
		expect(popupText).not.toContain('origin/journey-integration @');
	});

	test('selects branch basis before applying the selected branch', async () => {
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
				targetQueryState={{ catalog: targetCatalog(), message: null, status: 'ready' }}
			/>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Act: choosing the basis alone must not mutate the active comparison.
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Branch tip' }).click();
		});
		expect(applyTarget).not.toHaveBeenCalled();

		// Act: the chosen basis is applied with the selected branch.
		await act(async (): Promise<void> => {
			await rendered.getByTestId('comparison-branch-origin-main').click();
		});

		// Assert
		expect(applyTarget).toHaveBeenCalledExactlyOnceWith({
			basis: 'branchTip',
			branchName: 'main',
			kind: 'originDefaultBranch',
			remoteName: 'origin',
		});
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-trigger'))
			.toHaveTextContent('Compare to: journey-stack-base');
		expect(
			(
				rendered.getByTestId('bridge-review-comparison-current-state').element().textContent ?? ''
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
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-current-state'))
			.toHaveTextContent('Commit:dddddddddddd');
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
			.toHaveTextContent('Compare to: release/next · Unavailable');
		await expect.element(rendered.getByText('Comparison unavailable')).toBeVisible();
		await expect
			.element(
				rendered.getByText(
					'The selected target could not be refreshed. The previous comparison remains visible.',
				),
			)
			.toBeVisible();
		await expect.element(rendered.getByText('Branch: master', { exact: true })).toBeVisible();
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

	test('keeps an open target picker and its query result during same-session refresh', async () => {
		// Arrange
		const cancelTargetQuery = vi.fn();
		const queryTargets = vi.fn();
		const comparisonControl = (disabled: boolean): ReactElement => (
			<BridgeReviewComparisonControl
				comparisonPresentation={{
					activeTarget: {
						basis: 'commonCommit',
						branchName: 'main',
						kind: 'localDefaultBranch',
					},
					attempt: { reviewGeneration: 1, status: disabled ? 'pending' : 'settled' },
					displayedSnapshot: { status: 'none' },
					repositoryDefaultTarget: { branchName: 'main', remoteName: 'origin' },
				}}
				disabled={disabled}
				displayedReviewPackage={null}
				onApplyTarget={vi.fn()}
				onCancelTargetQuery={cancelTargetQuery}
				onQueryTargets={queryTargets}
				targetQueryState={{ catalog: targetCatalog(), message: null, status: 'ready' }}
			/>
		);
		const rendered = await render(comparisonControl(false));
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Act
		await rendered.rerender(comparisonControl(true));

		// Assert
		await expect.element(rendered.getByTestId('bridge-review-comparison-content')).toBeVisible();
		await expect.element(rendered.getByText('origin/main', { exact: true })).toBeVisible();
		expect(queryTargets).toHaveBeenCalledTimes(1);
		expect(cancelTargetQuery).not.toHaveBeenCalled();
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
		expect(selectorSurface.element().querySelector('[data-slot="input-group"]')).not.toBeNull();
		expect(
			rendered
				.getByTestId('bridge-review-comparison-content')
				.element()
				.querySelector('[data-slot="toggle-group"]'),
		).not.toBeNull();
	});

	test('uses one compact standard layout for the comparison selectors', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		const title = rendered.getByRole('heading', { name: 'Compare Worktree' });
		expect(getComputedStyle(title.element()).textTransform).toBe('uppercase');
		const compareWithHeading = rendered.getByText('Compare with', { exact: true });
		await expect.element(compareWithHeading).toBeVisible();
		const targetKindSelector = rendered.getByRole('group', { name: 'Comparison target kind' });
		const branchBasisHeading = rendered.getByText('Compare branches from', { exact: true });
		const branchBasisSelector = rendered.getByRole('group', { name: 'Branch comparison basis' });
		await expect
			.element(rendered.getByRole('button', { name: 'Common commit', exact: true }))
			.toBeVisible();
		const targetKindLayout = compareWithHeading.element().parentElement;
		const branchBasisLayout = branchBasisHeading.element().parentElement;
		expect(targetKindLayout).not.toBeNull();
		expect(branchBasisLayout).not.toBeNull();
		expect(targetKindSelector.element().parentElement?.dataset['slot']).toBe('field');
		expect(branchBasisSelector.element().parentElement?.dataset['slot']).toBe('field');
		const titleBounds = title.element().getBoundingClientRect();
		const compareWithBounds = compareWithHeading.element().getBoundingClientRect();
		const selectorBounds = targetKindSelector.element().getBoundingClientRect();
		const branchBasisHeadingBounds = branchBasisHeading.element().getBoundingClientRect();
		const branchBasisSelectorBounds = branchBasisSelector.element().getBoundingClientRect();
		expect(getComputedStyle(title.element().parentElement ?? title.element()).rowGap).toBe('8px');
		expect(compareWithBounds.top).toBeGreaterThan(titleBounds.bottom);
		expect(branchBasisHeadingBounds.left).toBe(compareWithBounds.left);
		expect(branchBasisSelectorBounds.left).toBe(selectorBounds.left);
		expect(selectorBounds.left).toBeGreaterThan(compareWithBounds.right);
		expect(branchBasisSelectorBounds.left).toBeGreaterThan(branchBasisHeadingBounds.right);
		expect(verticalCenter(selectorBounds)).toBe(verticalCenter(compareWithBounds));
		expect(verticalCenter(branchBasisSelectorBounds)).toBe(
			verticalCenter(branchBasisHeadingBounds),
		);
		expect(selectorBounds.width).toBe(branchBasisSelectorBounds.width);
		expect(Math.round(selectorBounds.height)).toBe(Math.round(branchBasisSelectorBounds.height));
		const toggleItems = [
			...targetKindSelector.element().querySelectorAll('button'),
			...branchBasisSelector.element().querySelectorAll('button'),
		];
		const toggleItemWidths = toggleItems.map((item) => item.getBoundingClientRect().width);
		expect(Math.max(...toggleItemWidths) - Math.min(...toggleItemWidths)).toBeLessThanOrEqual(1);
		expect(new Set(toggleItems.map((item) => getComputedStyle(item).fontSize))).toEqual(
			new Set(['11px']),
		);
		expectToggleGroupTrackToFitItems(targetKindSelector.element());
		expectToggleGroupTrackToFitItems(branchBasisSelector.element());
	});

	test('lets one Escape from branch search reach its parent picker', async () => {
		// Arrange
		const parentKeyDown = vi.fn();
		const rendered = await render(
			<div onKeyDown={parentKeyDown}>
				<BridgeReviewComparisonBranchSelector
					activeTarget={null}
					onRetry={vi.fn()}
					onSelectTarget={vi.fn()}
					searchInputRef={createRef<HTMLInputElement>()}
					targetQueryState={{ catalog: targetCatalog(), message: null, status: 'ready' }}
				/>
			</div>,
		);
		const branchSearch = rendered.getByRole('combobox', { name: 'Search branches' });
		branchSearch.element().focus();

		// Act
		await act(async (): Promise<void> => {
			branchSearch
				.element()
				.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
			await Promise.resolve();
		});

		// Assert
		expect(parentKeyDown).toHaveBeenCalledExactlyOnceWith(
			expect.objectContaining({ key: 'Escape' }),
		);
	});

	test('uses the neutral popover surface and shared compact toolbar trigger treatment', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();
		const trigger = rendered.getByTestId('bridge-review-comparison-trigger');
		expect(getComputedStyle(trigger.element()).fontSize).toBe('11px');
		expect(getComputedStyle(trigger.element()).lineHeight).toBe('11px');
		expect(getComputedStyle(trigger.element()).color).toBe('rgb(186, 194, 222)');

		// Act
		await act(async (): Promise<void> => {
			await trigger.click();
		});

		// Assert
		const content = rendered.getByTestId('bridge-review-comparison-content');
		expect(getComputedStyle(content.element()).backgroundColor).toBe('rgb(30, 30, 46)');
	});

	test('keeps the complete selected target readable in the closed toolbar control', async () => {
		// Arrange
		const targetBranchName = 'feature/review-comparison-target-with-a-realistic-long-name';
		const rendered = await renderComparisonTargetPicker({ targetBranchName });

		// Assert
		const trigger = rendered.getByTestId('bridge-review-comparison-trigger').element();
		const label = rendered.getByText(`Compare to: ${targetBranchName}`, { exact: true }).element();
		expect(label.scrollWidth).toBeLessThanOrEqual(label.clientWidth);
		expect(trigger.scrollWidth).toBeLessThanOrEqual(trigger.clientWidth);
	});

	test('remembers commit mode when the comparison popover reopens', async () => {
		// Arrange
		const cancelTargetQuery = vi.fn();
		const queryTargets = vi.fn();
		const rendered = await renderComparisonTargetPicker({ cancelTargetQuery, queryTargets });
		const trigger = rendered.getByTestId('bridge-review-comparison-trigger');
		await act(async (): Promise<void> => {
			await trigger.click();
			await rendered.getByRole('button', { exact: true, name: 'Commit' }).click();
		});
		expect(queryTargets).toHaveBeenCalledTimes(1);
		expect(cancelTargetQuery).not.toHaveBeenCalled();
		await act(async (): Promise<void> => {
			await trigger.click();
		});
		expect(cancelTargetQuery).toHaveBeenCalledTimes(1);

		// Act
		await act(async (): Promise<void> => {
			await trigger.click();
		});

		// Assert
		await expect
			.element(rendered.getByRole('button', { name: 'Commit', exact: true }))
			.toHaveAttribute('aria-pressed', 'true');
		await expect.element(rendered.getByRole('textbox', { name: 'Commit hash' })).toHaveFocus();
		expect(queryTargets).toHaveBeenCalledTimes(2);
	});

	test('focuses the active text field when the comparison target kind changes', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { exact: true, name: 'Commit' }).click();
		});

		// Assert
		await expect.element(rendered.getByRole('textbox', { name: 'Commit hash' })).toHaveFocus();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { exact: true, name: 'Branch' }).click();
		});

		// Assert
		await expect.element(rendered.getByRole('combobox', { name: 'Search branches' })).toHaveFocus();
	});

	test('uses the neutral themed action for an explicit commit comparison', async () => {
		// Arrange
		const rendered = await renderComparisonTargetPicker();
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
			await rendered.getByRole('button', { exact: true, name: 'Commit' }).click();
		});

		// Assert
		const compareButton = rendered.getByRole('button', { name: 'Compare to this commit' });
		expect(getComputedStyle(compareButton.element()).backgroundColor).toBe('rgb(49, 50, 68)');
	});
});

function expectToggleGroupTrackToFitItems(toggleGroup: Element): void {
	const subpixelRoundingTolerance = 0.01;
	const toggleItems = toggleGroup.querySelectorAll('button');
	const firstToggleItem = toggleItems.item(0);
	const lastToggleItem = toggleItems.item(toggleItems.length - 1);
	expect(toggleItems.length).toBeGreaterThan(0);
	const trackBounds = toggleGroup.getBoundingClientRect();
	const leadingInset = firstToggleItem.getBoundingClientRect().left - trackBounds.left;
	const trailingInset = trackBounds.right - lastToggleItem.getBoundingClientRect().right;
	expect(leadingInset).toBeGreaterThanOrEqual(-subpixelRoundingTolerance);
	expect(leadingInset).toBeLessThanOrEqual(3);
	expect(trailingInset).toBeGreaterThanOrEqual(-subpixelRoundingTolerance);
	expect(trailingInset).toBeLessThanOrEqual(3);
}

function verticalCenter(bounds: DOMRect): number {
	return Math.round(bounds.top + bounds.height / 2);
}

async function renderComparisonTargetPicker(callbacks?: {
	readonly cancelTargetQuery?: () => void;
	readonly queryTargets?: () => void;
	readonly targetBranchName?: string;
}): ReturnType<typeof render> {
	const cancelTargetQuery = callbacks?.cancelTargetQuery ?? vi.fn();
	const queryTargets = callbacks?.queryTargets ?? vi.fn();
	const targetBranchName = callbacks?.targetBranchName ?? 'main';
	return render(
		<BridgeReviewComparisonControl
			comparisonPresentation={{
				activeTarget: {
					basis: 'commonCommit',
					branchName: targetBranchName,
					kind: 'localDefaultBranch',
				},
				attempt: { reviewGeneration: 1, status: 'settled' },
				displayedSnapshot: { status: 'none' },
				repositoryDefaultTarget: { branchName: 'main', remoteName: 'origin' },
			}}
			displayedReviewPackage={null}
			onApplyTarget={vi.fn()}
			onCancelTargetQuery={cancelTargetQuery}
			onQueryTargets={queryTargets}
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
