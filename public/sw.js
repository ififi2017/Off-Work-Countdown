if(!self.define){let e,s={};const a=(a,n)=>(a=new URL(a+".js",n).href,s[a]||new Promise((s=>{if("document"in self){const e=document.createElement("script");e.src=a,e.onload=s,document.head.appendChild(e)}else e=a,importScripts(a),s()})).then((()=>{let e=s[a];if(!e)throw new Error(`Module ${a} didn’t register its module`);return e})));self.define=(n,o)=>{const c=e||("document"in self?document.currentScript.src:"")||location.href;if(s[c])return;let i={};const t=e=>a(e,c),r={module:{uri:c},exports:i,require:t};s[c]=Promise.all(n.map((e=>r[e]||t(e)))).then((e=>(o(...e),i)))}}define(["./workbox-4754cb34"],(function(e){"use strict";importScripts(),self.skipWaiting(),e.clientsClaim(),e.precacheAndRoute([{url:"/_next/app-build-manifest.json",revision:"c80dd199e7bf7c609456154be3ab6330"},{url:"/_next/static/HIDS3odvGtyzJvDRwGG3K/_buildManifest.js",revision:"3e372c67224d3da7d9272aa637736281"},{url:"/_next/static/HIDS3odvGtyzJvDRwGG3K/_ssgManifest.js",revision:"b6652df95db52feb4daf4eca35380933"},{url:"/_next/static/chunks/117-da84740ce82d5f7c.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/756-dda3e4c5c12cbd61.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/916-e1695593f0f14b8d.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/app/%5Blang%5D/layout-b753ad5399798615.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/app/%5Blang%5D/page-6fe255b7e882d1e0.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/app/_not-found/page-1094121d36a0541e.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/app/layout-01de71221bceaf78.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/fd9d1056-6922f449a204c2cc.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/framework-f66176bb897dc684.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/main-8279df72a14835cb.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/main-app-29537ef3dce0afb0.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/pages/_app-72b849fbd24ac258.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/pages/_error-7ba65e1336b92748.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/chunks/polyfills-42372ed130431b0a.js",revision:"846118c33b2c0e922d7b3a7676f81f6f"},{url:"/_next/static/chunks/webpack-b0d9f56bae70f1f0.js",revision:"HIDS3odvGtyzJvDRwGG3K"},{url:"/_next/static/css/c95d374c3925a10a.css",revision:"c95d374c3925a10a"},{url:"/_next/static/media/4473ecc91f70f139-s.p.woff",revision:"78e6fc13ea317b55ab0bd6dc4849c110"},{url:"/_next/static/media/463dafcda517f24f-s.p.woff",revision:"cbeb6d2d96eaa268b4b5beb0b46d9632"},{url:"/icon-192x192.png",revision:"baeef1ffa1a13ae617b33f65b08cf6cf"},{url:"/icon-512x512.png",revision:"baeef1ffa1a13ae617b33f65b08cf6cf"},{url:"/locales/ar/seo.json",revision:"804f0098dfda4197ea7786c999b2fbc2"},{url:"/locales/ar/translation.json",revision:"33a8dac5de6377d9b4f901305a563c41"},{url:"/locales/de/seo.json",revision:"fa1b5dbfb0c5b4f29f521be5a8aadfbe"},{url:"/locales/de/translation.json",revision:"a2685721a8c7035f37a72ed0f007454d"},{url:"/locales/en/seo.json",revision:"2765d25a019f77a071168b501fb2d87b"},{url:"/locales/en/translation.json",revision:"5fd9abec126f37cdc40dc0065ccdd1f2"},{url:"/locales/es/seo.json",revision:"9fc0081c20054510638ed312b49f55d1"},{url:"/locales/es/translation.json",revision:"7e00027b51b62a667b81a5ba5f0d059c"},{url:"/locales/fr/seo.json",revision:"4921d85f611c3f856b20879537f88398"},{url:"/locales/fr/translation.json",revision:"0f49762a0310be960452b12fea092a70"},{url:"/locales/hi-IN/seo.json",revision:"73a4bb5f7bde85999e7223614f1be937"},{url:"/locales/hi-IN/translation.json",revision:"1d0d78c5627ba8d7fad883edfae3b809"},{url:"/locales/id/seo.json",revision:"b1018aad822798264dda506e260ff825"},{url:"/locales/id/translation.json",revision:"1b4b9be5e3c9aeba95087141b6b9cfd0"},{url:"/locales/it/seo.json",revision:"71c0cdc3cbe432de9f5f33e8d1df3a43"},{url:"/locales/it/translation.json",revision:"dfc5152428b9007df0b0dfa1b63a63fc"},{url:"/locales/ja/seo.json",revision:"e97eddf0e6d3292f5f524487bcf93501"},{url:"/locales/ja/translation.json",revision:"507c7600270857e53a6dc8842775a471"},{url:"/locales/ko/seo.json",revision:"2bff6af7dbb36d7985e483169bd229ab"},{url:"/locales/ko/translation.json",revision:"c9150eb2db1aeb16f5cb3cf4f006a499"},{url:"/locales/mr-IN/seo.json",revision:"1610e1c1fc86212e8c2c77be768f7a45"},{url:"/locales/mr-IN/translation.json",revision:"eb2fc5286f02afb87b0d93136acc67b3"},{url:"/locales/pt/seo.json",revision:"ebaabd16dd965df0a6dfa69590c09e2b"},{url:"/locales/pt/translation.json",revision:"9617b6f0b5a5abed06174eca68e52c66"},{url:"/locales/ru/seo.json",revision:"451cf7d1a4fe65f9f73f283333cea997"},{url:"/locales/ru/translation.json",revision:"becab53e1a7a3a5a6e3f5125b5e000b9"},{url:"/locales/th/seo.json",revision:"522e69f7c56d4e44e85ca6d1353df866"},{url:"/locales/th/translation.json",revision:"e794234093301df95f6fc58e790d09f7"},{url:"/locales/tr/seo.json",revision:"fcd921c2be40599afa879cdcfcf9c945"},{url:"/locales/tr/translation.json",revision:"1c903c7c9b11c92c36564b5128008e10"},{url:"/locales/vi/seo.json",revision:"fac10795f7140819e9f4bdccc005a3bc"},{url:"/locales/vi/translation.json",revision:"6630faaf40dc1928ce6987e7b61dc7cb"},{url:"/locales/zh-CN/seo.json",revision:"c121286c1b5df1560b3bb06079bb5e32"},{url:"/locales/zh-CN/translation.json",revision:"86ee48a02ac5e72e41063eda59e454d3"},{url:"/locales/zh-HK/seo.json",revision:"a2c602ce1833bcb28e18b21ec5fe0954"},{url:"/locales/zh-HK/translation.json",revision:"cc4652ae310e050dfe537c06cb8dd374"},{url:"/locales/zh-TW/seo.json",revision:"7675267601e20016ae621f340de563ef"},{url:"/locales/zh-TW/translation.json",revision:"d9dec8bbbd97c6243fd9ffed0e71820f"}],{ignoreURLParametersMatching:[]}),e.cleanupOutdatedCaches(),e.registerRoute("/",new e.NetworkFirst({cacheName:"start-url",plugins:[{cacheWillUpdate:async({request:e,response:s,event:a,state:n})=>s&&"opaqueredirect"===s.type?new Response(s.body,{status:200,statusText:"OK",headers:s.headers}):s}]}),"GET"),e.registerRoute(/^https:\/\/fonts\.(?:gstatic)\.com\/.*/i,new e.CacheFirst({cacheName:"google-fonts-webfonts",plugins:[new e.ExpirationPlugin({maxEntries:4,maxAgeSeconds:31536e3})]}),"GET"),e.registerRoute(/^https:\/\/fonts\.(?:googleapis)\.com\/.*/i,new e.StaleWhileRevalidate({cacheName:"google-fonts-stylesheets",plugins:[new e.ExpirationPlugin({maxEntries:4,maxAgeSeconds:604800})]}),"GET"),e.registerRoute(/\.(?:eot|otf|ttc|ttf|woff|woff2|font.css)$/i,new e.StaleWhileRevalidate({cacheName:"static-font-assets",plugins:[new e.ExpirationPlugin({maxEntries:4,maxAgeSeconds:604800})]}),"GET"),e.registerRoute(/\.(?:jpg|jpeg|gif|png|svg|ico|webp)$/i,new e.StaleWhileRevalidate({cacheName:"static-image-assets",plugins:[new e.ExpirationPlugin({maxEntries:64,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\/_next\/image\?url=.+$/i,new e.StaleWhileRevalidate({cacheName:"next-image",plugins:[new e.ExpirationPlugin({maxEntries:64,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:mp3|wav|ogg)$/i,new e.CacheFirst({cacheName:"static-audio-assets",plugins:[new e.RangeRequestsPlugin,new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:mp4)$/i,new e.CacheFirst({cacheName:"static-video-assets",plugins:[new e.RangeRequestsPlugin,new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:js)$/i,new e.StaleWhileRevalidate({cacheName:"static-js-assets",plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:css|less)$/i,new e.StaleWhileRevalidate({cacheName:"static-style-assets",plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\/_next\/data\/.+\/.+\.json$/i,new e.StaleWhileRevalidate({cacheName:"next-data",plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute(/\.(?:json|xml|csv)$/i,new e.NetworkFirst({cacheName:"static-data-assets",plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute((({url:e})=>{if(!(self.origin===e.origin))return!1;const s=e.pathname;return!s.startsWith("/api/auth/")&&!!s.startsWith("/api/")}),new e.NetworkFirst({cacheName:"apis",networkTimeoutSeconds:10,plugins:[new e.ExpirationPlugin({maxEntries:16,maxAgeSeconds:86400})]}),"GET"),e.registerRoute((({url:e})=>{if(!(self.origin===e.origin))return!1;return!e.pathname.startsWith("/api/")}),new e.NetworkFirst({cacheName:"others",networkTimeoutSeconds:10,plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:86400})]}),"GET"),e.registerRoute((({url:e})=>!(self.origin===e.origin)),new e.NetworkFirst({cacheName:"cross-origin",networkTimeoutSeconds:10,plugins:[new e.ExpirationPlugin({maxEntries:32,maxAgeSeconds:3600})]}),"GET")}));
