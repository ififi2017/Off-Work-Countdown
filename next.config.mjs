import { fileURLToPath } from 'url';
import { dirname } from 'path';
import withSerwistInit from '@serwist/next';

const __dirname = dirname(fileURLToPath(import.meta.url));

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Pin the tracing root to this project; multiple lockfiles exist on the machine.
  outputFileTracingRoot: __dirname,
  // Expose a per-deploy build id to the client so translation fetches can be
  // versioned, busting stale caches on each deploy. Evaluated once at build time:
  // stable within a deploy (cacheable/offline), unique across deploys.
  env: {
    NEXT_PUBLIC_BUILD_ID:
      process.env.VERCEL_GIT_COMMIT_SHA ||
      process.env.NEXT_PUBLIC_BUILD_ID ||
      String(Date.now()),
  },
};

const withSerwist = withSerwistInit({
  // Service worker source and output. Runtime caching lives in app/sw.ts.
  swSrc: 'app/sw.ts',
  swDest: 'public/sw.js',
  // Disable the service worker in development, matching the previous next-pwa setup.
  disable: process.env.NODE_ENV === 'development',
  // Auto-register the worker (default), replacing next-pwa's `register: true`.
  register: true,
});

export default withSerwist(nextConfig);
