import { BotIcon, FileTextIcon, ListChecksIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';

import { bridgeViewerChromeToolbarClassName } from '../../app/bridge-viewer-chrome.js';
import { BridgeViewerContentHeader } from '../../app/bridge-viewer-content-header.js';
import { cn } from '../../app/class-name.js';
import { Skeleton } from '../../components/ui/skeleton.js';
import {
	createBridgeReviewItemRegistry,
	reviewItemPathLabel,
} from '../../foundation/review-package/bridge-review-item-registry.js';
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import {
	BridgeReviewFacetMenu,
	bridgeReviewFileClassIcon,
	type BridgeReviewFacetMenuOption,
} from '../chrome/bridge-review-facet-menu.js';
import { BridgeReviewSearchControl } from '../chrome/bridge-review-search-control.js';
import type {
	BridgeCodeViewContentResources,
	BridgeCodeViewItemPresentation,
} from '../code-view/bridge-code-view-materialization.js';
import {
	BridgeCodeViewPanel,
	type BridgeCodeViewControlHandle,
} from '../code-view/bridge-code-view-panel.js';
import { BridgeMarkdownPreview } from '../markdown/bridge-markdown-preview.js';
import type {
	BridgeReviewProjectionMode,
	BridgeReviewProjectionResult,
	BridgeReviewSearchMode,
} from '../models/review-projection-models.js';
import { BridgeReviewTreesPanel } from '../trees/bridge-trees-panel.js';

export interface ReviewViewerShellProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly selectedContentLoadingItemId?: string | null;
	readonly onSelectItem: (itemId: string) => void;
	readonly selectedContentText?: string | null;
	readonly selectedContentResources?: BridgeCodeViewContentResources | null;
	readonly selectedItemPresentation?: BridgeCodeViewItemPresentation | null;
	readonly selectedContentUnavailablePath?: string | null;
	readonly selectedCanvasLoadingReason?: BridgeReviewCanvasLoadingReason | null;
	readonly selectedMarkdownPreviewHtml?: string | null;
	readonly selectedMarkdownPreviewSourcePath?: string | null;
	readonly visibleContentResourcesByItemId?: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly visibleLoadingItemIds?: ReadonlySet<string>;
	readonly visibleLoadingItemCount?: number;
	readonly visibleReadyItemCount?: number;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly projectionMode?: BridgeReviewProjectionMode;
	readonly onProjectionModeChange?: (mode: BridgeReviewProjectionMode) => void;
	readonly treeSearchText?: string;
	readonly treeSearchMode?: BridgeReviewSearchMode;
	readonly treeSearchOpen?: boolean;
	readonly onTreeSearchOpen?: () => void;
	readonly onTreeSearchModeChange?: (mode: BridgeReviewSearchMode) => void;
	readonly onTreeSearchTextChange?: (searchText: string) => void;
	readonly gitStatusFilter?: BridgeFileChangeKind | 'all';
	readonly onGitStatusFilterChange?: (status: BridgeFileChangeKind | 'all') => void;
	readonly fileClassFilter?: BridgeFileClass | 'all';
	readonly onFileClassFilterChange?: (fileClass: BridgeFileClass | 'all') => void;
	readonly onCodeViewControlHandleChange?: (handle: BridgeCodeViewControlHandle | null) => void;
	readonly onCodeViewVisibleItemIdsChange?: (itemIds: readonly string[]) => void;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
	readonly telemetryParentTraceContext?: BridgeTraceContext | null;
	readonly viewerHeaderControls?: ReactNode;
}

export type BridgeReviewCanvasLoadingReason = 'content' | 'markdownPreview';

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
			className="flex h-full min-h-0 w-full items-center justify-center bg-[var(--bridge-app-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-projection-pending-shell"
		>
			<section aria-label="Review projection status" className="flex w-72 flex-col gap-3">
				<p className="text-sm">Projecting review</p>
				<BridgeReviewShellSkeleton />
			</section>
		</main>
	);
}

