import { FolderTreeIcon, MessageSquareIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import {
	createBridgeReviewItemRegistry,
	reviewItemPathLabel,
} from '../../foundation/review-package/bridge-review-item-registry.js';
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeReviewPackage,
	BridgeSourceEndpoint,
	BridgeSourceEndpointKind,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import { BridgeReviewButton, BridgeReviewIcon } from '../chrome/bridge-review-button.js';
import {
	BridgeReviewFilterMenu,
	type BridgeReviewFilterOption,
} from '../chrome/bridge-review-filter-menu.js';
import { BridgeReviewSearchControl } from '../chrome/bridge-review-search-control.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
import { BridgeCodeViewPanel } from '../code-view/bridge-code-view-panel.js';
import { BridgeMarkdownPreview } from '../markdown/bridge-markdown-preview.js';
import type {
	BridgeReviewProjectionMode,
	BridgeReviewProjectionResult,
} from '../models/review-projection-models.js';
import { BridgeReviewTreesPanel } from '../trees/bridge-trees-panel.js';

export interface ReviewViewerShellProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly onSelectItem: (itemId: string) => void;
	readonly selectedContentText?: string | null;
	readonly selectedContentResources?: BridgeCodeViewContentResources | null;
	readonly selectedContentUnavailablePath?: string | null;
	readonly selectedMarkdownPreviewHtml?: string | null;
	readonly selectedMarkdownPreviewSourcePath?: string | null;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly projectionMode?: BridgeReviewProjectionMode;
	readonly onProjectionModeChange?: (mode: BridgeReviewProjectionMode) => void;
	readonly treeSearchText?: string;
	readonly onTreeSearchTextChange?: (searchText: string) => void;
	readonly gitStatusFilter?: BridgeFileChangeKind | 'all';
	readonly onGitStatusFilterChange?: (status: BridgeFileChangeKind | 'all') => void;
	readonly fileClassFilter?: BridgeFileClass | 'all';
	readonly onFileClassFilterChange?: (fileClass: BridgeFileClass | 'all') => void;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
	readonly telemetryParentTraceContext?: BridgeTraceContext | null;
}

export function BridgeReviewEmptyShell(): ReactElement {
	return (
		<main data-testid="bridge-review-empty-shell">
			<section aria-label="Review summary">
				<p>Bridge Review</p>
				<p>Waiting for review package</p>
			</section>
			<nav aria-label="Changed files" />
			<section aria-label="Selected content">
				<pre />
			</section>
		</main>
	);
}

export function BridgeReviewProjectionPendingShell(): ReactElement {
	return (
		<main
			className="flex h-screen min-h-screen w-full items-center justify-center bg-[var(--bridge-app-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-projection-pending-shell"
		>
			<section aria-label="Review projection status">
				<p className="text-sm">Projecting review</p>
			</section>
		</main>
	);
}

export function BridgeReviewProjectionFailedShell(): ReactElement {
	return (
		<main
			className="flex h-screen min-h-screen w-full items-center justify-center bg-[var(--bridge-app-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-projection-failed-shell"
		>
			<section aria-label="Review projection status" className="text-center">
				<p className="text-sm text-[var(--bridge-text-primary)]">Review projection unavailable</p>
				<p className="mt-1 text-xs">The review package could not be projected.</p>
			</section>
		</main>
	);
}

