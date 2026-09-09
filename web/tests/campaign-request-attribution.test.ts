import { describe, expect, it, vi } from "vitest";

import {
  aggregateCampaignDimension,
  createCampaignRequestDataPoint,
  resolveCampaignRequestRoute,
} from "../src/campaign-attribution/campaign-request-attribution";
import worker, {
  type CampaignRequestWorkerEnvironment,
} from "../src/campaign-attribution/campaign-request-worker";

const createEnvironment = (
  response: Response,
): CampaignRequestWorkerEnvironment & { readonly writeDataPoint: ReturnType<typeof vi.fn> } => {
  const writeDataPoint = vi.fn();
  return {
    ANALYTICS: { writeDataPoint },
    ASSETS: { fetch: vi.fn(async () => response) },
    writeDataPoint,
  };
};

describe("campaign request attribution", () => {
  it("resolves creative and aggregate paths without accepting unknown codes", () => {
    expect(resolveCampaignRequestRoute("/x/73uz").kind).toBe("creative");
    expect(resolveCampaignRequestRoute("/yt")).toEqual({
      channel: "yt",
      kind: "channel-aggregate",
      path: "/yt",
    });
    expect(resolveCampaignRequestRoute("/x/zzzz")).toEqual({ kind: "unknown" });
    expect(resolveCampaignRequestRoute("/x/")).toEqual({ kind: "unknown" });
  });

  it("constructs fixed creative and aggregate datapoints", () => {
    const creative = resolveCampaignRequestRoute("/x/73uz");
    const aggregate = resolveCampaignRequestRoute("/x");
    if (creative.kind === "unknown" || aggregate.kind === "unknown") {
      throw new Error("fixture routes must resolve");
    }

    expect(createCampaignRequestDataPoint(creative)).toEqual({
      blobs: ["creative", "x", "launch-week", "launch-overview", "default", "post"],
      doubles: [1],
      indexes: ["/x/73uz"],
    });
    expect(createCampaignRequestDataPoint(aggregate).blobs).toEqual([
      "channel-aggregate",
      "x",
      aggregateCampaignDimension,
      aggregateCampaignDimension,
      aggregateCampaignDimension,
      aggregateCampaignDimension,
    ]);
  });

  it("writes once after a successful known GET while ignoring query strings", async () => {
    const environment = createEnvironment(new Response("ok", { status: 200 }));

    const response = await worker.fetch?.(
      new Request("https://example.test/x/73uz?proof=1"),
      environment,
    );

    expect(response?.status).toBe(200);
    expect(environment.ASSETS.fetch).toHaveBeenCalledTimes(1);
    expect(environment.writeDataPoint).toHaveBeenCalledTimes(1);
    expect(environment.writeDataPoint).toHaveBeenCalledWith(
      expect.objectContaining({ indexes: ["/x/73uz"] }),
    );
  });

  it("does not write for unknown, non-GET, or non-200 responses", async () => {
    const unknownEnvironment = createEnvironment(new Response("fallback", { status: 200 }));
    await worker.fetch?.(new Request("https://example.test/x/zzzz"), unknownEnvironment);
    expect(unknownEnvironment.writeDataPoint).not.toHaveBeenCalled();

    const postEnvironment = createEnvironment(new Response("ok", { status: 200 }));
    await worker.fetch?.(
      new Request("https://example.test/x/73uz", { method: "POST" }),
      postEnvironment,
    );
    expect(postEnvironment.writeDataPoint).not.toHaveBeenCalled();

    const notFoundEnvironment = createEnvironment(new Response("missing", { status: 404 }));
    await worker.fetch?.(new Request("https://example.test/x/73uz"), notFoundEnvironment);
    expect(notFoundEnvironment.writeDataPoint).not.toHaveBeenCalled();
  });

  it("propagates asset failures without attempting analytics", async () => {
    const writeDataPoint = vi.fn();
    const environment: CampaignRequestWorkerEnvironment = {
      ANALYTICS: { writeDataPoint },
      ASSETS: {
        fetch: vi.fn(async (): Promise<Response> => {
          throw new Error("asset unavailable");
        }),
      },
    };

    await expect(
      worker.fetch?.(new Request("https://example.test/x/73uz"), environment),
    ).rejects.toThrow("asset unavailable");
    expect(writeDataPoint).not.toHaveBeenCalled();
  });

  it("returns the asset response when analytics throws", async () => {
    const response = new Response("unchanged", { status: 200, headers: { "x-proof": "yes" } });
    const environment = createEnvironment(response);
    environment.writeDataPoint.mockImplementation(() => {
      throw new Error("analytics unavailable");
    });

    const result = await worker.fetch?.(new Request("https://example.test/x/73uz"), environment);

    expect(result).toBe(response);
    expect(await result?.text()).toBe("unchanged");
    expect(result?.headers.get("x-proof")).toBe("yes");
  });
});
