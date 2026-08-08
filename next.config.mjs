import { fileURLToPath } from 'url';
import { dirname } from 'path';
import withSerwistInit from '@serwist/next';

const __dirname = dirname(fileURLToPath(import.meta.url));

// 两个构建目标：
//   web     —— 部署到 Vercel，保留 middleware、动态路由与重定向
//   desktop —— 静态导出，供 Tauri 打包（见 docs/PLAN-M5-TAURI.md 决策 1）
//
// 桌面端排除 Web 专属路由的机制是 pageExtensions：这些文件命名为
// `*.web.ts`，只有 web 目标把该后缀视为路由，desktop 目标看不见它们。
// 这样不需要在构建期搬动文件，工作区始终保持干净。
const isDesktop = process.env.BUILD_TARGET === 'desktop';

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Pin the tracing root to this project; multiple lockfiles exist on the machine.
  outputFileTracingRoot: __dirname,

  pageExtensions: isDesktop
    ? ['ts', 'tsx']
    : ['web.ts', 'web.tsx', 'ts', 'tsx'],

  // Expose a per-deploy build id to the client so translation fetches can be
  // versioned, busting stale caches on each deploy. Evaluated once at build time:
  // stable within a deploy (cacheable/offline), unique across deploys.
  env: {
    NEXT_PUBLIC_BUILD_ID:
      process.env.VERCEL_GIT_COMMIT_SHA ||
      process.env.NEXT_PUBLIC_BUILD_ID ||
      String(Date.now()),
    // 构建期即确定运行形态，界面据此选择无边距布局，避免运行时探测造成首帧闪烁。
    NEXT_PUBLIC_BUILD_TARGET: isDesktop ? 'desktop' : 'web',
  },

  ...(isDesktop
    ? {
        output: 'export',
      }
    : {
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
      }),
};

const withSerwist = withSerwistInit({
  // Service worker source and output. Runtime caching lives in app/sw.ts.
  swSrc: 'app/sw.ts',
  swDest: 'public/sw.js',
  // 开发环境禁用；桌面端也不需要——Tauri 自带更新机制，且资源本就在本地。
  disable: process.env.NODE_ENV === 'development' || isDesktop,
  // Auto-register the worker (default), replacing next-pwa's `register: true`.
  register: true,
});

export default withSerwist(nextConfig);
