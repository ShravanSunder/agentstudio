import { act, type ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { createBridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	annotationSessionId,
	RecordingAnnotationBrowserSurface,
} from '../worktree-annotations/worktree-annotation-browser-test-support.js';
import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	WorktreeAnnotationSurfaceProvider,
} from '../worktree-annotations/worktree-annotation-surface-provider.js';

describe('Bridge Review annotation client retention', () => {
	test('retains known Share membership when telemetry installs after projection bootstrap', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const telemetryRecorderRef: { current: BridgeTelemetryRecorder } = {
			current: createBridgeTelemetryRecorder(null),
		};
		const rendered = await render(
			<ReviewAnnotationProviderCallSite
				surface={surface}
				telemetryRecorderRef={telemetryRecorderRef}
			/>,
		);

		await act(async (): Promise<void> => {
			surface.publishProjection(1, 0);
			await Promise.resolve();
		});
		await expect
			.element(rendered.getByTestId('review-annotation-membership'))
			.toHaveAttribute('data-session-id', annotationSessionId);
		await expect
			.element(rendered.getByTestId('review-annotation-membership'))
			.toHaveAttribute('data-eligible-message-count', '0');

		const previousRecorder = telemetryRecorderRef.current;
		const record = vi.fn<BridgeTelemetryRecorder['record']>();
		telemetryRecorderRef.current = { ...previousRecorder, record };
		expect(telemetryRecorderRef.current).not.toBe(previousRecorder);
		await rendered.rerender(
			<ReviewAnnotationProviderCallSite
				surface={surface}
				telemetryRecorderRef={telemetryRecorderRef}
			/>,
		);

		await expect
			.element(rendered.getByTestId('review-annotation-membership'))
			.toHaveAttribute('data-session-id', annotationSessionId);
		await expect
			.element(rendered.getByTestId('review-annotation-membership'))
			.toHaveAttribute('data-read-status', 'ready');
		record.mockClear();
		await act(async (): Promise<void> => {
			surface.publishProjection(2, 0);
		});
		expect(record).toHaveBeenCalled();
	});
});

function ReviewAnnotationProviderCallSite(props: {
	readonly surface: RecordingAnnotationBrowserSurface;
	readonly telemetryRecorderRef: { readonly current: BridgeTelemetryRecorder };
}): ReactElement {
	return (
		<WorktreeAnnotationSurfaceProvider
			surfaceClient={props.surface.client}
			telemetryRecorder={props.telemetryRecorderRef.current}
		>
			<ReviewAnnotationMembershipProbe />
		</WorktreeAnnotationSurfaceProvider>
	);
}

function ReviewAnnotationMembershipProbe(): ReactElement {
	const projection = useWorktreeAnnotationProjection();
	const selection = useWorktreeAnnotationSessionSelection();
	const activeSession = selection.sessions.find(
		(session) => session.sessionId === selection.activeSessionId,
	);
	return (
		<output
			data-eligible-message-count={activeSession?.eligibleMessageCount ?? 'unknown'}
			data-read-status={projection.readStatus.kind}
			data-session-id={selection.activeSessionId ?? 'unknown'}
			data-testid="review-annotation-membership"
		/>
	);
}
