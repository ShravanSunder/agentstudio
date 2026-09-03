import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerPanePresentationAuthority } from './bridge-comm-worker-pane-presentation.js';
import {
	createBridgeWorkerComparisonTargetsQueryRunner,
	type BridgeWorkerComparisonTargetsQueryRunner,
} from './bridge-comm-worker-review-comparison-target-query.js';
import type { BridgeProductReviewComparisonTargetsContentDescriptor } from './bridge-product-content-contracts.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import type { BridgeProductPanePresentationFrame } from './bridge-product-transport.js';

describe('Bridge worker comparison-target query runner', () => {
	test('uses the current foreground signal when the runner outlives pane admission', async () => {
		// Arrange
		const authority = new BridgeCommWorkerPanePresentationAuthority();
		const published: unknown[] = [];
		const runner = createRunner(authority, published);
		authority.apply(makePanePresentationFrame(1, 'foreground'));

		// Act
		await runner.run('query-current-admission', { descriptor: comparisonTargetsDescriptor() });

		// Assert
		expect(published).toHaveLength(1);
		expect(published[0]).toMatchObject({
			kind: 'reviewComparisonTargetsQuery',
			requestId: 'query-current-admission',
			status: 'empty',
		});
	});

	test('does not publish after foreground admission is lost', async () => {
		// Arrange
		const authority = new BridgeCommWorkerPanePresentationAuthority();
		const published: unknown[] = [];
		const terminal = deferredComparisonTargetsTerminal();
		const runner = createRunner(authority, published, () => terminal.promise);
		authority.apply(makePanePresentationFrame(1, 'foreground'));
		const running = runner.run('query-lost-admission', {
			descriptor: comparisonTargetsDescriptor(),
		});

		// Act
		authority.apply(makePanePresentationFrame(2, 'loadedHidden'));
		terminal.resolve(comparisonTargetsTerminal());
		await running;

		// Assert
		expect(published).toEqual([]);
	});

	test('publishes only the latest query result', async () => {
		// Arrange
		const authority = new BridgeCommWorkerPanePresentationAuthority();
		const published: unknown[] = [];
		const terminals = [deferredComparisonTargetsTerminal(), deferredComparisonTargetsTerminal()];
		let streamIndex = 0;
		const runner = createRunner(authority, published, (): Promise<ComparisonTargetsTerminal> => {
			const terminal = terminals[streamIndex++];
			if (terminal === undefined) throw new Error('Expected a deferred query terminal.');
			return terminal.promise;
		});
		authority.apply(makePanePresentationFrame(1, 'foreground'));
		const first = runner.run('query-old', { descriptor: comparisonTargetsDescriptor() });
		const second = runner.run('query-new', { descriptor: comparisonTargetsDescriptor() });

		// Act
		const firstTerminal = terminals[0];
		const secondTerminal = terminals[1];
		if (firstTerminal === undefined || secondTerminal === undefined) {
			throw new Error('Expected two deferred query terminals.');
		}
		firstTerminal.resolve(comparisonTargetsTerminal());
		secondTerminal.resolve(comparisonTargetsTerminal());
		await Promise.all([first, second]);

		// Assert
		expect(published).toHaveLength(1);
		expect(published[0]).toMatchObject({ requestId: 'query-new', status: 'empty' });
	});
});

function createRunner(
	authority: BridgeCommWorkerPanePresentationAuthority,
	published: unknown[],
	terminalFactory: () => Promise<ComparisonTargetsTerminal> = async (): Promise<ComparisonTargetsTerminal> =>
		comparisonTargetsTerminal(),
): BridgeWorkerComparisonTargetsQueryRunner {
	return createBridgeWorkerComparisonTargetsQueryRunner({
		getWorkAdmission: () => ({
			generation: authority.snapshot.workAdmissionGeneration,
			signal: authority.workSignal,
		}),
		isCurrentWorkAdmission: (generation) => authority.isCurrentWorkAdmission(generation),
		openContent: (): BridgeProductContentStream<'review.comparisonTargets'> => ({
			contentKind: 'review.comparisonTargets',
			contentRequestId: 'content-request-comparison-targets',
			frames: emptyFrames(),
			terminal: terminalFactory(),
		}),
		publish: (event): void => {
			published.push(event);
		},
	});
}

type ComparisonTargetsTerminal = Awaited<
	BridgeProductContentStream<'review.comparisonTargets'>['terminal']
>;

function comparisonTargetsDescriptor(): BridgeProductReviewComparisonTargetsContentDescriptor {
	return {
		contentKind: 'review.comparisonTargets' as const,
		descriptorId: 'comparison-targets-descriptor',
		maximumBytes: 1024 * 1024,
	};
}

function comparisonTargetsTerminal(): ComparisonTargetsTerminal {
	const bytes = new TextEncoder().encode(
		JSON.stringify({
			branches: [],
			capturedAtUnixMilliseconds: 1_700_000_000_000,
			cutoffUnixMilliseconds: 1_697_408_000_000,
			currentTarget: null,
			defaultTarget: null,
			isTruncated: false,
		}),
	);
	return {
		bytes: bytes.buffer,
		contentKind: 'review.comparisonTargets',
		descriptorId: 'comparison-targets-descriptor',
		endOfSource: true,
		kind: 'complete',
		observedByteLength: bytes.byteLength,
		observedSha256: 'a'.repeat(64),
	};
}

function deferredComparisonTargetsTerminal(): {
	readonly promise: Promise<ComparisonTargetsTerminal>;
	readonly resolve: (terminal: ComparisonTargetsTerminal) => void;
} {
	let resolve!: (terminal: ComparisonTargetsTerminal) => void;
	const promise = new Promise<ComparisonTargetsTerminal>((resolvePromise): void => {
		resolve = resolvePromise;
	});
	return { promise, resolve };
}

async function* emptyFrames(): AsyncIterable<never> {}

function makePanePresentationFrame(
	presentationRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
): BridgeProductPanePresentationFrame {
	return {
		fileRefreshFailure: null,
		kind: 'pane.presentation',

		operationCorrelationId: null,
		metadataStreamId: 'metadata-stream-query-unit-test',
		nativeActivity,
		paneSessionId: 'pane-session-query-unit-test',
		presentationRevision,
		refreshingLanes: [],
		reviewComparison: null,
		streamSequence: presentationRevision,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-query-unit-test',
	};
}
