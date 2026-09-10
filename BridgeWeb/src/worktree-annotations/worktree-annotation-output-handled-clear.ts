import type {
	WorktreeAnnotationCommandOutcome,
	WorktreeAnnotationProjectionSnapshot,
	WorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-client.js';

export async function clearWorktreeAnnotationOutputHandled(props: {
	readonly attemptId: string;
	readonly client: WorktreeAnnotationSurfaceClient;
	readonly sessionId: string;
}): Promise<WorktreeAnnotationCommandOutcome> {
	const expectedSessionRevision = requireSessionRevision(
		props.client.getSnapshot(),
		props.sessionId,
	);
	const firstOutcome = await props.client.execute({
		attemptId: props.attemptId,
		expectedSessionRevision,
		kind: 'output.handled.clear',
	});
	if (firstOutcome.status.kind !== 'failed' || firstOutcome.status.code !== 'conflict') {
		return firstOutcome;
	}
	const convergence = await props.client.waitForSnapshot((snapshot) => {
		const sessionRevision = sessionRevisionIn(snapshot, props.sessionId);
		if (sessionRevision === null) return { kind: 'sessionUnavailable' } as const;
		return sessionRevision > expectedSessionRevision
			? ({ kind: 'revisionAdvanced', sessionRevision } as const)
			: null;
	});
	if (convergence.kind === 'sessionUnavailable') {
		throw new Error('The review session is no longer available.');
	}
	return await props.client.execute({
		attemptId: props.attemptId,
		expectedSessionRevision: convergence.sessionRevision,
		kind: 'output.handled.clear',
	});
}

function requireSessionRevision(
	snapshot: WorktreeAnnotationProjectionSnapshot,
	sessionId: string,
): number {
	const sessionRevision = sessionRevisionIn(snapshot, sessionId);
	if (sessionRevision === null) throw new Error('The review session is no longer available.');
	return sessionRevision;
}

function sessionRevisionIn(
	snapshot: WorktreeAnnotationProjectionSnapshot,
	sessionId: string,
): number | null {
	return (
		snapshot.sessions.find((session) => session.sessionId === sessionId)?.semanticRevision ?? null
	);
}
