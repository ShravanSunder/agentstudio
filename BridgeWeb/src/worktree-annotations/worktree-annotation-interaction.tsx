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

import { createWorktreeAnnotationEditToken } from './worktree-annotation-edit-token.js';
import {
	createWorktreeAnnotationOutputSelection,
	type WorktreeAnnotationOutputSelection,
} from './worktree-annotation-output-selection.js';

export type WorktreeAnnotationEditorState =
	| { readonly editToken: string; readonly kind: 'message'; readonly messageId: string }
	| { readonly editToken: string; readonly kind: 'reply' };

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

export interface WorktreeAnnotationSavedRangeIdentity {
	readonly itemId: string;
	readonly range: WorktreeAnnotationRange;
	readonly threadId: string;
}

export interface WorktreeAnnotationInteractionController {
	readonly activeThreadId: string | null;
	readonly activateSavedThread: (identity: WorktreeAnnotationSavedRangeIdentity) => void;
	readonly clearRangePresentation: () => void;
	readonly collapseThread: () => Promise<void>;
	readonly exitThreadEditor: () => Promise<void>;
	readonly expandThread: (threadId: string, invoker: HTMLElement) => void;
	readonly finishThreadEditor: () => void;
	readonly handleCommentBlur: (nextTarget: EventTarget | null) => void;
	readonly outputSelection: WorktreeAnnotationOutputSelection;
	readonly pierreRangePresentation: WorktreeAnnotationPierreRangePresentation;
	readonly registerThreadEditorExit: (exitEditor: () => Promise<void>) => () => void;
	readonly resolveThreadFocus: () => HTMLElement | null;
	readonly setOutputSelection: (selection: WorktreeAnnotationOutputSelection) => void;
	readonly setPendingRange: (itemId: string, range: WorktreeAnnotationRange) => void;
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
	const [threadExpansion, setThreadExpansion] = useState<WorktreeAnnotationThreadExpansion>({
		kind: 'closed',
	});
	const [outputSelection, setOutputSelection] = useState<WorktreeAnnotationOutputSelection>(
		createWorktreeAnnotationOutputSelection,
	);
	const threadEditorExitRef = useRef<(() => Promise<void>) | null>(null);