export function BridgeReviewProjectionFailedShell(): ReactElement {
	return (
		<main
			className="flex h-full min-h-0 w-full items-center justify-center bg-[var(--bridge-app-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-projection-failed-shell"
		>
			<section aria-label="Review projection status" className="text-center">
				<p className="text-sm text-[var(--bridge-text-primary)]">Review projection unavailable</p>
				<p className="mt-1 text-xs">The review package could not be projected.</p>
			</section>
		</main>
	);
}

export function BridgeReviewPackageLoadingShell(): ReactElement {
	return (
		<main
			className="flex h-full min-h-0 w-full items-center justify-center bg-[var(--bridge-app-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-package-loading-shell"
		>
			<section aria-label="Review package status" className="flex w-72 flex-col gap-3">
				<p className="text-sm">Loading review package</p>
				<BridgeReviewShellSkeleton />
			</section>
		</main>
	);
}

export function BridgeReviewPackageFailedShell(props: {
	readonly error: string | null;
}): ReactElement {
	return (
		<main
			className="flex h-full min-h-0 w-full items-center justify-center bg-[var(--bridge-app-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-package-failed-shell"
		>
			<section aria-label="Review package status" className="text-center">
				<p className="text-sm text-[var(--bridge-text-primary)]">Review package unavailable</p>
				<p className="mt-1 text-xs">{props.error ?? 'The review package could not be loaded.'}</p>
			</section>
		</main>
	);
}

function BridgeReviewShellSkeleton(): ReactElement {
	return (
		<div className="flex w-full flex-col gap-2" data-testid="bridge-review-shell-skeleton">
			<Skeleton className="h-3 w-full bg-[var(--bridge-surface-raised-bg)]" />
			<Skeleton className="h-3 w-11/12 bg-[var(--bridge-surface-raised-bg)]" />
			<Skeleton className="h-3 w-3/4 bg-[var(--bridge-surface-raised-bg)]" />
		</div>
	);
}

