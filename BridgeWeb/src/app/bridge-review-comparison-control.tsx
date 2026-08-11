import { ChevronDownIcon } from 'lucide-react';
import {
	useEffect,
	useId,
	useLayoutEffect,
	useRef,
	useState,
	type FormEvent,
	type ReactElement,
} from 'react';

import { Button, buttonVariants } from '../components/ui/button.js';
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuRadioGroup,
	DropdownMenuRadioItem,
	DropdownMenuTrigger,
} from '../components/ui/dropdown-menu.js';
import { Input } from '../components/ui/input.js';
import { Popover, PopoverContent, PopoverTitle, PopoverTrigger } from '../components/ui/popover.js';
import { ToggleGroup, ToggleGroupItem } from '../components/ui/toggle-group.js';
import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerReviewComparisonUpdateCommand } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewComparisonTargetsQueryState } from './bridge-app-review-render-snapshot-controller.js';
import { BridgeReviewComparisonBranchSelector } from './bridge-review-comparison-branch-selector.js';
import { bridgeViewerChromeButtonClassName } from './bridge-viewer-chrome.js';
import { bridgeViewerFilterMenuSurfaceClassName } from './bridge-viewer-filter-menu.js';
import { cn } from './class-name.js';

export interface BridgeReviewComparisonControlProps {
	readonly comparisonPresentation: BridgeWorkerPanelChromePatchPayload['reviewComparison'];
	readonly displayedReviewPackage: BridgeReviewPackage | null;
	readonly isActive?: boolean;
	readonly onApplyTarget: (target: BridgeWorkerReviewComparisonUpdateCommand['target']) => void;
	readonly onCancelTargetQuery?: () => void;
	readonly onQueryTargets?: () => void;
	readonly targetQueryState?: BridgeReviewComparisonTargetsQueryState;
}

