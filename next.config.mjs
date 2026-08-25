import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';
import { readFileSync } from 'fs';
import withSerwistInit from '@serwist/next';

const __dirname = dirname(fileURLToPath(import.meta.url));
// Exposed to the Mobile target only. Desktop reads its version from the Tauri
// bundle and the native iOS app from MARKETING_VERSION, so neither needs this;
// it comes from the single source `npm run check:version` already validates.
const packageVersion = JSON.parse(
  readFileSync(resolve(__dirname, 'package.json'), 'utf8')
).version;

// 三个构建目标：
//   web     —— 部署到 Vercel，保留 middleware、动态路由与重定向
//   desktop —— 静态导出，供 Tauri 打包（见 plans/003-tauri-desktop.md 决策 1）
//   mobile  —— 独立静态导出。iOS 已切换为 SwiftUI 原生（见 docs/PLAN-MOBILE.md），
//              这个 target 目前只剩 `check:build:mobile` 在用它校验原生 iOS 工程
//
// Web Route Handlers 保持 Next 官方约定的 `route.ts` 文件名。静态壳目标不把
// 普通 `.ts` 识别为路由，因此 API、manifest、robots 与 sitemap 不会进入静态
// 导出；共享 page/layout 都是 `.tsx`，桌面专属页使用 `.desktop.tsx`。
// 不使用 `route.web.ts`：Next 本地编译虽然能识别它，但 Vercel 的部署打包阶段
// 会按标准 `route.ts` 产物名查找 manifest，导致 ENOENT。
const requestedBuildTarget = process.env.BUILD_TARGET ?? 'web';
const buildTargets = new Set(['web', 'desktop', 'mobile']);
if (!buildTargets.has(requestedBuildTarget)) {
  throw new Error(
    `Unknown BUILD_TARGET "${requestedBuildTarget}". Expected web, desktop, or mobile.`
  );
}

const isWeb = requestedBuildTarget === 'web';
const isDesktop = requestedBuildTarget === 'desktop';
const isMobile = requestedBuildTarget === 'mobile';
const isStaticShell = isDesktop || isMobile;

// 桌面端的分发渠道，与构建目标正交（见 docs/PLAN-MSSTORE.md 决策 1）：
//   github  —— NSIS / MSI / DMG，走 tauri-plugin-updater 自更新
//   msstore —— MSIX，更新由微软商店负责，应用内入口深链过去
//   macappstore —— Mac App Store，由 App Store 负责安装与更新
// 只有 isDesktop 时才有意义；Web 构建恒为 github，读到它的分支都在桌面端里。
const requestedDesktopChannel = process.env.DESKTOP_CHANNEL;
const desktopChannel =
  isDesktop &&
  (requestedDesktopChannel === 'msstore' ||
    requestedDesktopChannel === 'macappstore')
    ? requestedDesktopChannel
    : 'github';
