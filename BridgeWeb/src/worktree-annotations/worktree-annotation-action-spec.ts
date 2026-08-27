import { Check, ChevronDown, Pencil, Reply, RotateCcw, Undo2, type LucideIcon } from 'lucide-react';

export type WorktreeAnnotationActionId =
	| 'collapseThread'
	| 'editAnnotation'
	| 'expandThread'
	| 'reopenThread'
	| 'replyToThread'
	| 'resolveThread'
	| 'revertDraft'
	| 'saveAnnotation';

export interface WorktreeAnnotationActionSpec {
	readonly accessibleName: string;
	readonly icon: LucideIcon;
	readonly shortcutKeycap: string | null;
	readonly tooltip: string;
}

const staticActionSpecs = {
	editAnnotation: {
		accessibleName: 'Edit annotation',
		icon: Pencil,
		shortcutKeycap: 'E',
	},
	reopenThread: {
		accessibleName: 'Reopen annotation thread',
		icon: RotateCcw,
		shortcutKeycap: null,
	},
	replyToThread: {
		accessibleName: 'Reply to annotation thread',
		icon: Reply,
		shortcutKeycap: 'R',
	},
	resolveThread: {
		accessibleName: 'Resolve annotation thread',
		icon: Check,
		shortcutKeycap: null,
	},
	revertDraft: {
		accessibleName: 'Revert annotation draft',
		icon: Undo2,
		shortcutKeycap: null,
	},
	saveAnnotation: {
		accessibleName: 'Save annotation',
		icon: Check,
		shortcutKeycap: '⌘↵',
	},
} as const satisfies Readonly<
	Record<
		Exclude<WorktreeAnnotationActionId, 'collapseThread' | 'expandThread'>,
		Omit<WorktreeAnnotationActionSpec, 'tooltip'>
	>
>;

export function worktreeAnnotationActionSpec(
	actionId: WorktreeAnnotationActionId,
	annotationCount?: number,
): WorktreeAnnotationActionSpec {
	if (actionId === 'collapseThread' || actionId === 'expandThread') {
		if (annotationCount === undefined) {
			throw new Error(`${actionId} requires an annotation count.`);
		}
		const accessibleName = `${actionId === 'expandThread' ? 'Expand' : 'Collapse'} ${annotationCount} annotations`;
		return {
			accessibleName,
			icon: ChevronDown,
			shortcutKeycap: null,
			tooltip: accessibleName,
		};
	}
	const actionSpec = staticActionSpecs[actionId];
	return {
		...actionSpec,
		tooltip:
			actionSpec.shortcutKeycap === null
				? actionSpec.accessibleName
				: `${actionSpec.accessibleName} (${actionSpec.shortcutKeycap})`,
	};
}

export function matchesWorktreeAnnotationActionShortcut(
	event: Pick<KeyboardEvent, 'altKey' | 'ctrlKey' | 'key' | 'metaKey' | 'shiftKey'>,
	actionId: 'editAnnotation' | 'replyToThread',
): boolean {
	if (event.altKey || event.metaKey || event.shiftKey) return false;
	const expectedKey = actionId === 'editAnnotation' ? 'e' : 'r';
	return event.key.toLowerCase() === expectedKey;
}

export function worktreeAnnotationShortcutTargetOwnsTextInput(target: EventTarget | null): boolean {
	return (
		target instanceof Element &&
		target.closest(
			'input, textarea, select, [contenteditable="true"], [role="textbox"], [role="menu"], [role="menuitem"]',
		) !== null
	);
}