export function BridgeReviewComparisonControl(
	props: BridgeReviewComparisonControlProps,
): ReactElement | null {
	const descriptionId = useId();
	const isActive = props.isActive ?? true;
	const [commitOID, setCommitOID] = useState('');
	const [open, setOpen] = useState(false);
	const [selectionMode, setSelectionMode] = useState<'branch' | 'commit'>('branch');
	const [validationMessage, setValidationMessage] = useState<string | null>(null);
	const targetQueryState =
		props.targetQueryState ?? ({ catalog: null, message: null, status: 'idle' } as const);
	const onQueryTargets = props.onQueryTargets ?? ((): void => {});
	const onCancelTargetQuery = props.onCancelTargetQuery ?? ((): void => {});
	const branchSearchInputRef = useRef<HTMLInputElement>(null);
	const commitInputRef = useRef<HTMLInputElement>(null);
	useEffect((): void => {
		if (!isActive) {
			setOpen(false);
		}
	}, [isActive]);
	useLayoutEffect((): void => {
		if (!open) return;
		const activeInput =
			selectionMode === 'branch' ? branchSearchInputRef.current : commitInputRef.current;
		activeInput?.focus();
	}, [open, selectionMode]);
	const label = closedComparisonLabel(props);
	const narrowComparisonLabel = narrowComparisonLabelForPackage(props.displayedReviewPackage);
	const activeTarget = props.comparisonPresentation?.activeTarget ?? null;
	const displayedContribution = displayedContributionForComparison(props);
	const describedTarget =
		displayedContribution?.heading === 'Previous comparison'
			? displayedContribution.origin.symbolicTarget
			: activeTarget;
	const describedTargetLabel =
		describedTarget === null ? '' : comparisonTargetLabel(describedTarget);
	const statePresentation = comparisonStatePresentation(props, displayedContribution);
	const hasCurrentState = statePresentation !== null || displayedContribution !== null;
	const sharedHistoryDescription =
		narrowComparisonLabel !== null
			? narrowComparisonDescription(narrowComparisonLabel)
			: describedTarget === null
				? 'Choose a local branch, remote-tracking branch, or Git reference for this review.'
				: comparisonTargetDescription(describedTarget, describedTargetLabel);
	const applyCommitOID = (event: FormEvent<HTMLFormElement>): void => {
		event.preventDefault();
		const normalizedOID = commitOID.trim();
		if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/iu.test(normalizedOID)) {
			setValidationMessage('Enter a full 40- or 64-character hexadecimal commit hash.');
			return;
		}
		props.onApplyTarget({ kind: 'commit', oid: normalizedOID });
		setValidationMessage(null);
		setOpen(false);
	};
	if (!isActive) {
		return null;
	}
	if (narrowComparisonLabel !== null) {
		return (
			<span
				aria-describedby={descriptionId}
				className={cn(
					bridgeViewerChromeButtonClassName,
					'inline-flex max-w-56 items-center border-[var(--bridge-border-subtle)] bg-[var(--bridge-header-control-bg)] px-2 text-[var(--bridge-text-secondary)]',
				)}
				data-testid="bridge-review-comparison-trigger"
			>
				<span className="truncate">{label}</span>
				<span className="sr-only" id={descriptionId}>
					{sharedHistoryDescription}
				</span>
			</span>
		);
	}
	return (
		<Popover
			onOpenChange={(nextOpen): void => {
				setOpen(nextOpen);
				if (nextOpen) {
					setCommitOID('');
					setValidationMessage(null);
					if (selectionMode === 'branch') onQueryTargets();
				} else {
					onCancelTargetQuery();
				}
			}}
			open={open}
		>
			<PopoverTrigger
				aria-describedby={descriptionId}
				aria-label={label}
				className={cn(
					bridgeViewerChromeButtonClassName,
					'inline-flex max-w-56 items-center gap-1 border-[var(--bridge-border-subtle)] bg-[var(--bridge-header-control-bg)] px-2 text-[var(--bridge-text-secondary)] hover:bg-[var(--bridge-list-hover-bg)] hover:text-[var(--bridge-text-primary)] focus-visible:border-[var(--bridge-focus-border)] focus-visible:outline-none',
				)}
				data-testid="bridge-review-comparison-trigger"
			>
				<span className="truncate">{label}</span>
				<ChevronDownIcon aria-hidden="true" className="size-3 shrink-0" />
			</PopoverTrigger>
			<span className="sr-only" id={descriptionId}>
				{sharedHistoryDescription}
			</span>
			<PopoverContent
				aria-describedby={descriptionId}
				align="end"
				className={cn(bridgeViewerFilterMenuSurfaceClassName, 'w-96 gap-0')}
				data-testid="bridge-review-comparison-content"
				initialFocus={(): HTMLElement | null =>
					selectionMode === 'branch' ? branchSearchInputRef.current : commitInputRef.current
				}
				sideOffset={6}
			>
				{hasCurrentState ? (
					<>
						<div className="flex flex-col gap-2 py-0.5">
							{displayedContribution === null ? null : (
								<ComparisonCurrentState
									contribution={displayedContribution}
									onApplyTarget={props.onApplyTarget}
									repositoryDefaultTarget={
										props.comparisonPresentation?.repositoryDefaultTarget ?? null
									}
								/>
							)}
							{statePresentation === null ? null : (
								<ComparisonAttemptState
									onRetry={(target): void => {
										props.onApplyTarget(target);
										setOpen(false);
									}}
									presentation={statePresentation}
								/>
							)}
						</div>
						<div
							aria-hidden="true"
							className="-mx-2 my-3 h-px bg-[var(--bridge-border-subtle)]"
							data-testid="bridge-review-comparison-section-divider"
						/>
					</>
				) : null}
				<section
					className="flex flex-col gap-2"
					data-testid="bridge-review-comparison-target-selection"
				>
					<header className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 px-1">
						<PopoverTitle className="text-[11px] font-medium uppercase tracking-normal text-[var(--bridge-text-primary)]">
							Compare Worktree
						</PopoverTitle>
						<ToggleGroup aria-label="Comparison target kind" role="group" size="sm">
							<ToggleGroupItem
								onClick={(): void => {
									setSelectionMode('branch');
									setValidationMessage(null);
									onQueryTargets();
								}}
								pressed={selectionMode === 'branch'}
							>
								Branch
							</ToggleGroupItem>
							<ToggleGroupItem
								onClick={(): void => {
									setSelectionMode('commit');
									setValidationMessage(null);
									onCancelTargetQuery();
								}}
								pressed={selectionMode === 'commit'}
							>
								Commit
							</ToggleGroupItem>
						</ToggleGroup>
					</header>
					{selectionMode === 'branch' ? (
						<BridgeReviewComparisonBranchSelector
							activeTarget={activeTarget}
							onSelectTarget={(target): void => {
								props.onApplyTarget(target);
								setOpen(false);
							}}
							searchInputRef={branchSearchInputRef}
							targetQueryState={targetQueryState}
							onRetry={onQueryTargets}
						/>
					) : (
						<form className="flex flex-col gap-2" onSubmit={applyCommitOID}>
							<div className="min-w-0">
								<label className="sr-only" htmlFor={`${descriptionId}-commit-input`}>
									Commit hash
								</label>
								<Input
									aria-invalid={validationMessage === null ? undefined : true}
									className="border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] font-mono text-[var(--bridge-text-primary)] placeholder:text-[var(--bridge-text-muted)] focus-visible:border-[var(--bridge-focus-border)]"
									id={`${descriptionId}-commit-input`}
									onChange={(event): void => setCommitOID(event.currentTarget.value)}
									placeholder="Enter a full commit hash…"
									ref={commitInputRef}
									value={commitOID}
								/>
								{validationMessage === null ? null : (
									<p className="mt-1 text-[11px] text-destructive" role="alert">
										{validationMessage}
									</p>
								)}
							</div>
							<Button className="self-end" size="sm" type="submit" variant="secondary">
								Compare to this commit
							</Button>
						</form>
					)}
				</section>
			</PopoverContent>
		</Popover>
	);
}