export function ReviewViewerShell(props: ReviewViewerShellProps): ReactElement {
	const registry = createBridgeReviewItemRegistry({
		reviewPackage: props.reviewPackage,
		selectedItemId: props.selectedItemId,
	});
	const summary = props.reviewPackage.summary;
	const projectionMode = props.projectionMode ?? { kind: 'normalReview' };
	const gitStatusFilter = props.gitStatusFilter ?? 'all';
	const fileClassFilter = props.fileClassFilter ?? 'all';
	const treeSearchText = props.treeSearchText ?? '';
	const treeSearchMode = props.treeSearchMode ?? { kind: 'text' };
	const treeSearchOpen = props.treeSearchOpen === true || treeSearchText.length > 0;
	const projection = props.projection;
	const selectedItem =
		props.selectedItemId === null
			? null
			: (props.reviewPackage.itemsById[props.selectedItemId] ?? null);
	const selectedDisplayPath =
		selectedItem === null
			? null
			: (selectedItem.headPath ?? selectedItem.basePath ?? selectedItem.itemId);
	const contentHeaderTitle = bridgeReviewViewerHeaderTitle({
		reviewPackage: props.reviewPackage,
		selectedDisplayPath,
	});
	const selectedContentState = selectedContentStateForShell({
		selectedCanvasLoadingReason: props.selectedCanvasLoadingReason ?? null,
		selectedContentResources: props.selectedContentResources ?? null,
		selectedContentUnavailablePath: props.selectedContentUnavailablePath ?? null,
		selectedMarkdownPreviewHtml: props.selectedMarkdownPreviewHtml ?? null,
	});

	return (
		<main
			className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)]"
			data-selected-content-state={selectedContentState}
			data-selected-display-path={selectedDisplayPath ?? undefined}
			data-projection-id={projection.projectionId}
			data-projection-mode={projectionMode.kind}
			data-sidebar-position="right"
			data-testid="review-viewer-shell"
		>
			<div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_minmax(260px,340px)]">
				<section
					aria-label="Selected content"
					className="grid min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)] overflow-hidden overscroll-contain bg-[var(--bridge-canvas-bg)]"
					data-testid="bridge-review-code-scroll"
				>
					<BridgeViewerContentHeader
						controls={props.viewerHeaderControls}
						eyebrow="Review"
						title={contentHeaderTitle}
					/>
					<section
						aria-label="Code canvas"
						className="relative h-full min-h-0 min-w-0 bg-[var(--bridge-canvas-bg)]"
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
								selectedContentLoadingItemId={props.selectedContentLoadingItemId ?? null}
								selectedContentResources={props.selectedContentResources ?? null}
								selectedItemId={props.selectedItemId}
								selectedItemPresentation={props.selectedItemPresentation ?? null}
								telemetryParentTraceContext={props.telemetryParentTraceContext ?? null}
								{...(props.visibleLoadingItemIds === undefined
									? {}
									: { visibleLoadingItemIds: props.visibleLoadingItemIds })}
								visibleLoadingItemCount={props.visibleLoadingItemCount ?? 0}
								visibleReadyItemCount={props.visibleReadyItemCount ?? 0}
								{...(props.visibleContentResourcesByItemId === undefined
									? {}
									: {
											visibleContentResourcesByItemId: props.visibleContentResourcesByItemId,
										})}
								{...(props.onCodeViewVisibleItemIdsChange === undefined
									? {}
									: { onVisibleItemIdsChange: props.onCodeViewVisibleItemIdsChange })}
								{...(props.onCodeViewControlHandleChange === undefined
									? {}
									: {
											onControlHandleChange: props.onCodeViewControlHandleChange,
										})}
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
						{props.selectedCanvasLoadingReason === undefined ||
						props.selectedCanvasLoadingReason === null ||
						props.selectedCanvasLoadingReason === 'content' ? null : (
							<BridgeReviewCanvasLoadingState reason={props.selectedCanvasLoadingReason} />
						)}
					</section>
				</section>
				<aside
					className="order-last flex min-h-0 min-w-0 flex-col border-l border-[var(--bridge-border-opaque)] bg-[var(--bridge-surface-bg)]"
					data-testid="bridge-review-sidebar"
				>
					<div
						className={cn(
							'flex shrink-0 items-center justify-between gap-1',
							bridgeViewerChromeToolbarClassName,
						)}
						data-bridge-shared-rail-toolbar="true"
						data-testid="bridge-review-rail-toolbar"
					>
						<div
							className="flex min-w-0 items-center gap-1"
							data-testid="bridge-review-rail-toolbar-leading"
						>
							<BridgeReviewProjectionMenu
								projectionMode={projectionMode}
								{...(props.onProjectionModeChange === undefined
									? {}
									: { onProjectionModeChange: props.onProjectionModeChange })}
							/>
						</div>
						<div
							className="flex min-w-0 items-center justify-end gap-1"
							data-testid="bridge-review-rail-toolbar-trailing"
						>
							<div className="shrink-0" data-testid="bridge-review-facet-menu">
								<BridgeReviewFacetMenu
									fileClassFilter={fileClassFilter}
									fileClassOptions={fileClassOptions}
									gitStatusFilter={gitStatusFilter}
									gitStatusOptions={gitStatusOptions}
									onFileClassFilterChange={(value): void => props.onFileClassFilterChange?.(value)}
									onGitStatusFilterChange={(value): void => props.onGitStatusFilterChange?.(value)}
								/>
							</div>
							<div data-testid="bridge-review-search-control-slot">
								<span className="sr-only">Search files</span>
								<BridgeReviewSearchControl
									isActive={treeSearchOpen}
									onOpenSearch={(): void => props.onTreeSearchOpen?.()}
									onSearchModeChange={(mode): void => props.onTreeSearchModeChange?.(mode)}
									searchMode={treeSearchMode}
								/>
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
								{...(props.onTreeSearchTextChange === undefined
									? {}
									: { onSearchTextChange: props.onTreeSearchTextChange })}
								projection={projection}
								reviewPackage={props.reviewPackage}
								searchOpen={treeSearchOpen}
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
					<div
						aria-label="Review summary"
						className="grid shrink-0 grid-cols-2 gap-x-3 gap-y-1 border-t border-[var(--bridge-border-subtle)] p-2 text-[11px] text-[var(--bridge-text-secondary)]"
						data-testid="bridge-review-rail-stats"
					>
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

