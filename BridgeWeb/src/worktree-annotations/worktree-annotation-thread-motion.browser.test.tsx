import { act, useState, type ReactElement } from 'react';
import { expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import { Collapsible, CollapsibleContent } from '@/components/ui/collapsible.js';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production motion styles.
import '../app/bridge-app.css';
import {
	createDeferred,
	settleThreadMotion,
} from './worktree-annotation-thread.browser.test-support.js';

test('does not settle an opening Collapsible before Base UI releases its measured panel height', async () => {
	const rendered = await render(<CollapsibleMotionFixture />);
	const panel = rendered.getByTestId('worktree-annotation-thread-motion-panel').element();
	const originalGetAnimationsDescriptor = Object.getOwnPropertyDescriptor(panel, 'getAnimations');
	const visualAnimationProbe = createDeferred<void>();
	const baseUiCompletionProbe = createDeferred<void>();
	const visualAnimation = createPausedAnimation(panel);
	const baseUiCompletionAnimation = createPausedAnimation(panel);
	let completionFrame: number | null = null;

	Object.defineProperty(panel, 'getAnimations', {
		configurable: true,
		value: (options?: GetAnimationsOptions): Animation[] => {
			if (options?.subtree === true) {
				visualAnimationProbe.resolve();
				return [visualAnimation];
			}
			baseUiCompletionProbe.resolve();
			return [baseUiCompletionAnimation];
		},
	});

	try {
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Expand test annotation thread' }).click();
		});

		void visualAnimation.finished.then((): void => {
			completionFrame = requestAnimationFrame((): void => {
				completionFrame = null;
				baseUiCompletionAnimation.finish();
			});
		});

		const settlement = settleThreadMotion(
			panel,
			'Expected the controlled annotation thread opening motion to settle.',
		);
		await Promise.all([visualAnimationProbe.promise, baseUiCompletionProbe.promise]);
		visualAnimation.finish();
		await settlement;

		expect(panel.style.getPropertyValue('--collapsible-panel-height')).toBe('auto');
	} finally {
		if (completionFrame !== null) cancelAnimationFrame(completionFrame);
		await act(async (): Promise<void> => {
			if (visualAnimation.playState !== 'finished') visualAnimation.finish();
			if (baseUiCompletionAnimation.playState !== 'finished') {
				baseUiCompletionAnimation.finish();
			}
			await baseUiCompletionAnimation.finished;
		});
		visualAnimation.cancel();
		baseUiCompletionAnimation.cancel();
		if (originalGetAnimationsDescriptor === undefined)
			Reflect.deleteProperty(panel, 'getAnimations');
		else Object.defineProperty(panel, 'getAnimations', originalGetAnimationsDescriptor);
	}
});

function CollapsibleMotionFixture(): ReactElement {
	const [open, setOpen] = useState(false);
	return (
		<Collapsible open={open}>
			<button type="button" onClick={() => setOpen(true)}>
				Expand test annotation thread
			</button>
			<CollapsibleContent keepMounted data-testid="worktree-annotation-thread-motion-panel">
				Annotation thread history
			</CollapsibleContent>
		</Collapsible>
	);
}

function createPausedAnimation(panel: Element): Animation {
	const animation = panel.animate([{ opacity: 1 }, { opacity: 1 }], { duration: 1 });
	animation.pause();
	return animation;
}
