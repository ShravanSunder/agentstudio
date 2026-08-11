import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production CSS.
import './bridge-app.css';
import type { BridgeProductReviewComparisonTargetCatalog } from '../core/comm-worker/bridge-product-review-comparison-contracts.js';
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

describe('BridgeReviewComparisonControl Browser Mode', () => {
	test('shows the current base branch and effective comparison commit', async () => {
		// Arrange
		const reviewPackage = contributionPackage({
			baseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			packageId: 'package-current',
			resolvedTargetOID: 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
			revision: 3,
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					displayedSnapshot: {
						packageId: reviewPackage.packageId,
						reviewGeneration: reviewPackage.reviewGeneration,
						revision: reviewPackage.revision,
						status: 'current',
					},
				})}
				displayedReviewPackage={reviewPackage}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
			await Promise.resolve();
		});

		// Assert
		const content = rendered.getByTestId('bridge-review-comparison-content');
		await expect.element(content).toBeVisible();
		await expect.element(rendered.getByText('Base branch')).toBeVisible();
		await expect.element(content.getByText('master', { exact: true })).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-effective-revision'))
			.toHaveTextContent('bbbbbbbbbbbb');
		expect(content.element().textContent).not.toMatch(
			/Review starts from|Contribution|three-dot|merge base/u,
		);
	});

	test('describes the default base branch and effective common commit', async () => {
		// Arrange
		const reviewPackage = contributionPackage({
			baseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			packageId: 'package-default-relationship',
			resolvedTargetOID: 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
			revision: 4,
			symbolicTarget: {
				basis: 'commonCommit',
				branchName: 'main',
				kind: 'originDefaultBranch',
				remoteName: 'origin',
			},
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					activeTarget: {
						basis: 'commonCommit',
						branchName: 'main',
						kind: 'originDefaultBranch',
						remoteName: 'origin',
					},
					displayedSnapshot: {
						packageId: reviewPackage.packageId,
						reviewGeneration: reviewPackage.reviewGeneration,
						revision: reviewPackage.revision,
						status: 'current',
					},
				})}
				displayedReviewPackage={reviewPackage}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect.element(rendered.getByText('Base branch')).toBeVisible();
		await expect
			.element(rendered.getByRole('paragraph').getByText('origin/main', { exact: true }))
			.toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-effective-revision'))
			.toHaveTextContent('bbbbbbbbbbbb');
	});

	test('explains when a comparison target must be chosen', async () => {
		// Arrange
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					activeTarget: null,
					attempt: { status: 'selectionRequired' },
					displayedSnapshot: { status: 'none' },
				})}
				displayedReviewPackage={null}
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
			.toHaveTextContent('Choose target');
		await expect.element(rendered.getByText('Choose a comparison target')).toBeVisible();
		await expect
			.element(rendered.getByText('Select a branch or Git reference before reviewing changes.'))
			.toBeVisible();
	});

	test('keeps requested target and stale predecessor facts distinct while pending', async () => {
		// Arrange
		const stalePackage = contributionPackage({
			baseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-stale',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 4,
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					activeTarget: {
						basis: 'commonCommit',
						kind: 'ref',
						name: 'feature/new-target',
					},
					attempt: { reviewGeneration: 2, status: 'pending' },
					displayedSnapshot: {
						packageId: stalePackage.packageId,
						reviewGeneration: stalePackage.reviewGeneration,
						revision: stalePackage.revision,
						status: 'stale',
					},
				})}
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
			.toHaveTextContent('Compare: master · Updating');
		await expect.element(rendered.getByText('Updating comparison')).toBeVisible();
		await expect
			.element(
				rendered.getByText(
					'Showing the previous comparison while the requested target is prepared.',
				),
			)
			.toBeVisible();
		await expect.element(rendered.getByText('Base branch')).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-effective-revision'))
			.toHaveTextContent('aaaaaaaaaaaa');
	});

	test('retries a retryable unavailable comparison with the canonical active target', async () => {
		// Arrange
		const activeTarget = { basis: 'commonCommit', kind: 'branch', name: 'release/next' } as const;
		const applyTarget = vi.fn();
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					activeTarget,
					attempt: {
						failureKind: 'targetNotFound',
						retryable: true,
						status: 'unavailable',
					},
					displayedSnapshot: { status: 'none' },
				})}
				displayedReviewPackage={null}
				onApplyTarget={applyTarget}
				targetQueryState={{ catalog: targetCatalog(), message: null, status: 'ready' }}
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect.element(rendered.getByText('Comparison unavailable')).toBeVisible();
		await expect
			.element(rendered.getByText('The selected target could not be compared.'))
			.toBeVisible();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Retry' }).click();
		});

		// Assert
		expect(applyTarget).toHaveBeenCalledExactlyOnceWith(activeTarget);
	});

	test.each(narrowComparisonScenarios)(
		'hides the retained contribution target for $label comparisons',
		async (scenario) => {
			// Arrange
			const rendered = await render(
				<BridgeReviewComparisonControl
					comparisonPresentation={comparisonPresentation({
						displayedSnapshot: {
							packageId: scenario.reviewPackage.packageId,
							reviewGeneration: scenario.reviewPackage.reviewGeneration,
							revision: scenario.reviewPackage.revision,
							status: 'current',
						},
					})}
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

			// Assert
			expect(trigger.element().getAttribute('aria-haspopup')).toBeNull();
			expect(document.querySelector('[data-testid="bridge-review-comparison-content"]')).toBeNull();
			expect(document.querySelector('[role="combobox"]')).toBeNull();
			expect(document.querySelector('[role="button"][aria-label="Commit"]')).toBeNull();
		},
	);

	test('shows searchable default, local, and remote-tracking branch choices', async () => {
		// Arrange
		const applyTarget = vi.fn();
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					activeTarget: {
						basis: 'commonCommit',
						branchName: 'main',
						kind: 'originDefaultBranch',
						remoteName: 'origin',
					},
					displayedSnapshot: { status: 'none' },
				})}
				displayedReviewPackage={null}
				onApplyTarget={applyTarget}
				targetQueryState={{ catalog: targetCatalog(), message: null, status: 'ready' }}
			/>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-trigger'))
			.toHaveTextContent('Compare: origin/main');
		await expect.element(rendered.getByText('Compare Worktree')).toBeVisible();
		await expect
			.element(rendered.getByRole('button', { name: 'Branch' }))
			.toHaveAttribute('aria-pressed', 'true');
		await expect.element(rendered.getByRole('button', { name: 'Commit' })).toBeVisible();
		await expect
			.element(rendered.getByTestId('comparison-branch-origin-main'))
			.toHaveTextContent(/origin\/main.*Default.*Remote-tracking.*bbbbbbbbbbbb/u);
		await expect
			.element(rendered.getByTestId('comparison-branch-main'))
			.toHaveTextContent(/main.*Local.*aaaaaaaaaaaa/u);
		await expect.element(rendered.getByText('b'.repeat(40), { exact: true })).toBeInTheDocument();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('combobox', { name: 'Search branches' }).fill('feature');
		});

		// Assert
		await expect.element(rendered.getByTestId('comparison-branch-feature-stack')).toBeVisible();
		expect(document.querySelector('[data-testid="comparison-branch-main"]')).toBeNull();
		expect(document.querySelector('[data-testid="comparison-branch-origin-main"]')).toBeNull();
	});

	test.each([
		{
			expectedTarget: {
				basis: 'commonCommit',
				branchName: 'main',
				kind: 'originDefaultBranch',
				remoteName: 'origin',
			},
			rowTestId: 'comparison-branch-origin-main',
		},
		{
			expectedTarget: { basis: 'commonCommit', kind: 'branch', name: 'main' },
			rowTestId: 'comparison-branch-main',
		},
		{
			expectedTarget: {
				basis: 'commonCommit',
				branchName: 'release',
				kind: 'originDefaultBranch',
				remoteName: 'upstream',
			},
			rowTestId: 'comparison-branch-upstream-release',
		},
	])('applies $rowTestId immediately', async (scenario) => {
		// Arrange
		const applyTarget = vi.fn();
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					displayedSnapshot: { status: 'none' },
				})}
				displayedReviewPackage={null}
				onApplyTarget={applyTarget}
				targetQueryState={{ catalog: targetCatalog(), message: null, status: 'ready' }}
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
			await rendered.getByTestId(scenario.rowTestId).click();
		});

		// Assert
		expect(applyTarget).toHaveBeenCalledExactlyOnceWith(scenario.expectedTarget);
	});

	test('accepts only a full hexadecimal commit OID', async () => {
		// Arrange
		const applyTarget = vi.fn();
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					displayedSnapshot: { status: 'none' },
				})}
				displayedReviewPackage={null}
				onApplyTarget={applyTarget}
			/>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
			await rendered.getByRole('button', { name: 'Commit' }).click();
		});
		const commitInput = rendered.getByRole('textbox', { name: 'Commit hash' });

		// Act
		await act(async (): Promise<void> => {
			await commitInput.fill('abc123');
			await rendered.getByRole('button', { name: 'Compare to this commit' }).click();
		});

		// Assert
		await expect
			.element(rendered.getByRole('alert'))
			.toHaveTextContent('Enter a full 40- or 64-character hexadecimal commit hash.');
		expect(applyTarget).not.toHaveBeenCalled();

		// Act
		const fullOID = 'c'.repeat(40);
		await act(async (): Promise<void> => {
			await commitInput.fill(fullOID);
			await rendered.getByRole('button', { name: 'Compare to this commit' }).click();
		});

		// Assert
		expect(applyTarget).toHaveBeenCalledExactlyOnceWith({ kind: 'commit', oid: fullOID });
	});

	test('keeps the rendered predecessor labeled with its own target until the successor package arrives', async () => {
		// Arrange
		const predecessor = contributionPackage({
			baseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-delivery-predecessor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 24,
		});
		const successorTarget = {
			basis: 'commonCommit',
			kind: 'ref',
			name: 'feature/new-target',
		} as const;
		const successor = contributionPackage({
			baseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			packageId: 'package-delivery-successor',
			resolvedTargetOID: '2222222222222222222222222222222222222222',
			revision: 25,
			symbolicTarget: successorTarget,
		});
		const successorPresentation = comparisonPresentation({
			activeTarget: successorTarget,
			displayedSnapshot: {
				packageId: successor.packageId,
				reviewGeneration: successor.reviewGeneration,
				revision: successor.revision,
				status: 'current',
			},
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(predecessor)}
				displayedReviewPackage={predecessor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act — presentation can settle the successor before its package frame arrives.
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={successorPresentation}
				displayedReviewPackage={predecessor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Assert — closed chrome names the requested target while popup details retain the package visible now.
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-trigger'))
			.toHaveTextContent('Compare: master · Updating');
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});
		await expect.element(rendered.getByText('Updating comparison')).toBeVisible();
		await expect.element(rendered.getByText('Base branch')).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-effective-revision'))
			.toHaveTextContent('aaaaaaaaaaaa');

		// Act — the package frame catches up with the settled presentation.
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={successorPresentation}
				displayedReviewPackage={successor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Assert
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-trigger'))
			.toHaveTextContent('Compare: feature/new-target');
		await expect.element(rendered.getByText('Base branch')).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-effective-revision'))
			.toHaveTextContent('bbbbbbbbbbbb');
	});
});

