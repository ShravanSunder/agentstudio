import type { FileContents } from '@pierre/diffs';
import { z } from 'zod';

import { bridgePierreOptionalHighlightLanguage } from './bridge-pierre-language-normalization.js';

export const bridgePierreContentDescriptorSchema = z
	.object({
		contentHash: z.string().min(1),
		contentHashAlgorithm: z.string().min(1),
		generation: z.number().int().nonnegative(),
		maxBytes: z.number().int().positive(),
		resourceUrl: z.string().regex(/^agentstudio:\/\/resource\/review\/content\//u),
	})
	.strict();

export type BridgePierreContentDescriptor = z.infer<typeof bridgePierreContentDescriptorSchema>;

export const bridgePierreContentDescriptorFileSchema = z
	.object({
		bridgeContentDescriptor: bridgePierreContentDescriptorSchema,
		cacheKey: z.string().min(1),
		contents: z.string(),
		lang: z
			.custom<NonNullable<FileContents['lang']>>(
				(value): boolean => typeof value === 'string' && value.length > 0,
			)
			.optional(),
		name: z.string().min(1),
	})
	.passthrough();

export type BridgePierreContentDescriptorFile = FileContents & {
	readonly bridgeContentDescriptor: BridgePierreContentDescriptor;
	readonly cacheKey: string;
};

export interface CreateBridgePierreContentDescriptorFileProps extends BridgePierreContentDescriptor {
	readonly cacheKey: string;
	readonly lang?: FileContents['lang'] | null;
	readonly lineCount: number | null;
	readonly name: string;
	readonly text?: string;
}

export interface ReplaceBridgePierreContentDescriptorFileContentsProps {
	readonly file: BridgePierreContentDescriptorFile;
	readonly text: string;
}

export interface BridgePierreWorkerContentDescriptorDataset {
	bridgePierreWorkerContentFetchProbeResult?: string;
	bridgePierreWorkerContentFetchProbeFailureReason?: string;
	bridgePierreWorkerContentFetchProbeSuccessCount?: string;
	bridgePierreWorkerContentFetchProbeFailureCount?: string;
}

export interface BridgePierreWorkerContentDescriptorDatasetTarget {
	readonly dataset: BridgePierreWorkerContentDescriptorDataset;
}

export function createBridgePierreContentDescriptorFile(
	props: CreateBridgePierreContentDescriptorFileProps,
): BridgePierreContentDescriptorFile {
	const normalizedLanguage = bridgePierreOptionalHighlightLanguage(props.lang);
	const file: BridgePierreContentDescriptorFile = {
		name: props.name,
		contents: props.text ?? contentLineSkeleton(props.lineCount),
		cacheKey: props.cacheKey,
		...(normalizedLanguage === undefined ? {} : { lang: normalizedLanguage }),
		bridgeContentDescriptor: {
			contentHash: props.contentHash,
			contentHashAlgorithm: props.contentHashAlgorithm,
			generation: props.generation,
			maxBytes: props.maxBytes,
			resourceUrl: props.resourceUrl,
		},
	};
	bridgePierreContentDescriptorFileSchema.parse(file);
	return file;
}

export function replaceBridgePierreContentDescriptorFileContents(
	props: ReplaceBridgePierreContentDescriptorFileContentsProps,
): FileContents {
	const normalizedLanguage = bridgePierreOptionalHighlightLanguage(props.file.lang);
	return {
		name: props.file.name,
		contents: props.text,
		cacheKey: props.file.cacheKey,
		...(normalizedLanguage === undefined ? {} : { lang: normalizedLanguage }),
	};
}

export function bridgePierreWorkerContentDescriptorFetchIsEnabled(
	target: BridgePierreWorkerContentDescriptorDatasetTarget | undefined = defaultDatasetTarget(),
): boolean {
	return target?.dataset.bridgePierreWorkerContentFetchProbeResult === 'success';
}

export function writeBridgePierreWorkerContentFetchProbeSnapshotToDataset(props: {
	readonly failureReason: string;
	readonly result: 'failed' | 'success';
	readonly rootElement: BridgePierreWorkerContentDescriptorDatasetTarget;
}): void {
	const dataset = props.rootElement.dataset;
	dataset.bridgePierreWorkerContentFetchProbeResult = props.result;
	dataset.bridgePierreWorkerContentFetchProbeFailureReason = props.failureReason;
	const counterKey =
		props.result === 'success'
			? 'bridgePierreWorkerContentFetchProbeSuccessCount'
			: 'bridgePierreWorkerContentFetchProbeFailureCount';
	const previousCount = Number.parseInt(dataset[counterKey] ?? '0', 10);
	dataset[counterKey] = String(Number.isFinite(previousCount) ? previousCount + 1 : 1);
}

export const bridgePierreWorkerContentDescriptorSource = `
;(() => {
  const bridgeDescriptorKey = "bridgeContentDescriptor";
  const bridgePostDiagnostic = (payload) => {
    try {
      self.postMessage({ type: "bridge-diagnostic", ...payload });
    } catch {}
  };
  const bridgeToken = (value) => {
    if (typeof value !== "string" || value.length === 0) {
      return "unknown";
    }
    const token = value.replace(/[^A-Za-z0-9_.-]/gu, "_").slice(0, 64);
    return token.length > 0 ? token : "unknown";
  };
  const bridgeAllowedDescriptor = (descriptor) => {
    if (typeof descriptor !== "object" || descriptor === null) {
      return null;
    }
    if (typeof descriptor.resourceUrl !== "string" || !descriptor.resourceUrl.startsWith("agentstudio://resource/review/content/")) {
      return null;
    }
    if (!Number.isSafeInteger(descriptor.generation) || descriptor.generation < 0) {
      return null;
    }
    if (!Number.isSafeInteger(descriptor.maxBytes) || descriptor.maxBytes <= 0) {
      return null;
    }
    if (typeof descriptor.contentHash !== "string" || descriptor.contentHash.length === 0) {
      return null;
    }
    return descriptor;
  };
  const bridgeRequestGenerationMatchesUrl = (descriptor) => {
    try {
      const parsedUrl = new URL(descriptor.resourceUrl);
      return parsedUrl.searchParams.get("generation") === String(descriptor.generation);
    } catch {
      return false;
    }
  };
  const bridgeReadText = async (response, maxBytes) => {
    if (response.body === null) {
      throw new Error("missing_body");
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let byteLength = 0;
    let text = "";
    try {
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) {
          break;
        }
        byteLength += chunk.value.byteLength;
        if (byteLength > maxBytes) {
          throw new Error("byte_limit_exceeded");
        }
        text += decoder.decode(chunk.value, { stream: true });
      }
      text += decoder.decode();
      return { byteLength, text };
    } finally {
      reader.releaseLock();
    }
  };
  self.addEventListener("message", (event) => {
    const request = event.data;
    const file = request?.type === "file" ? request.file : null;
    const descriptor = bridgeAllowedDescriptor(file?.[bridgeDescriptorKey]);
    if (descriptor === null) {
      return;
    }
    event.stopImmediatePropagation();
    void (async () => {
      try {
        if (!bridgeRequestGenerationMatchesUrl(descriptor)) {
          throw new Error("generation_mismatch");
        }
        const response = await fetch(descriptor.resourceUrl);
        if (!response.ok) {
          throw new Error("http_error");
        }
        const result = await bridgeReadText(response, descriptor.maxBytes);
        bridgePostDiagnostic({
          requestType: "bridge-worker-content-fetch-probe",
          phase: "success",
          result: "success",
        });
        const forwardedFile = {
          ...file,
          contents: result.text,
        };
        delete forwardedFile[bridgeDescriptorKey];
        self.dispatchEvent(new MessageEvent("message", {
          data: {
            ...request,
            file: forwardedFile,
          },
        }));
      } catch (error) {
        bridgePostDiagnostic({
          requestType: "bridge-worker-content-fetch-probe",
          phase: "failed",
          result: "failed",
          failureReason: bridgeToken(error instanceof Error ? error.message : "unknown"),
        });
        const fallbackFile = { ...file };
        delete fallbackFile[bridgeDescriptorKey];
        self.dispatchEvent(new MessageEvent("message", {
          data: {
            ...request,
            file: fallbackFile,
          },
        }));
      }
    })();
  }, true);
})();
`.trim();

function contentLineSkeleton(lineCount: number | null): string {
	if (lineCount === null || lineCount <= 0) {
		return '';
	}
	return '\n'.repeat(lineCount);
}

function defaultDatasetTarget(): BridgePierreWorkerContentDescriptorDatasetTarget | undefined {
	return typeof document === 'undefined' ? undefined : document.documentElement;
}
