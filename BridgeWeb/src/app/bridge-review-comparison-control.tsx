import { ChevronDownIcon } from 'lucide-react';
import { useEffect, useId, useRef, useState, type FormEvent, type ReactElement } from 'react';

import { Button } from '../components/ui/button.js';
import { Input } from '../components/ui/input.js';
import { Popover, PopoverContent, PopoverTitle, PopoverTrigger } from '../components/ui/popover.js';
import { ToggleGroup, ToggleGroupItem } from '../components/ui/toggle-group.js';
import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerReviewComparisonUpdateCommand } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { BridgeReviewComparisonBranchSelector } from './bridge-review-comparison-branch-selector.js';
import { bridgeViewerChromeButtonClassName } from './bridge-viewer-chrome.js';
import { bridgeViewerFilterMenuSurfaceClassName } from './bridge-viewer-filter-menu.js';
import { cn } from './class-name.js';

export interface BridgeReviewComparisonControlProps {
	readonly comparisonPresentation: BridgeWorkerPanelChromePatchPayload['reviewComparison'];
	readonly displayedReviewPackage: BridgeReviewPackage | null;
	readonly isActive?: boolean;
	readonly onApplyTarget: (target: BridgeWorkerReviewComparisonUpdateCommand['target']) => void;
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
	const branchSearchInputRef = useRef<HTMLInputElement>(null);
	const commitInputRef = useRef<HTMLInputElement>(null);
	const displayedReviewPackage = displayedReviewPackageForComparison(props);
	const precedingDisplayedPackageRef = useRef<BridgeReviewPackage | null>(null);
	const [movementSummary, setMovementSummary] = useState<ComparisonMovementSummary | null>(null);
	useEffect((): void => {
		const precedingPackage = precedingDisplayedPackageRef.current;
		if (displayedReviewPackage === null) {
			setMovementSummary(null);
			return;
		}
		if (
			precedingPackage !== null &&
			reviewPackageIdentity(precedingPackage) === reviewPackageIdentity(displayedReviewPackage)
		) {
			return;
		}
		setMovementSummary(deriveComparisonMovementSummary(precedingPackage, displayedReviewPackage));
		precedingDisplayedPackageRef.current = displayedReviewPackage;
	}, [displayedReviewPackage]);
	useEffect((): void => {
		if (!isActive) {
			setOpen(false);
		}
	}, [isActive]);
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
	const hasComparisonDetails =
		statePresentation !== null || displayedContribution !== null || movementSummary !== null;
	const sharedHistoryDescription =
		narrowComparisonLabel !== null
			? narrowComparisonDescription(narrowComparisonLabel)
			: describedTarget === null
				? 'Choose a local branch, remote-tracking branch, or Git reference for this review.'
				: `Shows committed and uncommitted changes since this worktree's latest shared commit with ${describedTargetLabel}. Changes only on ${describedTargetLabel} are excluded.`;
	const targetCatalog = props.comparisonPresentation?.targetCatalog ?? null;
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
				align="end"
				className={cn(bridgeViewerFilterMenuSurfaceClassName, 'w-96 gap-3')}
				data-testid="bridge-review-comparison-content"
				initialFocus={(): HTMLElement | null =>
					selectionMode === 'branch' ? branchSearchInputRef.current : commitInputRef.current
				}
				sideOffset={6}
			>
				<header className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-0.5 px-1 pt-0.5">
					<PopoverTitle className="text-[13px] font-medium text-[var(--bridge-text-primary)]">
						Compare Worktree
					</PopoverTitle>
					<ToggleGroup aria-label="Comparison target kind" role="group" size="sm">
						<ToggleGroupItem
							onClick={(): void => {
								setSelectionMode('branch');
								setValidationMessage(null);
							}}
							pressed={selectionMode === 'branch'}
						>
							Branch
						</ToggleGroupItem>
						<ToggleGroupItem
							onClick={(): void => {
								setSelectionMode('commit');
								setValidationMessage(null);
							}}
							pressed={selectionMode === 'commit'}
						>
							Commit
						</ToggleGroupItem>
					</ToggleGroup>
					<p className="col-span-2 text-[11px] text-[var(--bridge-text-muted)]">
						{sharedHistoryDescription}
					</p>
				</header>
				{selectionMode === 'branch' ? (
					<BridgeReviewComparisonBranchSelector
						activeTarget={activeTarget}
						onSelectTarget={(target): void => {
							props.onApplyTarget(target);
							setOpen(false);
						}}
						searchInputRef={branchSearchInputRef}
						targetCatalog={targetCatalog}
					/>
				) : (
					<form className="flex flex-col gap-2" onSubmit={applyCommitOID}>
						<div className="min-w-0">
							<label className="sr-only" htmlFor={`${descriptionId}-commit-input`}>
								Commit hash
							</label>
							<Input
								aria-invalid={validationMessage === null ? undefined : true}
								className="font-mono"
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
						<Button className="self-end" size="sm" type="submit">
							Compare to this commit
						</Button>
					</form>
				)}
				{hasComparisonDetails ? (
					<div aria-hidden="true" className="-mx-2 h-px bg-[var(--bridge-border-subtle)]" />
				) : null}
				{statePresentation === null ? null : (
					<section aria-live="polite">
						<p className="text-[11px] font-medium uppercase text-[var(--bridge-text-muted)]">
							{statePresentation.heading}
						</p>
						<p className="mt-0.5 text-[11px] text-[var(--bridge-text-muted)]">
							{statePresentation.description}
						</p>
						{statePresentation.retryTarget === null ? null : (
							<Button
								className="mt-2"
								onClick={(): void => {
									const retryTarget = statePresentation.retryTarget;
									if (retryTarget === null) {
										return;
									}
									props.onApplyTarget(retryTarget);
									setOpen(false);
								}}
								size="sm"
								type="button"
								variant="outline"
							>
								Retry
							</Button>
						)}
					</section>
				)}
				{displayedContribution === null ? null : (
					<section aria-label={displayedContribution.heading}>
						<p className="text-[11px] font-medium uppercase text-[var(--bridge-text-muted)]">
							{displayedContribution.heading}
						</p>
						<dl className="mt-1 grid grid-cols-[auto_minmax(0,1fr)] gap-x-3 gap-y-1 text-[11px]">
							<dt className="text-[var(--bridge-text-muted)]">Target</dt>
							<dd>
								<span className="mr-1 text-[var(--bridge-text-secondary)]">
									{comparisonTargetLabel(displayedContribution.origin.symbolicTarget)} @
								</span>
								<ComparisonRevision
									testId="bridge-review-comparison-target-revision"
									value={displayedContribution.origin.resolvedTargetOID}
								/>
							</dd>
							<dt className="text-[var(--bridge-text-muted)]">Review starts from</dt>
							<dd>
								<ComparisonRevision
									testId="bridge-review-comparison-shared-start-revision"
									value={displayedContribution.origin.contributionBaseOID}
								/>
							</dd>
						</dl>
						<p className="mt-1 text-[11px] text-[var(--bridge-text-muted)]">
							{sharedStartRelationshipDescription(
								displayedContribution.origin.symbolicTarget,
								targetCatalog,
							)}
						</p>
					</section>
				)}
				{movementSummary === null ? null : (
					<ComparisonMovementSummaryView summary={movementSummary} />
				)}
			</PopoverContent>
		</Popover>
	);
}

