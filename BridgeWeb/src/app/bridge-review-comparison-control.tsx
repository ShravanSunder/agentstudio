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
import { Field, FieldTitle } from '../components/ui/field.js';
import { Input } from '../components/ui/input.js';
import { Popover, PopoverContent, PopoverTitle, PopoverTrigger } from '../components/ui/popover.js';
import { ToggleGroup, ToggleGroupItem } from '../components/ui/toggle-group.js';
import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerReviewComparisonUpdateCommand } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewComparisonTargetsQueryState } from './bridge-app-review-render-snapshot-controller.js';
import { BridgeReviewComparisonBranchSelector } from './bridge-review-comparison-branch-selector.js';
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
	const onCancelTargetQuery = props.onCancelTargetQuery;
	const branchSearchInputRef = useRef<HTMLInputElement>(null);
	const commitInputRef = useRef<HTMLInputElement>(null);
	const cancelTargetQueryAndClose = (): void => {
		onCancelTargetQuery?.();
		setOpen(false);
	};
	useEffect((): void => {
		if (!isActive && open) {
			onCancelTargetQuery?.();
			setOpen(false);
		}
	}, [isActive, onCancelTargetQuery, open]);
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
		cancelTargetQueryAndClose();
	};
	if (!isActive) {
		return null;
	}
	if (narrowComparisonLabel !== null) {
		return (
			<span
				aria-describedby={descriptionId}
				className={cn(buttonVariants({ size: 'sm', variant: 'outline' }), 'max-w-56')}
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
					onQueryTargets();
				} else {
					onCancelTargetQuery?.();
				}
			}}
			open={open}
		>
			<PopoverTrigger
				aria-describedby={descriptionId}
				aria-label={label}
				className={cn(buttonVariants({ size: 'sm', variant: 'outline' }), 'max-w-56')}
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
				className="w-96 gap-0"
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
									repositoryDefaultTarget={
										props.comparisonPresentation?.repositoryDefaultTarget ?? null
									}
								/>
							)}
							{statePresentation === null ? null : (
								<ComparisonAttemptState
									onRetry={(target): void => {
										props.onApplyTarget(target);
										cancelTargetQueryAndClose();
									}}
									presentation={statePresentation}
								/>
							)}
						</div>
						<div
							aria-hidden="true"
							className="-mx-2 my-3 h-px bg-border"
							data-testid="bridge-review-comparison-section-divider"
						/>
					</>
				) : null}
				<section
					className="grid grid-cols-[max-content_minmax(0,1fr)] gap-y-2"
					data-testid="bridge-review-comparison-target-selection"
				>
					<PopoverTitle className="col-span-2 px-1 text-xs/relaxed uppercase text-foreground">
						Compare Worktree
					</PopoverTitle>
					<Field
						className="col-span-2 grid grid-cols-subgrid items-center gap-x-3 px-1"
						orientation="horizontal"
					>
						<FieldTitle className="text-muted-foreground">Compare with</FieldTitle>
						<ToggleGroup
							aria-label="Comparison target kind"
							role="group"
							size="sm"
							spacing={0}
							value={[selectionMode]}
							variant="outline"
						>
							<ToggleGroupItem
								onPressedChange={(pressed): void => {
									if (pressed) {
										setSelectionMode('branch');
										setValidationMessage(null);
									}
								}}
								value="branch"
							>
								Branch
							</ToggleGroupItem>
							<ToggleGroupItem
								onPressedChange={(pressed): void => {
									if (pressed) {
										setSelectionMode('commit');
										setValidationMessage(null);
									}
								}}
								value="commit"
							>
								Commit
							</ToggleGroupItem>
						</ToggleGroup>
					</Field>
					{selectionMode === 'branch' ? (
						<BridgeReviewComparisonBranchSelector
							activeTarget={activeTarget}
							onSelectTarget={(target): void => {
								props.onApplyTarget(target);
								cancelTargetQueryAndClose();
							}}
							searchInputRef={branchSearchInputRef}
							targetQueryState={targetQueryState}
							onRetry={onQueryTargets}
						/>
					) : (
						<form className="col-span-2 flex flex-col gap-2" onSubmit={applyCommitOID}>
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
									<p className="mt-1 text-xs/relaxed text-destructive" role="alert">
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
				className="flex flex-col gap-2 px-1"
				data-resolved-target-oid={origin.resolvedTargetOID}
				data-testid="bridge-review-comparison-current-state"
			>
				<h2 className="text-xs/relaxed font-medium uppercase text-foreground">
					Current comparison
				</h2>
				<p className="flex min-w-0 items-baseline gap-1.5 text-xs/relaxed text-foreground">
					<span className="shrink-0">Commit:</span>
					<ComparisonRevision
						testId="bridge-review-comparison-effective-revision"
						value={origin.baseOID}
					/>
				</p>
			</section>
		);
	}
	const isDefault = targetMatchesRepositoryDefault(symbolicTarget, props.repositoryDefaultTarget);
	const activeBasis = origin.baseRole === 'commonCommit' ? 'commonCommit' : 'branchTip';
	const effectiveBasisLabel = activeBasis === 'commonCommit' ? 'Common commit' : 'Branch tip';
	return (
		<section
			className="flex flex-col gap-2 px-1"
			data-resolved-target-oid={origin.resolvedTargetOID}
			data-testid="bridge-review-comparison-current-state"
		>
			<h2 className="text-xs/relaxed font-medium uppercase text-foreground">Current comparison</h2>
			<div className="flex flex-col gap-1.5">
				<p
					className="flex min-w-0 items-baseline gap-1.5 text-xs/relaxed text-foreground"
					data-testid="bridge-review-comparison-current-target"
				>
					<span className="truncate">Branch: {targetLabel}</span>
					{isDefault ? (
						<span className="flex shrink-0 items-baseline gap-1 text-xs/relaxed text-muted-foreground">
							<span aria-hidden="true">·</span>
							<span>Default</span>
						</span>
					) : null}
				</p>
				<div
					className="flex min-w-0 items-center gap-2 text-xs/relaxed text-foreground"
					data-testid="bridge-review-comparison-current-basis"
				>
					<span className="shrink-0">Comparing from:</span>
					<span
						className="flex min-w-0 items-baseline gap-1"
						data-testid="bridge-review-comparison-effective-basis"
					>
						<span>{effectiveBasisLabel} @</span>
						<ComparisonRevision
							testId="bridge-review-comparison-effective-revision"
							value={origin.baseOID}
						/>
					</span>
				</div>
			</div>
		</section>
	);
}

