import { useState, type ReactElement, type ReactNode } from 'react';

import {
	createWorktreeAnnotationEditorPreparationRegistry,
	worktreeAnnotationEditorPreparationRegistryContext,
} from '../worktree-annotations/worktree-annotation-editor-preparation-registry.js';
import {
	WorktreeAnnotationNavigationProvider,
	type WorktreeAnnotationNavigationController,
} from '../worktree-annotations/worktree-annotation-navigation.js';
import { useBridgeAppNativeEditorPreparation } from './bridge-app-native-editor-preparation.js';

/**
 * The page-wide annotation scope of one Bridge app: cross-surface annotation
 * navigation, and the editor-preparation registry every surface's annotation
 * provider joins so a native navigation barrier can flush them all at once.
 */
export function BridgeAppAnnotationScope(props: {
	readonly children: ReactNode;
	readonly navigation: WorktreeAnnotationNavigationController;
}): ReactElement {
	const [editorPreparationRegistry] = useState(createWorktreeAnnotationEditorPreparationRegistry);
	useBridgeAppNativeEditorPreparation(editorPreparationRegistry);
	return (
		<worktreeAnnotationEditorPreparationRegistryContext.Provider value={editorPreparationRegistry}>
			<WorktreeAnnotationNavigationProvider controller={props.navigation}>
				{props.children}
			</WorktreeAnnotationNavigationProvider>
		</worktreeAnnotationEditorPreparationRegistryContext.Provider>
	);
}
