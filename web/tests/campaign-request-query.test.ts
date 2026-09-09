import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

import { describe, expect, it, vi } from "vitest";

import {
  buildCampaignRequestQuery,
  executeCampaignRequestQuery,
} from "../scripts/query-campaign-request-analytics";

const timeWindow = {
  from: "2026-08-28T00:00:00Z",
  to: "2026-08-29T00:00:00Z",
} as const;

describe("campaign request owner query", () => {
  it("starts through the declared native Node command and sanitizes missing credentials", () => {
    const environment = { ...process.env };
    delete environment["CLOUDFLARE_ACCOUNT_ID"];
    delete environment["CLOUDFLARE_API_TOKEN"];

    const result = spawnSync(
      process.execPath,
      [
        "--experimental-strip-types",
        resolve(import.meta.dirname, "../scripts/query-campaign-request-analytics.ts"),
        "--from",
        timeWindow.from,
        "--to",
        timeWindow.to,
        "--group",
        "total",
      ],
      { encoding: "utf8", env: environment, timeout: 10_000 },
    );

    expect(result.status).toBe(1);
    expect(result.stderr).toBe(
      "Campaign analytics query failed. Verify the time window, network access, and private credentials.\n",
    );
    expect(result.stderr).not.toContain("ERR_MODULE_NOT_FOUND");
  });

  it("uses sampling-aware totals and stable creative aliases", () => {
    const query = buildCampaignRequestQuery({ ...timeWindow, group: "creative" });

    expect(query).toContain('sum(_sample_interval) AS "campaign_path_requests"');
    expect(query).toContain("blob1 AS route_kind");
    expect(query).toContain("blob6 AS placement");
    expect(query).toContain("FROM agent_studio_campaign_requests");
    expect(query).toContain("WHERE timestamp >= toDateTime('2026-08-28 00:00:00', 'UTC')");
    expect(query).toContain("AND timestamp < toDateTime('2026-08-29 00:00:00', 'UTC')");
    expect(query).not.toContain("2026-08-28T00:00:00Z");
    expect(query).toContain("GROUP BY route_kind, channel, campaign, creative, variant, placement");
  });

  it("rejects missing, reversed, or over-retention time windows", () => {
    expect(() =>
      buildCampaignRequestQuery({
        from: "2026-08-29T00:00:00Z",
        group: "total",
        to: "2026-08-28T00:00:00Z",
      }),
    ).toThrow(/time window/i);

    expect(() =>
      buildCampaignRequestQuery({
        from: "2026-01-01T00:00:00Z",
        group: "total",
        to: "2026-08-29T00:00:00Z",
      }),
    ).toThrow(/93 days/i);
  });

  it("sends credentials only in the private request and redacts failed responses", async () => {
    const request = vi.fn(
      async (): Promise<Response> => new Response("private error", { status: 403 }),
    );

    await expect(
      executeCampaignRequestQuery(
        { ...timeWindow, group: "path" },
        "private-account",
        "private-token",
        request,
      ),
    ).rejects.toThrow("Cloudflare campaign analytics query failed with HTTP 403");

    expect(request).toHaveBeenCalledWith(
      expect.stringContaining("private-account"),
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: "Bearer private-token" }),
      }),
    );
  });
});
