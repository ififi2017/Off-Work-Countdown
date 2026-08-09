import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import type { ReactNode } from "react";
import { contentLocales, type ContentLocale } from "@/lib/content-locales";
import { siteConfig } from "@/config/site";

// 内容页语言的自称写法。
const localeLabels: Record<ContentLocale, string> = {
  en: "English",
  "zh-CN": "中文",
};

// 内容页外壳。刻意做成服务端组件：这些页面没有交互，全部内容随首屏 HTML
// 一起产出，是它们能被收录的前提。
interface ContentPageProps {
  lang: ContentLocale;
  /** 语言切换要跳到的同名路径，例如 "faq" 或预设页的 "996"。 */
  slug: string;
  backLabel: string;
  heading: string;
  intro: string;
  wide?: boolean;
  children: ReactNode;
}

export function ContentPage({
  lang,
  slug,
  backLabel,
  heading,
  intro,
  wide = false,
  children,
}: ContentPageProps) {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      {
        "@type": "ListItem",
        position: 1,
        name: siteConfig.name,
        item: `${siteConfig.baseUrl}/${lang}`,
      },
      {
        "@type": "ListItem",
        position: 2,
        name: heading,
        item: `${siteConfig.baseUrl}/${lang}/${slug}`,
      },
    ],
  };

  return (
    <div className="min-h-screen bg-gray-100 dark:bg-gray-900">
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

          <nav className="flex items-center gap-1 text-sm">
            {contentLocales.map((l) =>
              l === lang ? (
                <span
                  key={l}
                  aria-current="true"
                  className="rounded-md px-2 py-1 font-medium text-gray-900 dark:text-white"
                >
                  {localeLabels[l]}
                </span>
              ) : (
                <Link
                  key={l}
                  href={`/${l}/${slug}`}
                  hrefLang={l}
                  className="rounded-md px-2 py-1 text-gray-500 transition-colors hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
                >
                  {localeLabels[l]}
                </Link>
              )
            )}
          </nav>
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
