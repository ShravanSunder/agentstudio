import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerPanePresentationAuthority } from './bridge-comm-worker-pane-presentation.js';
import type { BridgeProductPanePresentationFrame } from './bridge-product-transport.js';

describe('Bridge comm worker pane presentation authority', () => {
	test('starts dormant with no admitted work generation', () => {
		// Arrange
		const authority = new BridgeCommWorkerPanePresentationAuthority();

		// Act
		const snapshot = authority.snapshot;

		// Assert
		expect(authority.admitsWork).toBe(false);
		expect(authority.workSignal.aborted).toBe(true);
		expect(snapshot).toEqual({
			activityRevision: 0,
			nativeActivity: 'dormant',
			refreshingLanes: [],
			workAdmissionGeneration: 0,
		});
		expect(authority.isCurrentWorkAdmission(0)).toBe(false);
	});

	test('admits the first native foreground frame with a fresh work signal', () => {
		// Arrange
		const authority = new BridgeCommWorkerPanePresentationAuthority();
		const dormantSignal = authority.workSignal;

		// Act
		const application = authority.apply(makePanePresentationFrame(1, 'foreground'));

		// Assert
		expect(application.disposition).toBe('applied');
		expect(application.enteredForeground).toBe(true);
		expect(application.leftForeground).toBe(false);
		expect(authority.admitsWork).toBe(true);
		expect(authority.workSignal).not.toBe(dormantSignal);
		expect(authority.workSignal.aborted).toBe(false);
		expect(authority.snapshot.workAdmissionGeneration).toBe(1);
		expect(authority.isCurrentWorkAdmission(1)).toBe(true);
	});

	test('rejects stale and changed same-revision frames without changing authority', () => {
		// Arrange
		const authority = new BridgeCommWorkerPanePresentationAuthority();
		authority.apply(makePanePresentationFrame(2, 'foreground', ['file']));
		const admittedSignal = authority.workSignal;
		const admittedSnapshot = authority.snapshot;

		// Act / Assert
		expect(() => authority.apply(makePanePresentationFrame(1, 'loadedHidden'))).toThrow(
			'Bridge pane presentation revision is stale.',
		);
		expect(() => authority.apply(makePanePresentationFrame(2, 'foreground', ['review']))).toThrow(
			'Bridge pane presentation revision was reused with changed state.',
		);
		expect(authority.snapshot).toEqual(admittedSnapshot);
		expect(authority.workSignal).toBe(admittedSignal);
		expect(admittedSignal.aborted).toBe(false);
	});

	test('accepts an exact replay without changing the work generation or signal', () => {
		// Arrange
		const authority = new BridgeCommWorkerPanePresentationAuthority();
		const frame = makePanePresentationFrame(1, 'foreground', ['file', 'review']);
		authority.apply(frame);
		const admittedSignal = authority.workSignal;
		const admittedGeneration = authority.snapshot.workAdmissionGeneration;

		// Act
		const replay = authority.apply(frame);

		// Assert
		expect(replay).toMatchObject({
			disposition: 'idempotentReplay',
			enteredForeground: false,
			leftForeground: false,
		});
		expect(authority.workSignal).toBe(admittedSignal);
		expect(authority.snapshot.workAdmissionGeneration).toBe(admittedGeneration);
		expect(admittedSignal.aborted).toBe(false);
	});

	test('aborts foreground work and requires a strictly newer native foreground revision to readmit', () => {
		// Arrange
		const authority = new BridgeCommWorkerPanePresentationAuthority();
		authority.apply(makePanePresentationFrame(1, 'foreground'));
		const firstForegroundSignal = authority.workSignal;

		// Act
		const hiddenApplication = authority.apply(
			makePanePresentationFrame(2, 'loadedHidden', ['review']),
		);
		const hiddenSignal = authority.workSignal;
		const dormantApplication = authority.apply(makePanePresentationFrame(3, 'dormant'));
		const secondForegroundApplication = authority.apply(makePanePresentationFrame(4, 'foreground'));

		// Assert
		expect(hiddenApplication.leftForeground).toBe(true);
		expect(firstForegroundSignal.aborted).toBe(true);
		expect(hiddenSignal).toBe(firstForegroundSignal);
		expect(hiddenSignal.aborted).toBe(true);
		expect(dormantApplication.enteredForeground).toBe(false);
		expect(secondForegroundApplication.enteredForeground).toBe(true);
		expect(authority.admitsWork).toBe(true);
		expect(authority.workSignal).not.toBe(firstForegroundSignal);
		expect(authority.workSignal.aborted).toBe(false);
		expect(authority.snapshot.workAdmissionGeneration).toBe(3);
		expect(authority.isCurrentWorkAdmission(1)).toBe(false);
		expect(authority.isCurrentWorkAdmission(3)).toBe(true);
	});

	test('tracks refreshing lanes without allowing them to mint work admission', () => {
		// Arrange
		const authority = new BridgeCommWorkerPanePresentationAuthority();

		// Act
		const dormantRefresh = authority.apply(
			makePanePresentationFrame(1, 'dormant', ['file', 'review']),
		);
		const hiddenRefresh = authority.apply(makePanePresentationFrame(2, 'loadedHidden', ['file']));

		// Assert
		expect(dormantRefresh.enteredForeground).toBe(false);
		expect(hiddenRefresh.enteredForeground).toBe(false);
		expect(authority.admitsWork).toBe(false);
		expect(authority.workSignal.aborted).toBe(true);
		expect(authority.snapshot).toEqual({
			activityRevision: 2,
			nativeActivity: 'loadedHidden',
			refreshingLanes: ['file'],
			workAdmissionGeneration: 0,
		});
	});
});

function makePanePresentationFrame(
	activityRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
	refreshingLanes: BridgeProductPanePresentationFrame['refreshingLanes'] = [],
): BridgeProductPanePresentationFrame {
	return {
		activityRevision,
		kind: 'pane.presentation',
		metadataStreamId: 'metadata-stream-pane-presentation-unit-test',
		nativeActivity,
		paneSessionId: 'pane-session-pane-presentation-unit-test',
		refreshingLanes,
		streamSequence: activityRevision,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-pane-presentation-unit-test',
	};
}
