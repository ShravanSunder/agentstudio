import {
	createContext,
	useCallback,
	useContext,
	useMemo,
	useRef,
	useState,
	useEffect,
	type ReactElement,
	type ReactNode,
} from 'react';

import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import { createWorktreeAnnotationEditToken } from './worktree-annotation-edit-token.js';
import type { WorktreeAnnotationShareScope } from './worktree-annotation-share-mode.js';

type WorktreeAnnotationRootCreateOperation = Extract<
	BridgeProductWorktreeAnnotationOperation,
	{ readonly kind: 'root.create' }
>;

type WorktreeAnnotationLocatedOrigin = Extract<
	WorktreeAnnotationRootCreateOperation['origin'],
	{ readonly kind: 'located' }
>;

export type WorktreeAnnotationEditorState =
	| { readonly editToken: string; readonly kind: 'message'; readonly messageId: string }
	| { readonly committed: boolean; readonly editToken: string; readonly kind: 'reply' };

export interface WorktreeAnnotationRange {
	readonly end: number;
	readonly endSide?: 'additions' | 'deletions';
	readonly side?: 'additions' | 'deletions';
	readonly start: number;
}

export type WorktreeAnnotationPierreRangePresentation =
	| { readonly kind: 'none' }
	| { readonly itemId: string; readonly kind: 'pending'; readonly range: WorktreeAnnotationRange }
	| {
			readonly itemId: string;
			readonly kind: 'savedThread';
			readonly range: WorktreeAnnotationRange;
			readonly threadId: string;
	  };

export type WorktreeAnnotationThreadExpansion =
	| { readonly kind: 'closed' }
	| {
			readonly editor: WorktreeAnnotationEditorState | null;
			readonly invoker: HTMLElement;
			readonly kind: 'open';
			readonly returnFocusPoint: { readonly x: number; readonly y: number };
			readonly threadId: string;
	  };

export type WorktreeAnnotationShareMode =
	| { readonly kind: 'closed' }
	| { readonly kind: 'open'; readonly scope: WorktreeAnnotationShareScope };

export interface WorktreeAnnotationSavedRangeIdentity {
	readonly itemId: string;
	readonly range: WorktreeAnnotationRange;
	readonly threadId: string;
}

export interface WorktreeAnnotationPendingRootComposer {
	readonly committed: boolean;
	readonly editToken: string;
	readonly hasDurableDraft: boolean;
	readonly itemId: string;
	readonly origin: WorktreeAnnotationLocatedOrigin;
	readonly range: WorktreeAnnotationRange;
}

export interface WorktreeAnnotationInteractionController {
	readonly activeMessageId: string | null;
	readonly activeThreadId: string | null;
	readonly admitPendingRootComposer: (composer: WorktreeAnnotationPendingRootComposer) => void;
	readonly activateSavedThread: (identity: WorktreeAnnotationSavedRangeIdentity) => void;
	readonly activateSavedMessage: (
		identity: WorktreeAnnotationSavedRangeIdentity,
		messageId: string,
	) => void;
	readonly clearPendingRootComposer: () => void;
	readonly clearRangePresentation: () => void;
	readonly closeShareMode: () => void;
	readonly collapseThread: () => Promise<void>;
	readonly exitThreadEditor: () => Promise<void>;
	readonly expandThread: (threadId: string, invoker: HTMLElement) => void;
	readonly finishThreadEditor: (editToken: string) => void;
	readonly leaveThread: () => Promise<void>;
	readonly openShareMode: () => void;
	readonly pendingRootComposer: WorktreeAnnotationPendingRootComposer | null;
	readonly pierreRangePresentation: WorktreeAnnotationPierreRangePresentation;
	readonly reattachPendingRootComposer: (props: {
		readonly editToken: string;
		readonly itemId: string;
		readonly range: WorktreeAnnotationRange;
	}) => void;
	readonly retainPendingRootComposer: (itemId: string, range: WorktreeAnnotationRange) => void;
	readonly registerThreadEditorExit: (exitEditor: () => Promise<void>) => () => void;
	readonly resolveThreadFocus: () => HTMLElement | null;
	readonly setPendingRange: (itemId: string, range: WorktreeAnnotationRange) => void;
	readonly setShareScope: (scope: WorktreeAnnotationShareScope) => void;
	readonly shareMode: WorktreeAnnotationShareMode;
	readonly markPendingRootComposerCommitted: (editToken: string) => void;
	readonly markPendingRootComposerDurable: (editToken: string) => void;
	readonly markThreadEditorCommitted: (editToken: string) => void;
	readonly startMessageEdit: (threadId: string, messageId: string, invoker: HTMLElement) => void;
	readonly startReply: (threadId: string, invoker: HTMLElement) => void;
	readonly threadExpansion: WorktreeAnnotationThreadExpansion;
}

