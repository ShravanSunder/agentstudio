import type { APIRoute } from "astro";

import { canonicalHomeUrl } from "@/site-metadata";

export const prerender = true;

export const GET: APIRoute = (): Response => {
  const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${canonicalHomeUrl}</loc>
  </url>
</urlset>
`;

  return new Response(sitemap, {
    headers: {
      "Content-Type": "application/xml; charset=utf-8",
    },
  });
};
