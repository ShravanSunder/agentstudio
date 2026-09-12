import {
	useCallback,
	useEffect,
	useRef,
	useState,
	type PointerEvent as ReactPointerEvent,
	type RefObject,
} from 'react';

import type { WorktreeAnnotationRange } from '../../worktree-annotations/worktree-annotation-interaction.js';
import type { BridgeMarkdownSourceTarget } from './bridge-markdown-source-target.js';
import type { BridgeMarkdownTargetLayout } from './use-bridge-markdown-annotation-layout.js';

export type BridgeMarkdownAnnotationGestureIntent = 'select' | 'annotate';

type BridgeMarkdownAnnotationGesture =
	| { readonly kind: 'idle' }
	| {
			readonly kind: 'dragging';
			readonly pointerId: number;
			readonly intent: BridgeMarkdownAnnotationGestureIntent;
			readonly anchor: BridgeMarkdownSourceTarget;
			readonly endpoint: BridgeMarkdownSourceTarget;
	  };

interface BridgeMarkdownAnnotationGestureRuntime {
	readonly articleRef: RefObject<HTMLElement | null>;
	readonly enabled: boolean;
	readonly layout: readonly BridgeMarkdownTargetLayout[];
	readonly onEnd: (props: {
		readonly intent: BridgeMarkdownAnnotationGestureIntent;
		readonly range: WorktreeAnnotationRange;
	}) => void;
}

interface BridgeMarkdownAnnotationGestureListeners {
	readonly attach: () => void;
	readonly detach: () => void;
}

/** Mirrors Pierre's pointer session: global listeners exist before pointerdown returns. */
export function useBridgeMarkdownAnnotationGesture(props: {
	readonly articleRef: RefObject<HTMLElement | null>;
	readonly enabled: boolean;
	readonly layout: readonly BridgeMarkdownTargetLayout[];
	readonly selection: WorktreeAnnotationRange | null;
	readonly onEnd: BridgeMarkdownAnnotationGestureRuntime['onEnd'];
}): {
	readonly begin: (
		event: ReactPointerEvent<HTMLButtonElement>,
		target: BridgeMarkdownSourceTarget,
		intent: BridgeMarkdownAnnotationGestureIntent,
	) => void;
	readonly cancel: () => void;
	readonly range: WorktreeAnnotationRange | null;
} {
	const [gesture, setGesture] = useState<BridgeMarkdownAnnotationGesture>({ kind: 'idle' });
	const gestureRef = useRef(gesture);
	gestureRef.current = gesture;
	const runtimeRef = useRef<BridgeMarkdownAnnotationGestureRuntime>({
		articleRef: props.articleRef,
		enabled: props.enabled,
		layout: props.layout,
		onEnd: props.onEnd,
	});
	runtimeRef.current = {
		articleRef: props.articleRef,
		enabled: props.enabled,
		layout: props.layout,
		onEnd: props.onEnd,
	};
	const listenersRef = useRef<BridgeMarkdownAnnotationGestureListeners | null>(null);
	if (listenersRef.current === null) {
		listenersRef.current = createBridgeMarkdownAnnotationGestureListeners({
			gestureRef,
			runtimeRef,
			setGesture,
		});
	}
	const cancel = useCallback((): void => {
		listenersRef.current?.detach();
		gestureRef.current = { kind: 'idle' };
		setGesture({ kind: 'idle' });
	}, []);
	useEffect((): (() => void) => (): void => listenersRef.current?.detach(), []);

	const begin = useCallback(
		(
			event: ReactPointerEvent<HTMLButtonElement>,
			target: BridgeMarkdownSourceTarget,
			intent: BridgeMarkdownAnnotationGestureIntent,
		): void => {
			if (
				(event.pointerType === 'mouse' && event.button !== 0) ||
				!props.enabled ||
				gestureRef.current.kind !== 'idle'
			)
				return;
			event.preventDefault();
			if (intent === 'annotate') event.stopPropagation();
			const selection = props.selection;
			const selectedRows =
				intent === 'annotate' &&
				selection !== null &&
				target.startLine <= selection.end &&
				target.endLine >= selection.start
					? props.layout.filter(
							(row): boolean =>
								row.target.startLine <= selection.end && row.target.endLine >= selection.start,
						)
					: [];
			const next = {
				kind: 'dragging',
				pointerId: event.pointerId,
				intent,
				anchor: selectedRows[0]?.target ?? target,
				endpoint: selectedRows.at(-1)?.target ?? target,
			} satisfies BridgeMarkdownAnnotationGesture;
			gestureRef.current = next;
			setGesture(next);
			listenersRef.current?.attach();
		},
		[props.enabled, props.layout, props.selection],
	);
	return {
		begin,
		cancel,
		range:
			gesture.kind === 'dragging'
				? {
						start: Math.min(gesture.anchor.startLine, gesture.endpoint.startLine),
						end: Math.max(gesture.anchor.endLine, gesture.endpoint.endLine),
					}
				: null,
	};
}