function ComparisonCurrentState(props: {
	readonly contribution: DisplayedContribution;
	readonly onApplyTarget: BridgeReviewComparisonControlProps['onApplyTarget'];
	readonly repositoryDefaultTarget: NonNullable<
		NonNullable<BridgeReviewComparisonControlProps['comparisonPresentation']>
	>['repositoryDefaultTarget'];
}): ReactElement {
	const { origin } = props.contribution;
	const symbolicTarget = origin.symbolicTarget;
	const targetLabel = comparisonTargetLabel(symbolicTarget);
	if (symbolicTarget.kind === 'commit') {
		return (
			<section
				className="flex flex-col gap-1 px-1"
				data-testid="bridge-review-comparison-current-state"
			>
				<p className="text-[11px] font-medium uppercase text-[var(--bridge-text-muted)]">
					Base commit
				</p>
				<div>
					<ComparisonRevision
						testId="bridge-review-comparison-effective-revision"
						value={origin.baseOID}
					/>
				</div>
			</section>
		);
	}
	const isDefault = targetMatchesRepositoryDefault(symbolicTarget, props.repositoryDefaultTarget);
	const activeBasis = origin.baseRole === 'commonCommit' ? 'commonCommit' : 'branchTip';
	const effectiveBasisLabel = activeBasis === 'commonCommit' ? 'Common commit' : 'Branch tip';
	return (
		<section
			className="flex flex-col gap-1.5 px-1"
			data-testid="bridge-review-comparison-current-state"
		>
			<p className="text-[11px] font-medium uppercase text-[var(--bridge-text-muted)]">
				Base branch
			</p>
			<div className="flex flex-col gap-2">
				<p className="flex min-w-0 items-baseline gap-1.5 text-xs text-[var(--bridge-text-primary)]">
					<span className="truncate">{targetLabel}</span>
					{isDefault ? (
						<span className="flex shrink-0 items-baseline gap-1 text-[11px] text-[var(--bridge-text-muted)]">
							<span aria-hidden="true">·</span>
							<span>Default</span>
						</span>
					) : null}
				</p>
				<div className="flex min-w-0 items-center gap-2">
					<span className="shrink-0 text-[11px] text-[var(--bridge-text-muted)]">
						Comparing from
					</span>
					<DropdownMenu>
						<DropdownMenuTrigger
							aria-label={`Comparing from ${effectiveBasisLabel}`}
							className={cn(
								buttonVariants({ size: 'sm', variant: 'outline' }),
								'min-w-0 max-w-full justify-start bg-[var(--bridge-header-control-bg)]',
							)}
							data-testid="bridge-review-comparison-basis-trigger"
						>
							<span>{effectiveBasisLabel} @</span>
							<ComparisonRevision
								testId="bridge-review-comparison-effective-revision"
								value={origin.baseOID}
							/>
							<ChevronDownIcon aria-hidden="true" data-icon="inline-end" />
						</DropdownMenuTrigger>
						<DropdownMenuContent
							align="start"
							className={cn(bridgeViewerFilterMenuSurfaceClassName, 'w-64')}
							sideOffset={4}
						>
							<DropdownMenuRadioGroup value={activeBasis}>
								<DropdownMenuRadioItem
									onClick={(): void =>
										props.onApplyTarget(comparisonTargetWithBasis(symbolicTarget, 'commonCommit'))
									}
									value="commonCommit"
								>
									Common commit
								</DropdownMenuRadioItem>
								<DropdownMenuRadioItem
									onClick={(): void =>
										props.onApplyTarget(comparisonTargetWithBasis(symbolicTarget, 'branchTip'))
									}
									value="branchTip"
								>
									Branch tip
								</DropdownMenuRadioItem>
							</DropdownMenuRadioGroup>
						</DropdownMenuContent>
					</DropdownMenu>
				</div>
			</div>
		</section>
	);
}

