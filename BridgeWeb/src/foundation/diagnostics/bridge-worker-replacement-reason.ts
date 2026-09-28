export type BridgeWorkerRuntimeRecoverySource =
	| 'renderDispositionProbeExhausted'
	| 'renderDispositionOverload'
	| 'reviewInstalledReceiptFailed';

export type BridgeWorkerReplacementReason =
	| {
			readonly kind: 'sessionSuspect';
			readonly reason: 'admissionReplyExhausted' | 'resultDeadlineExhausted';
	  }
	| { readonly kind: 'workerError' }
	| { readonly kind: 'messageError' }
	| { readonly kind: 'bootstrapTimeout' }
	| { readonly kind: 'sessionInUse' }
	| { readonly kind: 'explicitDispose' }
	| { readonly kind: 'runtimeRecovery'; readonly source: BridgeWorkerRuntimeRecoverySource };
