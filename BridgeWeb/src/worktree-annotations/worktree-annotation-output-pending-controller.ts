import { useCallback, useRef, useState } from 'react';

export interface WorktreeAnnotationOutputPendingLease {
	readonly release: () => void;
}

export interface WorktreeAnnotationOutputPendingController {
	readonly isPending: boolean;
	readonly tryAcquire: () => WorktreeAnnotationOutputPendingLease | null;
}

export function useWorktreeAnnotationOutputPendingController(): WorktreeAnnotationOutputPendingController {
	const activeLeaseRef = useRef<symbol | null>(null);
	const [isPending, setIsPending] = useState(false);
	const tryAcquire = useCallback((): WorktreeAnnotationOutputPendingLease | null => {
		if (activeLeaseRef.current !== null) return null;
		const leaseIdentity = Symbol('worktree-annotation-output-pending');
		activeLeaseRef.current = leaseIdentity;
		setIsPending(true);
		return {
			release: (): void => {
				if (activeLeaseRef.current !== leaseIdentity) return;
				activeLeaseRef.current = null;
				setIsPending(false);
			},
		};
	}, []);
	return { isPending, tryAcquire };
}
