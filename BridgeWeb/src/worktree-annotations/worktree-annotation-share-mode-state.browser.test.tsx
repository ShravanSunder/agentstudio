import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import {
	useWorktreeAnnotationInteraction,
	WorktreeAnnotationInteractionProvider,
} from './worktree-annotation-interaction.js';

describe('worktree annotation Share-mode state', () => {
	test('opens on Pending, changes scope, and closes without reviving stale scope', async () => {
		const rendered = await render(
			<WorktreeAnnotationInteractionProvider>
				<ShareModeStateProbe />
			</WorktreeAnnotationInteractionProvider>,
		);

		await expect.element(rendered.getByTestId('share-mode-state')).toHaveTextContent('closed');
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Open share mode' }).click(),
		);
		await expect
			.element(rendered.getByTestId('share-mode-state'))
			.toHaveTextContent('open:pending');
		await performBrowserAction(() => rendered.getByRole('button', { name: 'Show all' }).click());
		await expect.element(rendered.getByTestId('share-mode-state')).toHaveTextContent('open:all');
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Close share mode' }).click(),
		);
		await expect.element(rendered.getByTestId('share-mode-state')).toHaveTextContent('closed');
		await performBrowserAction(() => rendered.getByRole('button', { name: 'Show all' }).click());
		await expect.element(rendered.getByTestId('share-mode-state')).toHaveTextContent('closed');
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Open share mode' }).click(),
		);
		await expect
			.element(rendered.getByTestId('share-mode-state'))
			.toHaveTextContent('open:pending');
	});
});

function ShareModeStateProbe(): ReactElement {
	const interaction = useWorktreeAnnotationInteraction();
	const stateLabel =
		interaction.shareMode.kind === 'closed'
			? interaction.shareMode.kind
			: `${interaction.shareMode.kind}:${interaction.shareMode.scope}`;
	return (
		<div>
			<p data-testid="share-mode-state">{stateLabel}</p>
			<button type="button" onClick={interaction.openShareMode}>
				Open share mode
			</button>
			<button type="button" onClick={() => interaction.setShareScope('all')}>
				Show all
			</button>
			<button type="button" onClick={interaction.closeShareMode}>
				Close share mode
			</button>
		</div>
	);
}

async function performBrowserAction(action: () => Promise<void>): Promise<void> {
	await act(async (): Promise<void> => {
		await action();
		await Promise.resolve();
	});
}
