import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import { WorktreeAnnotationOutputHistoryControl } from './worktree-annotation-output-history-control.js';
import { WorktreeAnnotationRecoveryWarning } from './worktree-annotation-recovery-warning.js';
import type { WorktreeAnnotationOutputHistorySummary } from './worktree-annotation-surface-client.js';
import { WorktreeAnnotationSurfaceProvider } from './worktree-annotation-surface-provider.js';

describe('worktree annotation recovery and rail history controls', () => {
	test('shows a compact recovered-degraded warning and acknowledges through the strict operation', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(<RecoveryAndHistoryFixture surface={surface} />);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 0,
				recoveryStatus: 'recovered_degraded',
				revision: 1,
				sessions: [],
			});
			await Promise.resolve();
		});

		await expect
			.element(rendered.getByText('Comments recovered with missing local history'))
			.toBeVisible();
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Acknowledge' }).click();
			await settleInteraction();
		});

		expect(surface.sentOperations.findLast((): boolean => true)).toEqual({
			kind: 'recovery.acknowledge',
		});
	});

	test('shows history only when durable history exists and never lists comments', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<RecoveryAndHistoryFixture surface={surface} />);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({ expectedThreadCount: 0, revision: 1, sessions: [] });
			await Promise.resolve();
		});
		await expect
			.element(rendered.getByRole('button', { name: 'History (1)' }))
			.not.toBeInTheDocument();

		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 0,
				outputHistory: [outputHistorySummary()],
				revision: 2,
				sessions: [annotationSessionSummary({ revision: 2, sessionId: annotationSessionId })],
			});
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'History (1)' }).click();
			await settleInteraction();
		});
		await expect.element(rendered.getByText('Clipboard Markdown · 1 comment')).toBeVisible();
		expect(document.querySelector('[data-slot="popover-content"]')).toBeNull();
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Inspect output attempt 1' }).click();
			await settleInteraction();
		});
		expect(surface.sentOutputInspectionAttemptIds).toEqual([
			'00000000-0000-7000-8000-000000000071',
		]);
		await act(async (): Promise<void> => {
			surface.settleMostRecentInspection({
				attemptId: '00000000-0000-7000-8000-000000000071',
				content: '# Exact saved output',
				outputKind: 'clipboard_markdown',
			});
			await settleInteraction();
		});
		await expect.element(rendered.getByText('# Exact saved output')).toBeVisible();
		expect(document.body.textContent).not.toContain('Root comment');
		expect(document.body.textContent).not.toContain('Thread 1');
	});
});

function RecoveryAndHistoryFixture(props: {
	readonly surface: RecordingAnnotationBrowserSurface;
}): ReactElement {
	return (
		<WorktreeAnnotationSurfaceProvider surfaceClient={props.surface.client}>
			<WorktreeAnnotationRecoveryWarning />
			<WorktreeAnnotationOutputHistoryControl />
		</WorktreeAnnotationSurfaceProvider>
	);
}

async function settleInteraction(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	await Promise.resolve();
}

function outputHistorySummary(): WorktreeAnnotationOutputHistorySummary {
	return {
		attemptId: '00000000-0000-7000-8000-000000000071',
		canMarkNotHandled: true,
		createdAt: Date.UTC(2026, 7, 17, 10),
		messageCount: 1,
		outputKind: 'clipboard_markdown',
		repeatedFromAttemptId: null,
		sessionId: annotationSessionId,
		state: 'succeeded',
		updatedAt: Date.UTC(2026, 7, 17, 10),
	};
}
