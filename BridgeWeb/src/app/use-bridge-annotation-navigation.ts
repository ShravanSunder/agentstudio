import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { toast } from 'sonner';

import type {
	WorktreeAnnotationDestination,
	WorktreeAnnotationNavigationController,
	WorktreeAnnotationNavigationRequest,
	WorktreeAnnotationNavigationTarget,
} from '../worktree-annotations/worktree-annotation-navigation.js';

/** App owns only navigation identity; destination viewers own source resolution. */
export function useBridgeAnnotationNavigation(props: {
	readonly activeSurface: WorktreeAnnotationDestination;
	readonly activateDestination: (destination: WorktreeAnnotationDestination) => boolean;
}): WorktreeAnnotationNavigationController {
	const { activeSurface, activateDestination } = props;
	const [request, setRequest] = useState<WorktreeAnnotationNavigationRequest | null>(null);
	const requestRef = useRef(request);
	requestRef.current = request;
	const sequence = useRef(0);
	const open = useCallback(
		(target: WorktreeAnnotationNavigationTarget): void => {
			if (target.destination !== activeSurface && !activateDestination(target.destination)) return;
			sequence.current += 1;
			const next: WorktreeAnnotationNavigationRequest = {
				...target,
				requestId: sequence.current,
				phase: 'preparing',
			};
			requestRef.current = next;
			setRequest(next);
		},
		[activateDestination, activeSurface],
	);
	const finish = useCallback((requestId: number, error?: string): void => {
		if (requestRef.current?.requestId !== requestId) return;
		requestRef.current = null;
		setRequest(null);
		if (error !== undefined) toast.error(error);
	}, []);
	const admit = useCallback((requestId: number): void => {
		const current = requestRef.current;
		if (current?.requestId !== requestId || current.phase !== 'preparing') return;
		const next = { ...current, phase: 'ready' } satisfies WorktreeAnnotationNavigationRequest;
		requestRef.current = next;
		setRequest(next);
	}, []);
	useEffect((): void => {
		if (request !== null && request.destination !== activeSurface) finish(request.requestId);
	}, [finish, activeSurface, request]);
	return useMemo(
		() => ({ activeSurface: activeSurface, request, open, finish, admit }),
		[admit, finish, open, activeSurface, request],
	);
}