function createBridgeMarkdownAnnotationGestureListeners(props: {
	readonly gestureRef: RefObject<BridgeMarkdownAnnotationGesture>;
	readonly runtimeRef: RefObject<BridgeMarkdownAnnotationGestureRuntime>;
	readonly setGesture: (gesture: BridgeMarkdownAnnotationGesture) => void;
}): BridgeMarkdownAnnotationGestureListeners {
	let attached = false;
	const move = (event: PointerEvent): void => {
		const current = props.gestureRef.current;
		const runtime = props.runtimeRef.current;
		const article = runtime.articleRef.current;
		if (current.kind !== 'dragging' || event.pointerId !== current.pointerId || article === null)
			return;
		event.preventDefault();
		const position = event.clientY - article.getBoundingClientRect().top;
		const nearest = runtime.layout.reduce<BridgeMarkdownTargetLayout | undefined>((best, row) => {
			const distance = (candidate: BridgeMarkdownTargetLayout): number =>
				Math.abs(
					position - Math.max(candidate.top, Math.min(position, candidate.top + candidate.height)),
				);
			return best === undefined || distance(row) < distance(best) ? row : best;
		}, undefined);
		if (nearest === undefined) return;
		const next = { ...current, endpoint: nearest.target };
		props.gestureRef.current = next;
		props.setGesture(next);
	};
	const detach = (): void => {
		if (!attached) return;
		window.removeEventListener('pointermove', move);
		window.removeEventListener('pointerup', finish);
		window.removeEventListener('pointercancel', cancelPointer);
		window.removeEventListener('blur', cancel);
		attached = false;
	};
	const cancel = (): void => {
		detach();
		props.gestureRef.current = { kind: 'idle' };
		props.setGesture({ kind: 'idle' });
	};
	const cancelPointer = (event: PointerEvent): void => {
		const current = props.gestureRef.current;
		if (current.kind === 'dragging' && event.pointerId === current.pointerId) cancel();
	};
	const finish = (event: PointerEvent): void => {
		const started = props.gestureRef.current;
		if (started.kind !== 'dragging' || event.pointerId !== started.pointerId) return;
		move(event);
		const current = props.gestureRef.current;
		if (current.kind !== 'dragging') return;
		event.preventDefault();
		const runtime = props.runtimeRef.current;
		if (runtime.enabled) {
			runtime.onEnd({
				intent: current.intent,
				range: {
					start: Math.min(current.anchor.startLine, current.endpoint.startLine),
					end: Math.max(current.anchor.endLine, current.endpoint.endLine),
				},
			});
		}
		cancel();
	};
	const attach = (): void => {
		if (attached) return;
		window.addEventListener('pointermove', move);
		window.addEventListener('pointerup', finish);
		window.addEventListener('pointercancel', cancelPointer);
		window.addEventListener('blur', cancel);
		attached = true;
	};
	return { attach, detach };
}