export function BridgeReviewCanvasLoadingState(props: {
	readonly reason: BridgeReviewCanvasLoadingReason;
}): ReactElement {
	return (
		<div
			aria-hidden="true"
			className="pointer-events-none absolute left-8 top-12 z-20 flex w-[min(28rem,calc(100%-4rem))] flex-col gap-2 rounded-md border border-[var(--bridge-border-subtle)] bg-[var(--bridge-surface-bg)]/75 p-3 shadow-[0_18px_48px_rgb(0_0_0_/_0.45)] backdrop-blur"
			data-bridge-review-canvas-loading-reason={props.reason}
			data-testid="bridge-review-canvas-loading-state"
		>
			<Skeleton
				className="h-3 w-full bg-[var(--bridge-surface-raised-bg)]"
				data-testid="bridge-review-canvas-loading-line"
			/>
			<Skeleton
				className="h-3 w-11/12 bg-[var(--bridge-surface-raised-bg)]"
				data-testid="bridge-review-canvas-loading-line"
			/>
			<Skeleton
				className="h-3 w-3/4 bg-[var(--bridge-surface-raised-bg)]"
				data-testid="bridge-review-canvas-loading-line"
			/>
		</div>
	);
}

export function BridgeReviewProjectionMenu(props: {
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly onProjectionModeChange?: (mode: BridgeReviewProjectionMode) => void;
}): ReactElement {
	return (
		<div
			aria-label="Review mode"
			className={[
				'inline-flex h-7 shrink-0 items-center gap-0.5 rounded-md border border-[var(--bridge-border-subtle)]',
				'bg-[var(--bridge-header-control-bg)] p-0.5',
			].join(' ')}
			data-bridge-segmented-control="review-mode"
			data-testid="bridge-review-mode-segmented-control"
			role="radiogroup"
		>
			{projectionButtonSpecs.map((spec) => {
				const isSelected = spec.mode.kind === props.projectionMode.kind;
				return (
					<button
						aria-checked={isSelected ? 'true' : 'false'}
						aria-label={spec.label}
						className={[
							'flex size-6 items-center justify-center rounded-[5px] border border-transparent',
							'text-[var(--bridge-text-secondary)] transition-colors',
							'hover:bg-[var(--bridge-list-hover-bg)] hover:text-[var(--bridge-text-primary)]',
							'focus-visible:border-[var(--bridge-focus-border)] focus-visible:outline-none',
							isSelected &&
								'bg-[var(--bridge-header-control-active-bg)] text-[var(--bridge-text-primary)] shadow-none',
						]
							.filter(Boolean)
							.join(' ')}
						data-testid="bridge-review-mode-segment"
						key={spec.value}
						onClick={(): void => {
							if (!isSelected) {
								props.onProjectionModeChange?.(spec.mode);
							}
						}}
						role="radio"
						title={spec.label}
						type="button"
					>
						<spec.Icon aria-hidden="true" className="size-3.5" />
					</button>
				);
			})}
		</div>
	);
}

