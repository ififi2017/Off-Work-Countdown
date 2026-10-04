import Link from "next/link";
import { ArrowLeft, Globe } from "lucide-react";
import type { ReactNode } from "react";
import { siteConfig } from "@/config/site";
import { longFormLocales, type LongFormLocale } from "@/lib/content-locales";
import { webAppPageUrl } from "@/lib/site-urls";
import { languageNames } from "@/i18n-config";

// 长文页语言的自称写法。
const localeLabels: Record<LongFormLocale, string> = {
  en: "English",
  "zh-CN": "中文",
};

// 内容页外壳。刻意做成服务端组件：这些页面没有交互，全部内容随首屏 HTML
// 一起产出，是它们能被收录的前提。FAQ / About 等长文已迁到官网，不再走这里。
interface ContentPageProps {
  lang: string;
  /** 语言切换要跳到的同名路径，例如 "faq" 或预设页的 "996"。 */
  slug: string;
  backLabel: string;
  heading: string;
  intro: string;
  wide?: boolean;
  /** 可用语言列表。长文页传 longFormLocales 显示内联切换，预设页传 presetLocales 显示下拉菜单。 */
  availableLocales?: readonly string[];
  children: ReactNode;
}

export function ContentPage({
  lang,
  slug,
  backLabel,
  heading,
  intro,
  wide = false,
  availableLocales,
  children,
}: ContentPageProps) {
  const showInlineSwitcher =
    availableLocales && availableLocales.length <= 3;
  const showDropdownSwitcher =
    availableLocales && availableLocales.length > 3;
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      {
        "@type": "ListItem",
        position: 1,
        name: siteConfig.brandName,
        item: webAppPageUrl(lang),
      },
      {
        "@type": "ListItem",
        position: 2,
        name: heading,
        item: webAppPageUrl(lang, slug),
      },
    ],
  };

  return (
    <div className="min-h-screen bg-gray-100 dark:bg-gray-950">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(jsonLd).replace(/</g, "\\u003c"),
        }}
      />
      <div
        className={`mx-auto px-5 py-12 sm:py-16 ${
          wide ? "max-w-5xl" : "max-w-2xl"
        }`}
      >
        <div className="flex items-center justify-between gap-4">
          <Link
            href={`/${lang}`}
            className="inline-flex items-center gap-2 text-sm text-gray-600 transition-colors hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100"
          >
            <ArrowLeft size={16} className="rtl:rotate-180" />
            {backLabel}
          </Link>

          {showInlineSwitcher && (
            <nav className="flex items-center gap-1 text-sm">
              {availableLocales.map((l) =>
                l === lang ? (
                  <span
                    key={l}
                    aria-current="true"
                    className="rounded-md px-2 py-1 font-medium text-gray-900 dark:text-white"
                  >
                    {localeLabels[l as LongFormLocale] ?? languageNames[l] ?? l}
                  </span>
                ) : (
                  <Link
                    key={l}
                    href={`/${l}/${slug}`}
                    hrefLang={l}
                    className="rounded-md px-2 py-1 text-gray-500 transition-colors hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
                  >
                    {localeLabels[l as LongFormLocale] ?? languageNames[l] ?? l}
                  </Link>
                )
              )}
            </nav>
          )}

          {showDropdownSwitcher && (
            <details className="group relative">
              <summary className="flex h-8 cursor-pointer list-none items-center gap-1.5 rounded-lg border border-gray-200 bg-white/80 px-2.5 text-xs text-gray-700 backdrop-blur-sm transition-colors hover:border-gray-300 dark:border-gray-700 dark:bg-gray-800/80 dark:text-gray-300 dark:hover:border-gray-600 [&::-webkit-details-marker]:hidden">
                <Globe size={14} className="text-gray-500 dark:text-gray-400" />
                <span>{languageNames[lang] ?? lang}</span>
                <svg
                  className="ml-0.5 h-3 w-3 text-gray-500 transition-transform group-open:rotate-180 dark:text-gray-400"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M19 9l-7 7-7-7"
                  />
                </svg>
              </summary>
              <nav className="absolute end-0 top-full z-10 mt-1 max-h-64 w-44 overflow-y-auto rounded-lg border border-gray-200 bg-white py-1 shadow-lg dark:border-gray-700 dark:bg-gray-800">
                {availableLocales.map((l) => (
                  <Link
                    key={l}
                    href={`/${l}/${slug}`}
                    hrefLang={l}
                    className={`block px-3 py-1.5 text-sm transition-colors ${
                      l === lang
                        ? "bg-gray-100 font-medium text-gray-900 dark:bg-gray-700 dark:text-white"
                        : "text-gray-600 hover:bg-gray-50 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-700/50 dark:hover:text-white"
                    }`}
                  >
                    {languageNames[l] ?? l}
                  </Link>
                ))}
              </nav>
            </details>
          )}
        </div>

        <h1 className="mt-8 text-3xl font-bold tracking-tight text-gray-900 dark:text-white sm:text-4xl">
          {heading}
        </h1>
        <p className="mt-4 text-base leading-7 text-gray-600 dark:text-gray-300">
          {intro}
        </p>

        <div className="mt-10">{children}</div>
      </div>
    </div>
  );
}