function ComparisonAttemptState(props: {
	readonly onRetry: (target: ReviewComparisonTarget) => void;
	readonly presentation: ComparisonStatePresentation;
}): ReactElement {
	return (
		<section aria-live="polite" className="px-1">
			<p className="text-[11px] font-medium uppercase text-[var(--bridge-text-muted)]">
				{props.presentation.heading}
			</p>
			<p className="mt-0.5 text-[11px] text-[var(--bridge-text-muted)]">
				{props.presentation.description}
			</p>
			{props.presentation.retryTarget === null ? null : (
				<Button
					className="mt-2"
					onClick={(): void => {
						const retryTarget = props.presentation.retryTarget;
						if (retryTarget !== null) props.onRetry(retryTarget);
					}}
					size="sm"
					type="button"
					variant="outline"
				>
					Retry
				</Button>
			)}
		</section>
	);
}

function comparisonTargetWithBasis(
	target: Exclude<ReviewComparisonTarget, { readonly kind: 'commit' }>,
	basis: 'branchTip' | 'commonCommit',
): ReviewComparisonTarget {
	return { ...target, basis };
}

function ComparisonRevision(props: {
	readonly testId: string;
	readonly value: string;
}): ReactElement {
	return (
		<code
			className="font-mono text-[var(--bridge-text-secondary)]"
			data-testid={props.testId}
			title={props.value}
		>
			<span aria-hidden="true">{props.value.slice(0, 12)}</span>
			<span className="sr-only">{props.value}</span>
		</code>
	);
}

