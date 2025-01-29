import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

// 支持的语言列表
const languages = [
  'en',
  'zh-CN',
  'zh-TW',
  'zh-HK',
  'ja',
  'ko',
  'fr',
  'de',
  'es',
  'it',
  'pt',
  'ru',
  'hi-IN',
  'mr-IN',
  'tr',
  'ar',
  'th',
  'id',
  'vi'
];

// 语言代码映射
const languageMapping: { [key: string]: string } = {
  'zh': 'zh-CN',
  'zh-Hans': 'zh-CN',
  'zh-Hans-CN': 'zh-CN',
  'zh-Hans-SG': 'zh-CN',
  'zh-Hans-HK': 'zh-CN',
  'zh-Hans-MO': 'zh-CN',
  'zh-SG': 'zh-CN',
  'zh-Hant': 'zh-TW',
  'zh-Hant-TW': 'zh-TW',
  'zh-Hant-HK': 'zh-HK',
  'zh-Hant-MO': 'zh-HK',
  'zh-HK': 'zh-HK',
  'zh-MO': 'zh-HK',
  'mr': 'mr-IN',
  'hi': 'hi-IN'
};

// 获取语言的基础部分
function getBaseLanguage(lang: string): string {
  // 首先检查完整的语言代码是否在映射中
  if (languageMapping[lang]) {
    return languageMapping[lang];
  }
  
  // 然后检查基础语言代码是否在映射中
  const baseLang = lang.split('-')[0];
  if (languageMapping[baseLang]) {
    return languageMapping[baseLang];
  }
  
  // 如果语言代码包含区域（如 de-DE），返回基础语言代码（如 de）
  if (lang.includes('-') && languages.includes(baseLang)) {
    return baseLang;
  }
  
  // 返回原始语言代码
  return lang;
}

// 获取用户首选语言
function getPreferredLanguage(request: NextRequest): string {
  // 首先检查 cookie
  const savedLang = request.cookies.get('i18nextLng')?.value;
  if (savedLang) {
    const mappedLang = getBaseLanguage(savedLang);
    if (languages.includes(mappedLang)) {
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
      if (languages.includes(mappedLang)) {
        return mappedLang;
      }
    }
  }

  // 默认返回英语
  return 'en';
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
  const pathnameHasLocale = languages.some(
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
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico|manifest.json|locales|.*\\..*).*)']
}; 