import type { BridgeWorkerAckAttemptOutcome } from '../../core/comm-worker/bridge-worker-contracts.js';

export type BridgeWorkerRuntimeRecoverySource =
	| 'renderDispositionProbeExhausted'
	| 'renderDispositionOverload'
	| 'reviewInstalledReceiptFailed';

export type BridgeWorkerReplacementReason =
	| {
			readonly ackAttemptOutcomes: readonly BridgeWorkerAckAttemptOutcome[];
			readonly kind: 'sessionSuspect';
			readonly reason:
				| 'admissionReplyExhausted'
				| 'resultAcknowledgementExhausted'
				| 'resultDeadlineExhausted';
	  }
	| { readonly kind: 'workerError' }
	| { readonly kind: 'messageError' }
	| { readonly kind: 'bootstrapTimeout' }
	| { readonly kind: 'sessionInUse' }
	| { readonly kind: 'explicitDispose' }
	| { readonly kind: 'runtimeRecovery'; readonly source: BridgeWorkerRuntimeRecoverySource };