function ComparisonAttemptState(props: {
	readonly onRetry: (target: ReviewComparisonTarget) => void;
	readonly presentation: ComparisonStatePresentation;
}): ReactElement {
	switch (props.presentation.kind) {
		case 'message':
			return (
				<ComparisonAttemptMessage
					description={props.presentation.description}
					heading={props.presentation.heading}
				/>
			);
		case 'retry': {
			const retryTarget = props.presentation.retryTarget;
			return (
				<ComparisonAttemptMessage
					description={props.presentation.description}
					heading={props.presentation.heading}
				>
					<Button
						className="mt-2"
						onClick={(): void => props.onRetry(retryTarget)}
						size="sm"
						type="button"
						variant="outline"
					>
						Retry
					</Button>
				</ComparisonAttemptMessage>
			);
		}
	}
	return unreachableComparisonValue(props.presentation);
}

function ComparisonAttemptMessage(props: {
	readonly children?: ReactElement;
	readonly description: string | null;
	readonly heading: string;
}): ReactElement {
	return (
		<section aria-live="polite" className="px-1">
			<p className="text-xs/relaxed font-medium uppercase text-muted-foreground">{props.heading}</p>
			{props.description === null ? null : (
				<p className="mt-0.5 text-xs/relaxed text-muted-foreground">{props.description}</p>
			)}
			{props.children}
		</section>
	);
}

function ComparisonRevision(props: {
	readonly testId: string;
	readonly value: string;
}): ReactElement {
	return (
		<code className="font-mono text-foreground" data-testid={props.testId} title={props.value}>
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

type ComparisonStatePresentation =
	| {
			readonly description: string | null;
			readonly heading: string;
			readonly kind: 'message';
	  }
	| {
			readonly description: string;
			readonly heading: string;
			readonly kind: 'retry';
			readonly retryTarget: ReviewComparisonTarget;
	  };

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
				kind: 'message',
			};
		case 'pending':
			return displayedContribution?.heading === 'Previous comparison'
				? {
						description: null,
						heading: 'Updating comparison',
						kind: 'message',
					}
				: {
						description: 'No comparison is displayed yet.',
						heading: 'Preparing comparison',
						kind: 'message',
					};
		case 'settled':
			return displayedContribution?.heading === 'Previous comparison' &&
				isDisplayedPackageAwaitingPresentationDelivery(props)
				? {
						description: null,
						heading: 'Updating comparison',
						kind: 'message',
					}
				: null;
		case 'unavailable': {
			const unavailableDescription =
				displayedContribution?.heading === 'Previous comparison'
					? 'The selected target could not be refreshed. The previous comparison remains visible.'
					: 'The selected target could not be compared.';
			if (
				comparisonPresentation.attempt.retryable &&
				comparisonPresentation.activeTarget !== null
			) {
				return {
					description: unavailableDescription,
					heading: 'Comparison unavailable',
					kind: 'retry',
					retryTarget: comparisonPresentation.activeTarget,
				};
			}
			return {
				description: unavailableDescription,
				heading: 'Comparison unavailable',
				kind: 'message',
			};
		}
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
			? `Compare to: ${displayedTargetLabel} · Updating`
			: attemptStatus === 'unavailable'
				? `Compare to: ${displayedTargetLabel} · Unavailable`
				: `Compare to: ${displayedTargetLabel} · Stale`;
	}
	const activeTarget = props.comparisonPresentation?.activeTarget;
	if (activeTarget === undefined || activeTarget === null) {
		return 'Choose target';
	}
	return `Compare to: ${comparisonTargetLabel(activeTarget)}`;
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