function bridgeReviewViewerHeaderTitle(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedDisplayPath: string | null;
}): string {
	const sourceTitle = props.reviewPackage.query.queryId;
	return props.selectedDisplayPath === null
		? sourceTitle
		: `${sourceTitle} / ${props.selectedDisplayPath}`;
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

function selectedContentStateForShell(props: {
	readonly selectedCanvasLoadingReason: BridgeReviewCanvasLoadingReason | null;
	readonly selectedContentResources: BridgeCodeViewContentResources | null;
	readonly selectedContentUnavailablePath: string | null;
	readonly selectedMarkdownPreviewHtml: string | null;
}): 'failed' | 'loading' | 'ready' | 'unavailable' {
	if (props.selectedContentUnavailablePath !== null) {
		return 'failed';
	}
	if (props.selectedMarkdownPreviewHtml !== null || props.selectedContentResources !== null) {
		return 'ready';
	}
	if (props.selectedCanvasLoadingReason === 'content') {
		return 'loading';
	}
	return 'unavailable';
}

const projectionButtonSpecs: readonly {
	readonly label: string;
	readonly mode: BridgeReviewProjectionMode;
	readonly value: string;
	readonly Icon: typeof ListChecksIcon;
}[] = [
	{
		label: 'Normal review',
		mode: { kind: 'normalReview' },
		value: 'normalReview',
		Icon: ListChecksIcon,
	},
	{
		label: 'Guided review',
		mode: { kind: 'guidedReview' },
		value: 'guidedReview',
		Icon: BotIcon,
	},
	{
		label: 'Plans/specs',
		mode: { kind: 'plansAndSpecs' },
		value: 'plansAndSpecs',
		Icon: FileTextIcon,
	},
];

const gitStatusOptions: readonly BridgeReviewFacetMenuOption<BridgeFileChangeKind | 'all'>[] = [
	{ value: 'all', label: 'All statuses', description: 'Show every Git change kind', icon: '*' },
	{ value: 'added', label: 'Added', description: 'New files and created paths', icon: 'A' },
	{ value: 'modified', label: 'Modified', description: 'Files changed in place', icon: 'M' },
	{ value: 'renamed', label: 'Renamed', description: 'Moves and path renames', icon: 'R' },
	{ value: 'deleted', label: 'Deleted', description: 'Removed files and paths', icon: 'D' },
	{
		value: 'copied',
		label: 'Copied',
		description: 'Copied paths when Git reports them',
		icon: 'C',
	},
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

const fileClassOptions: readonly BridgeReviewFacetMenuOption<BridgeFileClass | 'all'>[] = [
	{ value: 'all', label: 'All file types', description: 'Show every classified file', icon: '*' },
	...bridgeFileClassOptions.map(
		(fileClass: BridgeFileClass): BridgeReviewFacetMenuOption<BridgeFileClass | 'all'> => ({
			value: fileClass,
			label: sentenceCase(fileClass),
			description: descriptionForFileClass(fileClass),
			icon: bridgeReviewFileClassIcon(fileClass),
		}),
	),
];

function sentenceCase(value: string): string {
	return value.length === 0 ? value : `${value.slice(0, 1).toUpperCase()}${value.slice(1)}`;
}

function descriptionForFileClass(fileClass: BridgeFileClass): string {
	switch (fileClass) {
		case 'source':
			return 'Application and library implementation files';
		case 'test':
			return 'Tests, specs, fixtures, and verification code';
		case 'docs':
			return 'Plans, specs, markdown, and documentation';
		case 'config':
			return 'Build, package, and tool configuration';
		case 'generated':
			return 'Generated files that may be lower review priority';
		case 'vendor':
			return 'Vendored or third-party source trees';
		case 'binary':
			return 'Binary files and non-text assets';
		case 'large':
			return 'Large text files that need careful hydration';
		case 'fixture':
			return 'Fixture data and test inputs';
		case 'unknown':
			return 'Files without a confident class';
	}
	const exhaustiveFileClass: never = fileClass;
	void exhaustiveFileClass;
	return 'Files in this class';
}
