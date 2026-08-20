import { OffWorkCountdown } from '@/components/off-work-countdown';
import { DesktopDownloadInvite } from '@/components/DesktopDownloadInvite';
import { I18nProvider } from '@/components/I18nProvider';
import { siteConfig } from '@/config/site';
import { resolveContentLocale } from '@/lib/content-locales';
import {
  getContent,
  pickMacAppStoreDialogCopy,
} from '@/lib/server/content';
import { getTranslations } from '@/lib/server/i18n';

const IS_DESKTOP_BUILD = process.env.NEXT_PUBLIC_BUILD_TARGET === 'desktop';

type Props = {
  params: Promise<{ lang: string }>
};

export default async function Home({ params }: Props) {
  const { lang } = await params;
  const [translation, seo, content] = await Promise.all([
    getTranslations(lang, 'translation'),
    getTranslations(lang, 'seo'),
    getContent(resolveContentLocale(lang)),
  ]);
  const macAppStoreCopy = pickMacAppStoreDialogCopy(content.download);
  const jsonLd = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebSite',
        name: siteConfig.name,
        ...(seo.siteName !== siteConfig.name
          ? { alternateName: seo.siteName }
          : {}),
        url: siteConfig.baseUrl,
      },
      {
        '@type': 'WebApplication',
        name: seo.siteName,
        description: seo.description,
        url: `${siteConfig.baseUrl}/${lang}`,
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
        <OffWorkCountdown lang={lang} macAppStoreCopy={macAppStoreCopy} />
      </div>
      {!IS_DESKTOP_BUILD && <DesktopDownloadInvite />}
    </I18nProvider>
  );
}