function displayedContributionForComparison(
	props: BridgeReviewComparisonControlProps,
): DisplayedContribution | null {
	const reviewPackage = displayedReviewPackageForComparison(props);
	if (reviewPackage?.comparisonOrigin?.kind !== 'contribution') {
		return null;
	}
	return {
		heading:
			props.comparisonPresentation?.displayedSnapshot.status === 'stale' ||
			isDisplayedPackageAwaitingPresentationDelivery(props)
				? 'Previous comparison'
				: 'Current comparison',
		origin: reviewPackage.comparisonOrigin,
	};
}

function displayedReviewPackageForComparison(
	props: BridgeReviewComparisonControlProps,
): BridgeReviewPackage | null {
	const reviewPackage = props.displayedReviewPackage;
	const displayedSnapshot = props.comparisonPresentation?.displayedSnapshot;
	if (
		reviewPackage === null ||
		displayedSnapshot === undefined ||
		displayedSnapshot.status === 'none'
	) {
		return null;
	}
	return reviewPackage;
}

function isDisplayedPackageAwaitingPresentationDelivery(
	props: BridgeReviewComparisonControlProps,
): boolean {
	const reviewPackage = props.displayedReviewPackage;
	const displayedSnapshot = props.comparisonPresentation?.displayedSnapshot;
	return (
		reviewPackage !== null &&
		displayedSnapshot !== undefined &&
		displayedSnapshot.status !== 'none' &&
		(displayedSnapshot.packageId !== reviewPackage.packageId ||
			displayedSnapshot.reviewGeneration !== reviewPackage.reviewGeneration ||
			displayedSnapshot.revision !== reviewPackage.revision)
	);
}

type ReviewComparisonTarget = NonNullable<
	NonNullable<BridgeReviewComparisonControlProps['comparisonPresentation']>['activeTarget']
>;

type ContributionOrigin = Extract<
	NonNullable<BridgeReviewPackage['comparisonOrigin']>,
	{ readonly kind: 'contribution' }
>;

interface DisplayedContribution {
	readonly heading: 'Current comparison' | 'Previous comparison';
	readonly origin: ContributionOrigin;
}

interface ComparisonStatePresentation {
	readonly description: string;
	readonly heading: string;
	readonly retryTarget: ReviewComparisonTarget | null;
}

function comparisonStatePresentation(
	props: BridgeReviewComparisonControlProps,
	displayedContribution: DisplayedContribution | null,
): ComparisonStatePresentation | null {
	const comparisonPresentation = props.comparisonPresentation;
	if (comparisonPresentation === null || comparisonPresentation === undefined) {
		return null;
	}
	switch (comparisonPresentation.attempt.status) {
		case 'selectionRequired':
			return {
				description: 'Select a branch or Git reference before reviewing changes.',
				heading: 'Choose a comparison target',
				retryTarget: null,
			};
		case 'pending':
			return displayedContribution?.heading === 'Previous comparison'
				? {
						description: 'Showing the previous comparison while the requested target is prepared.',
						heading: 'Updating comparison',
						retryTarget: null,
					}
				: {
						description: 'No comparison is displayed yet.',
						heading: 'Preparing comparison',
						retryTarget: null,
					};
		case 'settled':
			return displayedContribution?.heading === 'Previous comparison' &&
				isDisplayedPackageAwaitingPresentationDelivery(props)
				? {
						description: 'Showing the previous comparison while the requested target is prepared.',
						heading: 'Updating comparison',
						retryTarget: null,
					}
				: null;
		case 'unavailable':
			return {
				description:
					displayedContribution?.heading === 'Previous comparison'
						? 'The selected target could not be refreshed. The previous comparison remains visible.'
						: 'The selected target could not be compared.',
				heading: 'Comparison unavailable',
				retryTarget:
					comparisonPresentation.attempt.retryable && comparisonPresentation.activeTarget !== null
						? comparisonPresentation.activeTarget
						: null,
			};
	}
	return unreachableComparisonValue(comparisonPresentation.attempt);
}