function comparisonPresentation(props: {
	readonly activeTarget?: NonNullable<
		BridgeWorkerPanelChromePatchPayload['reviewComparison']
	>['activeTarget'];
	readonly attempt?: NonNullable<
		BridgeWorkerPanelChromePatchPayload['reviewComparison']
	>['attempt'];
	readonly displayedSnapshot: NonNullable<
		BridgeWorkerPanelChromePatchPayload['reviewComparison']
	>['displayedSnapshot'];
	readonly repositoryDefaultTarget?: NonNullable<
		NonNullable<BridgeWorkerPanelChromePatchPayload['reviewComparison']>
	>['repositoryDefaultTarget'];
}): NonNullable<BridgeWorkerPanelChromePatchPayload['reviewComparison']> {
	return {
		activeTarget:
			props.activeTarget === undefined
				? { basis: 'commonCommit', branchName: 'master', kind: 'localDefaultBranch' }
				: props.activeTarget,
		attempt: props.attempt ?? { reviewGeneration: 1, status: 'settled' },
		displayedSnapshot: props.displayedSnapshot,
		repositoryDefaultTarget: props.repositoryDefaultTarget ?? null,
	};
}

function targetCatalog(): BridgeProductReviewComparisonTargetCatalog {
	return {
		capturedAtUnixMilliseconds: 1_700_000_000_000,
		cutoffUnixMilliseconds: 1_699_000_000_000,
		branches: [
			{ branchName: 'main', kind: 'local', oid: 'a'.repeat(40) },
			{ branchName: 'feature/stack', kind: 'local', oid: 'f'.repeat(40) },
			{
				branchName: 'main',
				kind: 'remoteTracking',
				oid: 'b'.repeat(40),
				remoteName: 'origin',
			},
			{
				branchName: 'release',
				kind: 'remoteTracking',
				oid: 'd'.repeat(40),
				remoteName: 'upstream',
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

function currentPresentationForPackage(
	reviewPackage: BridgeReviewPackage,
): NonNullable<BridgeWorkerPanelChromePatchPayload['reviewComparison']> {
	return comparisonPresentation({
		displayedSnapshot: {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
			status: 'current',
		},
	});
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

function contributionPackage(props: {
	readonly baseOID: string;
	readonly packageId: string;
	readonly resolvedTargetOID: string;
	readonly revision: number;
	readonly symbolicTarget?: NonNullable<BridgeReviewPackage['comparisonOrigin']>['symbolicTarget'];
}): BridgeReviewPackage {
	return {
		...makeBridgeReviewPackage(),
		comparisonOrigin: {
			baseOID: props.baseOID,
			baseRole: 'commonCommit',
			comparedRole: 'capturedWorkingTree',
			kind: 'contribution',
			resolvedTargetOID: props.resolvedTargetOID,
			reviewedHeadOID: 'hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh',
			symbolicTarget: props.symbolicTarget ?? {
				basis: 'commonCommit',
				branchName: 'master',
				kind: 'localDefaultBranch',
			},
		},
		packageId: props.packageId,
		reviewedSubjectLabel: 'feature/annotations',
		revision: props.revision,
	};
}
