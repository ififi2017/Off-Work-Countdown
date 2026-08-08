import type { Metadata } from "next";
import { siteConfig } from "@/config/site";
import { getContent, getContentLocales } from "@/lib/server/content";
import { ContentPage } from "@/components/ContentPage";

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
    title: content.howItWorks.metaTitle,
    description: content.howItWorks.metaDescription,
    alternates: {
      canonical: `${siteConfig.baseUrl}/${lang}/how-it-works`,
      languages: Object.fromEntries(
        langs.map((l) => [l, `${siteConfig.baseUrl}/${l}/how-it-works`])
      ),
    },
    openGraph: {
      title: content.howItWorks.metaTitle,
      description: content.howItWorks.metaDescription,
      type: "article",
      locale: lang,
      url: `${siteConfig.baseUrl}/${lang}/how-it-works`,
      siteName: siteConfig.name,
    },
  };
}

export default async function HowItWorksPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const content = await getContent(lang);

  return (
    <ContentPage
      lang={lang}
      backLabel={content.backToApp}
      heading={content.howItWorks.heading}
      intro={content.howItWorks.intro}
    >
      <div className="space-y-10">
        {content.howItWorks.sections.map((section) => (
          <section key={section.heading}>
            <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
              {section.heading}
            </h2>
            {section.body.map((para, i) => (
              <p
                key={i}
                className="mt-3 text-base leading-7 text-gray-600 dark:text-gray-300"
              >
                {para}
              </p>
            ))}
          </section>
        ))}
      </div>
    </ContentPage>
  );
}
