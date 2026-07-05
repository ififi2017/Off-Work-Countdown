import type { PrecacheEntry, RuntimeCaching, SerwistGlobalConfig } from "serwist";
import {
  CacheFirst,
  ExpirationPlugin,
  NetworkFirst,
  Serwist,
  StaleWhileRevalidate,
} from "serwist";

declare global {
  interface WorkerGlobalScope extends SerwistGlobalConfig {
    // Injected by @serwist/next at build time.
    __SW_MANIFEST: (PrecacheEntry | string)[] | undefined;
  }
}

declare const self: ServiceWorkerGlobalScope;

const ONE_DAY = 24 * 60 * 60;
const ONE_WEEK = 7 * ONE_DAY;

// Runtime caching, migrated 1:1 from the previous next-pwa configuration.
const runtimeCaching: RuntimeCaching[] = [
  {
    // Static build assets: serve from cache first for instant, offline-capable loads.
    matcher: ({ url, sameOrigin }) =>
      sameOrigin && url.pathname.startsWith("/_next/static/"),
    handler: new CacheFirst({
      cacheName: "static-assets",
      plugins: [new ExpirationPlugin({ maxEntries: 64, maxAgeSeconds: ONE_DAY })],
    }),
  },
  {
    // Optimized images from the Next.js image pipeline.
    matcher: ({ url, sameOrigin }) =>
      sameOrigin && url.pathname.startsWith("/_next/image"),
    handler: new CacheFirst({
      cacheName: "next-image",
      plugins: [new ExpirationPlugin({ maxEntries: 64, maxAgeSeconds: ONE_DAY })],
    }),
  },
  {
    // Translation files: render immediately from cache, refresh in the background.
    matcher: ({ url, sameOrigin }) =>
      sameOrigin && url.pathname.startsWith("/locales/"),
    handler: new StaleWhileRevalidate({
      cacheName: "locales",
      plugins: [new ExpirationPlugin({ maxEntries: 64, maxAgeSeconds: ONE_WEEK })],
    }),
  },
  {
    // API routes: prefer the network, fall back to cache when offline.
    matcher: ({ url, sameOrigin }) =>
      sameOrigin && url.pathname.startsWith("/api/"),
    handler: new NetworkFirst({
      cacheName: "apis",
      networkTimeoutSeconds: 10,
      plugins: [new ExpirationPlugin({ maxEntries: 32, maxAgeSeconds: ONE_DAY })],
    }),
  },
  {
    // Page navigations: network first, fall back to cache so the PWA opens offline.
    matcher: ({ request, sameOrigin }) =>
      sameOrigin && request.mode === "navigate",
    handler: new NetworkFirst({
      cacheName: "pages",
      networkTimeoutSeconds: 10,
      plugins: [new ExpirationPlugin({ maxEntries: 32, maxAgeSeconds: ONE_DAY })],
    }),
  },
];

const serwist = new Serwist({
  precacheEntries: self.__SW_MANIFEST,
  skipWaiting: true,
  clientsClaim: true,
  navigationPreload: true,
  runtimeCaching,
});

serwist.addEventListeners();
