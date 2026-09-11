import { useEffect, useMemo, useRef } from 'react';

import {
	useWorktreeAnnotationNavigation,
	type WorktreeAnnotationDestination,
	type WorktreeAnnotationNavigationRequest,
} from './worktree-annotation-navigation.js';
import type { WorktreeAnnotationThreadProjection } from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationPrepareActiveEditorsForInstallation,
	useWorktreeAnnotationSessionSelection,
} from './worktree-annotation-surface-provider.js';

export interface WorktreeAnnotationResolvedNavigation {
	readonly request: WorktreeAnnotationNavigationRequest;
	readonly thread: WorktreeAnnotationThreadProjection;
}

/** Coordinates belong to the destination projection, never to the initiating drawer. */
export function useWorktreeAnnotationNavigationTarget(
	surface: WorktreeAnnotationDestination,
	isActive: boolean,
): WorktreeAnnotationResolvedNavigation | null {
	const navigation = useWorktreeAnnotationNavigation();
	const projection = useWorktreeAnnotationProjection();
	const selection = useWorktreeAnnotationSessionSelection();
	const request =
		isActive && navigation?.request?.destination === surface ? navigation.request : null;
	const prepareEditors = useWorktreeAnnotationPrepareActiveEditorsForInstallation();
	const interaction = useWorktreeAnnotationInteraction();
	const preparationRef = useRef({
		prepareEditors,
		leaveThread: interaction.leaveThread,
		navigation,
	});
	preparationRef.current = { prepareEditors, leaveThread: interaction.leaveThread, navigation };
	const requestId = request?.requestId;
	const requestPhase = request?.phase;
	useEffect((): (() => void) | undefined => {
		if (requestId === undefined || requestPhase !== 'preparing') return undefined;
		let current = true;
		void (async (): Promise<void> => {
			if (!(await preparationRef.current.prepareEditors())) {
				if (current)
					preparationRef.current.navigation?.finish(
						requestId,
						'Finish or cancel the destination draft before opening another annotation.',
					);
				return;
			}
			if (!current) return;
			await preparationRef.current.leaveThread();
			if (current) preparationRef.current.navigation?.admit(requestId);
		})().catch((): void => {
			if (current)
				preparationRef.current.navigation?.finish(
					requestId,
					'The destination draft could not be preserved.',
				);
		});
		return (): void => {
			current = false;
		};
	}, [requestId, requestPhase]);
	// The provider acquires content after the destination catalog admits the selected session.
	useEffect((): void => {
		if (request !== null && selection.activeSessionId !== request.sessionId)
			selection.selectSession(request.sessionId);
	}, [request, selection]);
	const thread =
		request === null
			? undefined
			: projection.threads.find(
					(candidate): boolean =>
						candidate.context.threadId === request.threadId &&
						candidate.messages.some((message): boolean => message.sessionId === request.sessionId),
				);
	const ready =
		projection.readStatus.kind === 'ready' && selection.activeSessionId === request?.sessionId;
	const located =
		thread !== undefined &&
		thread.context.scope === 'located' &&
		!(surface === 'file' && thread.context.sourceRole === 'review_base') &&
		(thread.context.placement === 'exact' || thread.context.placement === 'relocated') &&
		thread.context.path !== null &&
		thread.context.startLine !== null &&
		thread.context.endLine !== null;
	useEffect((): void => {
		if (request === null || navigation === null) return;
		const sessionMissing =
			projection.readStatus.kind === 'ready' &&
			!projection.sessions.some((session): boolean => session.sessionId === request.sessionId);
		if (
			projection.readStatus.kind === 'unavailable' ||
			(request.phase === 'ready' &&
				(sessionMissing || (ready && (!located || thread === undefined))))
		) {
			navigation.finish(
				request.requestId,
				`This comment cannot be located in ${surface === 'file' ? 'Files' : 'the current Review'}.`,
			);
		}
	}, [
		located,
		navigation,
		projection.sessions,
		projection.readStatus.kind,
		ready,
		request,
		surface,
		thread,
	]);
	return useMemo(
		() =>
			request !== null && request.phase === 'ready' && ready && located && thread !== undefined
				? { request, thread }
				: null,
		[located, ready, request, thread],
	);
}