function ComparisonMovementSummaryView(props: {
	readonly summary: ComparisonMovementSummary;
}): ReactElement {
	return (
		<section aria-label="Comparison refreshed">
			<p className="text-[11px] font-medium uppercase text-[var(--bridge-text-muted)]">
				Comparison refreshed
			</p>
			<dl className="mt-1 grid grid-cols-[auto_minmax(0,1fr)] gap-x-3 gap-y-1 text-[11px]">
				{props.summary.targetMovement === null ? null : (
					<>
						<dt className="text-[var(--bridge-text-muted)]">
							{comparisonTargetLabel(props.summary.symbolicTarget)} updated
						</dt>
						<dd data-testid="bridge-review-comparison-target-movement">
							<ComparisonRevision
								testId="bridge-review-comparison-previous-target-revision"
								value={props.summary.targetMovement.previousRevision}
							/>
							<span aria-hidden="true"> → </span>
							<span className="sr-only"> to </span>
							<ComparisonRevision
								testId="bridge-review-comparison-current-target-revision"
								value={props.summary.targetMovement.currentRevision}
							/>
						</dd>
					</>
				)}
				<dt className="text-[var(--bridge-text-muted)]">Shared starting point</dt>
				<dd data-testid="bridge-review-comparison-shared-start-movement">
					{props.summary.sharedStartMovement.kind === 'unchanged' ? (
						<>
							<span className="mr-1">remains</span>
							<ComparisonRevision
								testId="bridge-review-comparison-unchanged-shared-start-revision"
								value={props.summary.sharedStartMovement.revision}
							/>
						</>
					) : (
						<>
							<ComparisonRevision
								testId="bridge-review-comparison-previous-shared-start-revision"
								value={props.summary.sharedStartMovement.previousRevision}
							/>
							<span aria-hidden="true"> → </span>
							<span className="sr-only"> to </span>
							<ComparisonRevision
								testId="bridge-review-comparison-current-shared-start-revision"
								value={props.summary.sharedStartMovement.currentRevision}
							/>
						</>
					)}
				</dd>
			</dl>
			{props.summary.sharedStartMovement.kind === 'changed' ? (
				<p className="mt-1 text-[11px] text-[var(--bridge-text-muted)]">
					Files may have entered or left this review.
				</p>
			) : null}
		</section>
	);
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

interface ComparisonRevisionMovement {
	readonly currentRevision: string;
	readonly previousRevision: string;
}

interface ComparisonMovementSummary {
	readonly sharedStartMovement:
		| ({ readonly kind: 'changed' } & ComparisonRevisionMovement)
		| { readonly kind: 'unchanged'; readonly revision: string };
	readonly symbolicTarget: ReviewComparisonTarget;
	readonly targetMovement: ComparisonRevisionMovement | null;
}

function deriveComparisonMovementSummary(
	precedingPackage: BridgeReviewPackage | null,
	currentPackage: BridgeReviewPackage,
): ComparisonMovementSummary | null {
	if (
		precedingPackage === null ||
		!comparisonPackagesShareMovementIdentity(precedingPackage, currentPackage)
	) {
		return null;
	}
	const precedingOrigin = precedingPackage.comparisonOrigin;
	const currentOrigin = currentPackage.comparisonOrigin;
	if (precedingOrigin?.kind !== 'contribution' || currentOrigin?.kind !== 'contribution') {
		return null;
	}
	const targetChanged = precedingOrigin.resolvedTargetOID !== currentOrigin.resolvedTargetOID;
	const sharedStartChanged =
		precedingOrigin.contributionBaseOID !== currentOrigin.contributionBaseOID;
	if (!targetChanged && !sharedStartChanged) {
		return null;
	}
	return {
		sharedStartMovement: sharedStartChanged
			? {
					currentRevision: currentOrigin.contributionBaseOID,
					kind: 'changed',
					previousRevision: precedingOrigin.contributionBaseOID,
				}
			: { kind: 'unchanged', revision: currentOrigin.contributionBaseOID },
		symbolicTarget: currentOrigin.symbolicTarget,
		targetMovement: targetChanged
			? {
					currentRevision: currentOrigin.resolvedTargetOID,
					previousRevision: precedingOrigin.resolvedTargetOID,
				}
			: null,
	};
}

function comparisonPackagesShareMovementIdentity(
	precedingPackage: BridgeReviewPackage | null,
	currentPackage: BridgeReviewPackage,
): boolean {
	if (
		precedingPackage?.comparisonOrigin?.kind !== 'contribution' ||
		currentPackage.comparisonOrigin?.kind !== 'contribution'
	) {
		return false;
	}
	return (
		precedingPackage.query.repoId === currentPackage.query.repoId &&
		precedingPackage.query.worktreeId === currentPackage.query.worktreeId &&
		comparisonTargetsEqual(
			precedingPackage.comparisonOrigin.symbolicTarget,
			currentPackage.comparisonOrigin.symbolicTarget,
		)
	);
}

function comparisonTargetsEqual(
	leftTarget: ReviewComparisonTarget,
	rightTarget: ReviewComparisonTarget,
): boolean {
	if (leftTarget.kind !== rightTarget.kind) {
		return false;
	}
	switch (leftTarget.kind) {
		case 'localDefaultBranch':
			return (
				rightTarget.kind === 'localDefaultBranch' &&
				leftTarget.branchName === rightTarget.branchName
			);
		case 'originDefaultBranch':
			return (
				rightTarget.kind === 'originDefaultBranch' &&
				leftTarget.branchName === rightTarget.branchName &&
				leftTarget.remoteName === rightTarget.remoteName
			);
		case 'branch':
			return rightTarget.kind === 'branch' && leftTarget.name === rightTarget.name;
		case 'commit':
			return rightTarget.kind === 'commit' && leftTarget.oid === rightTarget.oid;
		case 'ref':
			return rightTarget.kind === 'ref' && leftTarget.name === rightTarget.name;
	}
	return unreachableComparisonValue(leftTarget);
}

function reviewPackageIdentity(reviewPackage: BridgeReviewPackage): string {
	return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}:${reviewPackage.revision}`;
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
			: `Compare: ${displayedTargetLabel} · Stale`;
	}
	const activeTarget = props.comparisonPresentation?.activeTarget;
	if (activeTarget === undefined || activeTarget === null) {
		return 'Choose target';
	}
	return `Compare: ${comparisonTargetLabel(activeTarget)}`;
}

type ReviewComparisonTargetCatalog = NonNullable<
	NonNullable<BridgeReviewComparisonControlProps['comparisonPresentation']>['targetCatalog']
>;

function sharedStartRelationshipDescription(
	target: ReviewComparisonTarget,
	targetCatalog: ReviewComparisonTargetCatalog | null,
): string {
	const targetLabel = comparisonTargetLabel(target);
	return targetCatalog !== null && targetMatchesCatalogDefault(target, targetCatalog.defaultTarget)
		? `Latest commit shared with default branch ${targetLabel}`
		: `Latest commit shared with ${targetLabel}`;
}

function targetMatchesCatalogDefault(
	target: ReviewComparisonTarget,
	defaultTarget: ReviewComparisonTargetCatalog['defaultTarget'],
): boolean {
	if (defaultTarget === null) {
		return false;
	}
	if (defaultTarget.kind === 'local') {
		return (
			(target.kind === 'localDefaultBranch' && target.branchName === defaultTarget.branchName) ||
			(target.kind === 'branch' && target.name === defaultTarget.branchName)
		);
	}
	return (
		target.kind === 'originDefaultBranch' &&
		target.remoteName === defaultTarget.remoteName &&
		target.branchName === defaultTarget.branchName
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