const isStoreChannel =
  desktopChannel === 'msstore' || desktopChannel === 'macappstore';

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Pin the tracing root to this project; multiple lockfiles exist on the machine.
  outputFileTracingRoot: __dirname,

  pageExtensions: isDesktop
    ? ['desktop.ts', 'desktop.tsx', 'shell.tsx', 'tsx']
    : isMobile
      ? ['mobile.ts', 'mobile.tsx']
      : ['web.ts', 'web.tsx', 'shell.tsx', 'ts', 'tsx'],

  // Expose a per-deploy build id to the client so translation fetches can be
  // versioned, busting stale caches on each deploy. Evaluated once at build time:
  // stable within a deploy (cacheable/offline), unique across deploys.
  env: {
    NEXT_PUBLIC_BUILD_ID:
      process.env.VERCEL_GIT_COMMIT_SHA ||
      process.env.NEXT_PUBLIC_BUILD_ID ||
      String(Date.now()),
    // 构建期即确定运行形态，界面据此选择无边距布局，避免运行时探测造成首帧闪烁。
    NEXT_PUBLIC_BUILD_TARGET: requestedBuildTarget,
    NEXT_PUBLIC_DESKTOP_CHANNEL: desktopChannel,
    NEXT_PUBLIC_APP_VERSION: packageVersion,
  },

  // Desktop 与 Mobile 都不回传任何数据。仅靠条件渲染
  // 无法把 Vercel 的埋点模块从产物中剔除——分支是死代码但模块仍会被打包，
  // 因此在模块解析层直接换成空实现。
  webpack: (config, { webpack }) => {
    if (isStaticShell) {
      config.resolve.alias = {
        ...config.resolve.alias,
        // ⚠️ 裸包名 '@vercel/analytics' 必须单独列一条。ShareDialog 从它引入
        // `track`，只 alias '/react' 会漏掉这个入口——实测桌面产物里因此仍带着
        // Vercel 埋点代码，而这个应用对外承诺「数据不出本机」。
        //
        // 结尾的 `$` 不能省：webpack 的 alias 键默认按**前缀**匹配，写成
        // '@vercel/analytics' 会连 '@vercel/analytics/react' 一起改写成
        // '<stub>/react'，构建直接报 Module not found。`$` 表示精确匹配。
        '@vercel/analytics$': resolve(__dirname, 'lib/analytics-stub.tsx'),
        '@vercel/analytics/react': resolve(__dirname, 'lib/analytics-stub.tsx'),
        '@vercel/speed-insights/next': resolve(
          __dirname,
          'lib/analytics-stub.tsx'
        ),
      };
    }
    if (isMobile) {
      const storeBadgesStub = resolve(
        __dirname,
        'components/store-badges-stub.tsx'
      );
      const mobileNotifications = resolve(
        __dirname,
        'lib/mobile-notifications.ts'
      );
      const mobileDesktopState = resolve(
        __dirname,
        'lib/mobile-desktop-state-stub.ts'
      );
      const desktopUpdaterStub = resolve(
        __dirname,
        'lib/desktop-updater-stub.ts'
      );
      const mobileTauriOpener = resolve(
        __dirname,
        'lib/mobile-tauri-opener-stub.ts'
      );
      config.resolve.alias = {
        ...config.resolve.alias,
        '@/lib/notify': mobileNotifications,
        '@/lib/desktop-state': mobileDesktopState,
        '@/lib/desktop-updater': desktopUpdaterStub,
        '@tauri-apps/plugin-opener': mobileTauriOpener,
        '@tauri-apps/plugin-os': mobileTauriOpener,
        '@tauri-apps/api/app': mobileTauriOpener,
      };
      config.plugins.push(
        new webpack.NormalModuleReplacementPlugin(
          /[\\/]components[\\/](?:MacAppStoreBadge|MicrosoftStoreBadge)(?:\.tsx)?$/,
          storeBadgesStub
        ),
        new webpack.NormalModuleReplacementPlugin(
          /(?:^@\/|[\\/])lib[\\/]notify(?:\.ts)?$/,
          mobileNotifications
        ),
        new webpack.NormalModuleReplacementPlugin(
          /(?:^@\/|[\\/])lib[\\/]desktop-state(?:\.ts)?$/,
          mobileDesktopState
        ),
        new webpack.NormalModuleReplacementPlugin(
          /(?:^@\/|[\\/])lib[\\/]desktop-updater(?:\.ts)?$/,
          desktopUpdaterStub
        )
      );
    }
    // 商店版不含更新器与重启插件：把整层桌面更新适配器替掉，不能只 alias
    // plugin-updater。否则调用方里的 downloadAndInstall 等代码仍会留在 chunk 中。
    if (isStoreChannel) {
      const desktopUpdaterStub = resolve(
        __dirname,
        'lib/desktop-updater-stub.ts'
      );
      const downloadMirrorStub = resolve(
        __dirname,
        'lib/download-mirror-stub.ts'
      );
      config.resolve.alias = {
        ...config.resolve.alias,
        '@/lib/desktop-updater': desktopUpdaterStub,
        '@/lib/download-mirror': downloadMirrorStub,
      };
      // tsconfig paths may resolve `@/` to an absolute filename before webpack's
      // alias table sees it. Replace both request forms so the real adapter can
      // never enter a Store chunk.
      config.plugins.push(
        new webpack.NormalModuleReplacementPlugin(
          /(?:^@\/|[\\/])lib[\\/]desktop-updater(?:\.ts)?$/,
          desktopUpdaterStub
        ),
        new webpack.NormalModuleReplacementPlugin(
          /(?:^@\/|[\\/])lib[\\/]download-mirror(?:\.ts)?$/,
          downloadMirrorStub
        )
      );
    }
    return config;
  },

  ...(isStaticShell
    ? {
        output: 'export',
        // 壳内 WebView 不显示 Next.js 的悬浮开发按钮；错误仍会正常输出到
        // 终端和错误覆盖层。
        devIndicators: false,
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
  // 开发环境禁用；两个静态壳的资源本就在安装包内，也不注册 Web Service Worker。
  disable: process.env.NODE_ENV === 'development' || !isWeb,
  // Auto-register the worker (default), replacing next-pwa's `register: true`.
  register: true,
});

export default withSerwist(nextConfig);
