import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { locales, defaultLocale, getBaseLanguage, Locale } from './i18n-config'

// 获取用户首选语言
function getPreferredLanguage(request: NextRequest): string {
  // 首先检查 cookie
  const savedLang = request.cookies.get('i18nextLng')?.value;
  if (savedLang) {
    const mappedLang = getBaseLanguage(savedLang);
    if (locales.includes(mappedLang as Locale)) {
      return mappedLang;
    }
  }

  // 从 Accept-Language 头部获取语言偏好
  const acceptLanguage = request.headers.get('accept-language');
  if (acceptLanguage) {
    const preferredLangs = acceptLanguage
      .split(',')
      .map(lang => lang.split(';')[0].trim());

    // 尝试找到第一个匹配的语言
    for (const lang of preferredLangs) {
      const mappedLang = getBaseLanguage(lang);
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
    pathname.startsWith('/_next') ||
    pathname.startsWith('/api') ||
    pathname.startsWith('/static') ||
    pathname.includes('.') ||
    pathname === '/favicon.ico'
  ) {
    return NextResponse.next();
  }

  // 检查 URL 是否已经包含语言代码
  const pathnameHasLocale = locales.some(
    locale => pathname.startsWith(`/${locale}/`) || pathname === `/${locale}`
  );

  if (pathnameHasLocale) return NextResponse.next();

  // 获取用户首选语言
  const locale = getPreferredLanguage(request);

  // 创建新的 URL，包含语言代码
  const newUrl = new URL(`/${locale}${pathname}`, request.url);
  
  // 返回重定向响应
  return NextResponse.redirect(newUrl);
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico|manifest.json|sw.js|workbox-*.js|locales|.*\\..*).*)']
}; 