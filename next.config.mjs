import withPWA from 'next-pwa';

/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      {
        source: "/locales/:path*",
        destination: "/locales/:path*",
      },
      {
        source: "/robots.txt",
        destination: "/robots.txt",
      },
      {
        source: "/sitemap.xml",
        destination: "/sitemap.xml",
      },
      {
        source: "/hreflang-sitemap.xml",
        destination: "/hreflang-sitemap.xml",
      },
    ];
  },
};

export default withPWA({
  dest: 'public',
  register: true,
  skipWaiting: true,
  disable: process.env.NODE_ENV === 'development',
  buildExcludes: [
    /middleware-manifest\.json$/,
    /app-build-manifest\.json$/
  ],
  runtimeCaching: [
    {
      urlPattern: /^https:\/\/off-work-30.*\/_next\/static\/.*/i,
      handler: 'CacheFirst',
      options: {
        cacheName: 'static-assets',
        expiration: {
          maxEntries: 64,
          maxAgeSeconds: 24 * 60 * 60 // 24 hours
        }
      }
    },
    {
      urlPattern: /^https:\/\/off-work-30.*\/_next\/image\?.*/i,
      handler: 'CacheFirst',
      options: {
        cacheName: 'next-image',
        expiration: {
          maxEntries: 64,
          maxAgeSeconds: 24 * 60 * 60 // 24 hours
        }
      }
    },
    {
      urlPattern: /^https:\/\/off-work-30.*\/api\/.*/i,
      handler: 'NetworkFirst',
      options: {
        cacheName: 'apis',
        expiration: {
          maxEntries: 32,
          maxAgeSeconds: 24 * 60 * 60 // 24 hours
        },
        networkTimeoutSeconds: 10
      }
    }
  ]
})(nextConfig);