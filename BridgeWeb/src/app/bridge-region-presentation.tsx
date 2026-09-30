import type { ReactElement, ReactNode } from 'react';

import { Alert, AlertAction, AlertDescription, AlertTitle } from '../components/ui/alert.js';
import { Skeleton } from '../components/ui/skeleton.js';
import { BridgePaneReloadControl, type BridgePaneReloadPort } from './bridge-pane-reload-port.js';
import type { BridgeRegionPresentationState } from './bridge-region-presentation-state.js';

export interface BridgeRegionPresentationProps {
	readonly paneReloadPort?: BridgePaneReloadPort;
	readonly keepContentMounted?: boolean;
	readonly children?: ReactNode;
	readonly emptyCopy?: {
		readonly noSelection: string;
		readonly certified: string;
		readonly noSource?: string;
	};
	readonly region: string;
	readonly retry?: ReactNode;
	readonly heldAction?: ReactNode;
	readonly shape: 'tree' | 'code' | 'diff' | 'comments' | 'markdown';
	readonly state: BridgeRegionPresentationState;
}

/** One non-content renderer; callers supply admitted content and command-backed actions. */
export function BridgeRegionPresentation(props: BridgeRegionPresentationProps): ReactElement {
	const { state } = props;
	const retryControl =
		state.kind === 'failed' &&
		state.failure.scope === 'pane' &&
		props.paneReloadPort !== undefined ? (
			<BridgePaneReloadControl port={props.paneReloadPort} />
		) : (
			props.retry
		);
	const showsContent =
		state.kind === 'content' ||
		state.kind === 'updating' ||
		(state.kind === 'failed' && state.retainsContent);
	return (
		<div
			className="relative flex h-full min-h-0 min-w-0 flex-col"
			data-bridge-region={props.region}
			data-presentation-state={state.kind}
			data-empty-reason={state.kind === 'empty' ? state.reason : undefined}
			data-content-current={state.kind === 'content' ? 'true' : 'false'}
		>
			{state.kind === 'updating' ? (
				<div
					className="flex shrink-0 items-center justify-between gap-2 px-2 py-1 text-xs text-muted-foreground"
					role="status"
				>
					Updating{state.rest === 'held' ? props.heldAction : null}
				</div>
			) : null}
			{state.kind === 'failed' ? (
				<Alert layout="banner" variant="warning">
					<AlertTitle>{state.failure.message}</AlertTitle>
					<AlertDescription>
						{state.failure.kind === 'permanent'
							? state.failure.correctiveAction
							: state.retainsContent
								? 'Last good content is shown. It is not current.'
								: null}
					</AlertDescription>
					{state.failure.kind === 'retryable' && retryControl !== undefined ? (
						<AlertAction>{retryControl}</AlertAction>
					) : null}
				</Alert>
			) : null}
			{state.kind === 'loading' ? (
				<div
					className="flex min-h-0 flex-1 flex-col gap-2 overflow-hidden p-3"
					aria-label="Loading"
					role="status"
					data-skeleton-shape={props.shape}
				>
					{[0, 1, 2, 3, 4, 5].map((rowIndex) => (
						<Skeleton
							key={rowIndex}
							className={
								props.shape === 'comments'
									? 'h-16 w-full'
									: rowIndex % 3 === 1
										? 'h-3 w-2/3'
										: 'h-3 w-full'
							}
						/>
					))}
				</div>
			) : state.kind === 'empty' ? (
				<p className="px-3 py-2 text-sm text-muted-foreground">
					{state.reason === 'noSource'
						? (props.emptyCopy?.noSource ?? 'This pane has no worktree files.')
						: state.reason === 'noSelection'
							? (props.emptyCopy?.noSelection ?? 'Nothing selected')
							: (props.emptyCopy?.certified ?? 'Nothing to show')}
				</p>
			) : null}
			{showsContent || props.keepContentMounted ? (
				<div
					className={
						showsContent
							? 'min-h-0 min-w-0 flex-1'
							: 'pointer-events-none invisible absolute inset-0'
					}
					aria-hidden={!showsContent}
					inert={!showsContent}
				>
					{props.children}
				</div>
			) : null}
		</div>
	);
}
