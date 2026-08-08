import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { locales, defaultLocale, getBaseLanguage, Locale } from "./i18n-config";

// 获取用户首选语言
function getPreferredLanguage(request: NextRequest): string {
  // 先读用户选择的语言（cookie）
  const savedLang = request.cookies.get("i18nextLng")?.value;
  if (savedLang) {
    const mappedLang = getBaseLanguage(savedLang);
    if (locales.includes(mappedLang as Locale)) {
      return mappedLang;
    }
  }

  // 再从 Accept-Language 头部获取语言偏好
  const acceptLanguage = request.headers.get("accept-language");
  if (acceptLanguage) {
    const preferredLangs = acceptLanguage
      .split(",")
      .map((lang) => {
        const [language, weight] = lang.split(";");
        return {
          language: language.trim(),
          weight: weight ? parseFloat(weight.split("=")[1]) : 1.0,
        };
      })
      .sort((a, b) => b.weight - a.weight);

    for (const { language } of preferredLangs) {
      const mappedLang = getBaseLanguage(language);
      if (locales.includes(mappedLang as Locale)) {
        return mappedLang;
      }
    }
  }

  // 默认返回英语
  return defaultLocale;
}

export function middleware(request: NextRequest) {
  const pathname = request.nextUrl.pathname;

  // 如果是静态资源或 API 路由，直接返回
  if (
    pathname.startsWith("/_next") ||
    pathname.startsWith("/api") ||
    pathname.startsWith("/static") ||
    pathname === "/favicon.ico" ||
    pathname === "/manifest.json" ||
    pathname === "/sw.js" ||
    pathname.startsWith("/workbox-") ||
    pathname.startsWith("/locales/") ||
    pathname.startsWith("/emoji/") ||
    pathname.match(/^\/icon-[\w-]+\.png$/) ||
    pathname === "/robots.txt" ||
    pathname === "/sitemap.xml"
  ) {
    return NextResponse.next();
  }

  // 注意：这里不能把「首段不是合法语言码」当成语言前缀写错来处理。曾经的实现
  // 会把首段剥掉再重定向到默认语言，导致 /faq 变成 /en 而不是 /en/faq —— 路径
  // 被吃掉了。以前站内只有 /[lang] 一种路由所以没暴露，加了内容页后就会出问题。
  // 统一交给下面的逻辑：没有合法语言前缀就整体补上首选语言。这样 /faq 得到
  // /en/faq；而真正写错的 /xx/faq 会得到 /en/xx/faq 并 404，这是诚实的结果。

  // 检查 URL 是否已经包含有效的语言代码
  const pathnameHasLocale = locales.some(
    (locale) => pathname.startsWith(`/${locale}/`) || pathname === `/${locale}`
  );

  if (pathnameHasLocale) return NextResponse.next();

  // 获取用户首选语言
  const locale = getPreferredLanguage(request);

  // 用 clone 而不是 new URL(path, base)：后者的第一个参数是绝对路径时会连同
  // 查询串一起替换掉。分享链接指向根路径并带着 ?s= 与 utm_*，走旧写法会在这次
  // 重定向中被整串丢弃——分享归因此前一直没生效，正是这个原因。
  const newUrl = request.nextUrl.clone();
  newUrl.pathname = `/${locale}${pathname}`;

  return NextResponse.redirect(newUrl);
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - api (API routes)
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - manifest.json
     * - sw.js (Service Worker)
     * - workbox-*.js (Workbox files)
     * - locales
     * - robots.txt
     * - sitemap.xml
     * - baidu_verify_codeva-SXZydSeYe0.html
     */
    "/((?!api|_next/static|_next/image|favicon.ico|manifest.json|sw.js|workbox-[^/]+|locales|emoji|robots.txt|sitemap.xml|baidu_verify_codeva-SXZydSeYe0.html).*)",
  ],
};
