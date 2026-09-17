import type { NextConfig } from "next";
import { initOpenNextCloudflareForDev } from "@opennextjs/cloudflare";

const nextConfig: NextConfig = {
  // Set when the app is mounted under a path prefix behind a reverse proxy -
  // the repo-root image serves it at /readme so the whole stack fits on a
  // single host:port. Must be set at build time as well as at runtime.
  basePath: process.env.NEXT_BASE_PATH || undefined,
};

export default nextConfig;

// added by create cloudflare to enable calling `getCloudflareContext()` in `next dev`.
// It spawns workerd, which is only available - and only wanted - in the
// Cloudflare dev server, so keep it out of `next build` and `next start`.
if (process.env.NODE_ENV === "development") {
  initOpenNextCloudflareForDev();
}
