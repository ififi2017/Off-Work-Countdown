import type { Metadata } from "next";
import { siteConfig } from "@/config/site";
import { getContent, getContentLocales } from "@/lib/server/content";
import { ContentPage } from "@/components/ContentPage";

// 只为已备好文案的语言生成路由；dynamicParams 关掉后，其余语言直接 404，
// 避免在该语言的 URL 下渲染英文内容。
export const dynamicParams = false;

export async function generateStaticParams() {
  const langs = await getContentLocales();
  return langs.map((lang) => ({ lang }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ lang: string }>;
}): Promise<Metadata> {
  const { lang } = await params;
  const content = await getContent(lang);
  const langs = await getContentLocales();

  return {
    metadataBase: new URL(siteConfig.baseUrl),
    title: content.faq.metaTitle,
    description: content.faq.metaDescription,
    alternates: {
      canonical: `${siteConfig.baseUrl}/${lang}/faq`,
      languages: Object.fromEntries(
        langs.map((l) => [l, `${siteConfig.baseUrl}/${l}/faq`])
      ),
    },
    openGraph: {
      title: content.faq.metaTitle,
      description: content.faq.metaDescription,
      type: "article",
      locale: lang,
      url: `${siteConfig.baseUrl}/${lang}/faq`,
      siteName: siteConfig.name,
    },
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
        lang={lang}
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
