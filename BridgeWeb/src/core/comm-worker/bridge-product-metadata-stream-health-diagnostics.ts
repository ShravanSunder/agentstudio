import type { BridgeProductMetadataRouteFailureCode } from './bridge-product-metadata-route-failure.js';
import type {
	BridgeProductMetadataStreamDecoderDiagnostics,
	BridgeProductMetadataStreamIdentityField,
} from './bridge-product-metadata-stream-decoder.js';
import type { BridgeProductMetadataFrame } from './bridge-product-session-contracts.js';

export interface BridgeProductMetadataStreamHealthDiagnostics {
	readonly lastSubscriptionTermination: {
		readonly subscriptionId: string;
		readonly outcome: 'terminal' | 'failed';
		readonly reason: BridgeProductMetadataRouteFailureCode | null;
	} | null;
	readonly routeFailureSubscriptionId: string | null;
	readonly activeSubscriptionCount: number;
	readonly committedFrameCount: number;
	readonly decoderState: BridgeProductMetadataStreamDecoderDiagnostics['state'];
	readonly expectedNextStreamSequence: number;
	readonly failureStage: BridgeProductMetadataStreamFailureStage | null;
	readonly failureCode: BridgeProductMetadataStreamDecoderDiagnostics['failureCode'];
	readonly identityMismatchField: BridgeProductMetadataStreamIdentityField | null;
	readonly lastChunkByteCount: number;
	readonly lastCommittedFrameKind: BridgeProductMetadataFrame['kind'] | null;
	readonly lastRoutedFrameKind: BridgeProductMetadataFrame['kind'] | null;
	readonly lifecycleState: BridgeProductMetadataStreamLifecycleState;
	readonly peakRetainedByteCount: number;
	readonly pushCount: number;
	readonly readFulfilledCount: number;
	readonly readPending: boolean;
	readonly readRequestCount: number;
	readonly receivedByteCount: number;
	readonly retainedByteCount: number;
	readonly routeFailureCode: BridgeProductMetadataRouteFailureCode | null;
	readonly routedFrameCount: number;
	readonly streamOpenCount: number;
}

export type BridgeProductMetadataStreamFailureStage =
	| 'authority'
	| 'decode'
	| 'fetch'
	| 'finish'
	| 'read'
	| 'route'
	| 'unexpectedEof';

export type BridgeProductMetadataStreamLifecycleState = 'failed' | 'idle' | 'opening' | 'reading';