const worktreeAnnotationInteractionContext =
	createContext<WorktreeAnnotationInteractionController | null>(null);

export function WorktreeAnnotationInteractionProvider(props: {
	readonly children: ReactNode;
}): ReactElement {
	const [pierreRangePresentation, setPierreRangePresentation] =
		useState<WorktreeAnnotationPierreRangePresentation>({ kind: 'none' });
	const [activeMessageId, setActiveMessageId] = useState<string | null>(null);
	const [pendingRootComposer, setPendingRootComposer] =
		useState<WorktreeAnnotationPendingRootComposer | null>(null);
	const [threadExpansion, setThreadExpansion] = useState<WorktreeAnnotationThreadExpansion>({
		kind: 'closed',
	});
	const threadExpansionRef = useRef(threadExpansion);
	threadExpansionRef.current = threadExpansion;
	const [shareMode, setShareMode] = useState<WorktreeAnnotationShareMode>({ kind: 'closed' });
	const threadEditorExitRef = useRef<(() => Promise<void>) | null>(null);

	const activateSavedThread = useCallback(
		(identity: WorktreeAnnotationSavedRangeIdentity): void => {
			setActiveMessageId(null);
			setPierreRangePresentation({ ...identity, kind: 'savedThread' });
		},
		[],
	);
	const activateSavedMessage = useCallback(
		(identity: WorktreeAnnotationSavedRangeIdentity, messageId: string): void => {
			setActiveMessageId(messageId);
			setPierreRangePresentation({ ...identity, kind: 'savedThread' });
		},
		[],
	);
	const admitPendingRootComposer = useCallback(
		(composer: WorktreeAnnotationPendingRootComposer): void => {
			setPendingRootComposer(composer);
		},
		[],
	);
	const clearPendingRootComposer = useCallback((): void => {
		setPendingRootComposer(null);
	}, []);
	const markPendingRootComposerCommitted = useCallback((editToken: string): void => {
		setPendingRootComposer((currentComposer) =>
			currentComposer?.editToken === editToken
				? { ...currentComposer, committed: true }
				: currentComposer,
		);
	}, []);
	const markPendingRootComposerDurable = useCallback((editToken: string): void => {
		setPendingRootComposer((currentComposer) =>
			currentComposer?.editToken === editToken
				? { ...currentComposer, hasDurableDraft: true }
				: currentComposer,
		);
	}, []);
	const reattachPendingRootComposer = useCallback(
		(props: {
			readonly editToken: string;
			readonly itemId: string;
			readonly range: WorktreeAnnotationRange;
		}): void => {
			setPendingRootComposer((currentComposer) =>
				currentComposer?.editToken === props.editToken
					? {
							...currentComposer,
							itemId: props.itemId,
							range: props.range,
						}
					: currentComposer,
			);
		},
		[],
	);
	const retainPendingRootComposer = useCallback(
		(itemId: string, range: WorktreeAnnotationRange): void => {
			setPendingRootComposer((currentComposer) =>
				currentComposer?.itemId === itemId && annotationRangesMatch(currentComposer.range, range)
					? currentComposer
					: null,
			);
		},
		[],
	);
	const setPendingRange = useCallback((itemId: string, range: WorktreeAnnotationRange): void => {
		setActiveMessageId(null);
		setPierreRangePresentation({ itemId, kind: 'pending', range });
	}, []);
	const clearRangePresentation = useCallback((): void => {
		setActiveMessageId(null);
		setPierreRangePresentation((currentPresentation) =>
			currentPresentation.kind === 'none' ? currentPresentation : { kind: 'none' },
		);
	}, []);
	const openShareMode = useCallback((): void => {
		setShareMode({ kind: 'open', scope: 'pending' });
	}, []);
	const closeShareMode = useCallback((): void => {
		setShareMode({ kind: 'closed' });
	}, []);
	const setShareScope = useCallback((scope: WorktreeAnnotationShareScope): void => {
		setShareMode((currentMode) =>
			currentMode.kind === 'closed' ? currentMode : { kind: 'open', scope },
		);
	}, []);
	const expandThread = useCallback((threadId: string, invoker: HTMLElement): void => {
		setThreadExpansion({
			editor: null,
			invoker,
			kind: 'open',
			returnFocusPoint: elementCenter(invoker),
			threadId,
		});
	}, []);
	const startMessageEdit = useCallback(
		(threadId: string, messageId: string, invoker: HTMLElement): void => {
			setThreadExpansion({
				editor: {
					editToken: createWorktreeAnnotationEditToken(),
					kind: 'message',
					messageId,
				},
				invoker,
				kind: 'open',
				returnFocusPoint: elementCenter(invoker),
				threadId,
			});
		},
		[],
	);
	const startReply = useCallback((threadId: string, invoker: HTMLElement): void => {
		setThreadExpansion({
			editor: { committed: false, editToken: createWorktreeAnnotationEditToken(), kind: 'reply' },
			invoker,
			kind: 'open',
			returnFocusPoint: elementCenter(invoker),
			threadId,
		});
	}, []);
	const markThreadEditorCommitted = useCallback((editToken: string): void => {
		setThreadExpansion((currentExpansion): WorktreeAnnotationThreadExpansion => {
			if (
				currentExpansion.kind === 'closed' ||
				currentExpansion.editor?.kind !== 'reply' ||
				currentExpansion.editor.editToken !== editToken
			) {
				return currentExpansion;
			}
			return {
				...currentExpansion,
				editor: { ...currentExpansion.editor, committed: true },
			};
		});
	}, []);
	const registerThreadEditorExit = useCallback((exitEditor: () => Promise<void>): (() => void) => {
		threadEditorExitRef.current = exitEditor;
		return (): void => {
			if (threadEditorExitRef.current === exitEditor) threadEditorExitRef.current = null;
		};
	}, []);
	const exitThreadEditor = useCallback(async (): Promise<void> => {
		await threadEditorExitRef.current?.();
		threadEditorExitRef.current = null;
		const focusTarget = focusTargetForThreadExpansion(threadExpansion);
		setThreadExpansion(
			(currentExpansion): WorktreeAnnotationThreadExpansion =>
				currentExpansion.kind === 'closed'
					? currentExpansion
					: { ...currentExpansion, editor: null },
		);
		queueMicrotask((): void => focusTarget?.focus());
	}, [threadExpansion]);
	const finishThreadEditor = useCallback((editToken: string): void => {
		const currentExpansion = threadExpansionRef.current;
		if (currentExpansion.kind === 'closed' || currentExpansion.editor?.editToken !== editToken) {
			return;
		}
		threadEditorExitRef.current = null;
		const focusTarget = focusTargetForThreadExpansion(currentExpansion);
		const nextExpansion = { ...currentExpansion, editor: null } as const;
		threadExpansionRef.current = nextExpansion;
		setThreadExpansion(nextExpansion);
		queueMicrotask((): void => focusTarget?.focus());
	}, []);
	const collapseThread = useCallback(async (): Promise<void> => {
		const exitEditor = threadEditorExitRef.current;
		if (exitEditor !== null) await exitEditor();
		threadEditorExitRef.current = null;
		setThreadExpansion((currentExpansion): WorktreeAnnotationThreadExpansion => {
			if (currentExpansion.kind === 'closed') return currentExpansion;
			return { kind: 'closed' };
		});
	}, []);
	const leaveThread = useCallback(async (): Promise<void> => {
		await collapseThread();
		clearRangePresentation();
	}, [clearRangePresentation, collapseThread]);
	const resolveThreadFocus = useCallback((): HTMLElement | null => {
		if (threadExpansion.kind === 'closed') return null;
		const sameThreadTarget = focusTargetForThreadExpansion(threadExpansion);
		if (sameThreadTarget !== null) return sameThreadTarget;
		const survivingControls = [
			...document.querySelectorAll<HTMLElement>(
				'[data-testid="worktree-annotation-thread"] button:not(:disabled)',
			),
		];
		return nearestElementToPoint(survivingControls, threadExpansion.returnFocusPoint);
	}, [threadExpansion]);
	useEffect((): (() => void) | undefined => {
		const dismissibleThreadId =
			threadExpansion.kind === 'open'
				? threadExpansion.threadId
				: pierreRangePresentation.kind === 'savedThread'
					? pierreRangePresentation.threadId
					: null;
		if (dismissibleThreadId === null) return undefined;
		const handleDocumentClick = (event: globalThis.MouseEvent): void => {
			if (!(event.target instanceof Element)) return;
			const currentThread = event.target.closest(
				`[data-annotation-thread-id="${CSS.escape(dismissibleThreadId)}"]`,
			);
			if (
				currentThread !== null ||
				event.target.closest('[data-worktree-annotation-preserve-expansion]') !== null
			)
				return;
			void leaveThread();
		};
		document.addEventListener('click', handleDocumentClick, true);
		return (): void => document.removeEventListener('click', handleDocumentClick, true);
	}, [leaveThread, pierreRangePresentation, threadExpansion]);
	const controller = useMemo<WorktreeAnnotationInteractionController>(
		() => ({
			activeMessageId,
			activeThreadId:
				threadExpansion.kind === 'open'
					? threadExpansion.threadId
					: pierreRangePresentation.kind === 'savedThread'
						? pierreRangePresentation.threadId
						: null,
			admitPendingRootComposer,
			activateSavedMessage,
			activateSavedThread,
			clearPendingRootComposer,
			clearRangePresentation,
			closeShareMode,
			collapseThread,
			exitThreadEditor,
			expandThread,
			finishThreadEditor,
			leaveThread,
			markPendingRootComposerCommitted,
			markPendingRootComposerDurable,
			markThreadEditorCommitted,
			openShareMode,
			pendingRootComposer,
			pierreRangePresentation,
			reattachPendingRootComposer,
			retainPendingRootComposer,
			registerThreadEditorExit,
			resolveThreadFocus,
			setPendingRange,
			setShareScope,
			shareMode,
			startMessageEdit,
			startReply,
			threadExpansion,
		}),
		[
			activeMessageId,
			admitPendingRootComposer,
			activateSavedMessage,
			activateSavedThread,
			clearPendingRootComposer,
			clearRangePresentation,
			closeShareMode,
			collapseThread,
			exitThreadEditor,
			expandThread,
			finishThreadEditor,
			leaveThread,
			markPendingRootComposerCommitted,
			markPendingRootComposerDurable,
			markThreadEditorCommitted,
			openShareMode,
			pendingRootComposer,
			pierreRangePresentation,
			reattachPendingRootComposer,
			retainPendingRootComposer,
			registerThreadEditorExit,
			resolveThreadFocus,
			setPendingRange,
			setShareScope,
			shareMode,
			startMessageEdit,
			startReply,
			threadExpansion,
		],
	);
	return (
		<worktreeAnnotationInteractionContext.Provider value={controller}>
			{props.children}
		</worktreeAnnotationInteractionContext.Provider>
	);
}

