import { act } from 'react';
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

	test('describes the shared start and its relationship to the named default branch', async () => {
		// Arrange
		const reviewPackage = contributionPackage({
			contributionBaseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			packageId: 'package-default-relationship',
			resolvedTargetOID: 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
			revision: 4,
			symbolicTarget: {
				branchName: 'main',
				kind: 'originDefaultBranch',
				remoteName: 'origin',
			},
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={comparisonPresentation({
					activeTarget: {
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
					targetCatalog: targetCatalog(),
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
		await expect.element(rendered.getByText('Review starts from')).toBeVisible();
		await expect
			.element(rendered.getByText('Latest commit shared with default branch origin/main'))
			.toBeVisible();
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
			.toHaveTextContent('Compare: master · Updating');
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
					activeTarget: { branchName: 'main', kind: 'originDefaultBranch', remoteName: 'origin' },
					displayedSnapshot: { status: 'none' },
					targetCatalog: targetCatalog(),
				})}
				displayedReviewPackage={null}
				onApplyTarget={applyTarget}
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
			.toHaveTextContent(/origin\/main.*DEFAULT.*REMOTE-TRACKING.*bbbbbbbbbbbb/u);
		await expect
			.element(rendered.getByTestId('comparison-branch-main'))
			.toHaveTextContent(/main.*LOCAL.*aaaaaaaaaaaa/u);
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
			expectedTarget: { branchName: 'main', kind: 'originDefaultBranch', remoteName: 'origin' },
			rowTestId: 'comparison-branch-origin-main',
		},
		{
			expectedTarget: { kind: 'branch', name: 'main' },
			rowTestId: 'comparison-branch-main',
		},
		{
			expectedTarget: {
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
					targetCatalog: targetCatalog(),
				})}
				displayedReviewPackage={null}
				onApplyTarget={applyTarget}
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
					targetCatalog: targetCatalog(),
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

	test('preserves the movement predecessor across separate presentation and package delivery', async () => {
		// Arrange
		const predecessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-separated-predecessor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 22,
		});
		const successor = contributionPackage({
			contributionBaseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			packageId: 'package-separated-successor',
			resolvedTargetOID: '2222222222222222222222222222222222222222',
			revision: 23,
		});
		const rendered = await render(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(predecessor)}
				displayedReviewPackage={predecessor}
				onApplyTarget={vi.fn()}
			/>,
		);

		// Act — presentation can identify the successor before its package frame arrives.
		await rendered.rerender(
			<BridgeReviewComparisonControl
				comparisonPresentation={currentPresentationForPackage(successor)}
				displayedReviewPackage={predecessor}
				onApplyTarget={vi.fn()}
			/>,
		);
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
			.toHaveTextContent(/aaaaaaaaaaaa.*bbbbbbbbbbbb/u);
	});

	test('keeps the rendered predecessor labeled with its own target until the successor package arrives', async () => {
		// Arrange
		const predecessor = contributionPackage({
			contributionBaseOID: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			packageId: 'package-delivery-predecessor',
			resolvedTargetOID: '1111111111111111111111111111111111111111',
			revision: 24,
		});
		const successorTarget = { kind: 'ref', name: 'feature/new-target' } as const;
		const successor = contributionPackage({
			contributionBaseOID: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
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

		// Assert — the control continues describing the package the user can actually see.
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-trigger'))
			.toHaveTextContent('Compare: master · Updating');
		await act(async (): Promise<void> => {
			await rendered.getByTestId('bridge-review-comparison-trigger').click();
		});
		await expect.element(rendered.getByText('Updating comparison')).toBeVisible();
		await expect.element(rendered.getByText('Previous comparison', { exact: true })).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-target-revision'))
			.toHaveTextContent('111111111111');
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-shared-start-revision'))
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
		await expect.element(rendered.getByText('Current comparison')).toBeVisible();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-target-revision'))
			.toHaveTextContent('222222222222');
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-shared-start-revision'))
			.toHaveTextContent('bbbbbbbbbbbb');
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
	readonly targetCatalog?: NonNullable<
		BridgeWorkerPanelChromePatchPayload['reviewComparison']
	>['targetCatalog'];
}): NonNullable<BridgeWorkerPanelChromePatchPayload['reviewComparison']> {
	return {
		activeTarget:
			props.activeTarget === undefined
				? { branchName: 'master', kind: 'localDefaultBranch' }
				: props.activeTarget,
		attempt: props.attempt ?? { reviewGeneration: 1, status: 'settled' },
		displayedSnapshot: props.displayedSnapshot,
		targetCatalog: props.targetCatalog ?? null,
	};
}

function targetCatalog(): NonNullable<
	NonNullable<BridgeWorkerPanelChromePatchPayload['reviewComparison']>['targetCatalog']
> {
	return {
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
	readonly symbolicTarget?: NonNullable<BridgeReviewPackage['comparisonOrigin']>['symbolicTarget'];
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
			symbolicTarget: props.symbolicTarget ?? {
				branchName: 'master',
				kind: 'localDefaultBranch',
			},
		},
		packageId: props.packageId,
		reviewedSubjectLabel: 'feature/annotations',
		revision: props.revision,
	};
}