export function ReviewViewerShell(props: ReviewViewerShellProps): ReactElement {
	const registry = createBridgeReviewItemRegistry({
		reviewPackage: props.reviewPackage,
		selectedItemId: props.selectedItemId,
	});
	const summary = props.reviewPackage.summary;
	const filterLabels = reviewFilterLabels(props.reviewPackage);
	const groupingLabel =
		props.reviewPackage.query.grouping.label ?? props.reviewPackage.query.grouping.kind;
	const reviewScopeLabel = reviewCheckpointOrCollationLabel(props.reviewPackage);
	const projectionMode = props.projectionMode ?? { kind: 'allFiles' };
	const gitStatusFilter = props.gitStatusFilter ?? 'all';
	const fileClassFilter = props.fileClassFilter ?? 'all';
	const treeSearchText = props.treeSearchText ?? '';
	const projection = props.projection;

	return (
		<main
			className="flex h-screen min-h-screen w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)]"
			data-sidebar-position="right"
			data-testid="review-viewer-shell"
		>
			<header
				className="flex min-h-9 shrink-0 items-center gap-3 border-b border-[var(--bridge-border-subtle)] bg-[var(--bridge-header-bg)] px-3"
				data-testid="bridge-review-top-header"
			>
				<section aria-label="Review summary" className="flex min-w-0 flex-1 items-center gap-3">
					<div className="flex min-w-0 items-center gap-2 text-sm">
						<span className="shrink-0 font-semibold text-[var(--bridge-text-primary)]">
							{summary.filesChanged} {summary.filesChanged === 1 ? 'file' : 'files'} changed
						</span>
						<span className="shrink-0 text-xs text-[var(--bridge-added)]">
							+{summary.additions}
						</span>
						<span className="shrink-0 text-xs text-[var(--bridge-deleted)]">
							-{summary.deletions}
						</span>
						<span className="truncate text-xs text-[var(--bridge-text-secondary)]">
							{props.reviewPackage.baseEndpoint.label} to {props.reviewPackage.headEndpoint.label}
						</span>
					</div>
					<div className="hidden min-w-0 items-center gap-2 text-[11px] text-[var(--bridge-text-muted)] md:flex">
						<span className="shrink-0">Generation {props.reviewPackage.reviewGeneration}</span>
						<span aria-hidden="true">/</span>
						<span className="shrink-0">{groupingLabel}</span>
						<span aria-hidden="true">/</span>
						<span className="truncate">{reviewScopeLabel}</span>
						<span className="sr-only">
							{filterLabels.length === 0 ? 'All files' : filterLabels.join(' ')}
						</span>
					</div>
				</section>
				<nav aria-label="Review controls" className="flex shrink-0 items-center gap-1">
					<div
						aria-label="Projection"
						className="inline-flex h-7 items-center gap-0.5 rounded-md bg-transparent p-0"
						data-bridge-segmented-control="true"
						data-testid="bridge-review-projection-scope"
						role="group"
					>
						{projectionButtonSpecs.map((spec) => (
							<BridgeReviewButton
								ariaPressed={projectionMode.kind === spec.mode.kind}
								className="bridge-review-projection-button h-6 rounded-[5px] px-2"
								data-testid={`bridge-review-projection-${spec.testIdSuffix}`}
								key={spec.label}
								onClick={() => props.onProjectionModeChange?.(spec.mode)}
							>
								{spec.label}
							</BridgeReviewButton>
						))}
					</div>
				</nav>
			</header>
			<div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_minmax(260px,340px)]">
				<section
					aria-label="Selected content"
					className="min-h-0 min-w-0 overflow-auto overscroll-contain bg-[var(--bridge-canvas-bg)]"
					data-testid="bridge-review-code-scroll"
				>
					<section
						aria-label="Code canvas"
						className="h-full min-h-0 min-w-0 bg-[var(--bridge-canvas-bg)]"
						data-testid="bridge-review-canvas"
					>
						{props.selectedMarkdownPreviewHtml !== undefined &&
						props.selectedMarkdownPreviewHtml !== null &&
						props.selectedMarkdownPreviewSourcePath !== undefined &&
						props.selectedMarkdownPreviewSourcePath !== null ? (
							<BridgeMarkdownPreview
								html={props.selectedMarkdownPreviewHtml}
								sourcePath={props.selectedMarkdownPreviewSourcePath}
							/>
						) : props.selectedContentUnavailablePath !== undefined &&
						  props.selectedContentUnavailablePath !== null ? (
							<BridgeReviewContentUnavailableState
								sourcePath={props.selectedContentUnavailablePath}
							/>
						) : (
							<BridgeCodeViewPanel
								projection={projection}
								reviewPackage={props.reviewPackage}
								selectedContentResources={props.selectedContentResources ?? null}
								selectedItemId={props.selectedItemId}
								telemetryParentTraceContext={props.telemetryParentTraceContext ?? null}
								{...(props.codeViewWorkerPoolEnabled === undefined
									? {}
									: { workerPoolEnabled: props.codeViewWorkerPoolEnabled })}
								{...(props.codeViewWorkerFactory === undefined
									? {}
									: { workerFactory: props.codeViewWorkerFactory })}
								{...(props.telemetryRecorder === undefined
									? {}
									: { telemetryRecorder: props.telemetryRecorder })}
							/>
						)}
					</section>
				</section>
				<aside
					className="order-last flex min-h-0 min-w-0 flex-col border-l border-[var(--bridge-border-opaque)] bg-[var(--bridge-surface-bg)]"
					data-testid="bridge-review-sidebar"
				>
					<div className="shrink-0 border-b border-[var(--bridge-border-subtle)] px-2 py-1.5">
						<div
							className="flex items-center justify-between gap-1"
							data-testid="bridge-review-rail-toolbar"
						>
							<div
								className="flex min-w-0 items-center gap-1"
								data-testid="bridge-review-rail-toolbar-leading"
							>
								<BridgeReviewButton
									data-testid="bridge-review-rail-files-view"
									ariaPressed
									ariaLabel="Show changed files"
									className="h-7 w-7 rounded-md border-transparent bg-transparent px-0"
									title="Changed files"
								>
									<BridgeReviewIcon>
										<FolderTreeIcon aria-hidden="true" className="size-4" />
									</BridgeReviewIcon>
								</BridgeReviewButton>
								<BridgeReviewButton
									data-testid="bridge-review-rail-comments-view"
									ariaLabel="Show review comments"
									className="h-7 w-7 rounded-md border-transparent bg-transparent px-0"
									title="Review comments"
								>
									<BridgeReviewIcon>
										<MessageSquareIcon aria-hidden="true" className="size-4" />
									</BridgeReviewIcon>
								</BridgeReviewButton>
							</div>
							<div
								className="flex min-w-0 items-center justify-end gap-1"
								data-testid="bridge-review-rail-toolbar-trailing"
							>
								<div data-testid="bridge-review-search-control-slot">
									<span className="sr-only">Search files</span>
									<BridgeReviewSearchControl
										onChange={(value: string): void => props.onTreeSearchTextChange?.(value)}
										value={treeSearchText}
									/>
								</div>
								<div className="shrink-0" data-testid="bridge-review-git-status-menu">
									<span className="sr-only">Git status</span>
									<BridgeReviewFilterMenu
										label="Git status filter"
										onChange={(value): void => props.onGitStatusFilterChange?.(value)}
										options={gitStatusOptions}
										showDefaultOptionInMenu={false}
										testId="bridge-review-git-status-menu-control"
										value={gitStatusFilter}
									/>
								</div>
								<div className="shrink-0" data-testid="bridge-review-file-class-menu">
									<span className="sr-only">File class</span>
									<BridgeReviewFilterMenu
										label="File class filter"
										onChange={(value): void => props.onFileClassFilterChange?.(value)}
										options={fileClassOptions}
										testId="bridge-review-file-class-menu-control"
										value={fileClassFilter}
									/>
								</div>
							</div>
						</div>
					</div>
					<div
						className="min-h-0 flex-1 overflow-hidden overscroll-contain"
						data-testid="bridge-review-rail-scroll"
					>
						<nav
							aria-label="Changed files"
							className="h-full min-h-0"
							data-testid="bridge-review-rail-tree-slot"
						>
							<BridgeReviewTreesPanel
								onSelectItem={props.onSelectItem}
								projection={projection}
								reviewPackage={props.reviewPackage}
								searchText={treeSearchText}
								selectedItemId={props.selectedItemId}
							/>
							{registry.visibleItems.length === 0 ? null : (
								<div aria-hidden="true" hidden>
									{registry.visibleItems.map((item) => reviewItemPathLabel(item)).join(' ')}
								</div>
							)}
						</nav>
					</div>
					<div className="grid shrink-0 grid-cols-2 gap-x-3 gap-y-1 border-t border-[var(--bridge-border-subtle)] p-2 text-[11px] text-[var(--bridge-text-secondary)]">
						<span>Files</span>
						<span className="text-right text-[var(--bridge-text-primary)]">
							{summary.filesChanged}
						</span>
						<span>Additions</span>
						<span className="text-right text-[var(--bridge-added)]">{summary.additions}</span>
						<span>Deletions</span>
						<span className="text-right text-[var(--bridge-deleted)]">{summary.deletions}</span>
					</div>
				</aside>
			</div>
		</main>
	);
}

