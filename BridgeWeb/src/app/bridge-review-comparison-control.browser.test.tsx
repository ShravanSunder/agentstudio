import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production CSS.
import './bridge-app.css';
import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { BridgeReviewComparisonControl } from './bridge-review-comparison-control.js';

describe('BridgeReviewComparisonControl Browser Mode', () => {
	test('shows exact current target and shared-start facts without Git implementation vocabulary', async () => {
		// Arrange
		const reviewPackage = contributionPackage({
			contributionBaseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
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
		await expect.element(rendered.getByText('Current comparison')).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-target-revision'))
			.toHaveTextContent('mmmmmmmmmmmm');
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-shared-start-revision'))
			.toHaveTextContent('bbbbbbbbbbbb');
		expect(content.element().textContent).not.toMatch(
			/Head vs Base|Default|Contribution|three-dot|merge base/u,
		);
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
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-stale',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 4,
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					activeTarget: { kind: 'ref', name: 'feature/new-target' },
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
			.toHaveTextContent('Compare to: feature/new-target');
		await expect.element(rendered.getByText('Updating comparison')).toBeVisible();
		await expect
			.element(
				rendered.getByText(
					'Showing the previous comparison while the requested target is prepared.',
				),
			)
			.toBeVisible();
		await expect.element(rendered.getByText('Previous comparison', { exact: true })).toBeVisible();
		await expect
			.element(rendered.getByText('1111111111111111111111111111111111111111', { exact: true }))
			.toBeInTheDocument();
	});

	test('retries a retryable unavailable comparison with the canonical active target', async () => {
		// Arrange
		const activeTarget = { kind: 'branch', name: 'release/next' } as const;
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

	test.each([
		{ label: 'Staged only', reviewPackage: stagedOnlyPackage() },
		{ label: 'Unstaged only', reviewPackage: unstagedOnlyPackage() },
	])('hides the retained contribution target for $label comparisons', async (scenario) => {
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
	});

	test('does not expose the retained contribution target through narrow-mode accessibility or input', async () => {
		// Arrange
		const reviewPackage = stagedOnlyPackage();
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(reviewPackage)}
				displayedReviewPackage={reviewPackage}
				onApplyTarget={vi.fn()}
			/>,
		);
		const trigger = rendered.getByTestId('bridge-review-comparison-trigger');
		const descriptionId = trigger.element().getAttribute('aria-describedby');

		// Assert
		expect(descriptionId).not.toBeNull();
		expect(document.getElementById(descriptionId ?? '')?.textContent).toBe(
			'Shows changes added to the staging area.',
		);

		// Act
		await act(async (): Promise<void> => {
			await trigger.click();
		});

		// Assert
		const content = rendered.getByTestId('bridge-review-comparison-content');
		expect(content.element().textContent).not.toContain('master');
		await expect
			.element(rendered.getByRole('textbox', { name: 'Branch or Git reference' }))
			.toHaveValue('');
	});

	test('rejects invalid and oversized refs without dispatching them', async () => {
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
		});
		const input = rendered.getByRole('textbox', { name: 'Branch or Git reference' });

		// Act
		await act(async (): Promise<void> => {
			await input.fill('feature branch');
			await rendered.getByRole('button', { name: 'Apply' }).click();
		});

		// Assert
		await expect
			.element(rendered.getByRole('alert'))
			.toHaveTextContent('Enter a Git reference up to 256 ASCII characters without spaces.');
		expect(applyTarget).not.toHaveBeenCalled();

		// Act
		await act(async (): Promise<void> => {
			await input.fill('x'.repeat(257));
			await rendered.getByRole('button', { name: 'Apply' }).click();
		});

		// Assert
		await expect.element(rendered.getByRole('alert')).toBeVisible();
		expect(applyTarget).not.toHaveBeenCalled();
	});

	test('applies an arbitrary valid symbolic ref', async () => {
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

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
			await rendered
				.getByRole('textbox', { name: 'Branch or Git reference' })
				.fill('feature/stack-base');
			await rendered.getByRole('button', { name: 'Apply' }).click();
		});

		// Assert
		expect(applyTarget).toHaveBeenCalledExactlyOnceWith({
			kind: 'ref',
			name: 'feature/stack-base',
		});
	});

	test('explains target-only movement from the directly preceding displayed origin', async () => {
		// Arrange
		const predecessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-target-predecessor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 10,
		});
		const successor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-target-successor',
			resolvedTargetOID: '2222222222222222222222222222222222222222',
			revision: 11,
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(predecessor)}
				displayedReviewPackage={predecessor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(successor)}
				displayedReviewPackage={successor}
				onApplyTarget={vi.fn()}
			/>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect.element(rendered.getByText('Comparison refreshed')).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-target-movement'))
			.toHaveTextContent(/111111111111.*222222222222/u);
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-shared-start-movement'))
			.toHaveTextContent(/remains.*aaaaaaaaaaaa/u);
	});

	test('explains shared-start movement without inventing target movement', async () => {
		// Arrange
		const predecessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-base-predecessor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 12,
		});
		const successor = contributionPackage({
			contributionBaseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			packageId: 'package-base-successor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 13,
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(predecessor)}
				displayedReviewPackage={predecessor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(successor)}
				displayedReviewPackage={successor}
				onApplyTarget={vi.fn()}
			/>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect.element(rendered.getByText('Comparison refreshed')).toBeVisible();
		expect(
			document.querySelector('[data-testid="bridge-review-comparison-target-movement"]'),
		).toBeNull();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-shared-start-movement'))
			.toHaveTextContent(/aaaaaaaaaaaa.*bbbbbbbbbbbb/u);
		await expect
			.element(rendered.getByText('Files may have entered or left this review.'))
			.toBeVisible();
	});

	test('explains both target and shared-start movement independently', async () => {
		// Arrange
		const predecessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-both-predecessor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 14,
		});
		const successor = contributionPackage({
			contributionBaseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			packageId: 'package-both-successor',
			resolvedTargetOID: '2222222222222222222222222222222222222222',
			revision: 15,
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(predecessor)}
				displayedReviewPackage={predecessor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(successor)}
				displayedReviewPackage={successor}
				onApplyTarget={vi.fn()}
			/>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-target-movement'))
			.toHaveTextContent(/111111111111.*222222222222/u);
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-shared-start-movement'))
			.toHaveTextContent(/aaaaaaaaaaaa.*bbbbbbbbbbbb/u);
		await expect
			.element(rendered.getByText('Files may have entered or left this review.'))
			.toBeVisible();
	});

	test.each([
		{
			label: 'repository changes',
			mutate: (reviewPackage: BridgeReviewPackage): BridgeReviewPackage => ({
				...reviewPackage,
				query: { ...reviewPackage.query, repoId: 'another-repo' },
			}),
		},
		{
			label: 'worktree changes',
			mutate: (reviewPackage: BridgeReviewPackage): BridgeReviewPackage => ({
				...reviewPackage,
				query: { ...reviewPackage.query, worktreeId: 'another-worktree' },
			}),
		},
		{
			label: 'symbolic target changes',
			mutate: (reviewPackage: BridgeReviewPackage): BridgeReviewPackage => ({
				...reviewPackage,
				comparisonOrigin:
					reviewPackage.comparisonOrigin?.kind === 'contribution'
						? {
								...reviewPackage.comparisonOrigin,
								symbolicTarget: { kind: 'ref', name: 'feature/another-base' },
							}
						: reviewPackage.comparisonOrigin,
			}),
		},
	])('does not claim movement when the adjacent $label', async (scenario) => {
		// Arrange
		const predecessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: `package-mismatch-predecessor-${scenario.label}`,
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 16,
		});
		const successor = scenario.mutate(
			contributionPackage({
				contributionBaseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
				packageId: `package-mismatch-successor-${scenario.label}`,
				resolvedTargetOID: '2222222222222222222222222222222222222222',
				revision: 17,
			}),
		);
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(predecessor)}
				displayedReviewPackage={predecessor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(successor)}
				displayedReviewPackage={successor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Assert
		await expect
			.poll(() => document.querySelector('[aria-label="Comparison refreshed"]'))
			.toBeNull();
	});

	test('does not claim movement for the first displayed package or a content-only successor', async () => {
		// Arrange
		const predecessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-content-predecessor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 18,
		});
		const contentOnlySuccessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-content-successor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 19,
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(predecessor)}
				displayedReviewPackage={predecessor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Assert
		await expect
			.poll(() => document.querySelector('[aria-label="Comparison refreshed"]'))
			.toBeNull();

		// Act
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(contentOnlySuccessor)}
				displayedReviewPackage={contentOnlySuccessor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Assert
		await expect
			.poll(() => document.querySelector('[aria-label="Comparison refreshed"]'))
			.toBeNull();
	});

	test('tracks an inactive successor while closing and hiding the comparison popover', async () => {
		// Arrange
		const predecessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-inactive-predecessor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 20,
		});
		const inactiveSuccessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-inactive-successor',
			resolvedTargetOID: '2222222222222222222222222222222222222222',
			revision: 21,
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(predecessor)}
				displayedReviewPackage={predecessor}
				isActive={true}
				onApplyTarget={vi.fn()}
			/>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});
		await expect.element(rendered.getByTestId('bridge-review-comparison-content')).toBeVisible();

		// Act
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(inactiveSuccessor)}
				displayedReviewPackage={inactiveSuccessor}
				isActive={false}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Assert
		await expect
			.poll(() => document.querySelector('[data-testid="bridge-review-comparison-trigger"]'))
			.toBeNull();
		await expect
			.poll(() => document.querySelector('[data-testid="bridge-review-comparison-content"]'))
			.toBeNull();

		// Act
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(inactiveSuccessor)}
				displayedReviewPackage={inactiveSuccessor}
				isActive={true}
				onApplyTarget={vi.fn()}
			/>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});

		// Assert
		await expect.element(rendered.getByText('Comparison refreshed')).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-target-movement'))
			.toHaveTextContent(/111111111111.*222222222222/u);
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
}): NonNullable<BridgeWorkerPanelChromePatchPayload['reviewComparison']> {
	return {
		activeTarget:
			props.activeTarget === undefined
				? { branchName: 'master', kind: 'localDefaultBranch' }
				: props.activeTarget,
		attempt: props.attempt ?? { reviewGeneration: 1, status: 'settled' },
		displayedSnapshot: props.displayedSnapshot,
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
	readonly contributionBaseOID: string;
	readonly packageId: string;
	readonly resolvedTargetOID: string;
	readonly revision: number;
}): BridgeReviewPackage {
	return {
		...makeBridgeReviewPackage(),
		comparisonOrigin: {
			baseRole: 'contributionBase',
			comparedRole: 'capturedWorkingTree',
			contributionBaseOID: props.contributionBaseOID,
			kind: 'contribution',
			resolvedTargetOID: props.resolvedTargetOID,
			reviewedHeadOID: 'hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh',
			symbolicTarget: { branchName: 'master', kind: 'localDefaultBranch' },
		},
		packageId: props.packageId,
		reviewedSubjectLabel: 'feature/annotations',
		revision: props.revision,
	};
}