	const activateSavedThread = useCallback(
		(identity: WorktreeAnnotationSavedRangeIdentity): void => {
			setPierreRangePresentation({ ...identity, kind: 'savedThread' });
		},
		[],
	);
	const setPendingRange = useCallback((itemId: string, range: WorktreeAnnotationRange): void => {
		setPierreRangePresentation({ itemId, kind: 'pending', range });
	}, []);
	const clearRangePresentation = useCallback((): void => {
		setPierreRangePresentation((currentPresentation) =>
			currentPresentation.kind === 'none' ? currentPresentation : { kind: 'none' },
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
			editor: { editToken: createWorktreeAnnotationEditToken(), kind: 'reply' },
			invoker,
			kind: 'open',
			returnFocusPoint: elementCenter(invoker),
			threadId,
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
		const focusTarget =
			threadExpansion.kind === 'open' && threadExpansion.invoker.isConnected
				? threadExpansion.invoker
				: null;
		setThreadExpansion(
			(currentExpansion): WorktreeAnnotationThreadExpansion =>
				currentExpansion.kind === 'closed'
					? currentExpansion
					: { ...currentExpansion, editor: null },
		);
		queueMicrotask((): void => focusTarget?.focus());
	}, [threadExpansion]);
	const finishThreadEditor = useCallback((): void => {
		threadEditorExitRef.current = null;
		const focusTarget =
			threadExpansion.kind === 'open' && threadExpansion.invoker.isConnected
				? threadExpansion.invoker
				: null;
		setThreadExpansion(
			(currentExpansion): WorktreeAnnotationThreadExpansion =>
				currentExpansion.kind === 'closed'
					? currentExpansion
					: { ...currentExpansion, editor: null },
		);
		queueMicrotask((): void => focusTarget?.focus());
	}, [threadExpansion]);
	const collapseThread = useCallback(async (): Promise<void> => {
		const exitEditor = threadEditorExitRef.current;
		if (exitEditor !== null) await exitEditor();
		threadEditorExitRef.current = null;
		setThreadExpansion((currentExpansion): WorktreeAnnotationThreadExpansion => {
			if (currentExpansion.kind === 'closed') return currentExpansion;
			return { kind: 'closed' };
		});
	}, []);
	const resolveThreadFocus = useCallback((): HTMLElement | null => {
		if (threadExpansion.kind === 'closed') return null;
		if (threadExpansion.invoker.isConnected) return threadExpansion.invoker;
		const survivingControls = [
			...document.querySelectorAll<HTMLElement>(
				'[data-testid="worktree-annotation-thread"] button:not(:disabled)',
			),
		];
		return nearestElementToPoint(survivingControls, threadExpansion.returnFocusPoint);
	}, [threadExpansion]);
	const handleCommentBlur = useCallback(
		(nextTarget: EventTarget | null): void => {
			requestAnimationFrame((): void => {
				const focusedElement = nextTarget instanceof Element ? nextTarget : document.activeElement;
				if (threadExpansion.kind === 'open') {
					if (
						focusedElement instanceof Element &&
						focusedElement.closest('[data-worktree-annotation-preserve-expansion]') !== null
					)
						return;
					const sameThread = focusedElement?.closest(
						`[data-annotation-thread-id="${CSS.escape(threadExpansion.threadId)}"]`,
					);
					if (sameThread === null) void collapseThread();
					return;
				}
				if (focusedElement?.closest('[data-worktree-annotation-interaction]') === null) {
					setPierreRangePresentation((currentPresentation) =>
						currentPresentation.kind === 'savedThread' ? { kind: 'none' } : currentPresentation,
					);
				}
			});
		},
		[collapseThread, threadExpansion],
	);
	useEffect((): (() => void) | undefined => {
		if (threadExpansion.kind !== 'open') return undefined;
		const handleDocumentClick = (event: globalThis.MouseEvent): void => {
			if (!(event.target instanceof Element)) return;
			const currentThread = event.target.closest(
				`[data-annotation-thread-id="${CSS.escape(threadExpansion.threadId)}"]`,
			);
			if (
				currentThread !== null ||
				event.target.closest('[data-worktree-annotation-preserve-expansion]') !== null
			)
				return;
			void collapseThread();
		};
		document.addEventListener('click', handleDocumentClick, true);
		return (): void => document.removeEventListener('click', handleDocumentClick, true);
	}, [collapseThread, threadExpansion]);
	const controller = useMemo<WorktreeAnnotationInteractionController>(
		() => ({
			activeThreadId:
				threadExpansion.kind === 'open'
					? threadExpansion.threadId
					: pierreRangePresentation.kind === 'savedThread'
						? pierreRangePresentation.threadId
						: null,
			activateSavedThread,
			clearRangePresentation,
			collapseThread,
			exitThreadEditor,
			expandThread,
			finishThreadEditor,
			handleCommentBlur,
			outputSelection,
			pierreRangePresentation,
			registerThreadEditorExit,
			resolveThreadFocus,
			setOutputSelection,
			setPendingRange,
			startMessageEdit,
			startReply,
			threadExpansion,
		}),
		[
			activateSavedThread,
			clearRangePresentation,
			collapseThread,
			exitThreadEditor,
			expandThread,
			finishThreadEditor,
			handleCommentBlur,
			outputSelection,
			pierreRangePresentation,
			registerThreadEditorExit,
			resolveThreadFocus,
			setPendingRange,
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

function elementCenter(element: HTMLElement): { readonly x: number; readonly y: number } {
	const bounds = element.getBoundingClientRect();
	return { x: bounds.left + bounds.width / 2, y: bounds.top + bounds.height / 2 };
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
