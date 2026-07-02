import type { ReactElement, ReactNode } from 'react';

import { BridgeViewerContentHeader } from '../../app/bridge-viewer-content-header.js';
import { BridgeViewerRailToolbar } from '../../app/bridge-viewer-rail-toolbar.js';
import { BridgeViewerResizableRailLayout } from '../../app/bridge-viewer-resizable-rail-layout.js';
import { BridgeViewerRightRailShell } from '../../app/bridge-viewer-right-rail-shell.js';
import { Skeleton } from '../../components/ui/skeleton.js';

export function BridgeReviewEmptyShell(props: {
	readonly viewerHeaderControls?: ReactNode;
}): ReactElement {
	return (
		<BridgeReviewFallbackFrame
			title="Waiting for review metadata"
			viewerHeaderControls={props.viewerHeaderControls}
		>
			<section
				aria-label="Review summary"
				className="flex h-full min-h-[260px] items-center justify-center px-8 text-center"
				data-testid="bridge-review-empty-shell"
			>
				<div className="max-w-sm">
					<p className="text-sm font-medium text-[var(--bridge-text-primary)]">Bridge Review</p>
					<p className="mt-1 text-xs text-[var(--bridge-text-secondary)]">
						Waiting for review metadata
					</p>
				</div>
			</section>
		</BridgeReviewFallbackFrame>
	);
}

export function BridgeReviewProjectionPendingShell(props: {
	readonly viewerHeaderControls?: ReactNode;
}): ReactElement {
	return (
		<BridgeReviewFallbackFrame
			title="Projecting review"
			viewerHeaderControls={props.viewerHeaderControls}
		>
			<section
				aria-label="Review projection status"
				className="flex h-full min-h-[260px] items-center justify-center px-8"
				data-testid="bridge-review-projection-pending-shell"
			>
				<div className="flex w-72 flex-col gap-3 text-[var(--bridge-text-secondary)]">
					<p className="text-sm">Projecting review</p>
					<BridgeReviewFallbackSkeleton />
				</div>
			</section>
		</BridgeReviewFallbackFrame>
	);
}

export function BridgeReviewProjectionFailedShell(props: {
	readonly viewerHeaderControls?: ReactNode;
}): ReactElement {
	return (
		<BridgeReviewFallbackFrame
			title="Review projection unavailable"
			viewerHeaderControls={props.viewerHeaderControls}
		>
			<section
				aria-label="Review projection status"
				className="flex h-full min-h-[260px] items-center justify-center px-8 text-center text-[var(--bridge-text-secondary)]"
				data-testid="bridge-review-projection-failed-shell"
			>
				<div>
					<p className="text-sm text-[var(--bridge-text-primary)]">Review projection unavailable</p>
					<p className="mt-1 text-xs">The review metadata could not be projected.</p>
				</div>
			</section>
		</BridgeReviewFallbackFrame>
	);
}

export function BridgeReviewMetadataLoadingShell(props: {
	readonly viewerHeaderControls?: ReactNode;
}): ReactElement {
	return (
		<BridgeReviewFallbackFrame
			title="Loading review metadata"
			viewerHeaderControls={props.viewerHeaderControls}
		>
			<section
				aria-label="Review metadata status"
				className="flex h-full min-h-[260px] items-center justify-center px-8"
				data-testid="bridge-review-metadata-loading-shell"
			>
				<div className="flex w-72 flex-col gap-3 text-[var(--bridge-text-secondary)]">
					<p className="text-sm">Loading review metadata</p>
					<BridgeReviewFallbackSkeleton />
				</div>
			</section>
		</BridgeReviewFallbackFrame>
	);
}

export function BridgeReviewMetadataFailedShell(props: {
	readonly error: string | null;
	readonly viewerHeaderControls?: ReactNode;
}): ReactElement {
	return (
		<BridgeReviewFallbackFrame
			title="Review metadata unavailable"
			viewerHeaderControls={props.viewerHeaderControls}
		>
			<section
				aria-label="Review metadata status"
				className="flex h-full min-h-[260px] items-center justify-center px-8 text-center text-[var(--bridge-text-secondary)]"
				data-testid="bridge-review-metadata-failed-shell"
			>
				<div>
					<p className="text-sm text-[var(--bridge-text-primary)]">Review metadata unavailable</p>
					<p className="mt-1 text-xs">
						{props.error ?? 'The review metadata stream could not be loaded.'}
					</p>
				</div>
			</section>
		</BridgeReviewFallbackFrame>
	);
}

function BridgeReviewFallbackFrame(props: {
	readonly children: ReactNode;
	readonly title: string;
	readonly viewerHeaderControls?: ReactNode;
}): ReactElement {
	return (
		<main
			className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)]"
			data-testid="bridge-review-fallback-frame"
		>
			<BridgeViewerResizableRailLayout
				autosaveId="bridge-viewer-right-rail"
				content={
					<section className="grid h-full min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)] overflow-hidden">
						<BridgeViewerContentHeader
							controls={props.viewerHeaderControls}
							eyebrow="Review"
							title={props.title}
						/>
						<section
							className="min-h-0 min-w-0 bg-[var(--bridge-canvas-bg)]"
							data-testid="bridge-review-fallback-canvas"
						>
							{props.children}
						</section>
					</section>
				}
				contentTestId="bridge-review-content-panel"
				handleTestId="bridge-review-rail-resize-handle"
				rail={BridgeViewerRightRailShell({
					body: (
						<div className="flex flex-col gap-2">
							<Skeleton className="h-3 w-full bg-[var(--bridge-surface-raised-bg)]" />
							<Skeleton className="h-3 w-11/12 bg-[var(--bridge-surface-raised-bg)]" />
							<Skeleton className="h-3 w-4/5 bg-[var(--bridge-surface-raised-bg)]" />
						</div>
					),
					bodyClassName: 'min-h-0 flex-1 overflow-hidden overscroll-contain p-3',
					bodyTestId: 'bridge-review-rail-scroll',
					border: 'opaque',
					layout: 'stack',
					testId: 'bridge-review-sidebar',
					toolbar: BridgeViewerRailToolbar({
						leading: <Skeleton className="h-6 w-14 bg-[var(--bridge-surface-raised-bg)]" />,
						leadingTestId: 'bridge-review-rail-toolbar-leading',
						testId: 'bridge-review-rail-toolbar',
						trailing: (
							<>
								<Skeleton className="h-6 w-6 bg-[var(--bridge-surface-raised-bg)]" />
								<Skeleton className="h-6 w-6 bg-[var(--bridge-surface-raised-bg)]" />
							</>
						),
						trailingTestId: 'bridge-review-rail-toolbar-trailing',
					}),
				})}
				railTestId="bridge-review-resizable-rail"
			/>
		</main>
	);
}

function BridgeReviewFallbackSkeleton(): ReactElement {
	return (
		<div className="flex flex-col gap-2">
			<Skeleton className="h-3 w-full bg-[var(--bridge-surface-raised-bg)]" />
			<Skeleton className="h-3 w-11/12 bg-[var(--bridge-surface-raised-bg)]" />
			<Skeleton className="h-3 w-3/4 bg-[var(--bridge-surface-raised-bg)]" />
		</div>
	);
}