function closedComparisonLabel(props: BridgeReviewComparisonControlProps): string {
	const narrowComparisonLabel = narrowComparisonLabelForPackage(props.displayedReviewPackage);
	if (narrowComparisonLabel !== null) {
		return narrowComparisonLabel;
	}
	const displayedContribution = displayedContributionForComparison(props);
	if (displayedContribution?.heading === 'Previous comparison') {
		const displayedTargetLabel = comparisonTargetLabel(displayedContribution.origin.symbolicTarget);
		const attemptStatus = props.comparisonPresentation?.attempt.status;
		return attemptStatus === 'pending' ||
			(attemptStatus === 'settled' && isDisplayedPackageAwaitingPresentationDelivery(props))
			? `Compare: ${displayedTargetLabel} · Updating`
			: attemptStatus === 'unavailable'
				? `Compare: ${displayedTargetLabel} · Unavailable`
				: `Compare: ${displayedTargetLabel} · Stale`;
	}
	const activeTarget = props.comparisonPresentation?.activeTarget;
	if (activeTarget === undefined || activeTarget === null) {
		return 'Choose target';
	}
	return `Compare: ${comparisonTargetLabel(activeTarget)}`;
}

function targetMatchesRepositoryDefault(
	target: ReviewComparisonTarget,
	defaultTarget: NonNullable<
		NonNullable<BridgeReviewComparisonControlProps['comparisonPresentation']>
	>['repositoryDefaultTarget'],
): boolean {
	if (defaultTarget === null) {
		return false;
	}
	return (
		(target.kind === 'originDefaultBranch' &&
			target.remoteName === defaultTarget.remoteName &&
			target.branchName === defaultTarget.branchName) ||
		(target.kind === 'localDefaultBranch' && target.branchName === defaultTarget.branchName) ||
		(target.kind === 'branch' && target.name === defaultTarget.branchName) ||
		(target.kind === 'ref' &&
			target.name === `${defaultTarget.remoteName}/${defaultTarget.branchName}`)
	);
}

function narrowComparisonLabelForPackage(
	reviewPackage: BridgeReviewPackage | null,
): 'Staged only' | 'Unstaged only' | null {
	if (
		reviewPackage?.query.comparisonSemantics === 'indexDelta' &&
		reviewPackage.headEndpoint.kind === 'index'
	) {
		return 'Staged only';
	}
	if (
		reviewPackage?.query.comparisonSemantics === 'workingTreeDelta' &&
		reviewPackage.baseEndpoint.kind === 'index' &&
		reviewPackage.headEndpoint.kind === 'workingTree'
	) {
		return 'Unstaged only';
	}
	return null;
}

function narrowComparisonDescription(
	narrowComparisonLabel: 'Staged only' | 'Unstaged only',
): string {
	return narrowComparisonLabel === 'Staged only'
		? 'Shows changes added to the staging area.'
		: 'Shows tracked working tree changes that have not been staged.';
}

function comparisonTargetDescription(target: ReviewComparisonTarget, targetLabel: string): string {
	if (target.kind === 'commit') {
		return `Shows committed and uncommitted changes directly from commit ${targetLabel}.`;
	}
	return target.basis === 'branchTip'
		? `Shows committed and uncommitted changes directly from the latest locally available ${targetLabel} revision.`
		: `Shows committed and uncommitted changes since this worktree's latest shared commit with ${targetLabel}. Changes only on ${targetLabel} are excluded.`;
}

function comparisonTargetLabel(target: ReviewComparisonTarget): string {
	switch (target.kind) {
		case 'localDefaultBranch':
			return target.branchName;
		case 'originDefaultBranch':
			return `${target.remoteName}/${target.branchName}`;
		case 'branch':
		case 'ref':
			return target.name;
		case 'commit':
			return target.oid;
	}
	return unreachableComparisonValue(target);
}

function unreachableComparisonValue(value: never): never {
	throw new Error(`Unexpected Review comparison value: ${JSON.stringify(value)}`);
}
