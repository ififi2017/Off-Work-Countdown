import { OffWorkCountdown } from '@/components/off-work-countdown';
import { DesktopDownloadInvite } from '@/components/DesktopDownloadInvite';
import { I18nProvider } from '@/components/I18nProvider';
import { siteConfig } from '@/config/site';
import { getTranslations } from '@/lib/server/i18n';
import { IS_WEB_BUILD } from '@/lib/build-target';

type Props = {
  params: Promise<{ lang: string }>
};

export default async function Home({ params }: Props) {
  const { lang } = await params;
  const [translation, seo] = await Promise.all([
    getTranslations(lang, 'translation'),
    getTranslations(lang, 'seo'),
  ]);
  const jsonLd = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebSite',
        name: siteConfig.brandName,
        alternateName: 'Off Work Countdown',
        url: siteConfig.webAppUrl,
      },
      {
        '@type': 'WebApplication',
        name: siteConfig.brandName,
        alternateName: seo.siteName !== siteConfig.brandName ? seo.siteName : undefined,
        description: seo.description,
        url: `${siteConfig.webAppUrl}/${lang}`,
        inLanguage: lang,
        applicationCategory: 'UtilitiesApplication',
        operatingSystem: 'Any',
        browserRequirements: 'Requires JavaScript',
        isAccessibleForFree: true,
        offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
        license: 'https://opensource.org/licenses/MIT',
        codeRepository: siteConfig.github,
      },
    ],
  };

  return (
    <I18nProvider lang={lang} resources={{ translation, seo }}>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(jsonLd).replace(/</g, '\\u003c'),
        }}
      />
      <div className="min-h-screen">
        <OffWorkCountdown lang={lang} />
      </div>
      {IS_WEB_BUILD && <DesktopDownloadInvite />}
    </I18nProvider>
  );
}
