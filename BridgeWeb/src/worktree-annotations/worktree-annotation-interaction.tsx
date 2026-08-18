import {
	createContext,
	useCallback,
	useContext,
	useMemo,
	useRef,
	useState,
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

export type WorktreeAnnotationThreadOverlay =
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
	readonly closeOverlay: () => Promise<void>;
	readonly exitOverlayEditor: () => Promise<void>;
	readonly finishOverlayEditor: () => void;
	readonly handleCommentBlur: (nextTarget: EventTarget | null) => void;
	readonly openThreadOverlay: (threadId: string, invoker: HTMLElement) => void;
	readonly outputSelection: WorktreeAnnotationOutputSelection;
	readonly pierreRangePresentation: WorktreeAnnotationPierreRangePresentation;
	readonly registerOverlayEditorExit: (exitEditor: () => Promise<void>) => () => void;
	readonly resolveOverlayFinalFocus: () => HTMLElement | null;
	readonly setOutputSelection: (selection: WorktreeAnnotationOutputSelection) => void;
	readonly setPendingRange: (itemId: string, range: WorktreeAnnotationRange) => void;
	readonly startMessageEdit: (threadId: string, messageId: string, invoker: HTMLElement) => void;
	readonly startReply: (threadId: string, invoker: HTMLElement) => void;
	readonly threadOverlay: WorktreeAnnotationThreadOverlay;
}

const worktreeAnnotationInteractionContext =
	createContext<WorktreeAnnotationInteractionController | null>(null);

export function WorktreeAnnotationInteractionProvider(props: {
	readonly children: ReactNode;
}): ReactElement {
	const [pierreRangePresentation, setPierreRangePresentation] =
		useState<WorktreeAnnotationPierreRangePresentation>({ kind: 'none' });
	const [threadOverlay, setThreadOverlay] = useState<WorktreeAnnotationThreadOverlay>({
		kind: 'closed',
	});
	const [outputSelection, setOutputSelection] = useState<WorktreeAnnotationOutputSelection>(
		createWorktreeAnnotationOutputSelection,
	);
	const overlayEditorExitRef = useRef<(() => Promise<void>) | null>(null);

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
	const openThreadOverlay = useCallback((threadId: string, invoker: HTMLElement): void => {
		setThreadOverlay({
			editor: null,
			invoker,
			kind: 'open',
			returnFocusPoint: elementCenter(invoker),
			threadId,
		});
	}, []);
	const startMessageEdit = useCallback(
		(threadId: string, messageId: string, invoker: HTMLElement): void => {
			setThreadOverlay({
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
		setThreadOverlay({
			editor: { editToken: createWorktreeAnnotationEditToken(), kind: 'reply' },
			invoker,
			kind: 'open',
			returnFocusPoint: elementCenter(invoker),
			threadId,
		});
	}, []);
	const registerOverlayEditorExit = useCallback((exitEditor: () => Promise<void>): (() => void) => {
		overlayEditorExitRef.current = exitEditor;
		return (): void => {
			if (overlayEditorExitRef.current === exitEditor) overlayEditorExitRef.current = null;
		};
	}, []);
	const exitOverlayEditor = useCallback(async (): Promise<void> => {
		await overlayEditorExitRef.current?.();
		overlayEditorExitRef.current = null;
		setThreadOverlay(
			(currentOverlay): WorktreeAnnotationThreadOverlay =>
				currentOverlay.kind === 'closed' ? currentOverlay : { ...currentOverlay, editor: null },
		);
	}, []);
	const finishOverlayEditor = useCallback((): void => {
		overlayEditorExitRef.current = null;
		setThreadOverlay(
			(currentOverlay): WorktreeAnnotationThreadOverlay =>
				currentOverlay.kind === 'closed' ? currentOverlay : { ...currentOverlay, editor: null },
		);
	}, []);
	const closeOverlay = useCallback(async (): Promise<void> => {
		await overlayEditorExitRef.current?.();
		overlayEditorExitRef.current = null;
		setThreadOverlay((currentOverlay): WorktreeAnnotationThreadOverlay => {
			if (currentOverlay.kind === 'closed') return currentOverlay;
			return { kind: 'closed' };
		});
	}, []);
	const resolveOverlayFinalFocus = useCallback((): HTMLElement | null => {
		if (threadOverlay.kind === 'closed') return null;
		if (threadOverlay.invoker.isConnected) return threadOverlay.invoker;
		const sameThreadControl = document.querySelector<HTMLElement>(
			`[data-annotation-thread-id="${CSS.escape(threadOverlay.threadId)}"] button:not(:disabled)`,
		);
		if (sameThreadControl !== null) return sameThreadControl;
		const survivingControls = [
			...document.querySelectorAll<HTMLElement>(
				'[data-testid="worktree-annotation-thread"] button:not(:disabled)',
			),
		];
		return nearestElementToPoint(survivingControls, threadOverlay.returnFocusPoint);
	}, [threadOverlay]);
	const handleCommentBlur = useCallback(
		(nextTarget: EventTarget | null): void => {
			if (threadOverlay.kind === 'open') return;
			queueMicrotask((): void => {
				const focusedElement = nextTarget instanceof Element ? nextTarget : document.activeElement;
				if (focusedElement?.closest('[data-worktree-annotation-interaction]') === null) {
					setPierreRangePresentation((currentPresentation) =>
						currentPresentation.kind === 'savedThread' ? { kind: 'none' } : currentPresentation,
					);
				}
			});
		},
		[threadOverlay.kind],
	);
	const controller = useMemo<WorktreeAnnotationInteractionController>(
		() => ({
			activeThreadId:
				threadOverlay.kind === 'open'
					? threadOverlay.threadId
					: pierreRangePresentation.kind === 'savedThread'
						? pierreRangePresentation.threadId
						: null,
			activateSavedThread,
			clearRangePresentation,
			closeOverlay,
			exitOverlayEditor,
			finishOverlayEditor,
			handleCommentBlur,
			openThreadOverlay,
			outputSelection,
			pierreRangePresentation,
			registerOverlayEditorExit,
			resolveOverlayFinalFocus,
			setOutputSelection,
			setPendingRange,
			startMessageEdit,
			startReply,
			threadOverlay,
		}),
		[
			activateSavedThread,
			clearRangePresentation,
			closeOverlay,
			exitOverlayEditor,
			finishOverlayEditor,
			handleCommentBlur,
			openThreadOverlay,
			outputSelection,
			pierreRangePresentation,
			registerOverlayEditorExit,
			resolveOverlayFinalFocus,
			setPendingRange,
			startMessageEdit,
			startReply,
			threadOverlay,
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
	point: { readonly x: number; readonly y: number } | null,
): HTMLElement | null {
	if (point === null) return elements[0] ?? null;
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
