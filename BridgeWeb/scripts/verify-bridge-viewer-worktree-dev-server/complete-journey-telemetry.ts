import type { Page } from 'playwright';

import type { WorktreeBridgeTelemetrySampleProof } from './types.ts';

const bridgeCompleteJourneyTelemetryTimeoutMilliseconds = 30_000;

export function bridgeCompleteJourneyActivationSequenceAfter(props: {
	readonly minimumExclusive: number;
	readonly samples: readonly WorktreeBridgeTelemetrySampleProof[];
	readonly viewer: 'file' | 'review';
}): number | null {
	const sequences = new Set(
		props.samples.flatMap((sample): number[] => {
			const sequence = sample.numericAttributes['agentstudio.bridge.activation.sequence'];
			return sample.name === 'performance.bridge.web.viewer_activation' &&
				sample.viewer === props.viewer &&
				sequence !== undefined &&
				Number.isSafeInteger(sequence) &&
				sequence > props.minimumExclusive
				? [sequence]
				: [];
		}),
	);
	if (sequences.size === 0) return null;
	if (sequences.size !== 1) {
		throw new Error(
			`Expected exactly one new ${props.viewer === 'file' ? 'File' : 'Review'} activation.`,
		);
	}
	return sequences.values().next().value ?? null;
}

export function bridgeCompleteJourneyTelemetryWitnessesSatisfied(props: {
	readonly activationSequence: number | null;
	readonly samples: readonly WorktreeBridgeTelemetrySampleProof[];
	readonly viewer: 'file' | 'review';
}): boolean {
	const requiredNames =
		props.viewer === 'review' && props.activationSequence !== null
			? [
					'performance.bridge.viewer.time_to_first_interaction',
					'performance.bridge.web.selected_content_painted',
				]
			: props.activationSequence === null
				? ['performance.bridge.viewer.time_to_first_interaction']
				: [
						'performance.bridge.viewer.time_to_first_interaction',
						'performance.bridge.web.file_open_ready',
					];
	return requiredNames.every((name): boolean =>
		props.samples.some((sample): boolean =>
			bridgeCompleteJourneyTelemetryWitnessMatches({
				activationSequence: props.activationSequence,
				name,
				sample,
				viewer: props.viewer,
			}),
		),
	);
}

export async function maximumBridgeCompleteJourneyActivationSequence(page: Page): Promise<number> {
	const samples = await readBridgeCompleteJourneyTelemetrySamples(page);
	return samples.reduce((maximumSequence, sample): number => {
		const sequence = sample.numericAttributes['agentstudio.bridge.activation.sequence'];
		return sample.name === 'performance.bridge.web.viewer_activation' &&
			sequence !== undefined &&
			Number.isSafeInteger(sequence)
			? Math.max(maximumSequence, sequence)
			: maximumSequence;
	}, 0);
}

export async function waitForBridgeCompleteJourneyActivationSequence(props: {
	readonly minimumExclusive: number;
	readonly page: Page;
	readonly viewer: 'file' | 'review';
}): Promise<number> {
	await props.page.waitForFunction(
		({ minimumExclusive, viewer }): boolean =>
			(window.bridgeWorktreeVerifierTelemetrySamples ?? []).some((sample): boolean => {
				const sequence = sample.numericAttributes['agentstudio.bridge.activation.sequence'];
				return (
					sample.name === 'performance.bridge.web.viewer_activation' &&
					sample.viewer === viewer &&
					sequence !== undefined &&
					Number.isSafeInteger(sequence) &&
					sequence > minimumExclusive
				);
			}),
		{ minimumExclusive: props.minimumExclusive, viewer: props.viewer },
		{ timeout: bridgeCompleteJourneyTelemetryTimeoutMilliseconds },
	);
	const activationSequence = bridgeCompleteJourneyActivationSequenceAfter({
		minimumExclusive: props.minimumExclusive,
		samples: await readBridgeCompleteJourneyTelemetrySamples(props.page),
		viewer: props.viewer,
	});
	if (activationSequence === null) {
		throw new Error('Expected the target viewer activation sequence.');
	}
	return activationSequence;
}

export async function waitForBridgeCompleteJourneyTelemetryWitnesses(props: {
	readonly activationSequence: number | null;
	readonly page: Page;
	readonly viewer: 'file' | 'review';
}): Promise<void> {
	await props.page.waitForFunction(
		({ activationSequence, viewer }): boolean => {
			const samples = window.bridgeWorktreeVerifierTelemetrySamples ?? [];
			const requiredNames =
				viewer === 'review' && activationSequence !== null
					? [
							'performance.bridge.viewer.time_to_first_interaction',
							'performance.bridge.web.selected_content_painted',
						]
					: activationSequence === null
						? ['performance.bridge.viewer.time_to_first_interaction']
						: [
								'performance.bridge.viewer.time_to_first_interaction',
								'performance.bridge.web.file_open_ready',
							];
			return requiredNames.every((name): boolean =>
				samples.some((sample): boolean => {
					if (sample.name !== name || sample.viewer !== viewer) return false;
					const sequenceAttribute =
						name === 'performance.bridge.web.file_open_ready'
							? 'agentstudio.bridge.demand.request.sequence'
							: 'agentstudio.bridge.activation.sequence';
					const observedSequence = sample.numericAttributes[sequenceAttribute];
					return activationSequence === null ? true : observedSequence === activationSequence;
				}),
			);
		},
		{ activationSequence: props.activationSequence, viewer: props.viewer },
		{ timeout: bridgeCompleteJourneyTelemetryTimeoutMilliseconds },
	);
	if (
		!bridgeCompleteJourneyTelemetryWitnessesSatisfied({
			activationSequence: props.activationSequence,
			samples: await readBridgeCompleteJourneyTelemetrySamples(props.page),
			viewer: props.viewer,
		})
	) {
		throw new Error('Expected complete journey telemetry paint witnesses.');
	}
}

function bridgeCompleteJourneyTelemetryWitnessMatches(props: {
	readonly activationSequence: number | null;
	readonly name: string;
	readonly sample: WorktreeBridgeTelemetrySampleProof;
	readonly viewer: 'file' | 'review';
}): boolean {
	if (props.sample.name !== props.name || props.sample.viewer !== props.viewer) return false;
	const sequenceAttribute =
		props.name === 'performance.bridge.web.file_open_ready'
			? 'agentstudio.bridge.demand.request.sequence'
			: 'agentstudio.bridge.activation.sequence';
	const observedSequence = props.sample.numericAttributes[sequenceAttribute];
	return props.activationSequence === null ? true : observedSequence === props.activationSequence;
}

async function readBridgeCompleteJourneyTelemetrySamples(
	page: Page,
): Promise<readonly WorktreeBridgeTelemetrySampleProof[]> {
	return await page.evaluate(
		(): readonly WorktreeBridgeTelemetrySampleProof[] =>
			window.bridgeWorktreeVerifierTelemetrySamples ?? [],
	);
}
