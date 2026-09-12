import { act, type ReactElement } from 'react';
import { expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import type { WorktreeAnnotationNavigationController } from '../worktree-annotations/worktree-annotation-navigation.js';
import { useBridgeAnnotationNavigation } from './use-bridge-annotation-navigation.js';

test('same-viewer Open enqueues a request and a stale completion cannot cancel its successor', async () => {
	const activate = vi.fn((): boolean => false);
	let controller: WorktreeAnnotationNavigationController | null = null;
	function Fixture(): ReactElement {
		controller = useBridgeAnnotationNavigation({
			activeSurface: 'file',
			activateDestination: activate,
		});
		return <output>{controller.request?.threadId ?? 'idle'}</output>;
	}
	const screen = await render(<Fixture />);
	const current = (): WorktreeAnnotationNavigationController => {
		if (controller === null) throw new Error('No controller');
		return controller;
	};
	act((): void => current().open({ destination: 'file', sessionId: 'session', threadId: 'first' }));
	await expect.element(screen.getByText('first', { exact: true })).toBeVisible();
	const firstId = current().request?.requestId;
	if (firstId === undefined) throw new Error('Missing first request');
	act((): void =>
		current().open({ destination: 'file', sessionId: 'session', threadId: 'second' }),
	);
	act((): void => current().finish(firstId));
	await expect.element(screen.getByText('second', { exact: true })).toBeVisible();
	expect(activate).not.toHaveBeenCalled();
});
