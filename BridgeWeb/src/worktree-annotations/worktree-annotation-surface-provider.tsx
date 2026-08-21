import {
	createContext,
	useCallback,
	useContext,
	useEffect,
	useLayoutEffect,
	useMemo,
	useRef,
	useState,
	useSyncExternalStore,
	type ReactElement,
	type ReactNode,
} from 'react';

import type { BridgeMarkdownRenderWorkerClient } from '../app/markdown/worker/bridge-markdown-render-worker-client.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	useWorktreeAnnotationInteraction,
	WorktreeAnnotationInteractionProvider,
} from './worktree-annotation-interaction.js';
import { recordWorktreeAnnotationLifecycleTelemetry } from './worktree-annotation-lifecycle-telemetry.js';
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
const worktreeAnnotationEditSurfaceRegistryContext =
	createContext<WorktreeAnnotationEditSurfaceRegistry | null>(null);

export interface WorktreeAnnotationSessionCapabilities {
	readonly canCreateAnnotations: boolean;
	readonly canEditMessages: boolean;
	readonly canFinish: boolean;
	readonly canOutput: boolean;
	readonly canReopen: boolean;
	readonly canReply: boolean;
	readonly canSetThreadResolution: boolean;
}

interface WorktreeAnnotationEditSurfaceRegistry {
	readonly activeEditTokens: ReadonlySet<string>;
	readonly activeNewMessageEditTokens: ReadonlySet<string>;
	readonly register: (editToken: string, kind: WorktreeAnnotationEditSurfaceKind) => () => void;
	readonly releaseWhenInactive: (editToken: string, release: () => Promise<void>) => Promise<void>;
}

type WorktreeAnnotationEditSurfaceKind = 'message' | 'newMessage';

interface WorktreeAnnotationEditSurfaceCounts {
	readonly message: number;
	readonly newMessage: number;
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
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
}

export function WorktreeAnnotationSurfaceProvider(
	props: WorktreeAnnotationSurfaceProviderProps,
): ReactElement {
	const annotationClient = useMemo(
		() => createWorktreeAnnotationSurfaceClient(props.surfaceClient, props.telemetryRecorder),
		[props.surfaceClient, props.telemetryRecorder],
	);
	const projection = useSyncExternalStore(
		annotationClient.subscribe,
		annotationClient.getSnapshot,
		annotationClient.getServerSnapshot,
	);
	useEffect((): (() => void) | undefined => {
		if (projection.operationCorrelationId === null || projection.revision === null)
			return undefined;
		const operationCorrelationId = projection.operationCorrelationId;
		const sourceGeneration = projection.sourceGeneration;
		recordWorktreeAnnotationLifecycleTelemetry({
			operationCorrelationId,
			phase: 'annotation_paint_started',
			recorder: props.telemetryRecorder,
			result: 'started',
			sourceGeneration,
			transport: 'local',
			viewer: props.surfaceClient.surface === 'fileView' ? 'file' : 'review',
		});
		let terminalRecorded = false;
		const frame = requestAnimationFrame((): void => {
			terminalRecorded = true;
			recordWorktreeAnnotationLifecycleTelemetry({
				operationCorrelationId,
				phase: 'annotation_paint_terminal',
				recorder: props.telemetryRecorder,
				result: 'success',
				sourceGeneration,
				transport: 'local',
				viewer: props.surfaceClient.surface === 'fileView' ? 'file' : 'review',
			});
		});
		return (): void => {
			cancelAnimationFrame(frame);
			if (terminalRecorded) return;
			recordWorktreeAnnotationLifecycleTelemetry({
				operationCorrelationId,
				phase: 'annotation_paint_terminal',
				recorder: props.telemetryRecorder,
				result: 'cancelled',
				sourceGeneration,
				transport: 'local',
				viewer: props.surfaceClient.surface === 'fileView' ? 'file' : 'review',
			});
		};
	}, [
		projection.operationCorrelationId,
		projection.revision,
		projection.sourceGeneration,
		props.surfaceClient.surface,
		props.telemetryRecorder,
	]);
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
	const [editSurfaceCountsByEditToken, setEditSurfaceCountsByEditToken] = useState<
		ReadonlyMap<string, WorktreeAnnotationEditSurfaceCounts>
	>(() => new Map<string, WorktreeAnnotationEditSurfaceCounts>());
	const editSurfaceCountsByEditTokenRef = useRef<
		ReadonlyMap<string, WorktreeAnnotationEditSurfaceCounts>
	>(new Map());
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
	useEffect((): (() => void) | undefined => {
		if (activeSessionId === null) return undefined;
		return annotationClient.acquireSession(activeSessionId);
	}, [activeSessionId, annotationClient]);
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
	const registerEditSurfaceToken = useCallback(
		(editToken: string, kind: WorktreeAnnotationEditSurfaceKind): (() => void) => {
			const registeredCounts = new Map(editSurfaceCountsByEditTokenRef.current);
			const currentCounts = registeredCounts.get(editToken) ?? { message: 0, newMessage: 0 };
			registeredCounts.set(editToken, {
				...currentCounts,
				[kind]: currentCounts[kind] + 1,
			});
			editSurfaceCountsByEditTokenRef.current = registeredCounts;
			setEditSurfaceCountsByEditToken(registeredCounts);
			return (): void => {
				const latestCountsByToken = editSurfaceCountsByEditTokenRef.current;
				const latestCounts = latestCountsByToken.get(editToken);
				if (latestCounts === undefined || latestCounts[kind] === 0) return;
				const unregisteredCounts = new Map(latestCountsByToken);
				const nextCounts = { ...latestCounts, [kind]: latestCounts[kind] - 1 };
				if (nextCounts.message === 0 && nextCounts.newMessage === 0) {
					unregisteredCounts.delete(editToken);
				} else {
					unregisteredCounts.set(editToken, nextCounts);
				}
				editSurfaceCountsByEditTokenRef.current = unregisteredCounts;
				setEditSurfaceCountsByEditToken(unregisteredCounts);
			};
		},
		[],
	);
	const releaseEditWhenInactive = useCallback(
		(editToken: string, release: () => Promise<void>): Promise<void> =>
			new Promise<void>((resolve, reject): void => {
				queueMicrotask((): void => {
					if (editSurfaceCountsByEditTokenRef.current.has(editToken)) {
						resolve();
						return;
					}
					void release().then(resolve, reject);
				});
			}),
		[],
	);
	const activeEditTokens = useMemo<ReadonlySet<string>>(
		() => new Set(editSurfaceCountsByEditToken.keys()),
		[editSurfaceCountsByEditToken],
	);
	const activeNewMessageEditTokens = useMemo<ReadonlySet<string>>(
		() =>
			new Set(
				[...editSurfaceCountsByEditToken]
					.filter(([, counts]): boolean => counts.newMessage > 0)
					.map(([editToken]): string => editToken),
			),
		[editSurfaceCountsByEditToken],
	);
	const editSurfaceRegistry = useMemo<WorktreeAnnotationEditSurfaceRegistry>(
		() => ({
			activeEditTokens,
			activeNewMessageEditTokens,
			register: registerEditSurfaceToken,
			releaseWhenInactive: releaseEditWhenInactive,
		}),
		[
			activeEditTokens,
			activeNewMessageEditTokens,
			registerEditSurfaceToken,
			releaseEditWhenInactive,
		],
	);
	useEffect((): (() => void) => {
		void annotationClient.execute({ kind: 'session.discover' }).catch((): void => {});
		return (): void => annotationClient.dispose();
	}, [annotationClient]);
	return (
		<worktreeAnnotationMarkdownClientContext.Provider value={props.markdownWorkerClient ?? null}>
			<worktreeAnnotationSurfaceClientContext.Provider value={annotationClient}>
				<WorktreeAnnotationInteractionProvider>
					<worktreeAnnotationEditSurfaceRegistryContext.Provider value={editSurfaceRegistry}>
						<worktreeAnnotationSessionSelectionContext.Provider value={sessionSelection}>
							{props.children}
							<WorktreeAnnotationThreadExpansionReconciler />
						</worktreeAnnotationSessionSelectionContext.Provider>
					</worktreeAnnotationEditSurfaceRegistryContext.Provider>
				</WorktreeAnnotationInteractionProvider>
			</worktreeAnnotationSurfaceClientContext.Provider>
		</worktreeAnnotationMarkdownClientContext.Provider>
	);
}

