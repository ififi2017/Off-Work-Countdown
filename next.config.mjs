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
  async redirects() {
    return [
      {
        // /hreflang-sitemap.xml 已并入 /sitemap.xml 的 alternates。该 URL 曾写在
        // robots.txt 里，搜索引擎大概率已收录，给它一个 301 而不是让 middleware
        // 加上语言前缀重定向到不存在的路径。next.config 的 redirects 先于
        // middleware 执行，因此这里能拦下。
        source: '/hreflang-sitemap.xml',
        destination: '/sitemap.xml',
        permanent: true,
      },
    ];
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
