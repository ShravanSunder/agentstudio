import {
	projectBridgeRegionPresentation,
	type BridgeRegionPresentationState,
	type BridgeRegionSurfaceStatus,
} from '../bridge-region-presentation-state.js';
import type { BridgeMarkdownPresentationState } from './use-bridge-markdown-presentation.js';

export function bridgeMarkdownRegionPresentation(props: {
	readonly presentation: BridgeMarkdownPresentationState;
	readonly displayed?: Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }>;
	readonly isActive: boolean;
	readonly held?: boolean;
	readonly surface?: BridgeRegionSurfaceStatus | undefined;
}): BridgeRegionPresentationState {
	const state = props.presentation;
	const displayed = props.displayed ?? (state.status === 'ready' ? state : null);
	const demandedIdentity =
		state.status === 'idle'
			? null
			: state.status === 'ready'
				? markdownIdentity(state)
				: state.sourcePath;
	const surface: BridgeRegionSurfaceStatus =
		props.surface?.kind === 'failed'
			? props.surface
			: state.status === 'ready' && state.refresh.kind === 'failed'
				? {
						kind: 'failed',
						failure: {
							kind: 'retryable',
							scope: 'read',
							message: 'Markdown refresh failed. Showing the previous document.',
						},
					}
				: state.status === 'ready' && (state.refresh.kind === 'pending' || props.held)
					? {
							kind: 'updating',
							...(props.held ? { rest: 'held' } : !props.isActive ? { rest: 'hidden' } : {}),
						}
					: (props.surface ?? { kind: 'current' });
	return projectBridgeRegionPresentation({
		demandedIdentity,
		read:
			state.status === 'failed'
				? {
						kind: 'failed',
						retainedIdentity: displayed === null ? null : markdownIdentity(displayed),
						failure: {
							kind: 'retryable',
							scope: 'read',
							message: 'Markdown could not be rendered.',
						},
					}
				: displayed === null
					? { kind: 'loading' }
					: { kind: 'complete', identity: markdownIdentity(displayed), hasContent: true },
		surface,
	});
}

function markdownIdentity(
	state: Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }>,
): string {
	return `${state.identity.sourceIdentity.fileId}:${state.sourcePath}`;
}
