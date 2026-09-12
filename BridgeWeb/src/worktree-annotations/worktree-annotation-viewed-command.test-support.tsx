import { useImperativeHandle, type Ref } from 'react';

import { annotationSessionId } from './worktree-annotation-browser-test-support.js';
import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationViewedController,
} from './worktree-annotation-surface-provider.js';

export interface ViewedCommandTestHandle {
	readonly markViewed: () => void;
}

export function ViewedCommandTestControl(props: {
	readonly controlRef: Ref<ViewedCommandTestHandle>;
}): null {
	const projection = useWorktreeAnnotationProjection();
	const viewedController = useWorktreeAnnotationViewedController();
	// Model an incoming viewed command without generating an outside press that
	// legitimately dismisses the Share drawer.
	useImperativeHandle(props.controlRef, () => ({
		markViewed: (): void => {
			const messages = projection.threads.flatMap((thread) => thread.messages);
			void viewedController.markMessagesViewed(annotationSessionId, messages);
		},
	}));
	return null;
}