function WorktreeAnnotationThreadExpansionReconciler(): null {
	const interaction = useWorktreeAnnotationInteraction();
	const projection = useWorktreeAnnotationProjection();
	useEffect((): void => {
		const expansion = interaction.threadExpansion;
		if (expansion.kind !== 'open') return;
		if (
			projection.threads.some((thread): boolean => thread.context.threadId === expansion.threadId)
		)
			return;
		const focusTarget = interaction.resolveThreadFocus();
		void interaction.collapseThread().then((): void => focusTarget?.focus());
	}, [interaction, projection.threads]);
	return null;
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

export { useWorktreeAnnotationInteraction };

export function useWorktreeAnnotationActiveEditTokens(): ReadonlySet<string> {
	return (
		useContext(worktreeAnnotationEditSurfaceRegistryContext)?.activeEditTokens ?? emptyEditTokens
	);
}

export function useWorktreeAnnotationActiveNewMessageEditTokens(): ReadonlySet<string> {
	return (
		useContext(worktreeAnnotationEditSurfaceRegistryContext)?.activeNewMessageEditTokens ??
		emptyEditTokens
	);
}

export function useWorktreeAnnotationEditSurfaceToken(
	editToken: string | null,
	kind: WorktreeAnnotationEditSurfaceKind = 'newMessage',
): void {
	const editSurfaceRegistry = useContext(worktreeAnnotationEditSurfaceRegistryContext);
	const register = editSurfaceRegistry?.register;
	useLayoutEffect((): (() => void) | undefined => {
		if (register === undefined || editToken === null) return undefined;
		return register(editToken, kind);
	}, [editToken, kind, register]);
}

export function useWorktreeAnnotationDeferredEditRelease(): WorktreeAnnotationEditSurfaceRegistry['releaseWhenInactive'] {
	return (
		useContext(worktreeAnnotationEditSurfaceRegistryContext)?.releaseWhenInactive ??
		releaseComposerImmediately
	);
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

function releaseComposerImmediately(
	_editToken: string,
	release: () => Promise<void>,
): Promise<void> {
	return release();
}
