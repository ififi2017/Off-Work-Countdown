if(!self.define){let e,s={};const a=(a,n)=>(a=new URL(a+".js",n).href,s[a]||new Promise((s=>{if("document"in self){const e=document.createElement("script");e.src=a,e.onload=s,document.head.appendChild(e)}else e=a,importScripts(a),s()})).then((()=>{let e=s[a];if(!e)throw new Error(`Module ${a} didn’t register its module`);return e})));self.define=(n,c)=>{const i=e||("document"in self?document.currentScript.src:"")||location.href;if(s[i])return;let o={};const t=e=>a(e,i),r={module:{uri:i},exports:o,require:t};s[i]=Promise.all(n.map((e=>r[e]||t(e)))).then((e=>(c(...e),o)))}}define(["./workbox-4754cb34"],(function(e){"use strict";importScripts(),self.skipWaiting(),e.clientsClaim(),e.precacheAndRoute([{url:"/_next/app-build-manifest.json",revision:"f7f62ce406cbc7e0c720ac6a1bd51e06"},{url:"/_next/static/Hc8bfF0PIechqUuY7D7NS/_buildManifest.js",revision:"97560e2b25bf94206370e61bf65f7595"},{url:"/_next/static/Hc8bfF0PIechqUuY7D7NS/_ssgManifest.js",revision:"b6652df95db52feb4daf4eca35380933"},{url:"/_next/static/chunks/23-c79033f812a17099.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/389-9f8e77f9c99b453f.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/676-19a91e0db599d1ec.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/app/%5Blang%5D/layout-80c066aa2f68c20c.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/app/%5Blang%5D/page-2b13ae78fe4396ed.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/app/_not-found/page-3d23e5cfbcc8f238.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/app/layout-1fedd3aea6311e1a.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/fd9d1056-844a5cc198651369.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/framework-f66176bb897dc684.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/main-app-7015af0a295111d9.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/main-c77071528c32fca2.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/pages/_app-6a626577ffa902a4.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/pages/_error-1be831200e60c5c0.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/chunks/polyfills-78c92fac7aa8fdd8.js",revision:"79330112775102f91e1010318bae2bd3"},{url:"/_next/static/chunks/webpack-76a560eb82b18f34.js",revision:"Hc8bfF0PIechqUuY7D7NS"},{url:"/_next/static/css/9d947dd94c110d36.css",revision:"9d947dd94c110d36"},{url:"/_next/static/media/4473ecc91f70f139-s.p.woff",revision:"78e6fc13ea317b55ab0bd6dc4849c110"},{url:"/_next/static/media/463dafcda517f24f-s.p.woff",revision:"cbeb6d2d96eaa268b4b5beb0b46d9632"},{url:"/icon-192x192.png",revision:"baeef1ffa1a13ae617b33f65b08cf6cf"},{url:"/icon-512x512.png",revision:"baeef1ffa1a13ae617b33f65b08cf6cf"},{url:"/locales/de/seo.json",revision:"fa1b5dbfb0c5b4f29f521be5a8aadfbe"},{url:"/locales/de/translation.json",revision:"86340b9fefd6d0d32c5fb7a3ec8e9af8"},{url:"/locales/en/seo.json",revision:"2765d25a019f77a071168b501fb2d87b"},{url:"/locales/en/translation.json",revision:"f9387c562f3bf17c0fe863ef8405ab66"},{url:"/locales/es/seo.json",revision:"9fc0081c20054510638ed312b49f55d1"},{url:"/locales/es/translation.json",revision:"44606774fd47ab20e28a447a029bd344"},{url:"/locales/fr/seo.json",revision:"4921d85f611c3f856b20879537f88398"},{url:"/locales/fr/translation.json",revision:"7c784c58ac27d4865bb3a3623d4a965e"},{url:"/locales/hi-IN/seo.json",revision:"73a4bb5f7bde85999e7223614f1be937"},{url:"/locales/hi-IN/translation.json",revision:"9985b213d515c6e39867fd722f10f545"},{url:"/locales/it/seo.json",revision:"71c0cdc3cbe432de9f5f33e8d1df3a43"},{url:"/locales/it/translation.json",revision:"fbdbe58463b06c542322ec100b540a53"},{url:"/locales/ja/seo.json",revision:"e97eddf0e6d3292f5f524487bcf93501"},{url:"/locales/ja/translation.json",revision:"f1e8ab5939c19aea806d8d1bc2f7d06e"},{url:"/locales/ko/seo.json",revision:"2bff6af7dbb36d7985e483169bd229ab"},{url:"/locales/ko/translation.json",revision:"2f5b25fd660c1dbe3c82507488bf7b38"},{url:"/locales/mr-IN/seo.json",revision:"1610e1c1fc86212e8c2c77be768f7a45"},{url:"/locales/mr-IN/translation.json",revision:"e0a2a5580477800ad14043618f0036ca"},{url:"/locales/pt/seo.json",revision:"ebaabd16dd965df0a6dfa69590c09e2b"},{url:"/locales/pt/translation.json",revision:"346d93d83cef2e94eafb3a5e4dffe92d"},{url:"/locales/ru/seo.json",revision:"451cf7d1a4fe65f9f73f283333cea997"},{url:"/locales/ru/translation.json",revision:"5a6f529b72a0f7c92e5b07df9545c36f"},{url:"/locales/zh-CN/seo.json",revision:"c121286c1b5df1560b3bb06079bb5e32"},{url:"/locales/zh-CN/translation.json",revision:"aed04509e357e1b0fe4fb8ef61ea496a"},{url:"/locales/zh-HK/seo.json",revision:"a2c602ce1833bcb28e18b21ec5fe0954"},{url:"/locales/zh-HK/translation.json",revision:"a5b3ba0df09085cfded247e92a597242"},{url:"/locales/zh-TW/seo.json",revision:"7675267601e20016ae621f340de563ef"},{url:"/locales/zh-TW/translation.json",revision:"ef8042adb53113fc7dfce85c2a37a917"},{url:"/manifest.json",revision:"c062d3890dffa906ad2423c3b3f5544e"},{url:"/robots.txt",revision:"80ff412037c6331167fd5775f5b76da0"}],{ignoreURLParametersMatching:[]}),e.cleanupOutdatedCaches(),e.registerRoute("/",new e.NetworkFirst({cacheName:"start-url",plugins:[{cacheWillUpdate:async({request:e,response:s,event:a,state:n})=>s&&"opaqueredirect"===s.type?new Response(s.body,{status:200,statusText:"OK",headers:s.headers}):s}]}),"GET"),e.registerRoute(/^https:\/\/fonts\.(?:gstatic)\.com\/.*/i,new e.CacheFirst({cacheName:"google-fonts-webfonts",plugins:[new e.ExpirationPlugin({maxEntries:4,maxAgeSeconds:31536e3})]}),"GET"),e.registerRoute(/^https:\/\/fonts\.(?:googleapis)\.com\/.*/i,new e.StaleWhileRevalidate({cacheName:"google-fonts-stylesheets",plugins:[new e.ExpirationPlugin({maxEntries:4,maxAgeSeconds:604800})]}),"GET"),e.registerRoute(/\.(?:eot|otf|ttc|ttf|woff|woff2|font.css)$/i,new e.StaleWhileRevalidate({cacheName:"static-font-assets",plugins:[new e.ExpirationPlugin({maxEntries:4,maxAgeSeconds:604800})]}),"GET"),e.registerRoute(/\.(?:jpg|jpeg|gif|png|svg|ico|webp)$/i,new e.StaleWhileRevalidate({cacheName:"static-image-assets",plugins:[new e.ExpirationPlugin({maxEntries:64,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\/_next\/image\?url=.+$/i,new e.StaleWhileRevalidate({cacheName:"next-image",plugins:[new e.ExpirationPlugin({maxEntries:64,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:mp3|wav|ogg)$/i,new e.CacheFirst({cacheName:"static-audio-assets",plugins:[new e.RangeRequestsPlugin,new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:mp4)$/i,new e.CacheFirst({cacheName:"static-video-assets",plugins:[new e.RangeRequestsPlugin,new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:js)$/i,new e.StaleWhileRevalidate({cacheName:"static-js-assets",plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:css|less)$/i,new e.StaleWhileRevalidate({cacheName:"static-style-assets",plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\/_next\/data\/.+\/.+\.json$/i,new e.StaleWhileRevalidate({cacheName:"next-data",plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:json|xml|csv)$/i,new e.NetworkFirst({cacheName:"static-data-assets",plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute((({url:e})=>{if(!(self.origin===e.origin))return!1;const s=e.pathname;return!s.startsWith("/api/auth/")&&!!s.startsWith("/api/")}),new e.NetworkFirst({cacheName:"apis",networkTimeoutSeconds:10,plugins:[new e.ExpirationPlugin({maxEntries:16,maxAgeSeconds:86400})]}),"GET"),e.registerRoute((({url:e})=>{if(!(self.origin===e.origin))return!1;return!e.pathname.startsWith("/api/")}),new e.NetworkFirst({cacheName:"others",networkTimeoutSeconds:10,plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute((({url:e})=>!(self.origin===e.origin)),new e.NetworkFirst({cacheName:"cross-origin",networkTimeoutSeconds:10,plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:3600})]}),"GET")}));
