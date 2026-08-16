import {
	createContext,
	useCallback,
	useContext,
	useEffect,
	useLayoutEffect,
	useMemo,
	useState,
	useSyncExternalStore,
	type ReactElement,
	type ReactNode,
} from 'react';

import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeMarkdownRenderWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import {
	createWorktreeAnnotationSurfaceClient,
	emptyWorktreeAnnotationProjectionSnapshot,
	type WorktreeAnnotationProjectionSnapshot,
	type WorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-client.js';

const worktreeAnnotationSurfaceClientContext =
	createContext<WorktreeAnnotationSurfaceClient | null>(null);
const worktreeAnnotationMarkdownClientContext =
	createContext<BridgeMarkdownRenderWorkerClient | null>(null);
const worktreeAnnotationSessionSelectionContext =
	createContext<WorktreeAnnotationSessionSelection | null>(null);
const worktreeAnnotationComposerRegistryContext =
	createContext<WorktreeAnnotationComposerRegistry | null>(null);

export interface WorktreeAnnotationSessionCapabilities {
	readonly canCreateAnnotations: boolean;
	readonly canEditMessages: boolean;
	readonly canFinish: boolean;
	readonly canOutput: boolean;
	readonly canReopen: boolean;
	readonly canReply: boolean;
	readonly canSetThreadResolution: boolean;
}

interface WorktreeAnnotationComposerRegistry {
	readonly activeEditTokens: ReadonlySet<string>;
	readonly register: (editToken: string) => () => void;
}

export interface WorktreeAnnotationSessionSelection {
	readonly activeSessionId: string | null;
	readonly capabilities: WorktreeAnnotationSessionCapabilities;
	readonly requiresExplicitSelection: boolean;
	readonly rootAdmission:
		| { readonly kind: 'implicitOrSingle' }
		| { readonly kind: 'selected'; readonly sessionId: string };
	readonly selectSession: (sessionId: string) => void;
	readonly sessions: WorktreeAnnotationProjectionSnapshot['sessions'];
}

export interface WorktreeAnnotationSurfaceProviderProps {
	readonly children: ReactNode;
	readonly markdownWorkerClient?: BridgeMarkdownRenderWorkerClient | null | undefined;
	readonly surfaceClient: BridgePaneSurfaceClient;
}

export function WorktreeAnnotationSurfaceProvider(
	props: WorktreeAnnotationSurfaceProviderProps,
): ReactElement {
	const annotationClient = useMemo(
		() => createWorktreeAnnotationSurfaceClient(props.surfaceClient),
		[props.surfaceClient],
	);
	const projection = useSyncExternalStore(
		annotationClient.subscribe,
		annotationClient.getSnapshot,
		annotationClient.getServerSnapshot,
	);
	const applicableLivingSessionIds = useMemo(
		() =>
			projection.sessions
				.filter(
					(session): boolean =>
						session.lifecycle === 'living' && session.sourceRelationship === 'applicable',
				)
				.map((session) => session.sessionId),
		[projection.sessions],
	);
	const [explicitSessionId, setExplicitSessionId] = useState<string | null>(null);
	const [activeComposerEditTokens, setActiveComposerEditTokens] = useState<ReadonlySet<string>>(
		() => new Set<string>(),
	);
	useEffect((): void => {
		if (explicitSessionId === null && applicableLivingSessionIds.length === 1) {
			setExplicitSessionId(applicableLivingSessionIds[0] ?? null);
		}
	}, [applicableLivingSessionIds, explicitSessionId]);
	const selectSession = useCallback((sessionId: string): void => {
		setExplicitSessionId(sessionId);
	}, []);
	const explicitSessionStillExists =
		explicitSessionId !== null &&
		projection.sessions.some((session): boolean => session.sessionId === explicitSessionId);
	const activeSessionId = explicitSessionStillExists
		? explicitSessionId
		: applicableLivingSessionIds.length === 1
			? (applicableLivingSessionIds[0] ?? null)
			: null;
	const activeSession =
		projection.sessions.find((session): boolean => session.sessionId === activeSessionId) ?? null;
	const recoveryAllowsMutations = projection.recoveryStatus === 'available';
	const canMutateActiveSession =
		recoveryAllowsMutations &&
		activeSession?.lifecycle === 'living' &&
		activeSession.sourceRelationship === 'applicable';
	const requiresExplicitSelection =
		activeSessionId === null && applicableLivingSessionIds.length > 1;
	const capabilities = useMemo<WorktreeAnnotationSessionCapabilities>(
		() => ({
			canCreateAnnotations:
				recoveryAllowsMutations &&
				!requiresExplicitSelection &&
				(activeSession === null ? projection.sessions.length === 0 : canMutateActiveSession),
			canEditMessages: canMutateActiveSession,
			canFinish: recoveryAllowsMutations && activeSession?.lifecycle === 'living',
			canOutput: recoveryAllowsMutations && activeSession !== null,
			canReopen: recoveryAllowsMutations && activeSession?.lifecycle === 'completed',
			canReply: canMutateActiveSession,
			canSetThreadResolution: canMutateActiveSession,
		}),
		[
			activeSession,
			canMutateActiveSession,
			projection.sessions.length,
			recoveryAllowsMutations,
			requiresExplicitSelection,
		],
	);
	const sessionSelection = useMemo<WorktreeAnnotationSessionSelection>(
		() => ({
			activeSessionId,
			capabilities,
			requiresExplicitSelection,
			rootAdmission:
				activeSessionId === null
					? { kind: 'implicitOrSingle' }
					: { kind: 'selected', sessionId: activeSessionId },
			selectSession,
			sessions: projection.sessions,
		}),
		[activeSessionId, capabilities, projection.sessions, requiresExplicitSelection, selectSession],
	);
	const registerComposerEditToken = useCallback((editToken: string): (() => void) => {
		setActiveComposerEditTokens((currentTokens) => {
			if (currentTokens.has(editToken)) return currentTokens;
			return new Set([...currentTokens, editToken]);
		});
		return (): void => {
			setActiveComposerEditTokens((currentTokens) => {
				if (!currentTokens.has(editToken)) return currentTokens;
				const nextTokens = new Set(currentTokens);
				nextTokens.delete(editToken);
				return nextTokens;
			});
		};
	}, []);
	const composerRegistry = useMemo<WorktreeAnnotationComposerRegistry>(
		() => ({
			activeEditTokens: activeComposerEditTokens,
			register: registerComposerEditToken,
		}),
		[activeComposerEditTokens, registerComposerEditToken],
	);
	useEffect((): (() => void) => {
		void annotationClient.execute({ kind: 'session.discover' }).catch((): void => {});
		return (): void => annotationClient.dispose();
	}, [annotationClient]);
	return (
		<worktreeAnnotationMarkdownClientContext.Provider value={props.markdownWorkerClient ?? null}>
			<worktreeAnnotationSurfaceClientContext.Provider value={annotationClient}>
				<worktreeAnnotationComposerRegistryContext.Provider value={composerRegistry}>
					<worktreeAnnotationSessionSelectionContext.Provider value={sessionSelection}>
						{props.children}
					</worktreeAnnotationSessionSelectionContext.Provider>
				</worktreeAnnotationComposerRegistryContext.Provider>
			</worktreeAnnotationSurfaceClientContext.Provider>
		</worktreeAnnotationMarkdownClientContext.Provider>
	);
}

export function useWorktreeAnnotationMarkdownClient(): BridgeMarkdownRenderWorkerClient | null {
	return useContext(worktreeAnnotationMarkdownClientContext);
}

export function useWorktreeAnnotationSurfaceClient(): WorktreeAnnotationSurfaceClient {
	const annotationClient = useContext(worktreeAnnotationSurfaceClientContext);
	if (annotationClient === null) {
		throw new Error('Worktree annotations require a pane-owned surface provider.');
	}
	return annotationClient;
}

export function useWorktreeAnnotationSessionSelection(): WorktreeAnnotationSessionSelection {
	const selection = useContext(worktreeAnnotationSessionSelectionContext);
	if (selection === null) {
		throw new Error('Worktree annotation session selection requires a surface provider.');
	}
	return selection;
}

export function useWorktreeAnnotationActiveComposerEditTokens(): ReadonlySet<string> {
	return useContext(worktreeAnnotationComposerRegistryContext)?.activeEditTokens ?? emptyEditTokens;
}

export function useWorktreeAnnotationComposerEditToken(editToken: string): void {
	const composerRegistry = useContext(worktreeAnnotationComposerRegistryContext);
	const register = composerRegistry?.register;
	useLayoutEffect((): (() => void) | undefined => {
		if (register === undefined) return undefined;
		return register(editToken);
	}, [editToken, register]);
}

export function useWorktreeAnnotationProjection(): WorktreeAnnotationProjectionSnapshot {
	const annotationClient = useContext(worktreeAnnotationSurfaceClientContext);
	return useSyncExternalStore(
		annotationClient?.subscribe ?? noAnnotationProjectionSubscription,
		annotationClient?.getSnapshot ?? emptyAnnotationProjectionSnapshot,
		annotationClient?.getServerSnapshot ?? emptyAnnotationProjectionSnapshot,
	);
}

export function useWorktreeAnnotationSessionDemand(sessionId: string | null): void {
	const annotationClient = useContext(worktreeAnnotationSurfaceClientContext);
	useEffect((): (() => void) | undefined => {
		if (annotationClient === null || sessionId === null) return undefined;
		return annotationClient.acquireSession(sessionId);
	}, [annotationClient, sessionId]);
}

function noAnnotationProjectionSubscription(): () => void {
	return (): void => {};
}

function emptyAnnotationProjectionSnapshot(): WorktreeAnnotationProjectionSnapshot {
	return emptyWorktreeAnnotationProjectionSnapshot;
}

const emptyEditTokens: ReadonlySet<string> = new Set<string>();