function BridgeReviewContentUnavailableState(props: { readonly sourcePath: string }): ReactElement {
	return (
		<section
			aria-label="Selected content unavailable"
			className="flex h-full min-h-[260px] items-center justify-center bg-[var(--bridge-canvas-bg)] px-8 text-center"
			data-testid="bridge-review-content-unavailable"
		>
			<div className="max-w-md">
				<p className="text-sm font-medium text-[var(--bridge-text-primary)]">Content unavailable</p>
				<p className="mt-1 truncate text-xs text-[var(--bridge-text-muted)]">{props.sourcePath}</p>
			</div>
		</section>
	);
}

const projectionButtonSpecs: readonly {
	readonly label: string;
	readonly mode: BridgeReviewProjectionMode;
	readonly testIdSuffix: string;
}[] = [
	{ label: 'All', mode: { kind: 'allFiles' }, testIdSuffix: 'all-files' },
	{ label: 'Changed', mode: { kind: 'changedFiles' }, testIdSuffix: 'changed-files' },
	{ label: 'Guided', mode: { kind: 'guidedReview' }, testIdSuffix: 'guided-review' },
	{
		label: 'Change set',
		mode: { kind: 'currentChangeSet', scope: { kind: 'activePackage' } },
		testIdSuffix: 'change-set',
	},
	{ label: 'Docs/plans', mode: { kind: 'docsAndPlans' }, testIdSuffix: 'docs-plans' },
	{ label: 'Tests', mode: { kind: 'tests' }, testIdSuffix: 'tests' },
	{ label: 'Source', mode: { kind: 'source' }, testIdSuffix: 'source' },
];

