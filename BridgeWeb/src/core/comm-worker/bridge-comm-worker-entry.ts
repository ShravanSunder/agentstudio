// oxlint-disable unicorn/require-post-message-target-origin -- WorkerGlobalScope.postMessage does not accept a targetOrigin argument.
import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type RegisterBridgeCommWorkerRuntimePortProtocolProps,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	BridgeProductControlMux,
	BridgeProductSessionAuthorityStore,
	type BridgeProductSessionAuthorityInstallInput,
} from './bridge-product-session-authority.js';
import { bridgePaneCommWorkerInstallSchema } from './bridge-product-session-contracts.js';
import {
	createBridgeProductTransport,
	type BridgeProductTransportSession,
} from './bridge-product-transport.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeCommWorkerBootstrapRequestSchema,
	bridgeWorkerMainToServerMessageSchema,
	type BridgeCommWorkerBootstrapRequest,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { PreparedBridgeWorkerStructuredMessage } from './bridge-worker-transfer-list.js';

export interface BridgeCommWorkerPort {
	postMessage(message: BridgeWorkerServerToMainMessage): void;
	postMessage(message: BridgeWorkerServerToMainMessage, transferList: Transferable[]): void;
	readonly addEventListener: (
		type: 'message',
		listener: (event: MessageEvent<unknown>) => void,
	) => void;
	readonly dispatchEvent?: (event: Event) => boolean;
	readonly start?: () => void;
}

export interface BridgeCommWorkerGlobalScope {
	postMessage(message: BridgeWorkerServerToMainMessage): void;
	postMessage(message: BridgeWorkerServerToMainMessage, transferList: Transferable[]): void;
	readonly addEventListener: (
		type: 'message',
		listener: (event: MessageEvent<unknown>) => void,
	) => void;
	readonly dispatchEvent?: (event: Event) => boolean;
}

export interface BridgeCommWorkerEntryDependencies {
	readonly installProductSession: (
		input: BridgeProductSessionAuthorityInstallInput,
	) => BridgeCommWorkerInstalledProductSession;
}

export interface BridgeCommWorkerInstalledProductSession {
	readonly open: Promise<void>;
	readonly productTransport: BridgeProductTransportSession;
}

export function postPreparedBridgeCommWorkerMessage(
	port: BridgeCommWorkerPort,
	preparedMessage: PreparedBridgeWorkerStructuredMessage<BridgeWorkerServerToMainMessage>,
): void {
	port.postMessage(preparedMessage.message, [...preparedMessage.transferList]);
}

export function registerInertBridgeCommWorkerPortProtocol(port: BridgeCommWorkerPort): void {
	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		const parsedMessage = bridgeWorkerMainToServerMessageSchema.safeParse(event.data);
		if (!parsedMessage.success) {
			port.postMessage({
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				status: 'degraded',
				message: 'Bridge comm worker received invalid message.',
			});
			return;
		}
		port.postMessage(buildBridgeWorkerReadyHealthEvent(parsedMessage.data.requestId));
	});
	port.start?.();
}

export function createBridgeCommWorkerScopePortAdapter(
	scope: BridgeCommWorkerGlobalScope,
): BridgeCommWorkerPort {
	return {
		postMessage: (
			message: BridgeWorkerServerToMainMessage,
			transferList?: Transferable[],
		): void => {
			if (transferList === undefined) {
				scope.postMessage(message);
				return;
			}
			scope.postMessage(message, transferList);
		},
		addEventListener: (type: 'message', listener: (event: MessageEvent<unknown>) => void): void => {
			scope.addEventListener(type, listener);
		},
		...(scope.dispatchEvent === undefined
			? {}
			: {
					dispatchEvent: (event: Event): boolean => scope.dispatchEvent?.(event) ?? false,
				}),
	};
}

export function bootstrapInertBridgeCommWorkerEntry(scope: BridgeCommWorkerGlobalScope): void {
	registerInertBridgeCommWorkerPortProtocol(createBridgeCommWorkerScopePortAdapter(scope));
}

export function bootstrapBridgeCommWorkerEntry(
	port: BridgeCommWorkerPort,
	dependencies: BridgeCommWorkerEntryDependencies = defaultBridgeCommWorkerEntryDependencies(),
): void {
	let installedProductPort: MessagePort | null = null;

	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		const parsedInstall = bridgePaneCommWorkerInstallSchema.safeParse(event.data);
		if (parsedInstall.success) {
			event.stopImmediatePropagation();
			if (installedProductPort !== null) {
				parsedInstall.data.productPort.close();
				port.postMessage(
					buildBridgeWorkerEntryDegradedHealthEvent({
						message: 'Bridge pane comm worker was already installed.',
					}),
				);
				return;
			}
			const productSession = dependencies.installProductSession({
				bootstrap: parsedInstall.data.bootstrap,
				productCapability: parsedInstall.data.productCapability,
			});
			installedProductPort = parsedInstall.data.productPort;
			bootstrapBridgeCommWorkerRuntimeEntry(installedProductPort, productSession);
			return;
		}

		const parsedCommand = bridgeWorkerMainToServerMessageSchema.safeParse(event.data);
		port.postMessage(
			buildBridgeWorkerEntryDegradedHealthEvent({
				...(parsedCommand.success ? { requestId: parsedCommand.data.requestId } : {}),
				message:
					installedProductPort === null
						? 'Bridge pane comm worker requires a typed install message.'
						: 'Bridge pane comm worker accepts ordinary commands only on the installed port.',
			}),
		);
	});
	port.start?.();
}

