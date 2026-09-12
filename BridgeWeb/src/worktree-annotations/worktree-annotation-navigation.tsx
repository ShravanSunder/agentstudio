import { createContext, useContext, type ReactElement, type ReactNode } from 'react';

import type { WorktreeAnnotationThreadProjection } from './worktree-annotation-surface-client.js';

export type WorktreeAnnotationDestination = 'file' | 'review';
export interface WorktreeAnnotationNavigationTarget {
	readonly destination: WorktreeAnnotationDestination;
	readonly sessionId: string;
	readonly threadId: string;
}
export interface WorktreeAnnotationNavigationRequest extends WorktreeAnnotationNavigationTarget {
	readonly requestId: number;
	readonly phase: 'preparing' | 'ready';
}
export interface WorktreeAnnotationNavigationController {
	readonly activeSurface: WorktreeAnnotationDestination;
	readonly request: WorktreeAnnotationNavigationRequest | null;
	readonly open: (target: WorktreeAnnotationNavigationTarget) => void;
	readonly finish: (requestId: number, error?: string) => void;
	readonly admit: (requestId: number) => void;
}
const navigationContext = createContext<WorktreeAnnotationNavigationController | null>(null);
export function WorktreeAnnotationNavigationProvider(props: {
	readonly children: ReactNode;
	readonly controller: WorktreeAnnotationNavigationController;
}): ReactElement {
	return (
		<navigationContext.Provider value={props.controller}>
			{props.children}
		</navigationContext.Provider>
	);
}
export function useWorktreeAnnotationNavigation(): WorktreeAnnotationNavigationController | null {
	return useContext(navigationContext);
}

export function worktreeAnnotationDestination(
	thread: WorktreeAnnotationThreadProjection,
	current: WorktreeAnnotationDestination,
): WorktreeAnnotationDestination | null {
	if (thread.context.scope !== 'located') return null;
	if (current === 'file' && thread.context.sourceRole === 'review_base') return 'review';
	if (thread.context.placement === 'exact' || thread.context.placement === 'relocated')
		return current;
	// A source role can identify the other viewer, but that viewer must resolve its own location.
	if (
		current === 'file' &&
		(thread.context.sourceRole === 'review_base' || thread.context.sourceRole === 'review_head')
	)
		return 'review';
	if (current === 'review' && thread.context.sourceRole === 'file') return 'file';
	return null;
}

export function worktreeAnnotationOpenLabel(
	current: WorktreeAnnotationDestination,
	destination: WorktreeAnnotationDestination,
): string {
	return current === destination
		? 'Open'
		: destination === 'file'
			? 'Open in Files'
			: 'Open in Review';
}
