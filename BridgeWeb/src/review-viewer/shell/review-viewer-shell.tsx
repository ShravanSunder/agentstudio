import type { ChangeEvent, ReactElement } from 'react';

import { cn } from '../../app/class-name.js';
import type {
	BridgeContentFetch,
	BridgeContentResource,
	LoadBridgeContentResourceProps,
} from '../../foundation/content/content-resource-loader.js';
import { loadBridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import {
	createBridgeReviewItemRegistry,
	reviewItemPathLabel,
} from '../../foundation/review-package/bridge-review-item-registry.js';
import type {
	BridgeContentHandle,
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
	BridgeSourceEndpoint,
	BridgeSourceEndpointKind,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
import { BridgeCodeViewPanel } from '../code-view/bridge-code-view-panel.js';
import type {
	BridgeReviewProjectionMode,
	BridgeReviewProjectionResult,
} from '../models/review-projection-models.js';
import {
	bridgeFileChangeKindSchema,
	bridgeFileClassSchema,
} from '../models/review-projection-models.js';
import { BridgeReviewTreesPanel } from '../trees/bridge-trees-panel.js';

export interface ReviewViewerShellProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly onSelectItem: (itemId: string) => void;
	readonly selectedContentText?: string | null;
	readonly selectedContentResources?: BridgeCodeViewContentResources | null;
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

export interface LoadSelectedReviewItemContentProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
	readonly fetchContent?: BridgeContentFetch;
	readonly traceContext?: BridgeTraceContext | null;
	readonly sendTraceparentHeader?: boolean;
	readonly signal?: AbortSignal;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
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
			<header className="flex min-h-12 shrink-0 items-center gap-3 border-b border-[var(--bridge-border-opaque)] bg-[var(--bridge-surface-bg)] px-3">
				<section aria-label="Review summary" className="min-w-0 flex-1">
					<div className="flex min-w-0 items-center gap-3 text-sm">
						<p className="shrink-0 font-medium text-[var(--bridge-text-primary)]">
							{summary.filesChanged} {summary.filesChanged === 1 ? 'file' : 'files'} changed
						</p>
						<p className="shrink-0 text-xs text-[var(--bridge-text-secondary)]">
							<span className="text-[var(--bridge-added)]">{summary.additions}</span> additions /{' '}
							<span className="text-[var(--bridge-deleted)]">{summary.deletions}</span> deletions
						</p>
						<p className="truncate text-xs text-[var(--bridge-text-secondary)]">
							{props.reviewPackage.baseEndpoint.label} to {props.reviewPackage.headEndpoint.label}
						</p>
					</div>
					<div className="mt-0.5 flex min-w-0 items-center gap-2 text-[11px] text-[var(--bridge-text-muted)]">
						<p className="shrink-0">
							Generation {props.reviewPackage.reviewGeneration} · {groupingLabel}
						</p>
						<p className="truncate">{reviewScopeLabel}</p>
						<p className="truncate">
							{filterLabels.length === 0 ? 'All files' : filterLabels.join(' · ')}
						</p>
					</div>
				</section>
				<nav aria-label="Review controls" className="flex shrink-0 items-center gap-1.5">
					<div aria-label="Projection" className="flex items-center gap-1">
						{projectionButtonSpecs.map((spec) => (
							<button
								aria-pressed={projectionMode.kind === spec.mode.kind}
								className={cn(
									'h-7 rounded-[6px] px-2 text-xs text-[var(--bridge-text-secondary)] transition-colors',
									'hover:bg-[var(--bridge-surface-raised-bg)] hover:text-[var(--bridge-text-primary)]',
									projectionMode.kind === spec.mode.kind &&
										'bg-[var(--bridge-accent-soft)] text-[var(--bridge-text-primary)]',
								)}
								key={spec.label}
								onClick={() => props.onProjectionModeChange?.(spec.mode)}
								type="button"
							>
								{spec.label}
							</button>
						))}
					</div>
				</nav>
			</header>
			<div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_minmax(260px,340px)]">
				<section
					aria-label="Selected content"
					className="min-h-0 min-w-0 overflow-hidden bg-[var(--bridge-canvas-bg)]"
					data-testid="bridge-review-canvas"
				>
					<BridgeCodeViewPanel
						projection={projection}
						reviewPackage={props.reviewPackage}
						selectedContentResources={props.selectedContentResources ?? null}
						selectedItemId={props.selectedItemId}
						telemetryParentTraceContext={props.telemetryParentTraceContext ?? null}
						{...(props.telemetryRecorder === undefined
							? {}
							: { telemetryRecorder: props.telemetryRecorder })}
					/>
				</section>
				<aside
					className="order-last flex min-h-0 min-w-0 flex-col border-l border-[var(--bridge-border-opaque)] bg-[var(--bridge-surface-bg)]"
					data-testid="bridge-review-sidebar"
				>
					<div className="shrink-0 border-b border-[var(--bridge-border-subtle)] p-2">
						<label className="block text-[11px] text-[var(--bridge-text-muted)]">
							Search files
							<input
								aria-label="Search files"
								className="mt-1 h-8 w-full rounded-[6px] border border-[var(--bridge-border-opaque)] bg-[var(--bridge-canvas-bg)] px-2 text-xs text-[var(--bridge-text-primary)] outline-none focus:border-[var(--bridge-accent)]"
								onChange={(event: ChangeEvent<HTMLInputElement>): void =>
									props.onTreeSearchTextChange?.(event.target.value)
								}
								type="search"
								value={treeSearchText}
							/>
						</label>
						<div className="mt-2 grid grid-cols-2 gap-2">
							<label className="block text-[11px] text-[var(--bridge-text-muted)]">
								Git status
								<select
									aria-label="Git status filter"
									className="mt-1 h-7 w-full rounded-[6px] border border-[var(--bridge-border-opaque)] bg-[var(--bridge-canvas-bg)] px-1.5 text-xs text-[var(--bridge-text-primary)] outline-none focus:border-[var(--bridge-accent)]"
									onChange={(event: ChangeEvent<HTMLSelectElement>): void =>
										props.onGitStatusFilterChange?.(parseGitStatusFilter(event.target.value))
									}
									value={gitStatusFilter}
								>
									<option value="all">All statuses</option>
									<option value="added">Added</option>
									<option value="modified">Modified</option>
									<option value="renamed">Renamed</option>
									<option value="deleted">Deleted</option>
									<option value="copied">Copied</option>
								</select>
							</label>
							<label className="block text-[11px] text-[var(--bridge-text-muted)]">
								File class
								<select
									aria-label="File class filter"
									className="mt-1 h-7 w-full rounded-[6px] border border-[var(--bridge-border-opaque)] bg-[var(--bridge-canvas-bg)] px-1.5 text-xs text-[var(--bridge-text-primary)] outline-none focus:border-[var(--bridge-accent)]"
									onChange={(event: ChangeEvent<HTMLSelectElement>): void =>
										props.onFileClassFilterChange?.(parseFileClassFilter(event.target.value))
									}
									value={fileClassFilter}
								>
									<option value="all">All classes</option>
									{bridgeFileClassOptions.map((fileClass: BridgeFileClass) => (
										<option key={fileClass} value={fileClass}>
											{fileClass}
										</option>
									))}
								</select>
							</label>
						</div>
					</div>
					<nav aria-label="Changed files" className="min-h-0 flex-1 overflow-hidden">
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

const projectionButtonSpecs: readonly {
	readonly label: string;
	readonly mode: BridgeReviewProjectionMode;
}[] = [
	{ label: 'All', mode: { kind: 'allFiles' } },
	{ label: 'Changed', mode: { kind: 'changedFiles' } },
	{ label: 'Guided', mode: { kind: 'guidedReview' } },
	{
		label: 'Change set',
		mode: { kind: 'currentChangeSet', scope: { kind: 'activePackage' } },
	},
	{ label: 'Docs/plans', mode: { kind: 'docsAndPlans' } },
	{ label: 'Tests', mode: { kind: 'tests' } },
	{ label: 'Source', mode: { kind: 'source' } },
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

function parseGitStatusFilter(value: string): BridgeFileChangeKind | 'all' {
	if (value === 'all') {
		return 'all';
	}
	const parsed = bridgeFileChangeKindSchema.safeParse(value);
	return parsed.success ? parsed.data : 'all';
}

function parseFileClassFilter(value: string): BridgeFileClass | 'all' {
	if (value === 'all') {
		return 'all';
	}
	const parsed = bridgeFileClassSchema.safeParse(value);
	return parsed.success ? parsed.data : 'all';
}

export async function loadSelectedReviewItemContent(
	props: LoadSelectedReviewItemContentProps,
): Promise<BridgeContentResource | null> {
	if (props.selectedItemId === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem === undefined) {
		return null;
	}
	const contentHandle = preferredContentHandle(selectedItem);
	if (contentHandle === null) {
		return null;
	}
	return await loadContentHandle({ handle: contentHandle, props });
}

export async function loadSelectedReviewItemContentResources(
	props: LoadSelectedReviewItemContentProps,
): Promise<BridgeCodeViewContentResources | null> {
	if (props.selectedItemId === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem === undefined) {
		return null;
	}

	const baseHandle = selectedItem.contentRoles.base ?? null;
	const headHandle = selectedItem.contentRoles.head ?? null;
	if (selectedItem.itemKind === 'diff' && baseHandle !== null && headHandle !== null) {
		const [base, head] = await Promise.all([
			loadContentHandle({ handle: baseHandle, props }),
			loadContentHandle({ handle: headHandle, props }),
		]);
		return { base, head };
	}

	const diffHandle = selectedItem.contentRoles.diff ?? null;
	if (selectedItem.itemKind === 'diff' && diffHandle !== null) {
		return {
			diff: await loadContentHandle({ handle: diffHandle, props }),
		};
	}

	const contentHandle = preferredContentHandle(selectedItem);
	if (contentHandle === null) {
		return null;
	}

	const content = await loadContentHandle({ handle: contentHandle, props });
	return {
		[contentHandle.role]: content,
	};
}

interface LoadContentHandleProps {
	readonly handle: BridgeContentHandle;
	readonly props: LoadSelectedReviewItemContentProps;
}

async function loadContentHandle(
	loadContentHandleProps: LoadContentHandleProps,
): Promise<BridgeContentResource> {
	const props = loadContentHandleProps.props;
	const loadProps: LoadBridgeContentResourceProps = {
		handle: loadContentHandleProps.handle,
		traceContext: props.traceContext ?? null,
		sendTraceparentHeader: props.sendTraceparentHeader ?? false,
		...(props.signal === undefined ? {} : { signal: props.signal }),
		...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
		...(props.telemetryRecorder === undefined
			? {}
			: { telemetryRecorder: props.telemetryRecorder }),
	};
	return await loadBridgeContentResource(loadProps);
}

function preferredContentHandle(item: BridgeReviewItemDescriptor): BridgeContentHandle | null {
	return (
		item.contentRoles.head ??
		item.contentRoles.file ??
		item.contentRoles.diff ??
		item.contentRoles.base ??
		null
	);
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