function annotationRangesMatch(
	left: WorktreeAnnotationRange,
	right: WorktreeAnnotationRange,
): boolean {
	return (
		left.start === right.start &&
		left.end === right.end &&
		left.side === right.side &&
		left.endSide === right.endSide
	);
}

function elementCenter(element: HTMLElement): { readonly x: number; readonly y: number } {
	const bounds = element.getBoundingClientRect();
	return { x: bounds.left + bounds.width / 2, y: bounds.top + bounds.height / 2 };
}

function focusTargetForThreadExpansion(
	expansion: WorktreeAnnotationThreadExpansion,
): HTMLElement | null {
	if (expansion.kind === 'closed') return null;
	if (expansion.invoker.isConnected) return expansion.invoker;
	return document.querySelector<HTMLElement>(
		`[data-annotation-thread-id="${CSS.escape(expansion.threadId)}"] [data-testid="worktree-annotation-message"]`,
	);
}

function nearestElementToPoint(
	elements: readonly HTMLElement[],
	point: { readonly x: number; readonly y: number },
): HTMLElement | null {
	return (
		elements.toSorted((left, right): number => {
			const leftCenter = elementCenter(left);
			const rightCenter = elementCenter(right);
			const leftDistance = (leftCenter.x - point.x) ** 2 + (leftCenter.y - point.y) ** 2;
			const rightDistance = (rightCenter.x - point.x) ** 2 + (rightCenter.y - point.y) ** 2;
			return leftDistance - rightDistance;
		})[0] ?? null
	);
}

export function useWorktreeAnnotationInteraction(): WorktreeAnnotationInteractionController {
	const interaction = useContext(worktreeAnnotationInteractionContext);
	if (interaction === null) {
		throw new Error('Worktree annotation interaction requires a surface provider.');
	}
	return interaction;
}