function defaultBridgeCommWorkerEntryDependencies(): BridgeCommWorkerEntryDependencies {
	const productSessionAuthority = new BridgeProductSessionAuthorityStore();
	return {
		installProductSession: (input): BridgeCommWorkerInstalledProductSession => {
			const authority = productSessionAuthority.install(input);
			const controlMux = new BridgeProductControlMux({ authority });
			return {
				open: authority.open,
				productTransport: createBridgeProductTransport({ authority, controlMux }),
			};
		},
	};
}

function bootstrapBridgeCommWorkerRuntimeEntry(
	port: BridgeCommWorkerPort,
	productSession: BridgeCommWorkerInstalledProductSession,
): void {
	let didBootstrapRuntime = false;
	let didReceiveBootstrap = false;
	const pendingMessagesBeforeBootstrap: unknown[] = [];

	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		const parsedBootstrap = bridgeCommWorkerBootstrapRequestSchema.safeParse(event.data);
		if (parsedBootstrap.success) {
			event.stopImmediatePropagation();
			if (didReceiveBootstrap) {
				port.postMessage(
					buildBridgeWorkerEntryDegradedHealthEvent({
						requestId: parsedBootstrap.data.requestId,
						message: 'Bridge comm worker runtime was already bootstrapped.',
					}),
				);
				return;
			}
			didReceiveBootstrap = true;
			void productSession.open
				.then((): void => {
					didBootstrapRuntime = true;
					registerBridgeCommWorkerRuntimePortProtocol(
						port,
						runtimePropsFromBootstrapRequest(parsedBootstrap.data, productSession.productTransport),
					);
					port.postMessage(buildBridgeWorkerReadyHealthEvent(parsedBootstrap.data.requestId));
					for (const pendingMessage of pendingMessagesBeforeBootstrap.splice(
						0,
						pendingMessagesBeforeBootstrap.length,
					)) {
						dispatchPendingMessageToRuntime(port, pendingMessage);
					}
				})
				.catch((): void => {
					pendingMessagesBeforeBootstrap.splice(0, pendingMessagesBeforeBootstrap.length);
					port.postMessage(
						buildBridgeWorkerEntryDegradedHealthEvent({
							requestId: parsedBootstrap.data.requestId,
							message: 'Bridge product session open was rejected.',
						}),
					);
				});
			return;
		}

		if (didBootstrapRuntime) {
			return;
		}

		const parsedCommand = bridgeWorkerMainToServerMessageSchema.safeParse(event.data);
		if (parsedCommand.success) {
			pendingMessagesBeforeBootstrap.push(parsedCommand.data);
			port.postMessage(
				buildBridgeWorkerEntryDegradedHealthEvent({
					requestId: parsedCommand.data.requestId,
					message: 'Bridge comm worker command received before bootstrap.',
				}),
			);
			return;
		}

		port.postMessage(
			buildBridgeWorkerEntryDegradedHealthEvent({
				message: 'Bridge comm worker received invalid bootstrap message.',
			}),
		);
	});
	port.start?.();
}

function runtimePropsFromBootstrapRequest(
	request: BridgeCommWorkerBootstrapRequest,
	productTransport: BridgeProductTransportSession,
): RegisterBridgeCommWorkerRuntimePortProtocolProps {
	const reviewPolicy = request.runtime.surfacePolicies?.review;
	const fileViewPolicy = request.runtime.surfacePolicies?.fileView;
	return {
		bridgeDemandRank: reviewPolicy?.bridgeDemandRank ?? request.runtime.bridgeDemandRank,
		budget: reviewPolicy?.budget ?? request.runtime.budget,
		contentItems: request.runtime.contentItems,
		contentRequestDescriptors: request.runtime.contentRequestDescriptors,
		...(fileViewPolicy === undefined
			? {}
			: {
					fileViewBridgeDemandRank: fileViewPolicy.bridgeDemandRank,
					fileViewBudget: fileViewPolicy.budget,
				}),
		...(request.runtime.maxPreparationSliceMs === undefined
			? {}
			: { maxPreparationSliceMs: request.runtime.maxPreparationSliceMs }),
		renderSemantics: request.runtime.renderSemantics,
		rows: request.runtime.rows,
		productTransport,
	};
}

function dispatchPendingMessageToRuntime(port: BridgeCommWorkerPort, data: unknown): void {
	if (port.dispatchEvent === undefined) {
		return;
	}
	port.dispatchEvent(new MessageEvent('message', { data }));
}

function buildBridgeWorkerEntryDegradedHealthEvent(props: {
	readonly requestId?: string;
	readonly message: string;
}): BridgeWorkerServerToMainMessage {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'health',
		...(props.requestId === undefined ? {} : { requestId: props.requestId }),
		status: 'degraded',
		message: props.message,
	};
}

declare const self: BridgeCommWorkerGlobalScope | undefined;

if (typeof self !== 'undefined' && typeof self.addEventListener === 'function') {
	bootstrapBridgeCommWorkerEntry(createBridgeCommWorkerScopePortAdapter(self));
}
