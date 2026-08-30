import { act, useRef, useState, type ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';
import { page } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import { BridgeViewerHeaderShelf } from '../app/bridge-viewer-header-shelf.js';
import { Alert } from '../components/ui/alert.js';
import { Popover } from '../components/ui/popover.js';
import {
	WorktreeAnnotationShareModeRow,
	WorktreeAnnotationShareTrigger,
	type WorktreeAnnotationShareScope,
} from './worktree-annotation-share-mode.js';

describe('worktree annotation Share comments presentation', () => {
	test('uses the owned action surface without a route-local color', async () => {
		const rendered = await render(
			<div>
				<Alert data-testid="loading-status-surface">Loading comparison…</Alert>
				<WorktreeAnnotationShareModeRow
					error={null}
					isOutputPending={false}
					membership={{ allCount: 11, kind: 'ready', pendingCount: 4 }}
					onCopy={vi.fn()}
					onDone={vi.fn()}
					onExport={vi.fn()}
					onScopeChange={vi.fn()}
					scope="pending"
				/>
			</div>,
		);

		const loadingSurface = rendered.getByTestId('loading-status-surface').element();
		const shareSurface = rendered.getByRole('region', { name: 'Share comments' }).element();
		expect(getComputedStyle(shareSurface).backgroundColor).toBe('rgba(0, 0, 0, 0)');
		expect(getComputedStyle(loadingSurface).backgroundColor).not.toBe('rgba(0, 0, 0, 0)');
	});

	test('opens one floating Pending/All shelf without selection UI', async () => {
		const onCopy = vi.fn<(scope: WorktreeAnnotationShareScope) => void>();
		const onExport = vi.fn<(scope: WorktreeAnnotationShareScope) => void>();
		const rendered = await render(<ShareModeFixture onCopy={onCopy} onExport={onExport} />);
		const shareTrigger = rendered.getByRole('button', { name: 'Share comments' });
		expect(shareTrigger.element().textContent).toBe('');
		expect(shareTrigger.element().querySelector('.lucide-share-2')).not.toBeNull();
		expect(shareTrigger.element().getAttribute('data-slot')).toBe('tooltip-trigger');
		expect(shareTrigger.element().getAttribute('data-tooltip')).toBe('Share comments');
		expect(getComputedStyle(shareTrigger.element()).width).toBe('24px');

		await performBrowserAction(() => shareTrigger.click());
		const shareMode = rendered.getByRole('region', { name: 'Share comments' });
		await expect.element(shareMode).toBeVisible();
		expect(shareMode.element().textContent).toContain('Share');
		expect(shareMode.element().textContent).not.toContain('Share comments');
		expect(shareMode.element().textContent).toContain('Copy');
		expect(shareMode.element().textContent).not.toContain('Copy Markdown');
		expect(shareMode.element().textContent).toContain('Export');
		expect(shareMode.element().textContent).not.toContain('Export JSON');
		expect(shareMode.element().querySelector('.lucide-share-2')).not.toBeNull();
		expect(shareMode.element().querySelector('.lucide-copy')).not.toBeNull();
		expect(
			rendered.getByRole('button', { name: 'Export JSON' }).element().querySelector('svg'),
		).not.toBeNull();
		expect(shareMode.element().querySelector('.lucide-x')).not.toBeNull();
		await expect
			.element(rendered.getByRole('button', { name: 'Close Share comments' }))
			.toBeVisible();
		await expect
			.element(rendered.getByRole('button', { name: 'Pending comments, 4' }))
			.toHaveAttribute('aria-pressed', 'true');
		await expect
			.element(rendered.getByRole('button', { name: 'Pending comments, 4' }))
			.toHaveFocus();
		await expect.element(rendered.getByRole('button', { name: 'All comments, 11' })).toBeVisible();
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeEnabled();
		await expect.element(rendered.getByRole('button', { name: 'Export JSON' })).toBeEnabled();
		expect(document.querySelector('[data-slot="popover-content"]')).toBe(
			rendered.getByTestId('worktree-annotation-share-shelf').element(),
		);
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
			<ShareModeFixture allCount={0} pendingCount={0} onCopy={onCopy} onExport={onExport} />,
		);

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeDisabled();
		await expect.element(rendered.getByRole('button', { name: 'Export JSON' })).toBeDisabled();
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Close Share comments' }).click(),
		);
		await expect
			.element(rendered.getByRole('region', { name: 'Share comments' }))
			.not.toBeInTheDocument();

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		const shareMode = rendered.getByRole('region', { name: 'Share comments' });
		await performBrowserAction(async (): Promise<void> => {
			rendered
				.getByRole('button', { name: 'Pending comments, 0' })
				.element()
				.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
		});
		await expect.element(shareMode).not.toBeInTheDocument();
		expect(onCopy).not.toHaveBeenCalled();
		expect(onExport).not.toHaveBeenCalled();
	});

	test('retains failure feedback inside the 90%-width floating shelf', async () => {
		const rendered = await render(
			<div className="w-[420px]">
				<ShareModeFixture error="Export failed. No comments were handled." />
			</div>,
		);

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await expect
			.element(rendered.getByRole('alert'))
			.toHaveTextContent('Export failed. No comments were handled.');
		expect(
			rendered.getByTestId('worktree-annotation-share-shelf').element().getBoundingClientRect()
				.width,
		).toBeCloseTo(378, 0);
	});
});

function ShareModeFixture(props: {
	readonly allCount?: number;
	readonly error?: string | null;
	readonly pendingCount?: number;
	readonly onCopy?: (scope: WorktreeAnnotationShareScope) => void;
	readonly onExport?: (scope: WorktreeAnnotationShareScope) => void;
}): ReactElement {
	const [isOpen, setIsOpen] = useState(false);
	const [scope, setScope] = useState<WorktreeAnnotationShareScope>('pending');
	const headerRef = useRef<HTMLDivElement | null>(null);
	const triggerRef = useRef<HTMLButtonElement | null>(null);
	return (
		<div ref={headerRef} data-bridge-viewer-content-topbar="true">
			<Popover onOpenChange={setIsOpen} open={isOpen}>
				<WorktreeAnnotationShareTrigger buttonRef={triggerRef} disabled={false} open={isOpen} />
				<BridgeViewerHeaderShelf
					anchor={headerRef}
					ariaLabel="Share comments"
					finalFocus={triggerRef}
					testId="worktree-annotation-share-shelf"
				>
					<WorktreeAnnotationShareModeRow
						error={props.error ?? null}
						isOutputPending={false}
						membership={{
							allCount: props.allCount ?? 11,
							kind: 'ready',
							pendingCount: props.pendingCount ?? 4,
						}}
						onCopy={(selectedScope) => props.onCopy?.(selectedScope)}
						onDone={() => setIsOpen(false)}
						onExport={(selectedScope) => props.onExport?.(selectedScope)}
						onScopeChange={setScope}
						scope={scope}
					/>
				</BridgeViewerHeaderShelf>
			</Popover>
		</div>
	);
}

async function performBrowserAction(action: () => Promise<void>): Promise<void> {
	await act(async (): Promise<void> => {
		await action();
		await Promise.resolve();
	});
}