const gitStatusOptions: readonly BridgeReviewFilterOption<BridgeFileChangeKind | 'all'>[] = [
	{ value: 'all', label: 'All statuses', selectedLabel: 'All', icon: '*' },
	{ value: 'added', label: 'Added', icon: 'A' },
	{ value: 'modified', label: 'Modified', icon: 'M' },
	{ value: 'renamed', label: 'Renamed', icon: 'R' },
	{ value: 'deleted', label: 'Deleted', icon: 'D' },
	{ value: 'copied', label: 'Copied', icon: 'C' },
];

const bridgeFileClassOptions: readonly BridgeFileClass[] = [
	'source',
	'test',
	'docs',
	'config',
	'generated',
	'vendor',
	'binary',
	'large',
	'fixture',
	'unknown',
];

const fileClassOptions: readonly BridgeReviewFilterOption<BridgeFileClass | 'all'>[] = [
	{ value: 'all', label: 'All classes', selectedLabel: 'All', icon: '*' },
	...bridgeFileClassOptions.map(
		(fileClass: BridgeFileClass): BridgeReviewFilterOption<BridgeFileClass | 'all'> => ({
			value: fileClass,
			label: sentenceCase(fileClass),
			icon: fileClass.slice(0, 1).toUpperCase(),
		}),
	),
];

function sentenceCase(value: string): string {
	return value.length === 0 ? value : `${value.slice(0, 1).toUpperCase()}${value.slice(1)}`;
}

function reviewFilterLabels(reviewPackage: BridgeReviewPackage): readonly string[] {
	const filter = reviewPackage.filterState;
	return [
		...reviewPackage.query.pathScope.map((pathScope: string): string => `Folder: ${pathScope}`),
		...filter.includedFileClasses.map((fileClass: string): string => `Class: ${fileClass}`),
		...filter.changeKinds.map((changeKind: string): string => `Change: ${changeKind}`),
		...filter.reviewStates.map((reviewState: string): string => `State: ${reviewState}`),
		...filter.includedExtensions.map((extension: string): string => `Extension: ${extension}`),
	];
}

function reviewCheckpointOrCollationLabel(reviewPackage: BridgeReviewPackage): string {
	const checkpointEndpoint =
		checkpointEndpointLabel(reviewPackage.headEndpoint) ??
		checkpointEndpointLabel(reviewPackage.baseEndpoint);
	if (checkpointEndpoint !== null) {
		return `Checkpoint: ${checkpointEndpoint}`;
	}
	const groupingLabel = reviewPackage.query.grouping.label ?? reviewPackage.query.grouping.kind;
	return `Collation: ${groupingLabel}`;
}

function checkpointEndpointLabel(endpoint: BridgeSourceEndpoint): string | null {
	return isCheckpointEndpointKind(endpoint.kind) ? endpoint.label : null;
}

function isCheckpointEndpointKind(kind: BridgeSourceEndpointKind): boolean {
	return (
		kind === 'promptCheckpoint' ||
		kind === 'sessionCheckpoint' ||
		kind === 'manualCheckpoint' ||
		kind === 'savedTimeWindowCheckpoint'
	);
}
