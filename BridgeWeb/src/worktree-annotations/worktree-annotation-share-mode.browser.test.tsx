import { act, useState, type ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';
import { page } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	WorktreeAnnotationShareModeRow,
	WorktreeAnnotationShareTrigger,
	type WorktreeAnnotationShareScope,
} from './worktree-annotation-share-mode.js';

describe('worktree annotation Share comments presentation', () => {
	test('opens one in-flow New/All row without selection or floating UI', async () => {
		const onCopy = vi.fn<(scope: WorktreeAnnotationShareScope) => void>();
		const onExport = vi.fn<(scope: WorktreeAnnotationShareScope) => void>();
		const rendered = await render(<ShareModeFixture onCopy={onCopy} onExport={onExport} />);

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		const shareMode = rendered.getByRole('region', { name: 'Share comments' });
		await expect.element(shareMode).toBeVisible();
		await expect
			.element(rendered.getByRole('button', { name: 'New comments, 4' }))
			.toHaveAttribute('aria-pressed', 'true');
		await expect.element(rendered.getByRole('button', { name: 'All comments, 11' })).toBeVisible();
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeEnabled();
		await expect.element(rendered.getByRole('button', { name: 'Export JSON' })).toBeEnabled();
		expect(document.querySelector('[data-slot="popover-content"]')).toBeNull();
		expect(document.querySelector('[role="checkbox"]')).toBeNull();
		expect(shareMode.element().querySelector('[data-slot="scroll-area"]')).toBeNull();
		expect(shareMode.element().textContent).not.toContain('selected');
		await page.screenshot({
			element: shareMode.element(),
			path: '../../../tmp/bridgeweb-worktree-annotation-share-mode.png',
		});

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'All comments, 11' }).click(),
		);
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Copy Markdown' }).click(),
		);
		await performBrowserAction(() => rendered.getByRole('button', { name: 'Export JSON' }).click());

		expect(onCopy).toHaveBeenCalledWith('all');
		expect(onExport).toHaveBeenCalledWith('all');
	});

	test('disables empty output and closes with Done or Escape without an effect', async () => {
		const onCopy = vi.fn<(scope: WorktreeAnnotationShareScope) => void>();
		const onExport = vi.fn<(scope: WorktreeAnnotationShareScope) => void>();
		const rendered = await render(
			<ShareModeFixture allCount={0} newCount={0} onCopy={onCopy} onExport={onExport} />,
		);

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeDisabled();
		await expect.element(rendered.getByRole('button', { name: 'Export JSON' })).toBeDisabled();
		await performBrowserAction(() => rendered.getByRole('button', { name: 'Done' }).click());
		await expect
			.element(rendered.getByRole('region', { name: 'Share comments' }))
			.not.toBeInTheDocument();

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		const shareMode = rendered.getByRole('region', { name: 'Share comments' });
		await performBrowserAction(async (): Promise<void> => {
			shareMode
				.element()
				.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
		});
		await expect.element(shareMode).not.toBeInTheDocument();
		expect(onCopy).not.toHaveBeenCalled();
		expect(onExport).not.toHaveBeenCalled();
	});

	test('retains in-flow failure feedback and compact geometry', async () => {
		const rendered = await render(
			<div className="w-[420px]">
				<ShareModeFixture error="Export failed. No comments were handled." />
			</div>,
		);

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		const shareMode = rendered.getByRole('region', { name: 'Share comments' });
		await expect
			.element(rendered.getByRole('alert'))
			.toHaveTextContent('Export failed. No comments were handled.');
		expect(shareMode.element().getBoundingClientRect().width).toBe(420);
		expect(getComputedStyle(shareMode.element()).position).not.toBe('fixed');
		expect(getComputedStyle(shareMode.element()).position).not.toBe('absolute');
	});
});

function ShareModeFixture(props: {
	readonly allCount?: number;
	readonly error?: string | null;
	readonly newCount?: number;
	readonly onCopy?: (scope: WorktreeAnnotationShareScope) => void;
	readonly onExport?: (scope: WorktreeAnnotationShareScope) => void;
}): ReactElement {
	const [isOpen, setIsOpen] = useState(false);
	const [scope, setScope] = useState<WorktreeAnnotationShareScope>('new');
	return (
		<div>
			<WorktreeAnnotationShareTrigger disabled={false} onOpen={() => setIsOpen(true)} />
			{isOpen ? (
				<WorktreeAnnotationShareModeRow
					error={props.error ?? null}
					isOutputPending={false}
					membership={{
						allCount: props.allCount ?? 11,
						kind: 'ready',
						newCount: props.newCount ?? 4,
					}}
					onCopy={(selectedScope) => props.onCopy?.(selectedScope)}
					onDone={() => setIsOpen(false)}
					onExport={(selectedScope) => props.onExport?.(selectedScope)}
					onScopeChange={setScope}
					scope={scope}
				/>
			) : null}
		</div>
	);
}

async function performBrowserAction(action: () => Promise<void>): Promise<void> {
	await act(async (): Promise<void> => {
		await action();
		await Promise.resolve();
	});
}
