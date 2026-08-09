import type { Metadata } from "next";
import { siteConfig } from "@/config/site";
import { getContent } from "@/lib/server/content";
import { ContentPage } from "@/components/ContentPage";
import { localizedSocialMetadata } from "@/lib/server/metadata";
import {
  contentLocales,
  defaultContentLocale,
  type ContentLocale,
} from "@/lib/content-locales";

// 内容页只做中英两种语言（见 lib/content-locales.ts）。dynamicParams 关掉后，
// 其余语言直接 404，而不是在该语言的 URL 下渲染英文内容——后者会让搜索引擎
// 收录到语言与内容不符的页面。应用内的入口链接会按界面语言指向正确的一版。
export const dynamicParams = false;

export function generateStaticParams() {
  return contentLocales.map((lang) => ({ lang }));
}

const alternateLanguages = {
  ...Object.fromEntries(
    contentLocales.map((l) => [l, `${siteConfig.baseUrl}/${l}/faq`])
  ),
  "x-default": `${siteConfig.baseUrl}/${defaultContentLocale}/faq`,
};

export async function generateMetadata({
  params,
}: {
  params: Promise<{ lang: string }>;
}): Promise<Metadata> {
  const { lang } = await params;
  const content = await getContent(lang);

  return {
    metadataBase: new URL(siteConfig.baseUrl),
    title: content.faq.metaTitle,
    description: content.faq.metaDescription,
    alternates: {
      canonical: `${siteConfig.baseUrl}/${lang}/faq`,
      languages: alternateLanguages,
    },
    ...localizedSocialMetadata({
      lang,
      path: "faq",
      title: content.faq.metaTitle,
      description: content.faq.metaDescription,
      type: "article",
    }),
  };
}

export default async function FaqPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const content = await getContent(lang);

  // FAQPage schema：问答页最直接的富摘要来源，Google 会把问题折叠展示在结果里。
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    inLanguage: lang,
    mainEntity: content.faq.items.map((item) => ({
      "@type": "Question",
      name: item.q,
      acceptedAnswer: { "@type": "Answer", text: item.a },
    })),
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(jsonLd).replace(/</g, "\\u003c"),
        }}
      />
      <ContentPage
        lang={lang as ContentLocale}
        slug="faq"
        backLabel={content.backToApp}
        heading={content.faq.heading}
        intro={content.faq.intro}
      >
        <dl className="space-y-8">
          {content.faq.items.map((item) => (
            <div key={item.q}>
              <dt className="text-lg font-semibold text-gray-900 dark:text-white">
                {item.q}
              </dt>
              <dd className="mt-2 text-base leading-7 text-gray-600 dark:text-gray-300">
                {item.a}
              </dd>
            </div>
          ))}
        </dl>
      </ContentPage>
    </>
  );
}
