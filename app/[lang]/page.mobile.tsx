import { MobileApp } from "@/components/mobile/MobileApp";
import { I18nProvider } from "@/components/I18nProvider";
import { getTranslations } from "@/lib/server/i18n";

type Props = {
  params: Promise<{ lang: string }>;
};

/**
 * Mobile shell entry.
 *
 * It mounts the iOS app rather than the Web page: no marketing metadata, no
 * download prompt, no JSON-LD — and, deliberately, none of the Web/Desktop
 * `OffWorkCountdown` UI. See components/mobile/MobileApp.tsx.
 */
export default async function MobileHome({ params }: Props) {
  const { lang } = await params;
  const [translation, seo] = await Promise.all([
    getTranslations(lang, "translation"),
    getTranslations(lang, "seo"),
  ]);

  return (
    <I18nProvider lang={lang} resources={{ translation, seo }}>
      <MobileApp lang={lang} />
    </I18nProvider>
  );
}
