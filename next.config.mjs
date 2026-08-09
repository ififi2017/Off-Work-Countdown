import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';
import withSerwistInit from '@serwist/next';

const __dirname = dirname(fileURLToPath(import.meta.url));

// 两个构建目标：
//   web     —— 部署到 Vercel，保留 middleware、动态路由与重定向
//   desktop —— 静态导出，供 Tauri 打包（见 docs/PLAN-M5-TAURI.md 决策 1）
//
// Web Route Handlers 保持 Next 官方约定的 `route.ts` 文件名。桌面目标不把
// 普通 `.ts` 识别为路由，因此 API、manifest、robots 与 sitemap 不会进入静态
// 导出；共享 page/layout 都是 `.tsx`，桌面专属页使用 `.desktop.tsx`。
// 不使用 `route.web.ts`：Next 本地编译虽然能识别它，但 Vercel 的部署打包阶段
// 会按标准 `route.ts` 产物名查找 manifest，导致 ENOENT。
const isDesktop = process.env.BUILD_TARGET === 'desktop';

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Pin the tracing root to this project; multiple lockfiles exist on the machine.
  outputFileTracingRoot: __dirname,

  pageExtensions: isDesktop
    ? ['desktop.ts', 'desktop.tsx', 'tsx']
    : ['ts', 'tsx'],

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

  // 桌面端不回传任何数据（见 docs/PLAN-M5-TAURI.md 决策 5）。仅靠条件渲染
  // 无法把 Vercel 的埋点模块从产物中剔除——分支是死代码但模块仍会被打包，
  // 因此在模块解析层直接换成空实现。
  webpack: (config) => {
    if (isDesktop) {
      config.resolve.alias = {
        ...config.resolve.alias,
        '@vercel/analytics/react': resolve(__dirname, 'lib/analytics-stub.tsx'),
        '@vercel/speed-insights/next': resolve(
          __dirname,
          'lib/analytics-stub.tsx'
        ),
      };
    }
    return config;
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
