import { OffWorkCountdown } from "@/components/off-work-countdown";
import { I18nProvider } from "@/components/I18nProvider";
import { getTranslations } from "@/lib/server/i18n";

type Props = {
  params: Promise<{ lang: string }>;
};

/** Mobile shell entry: no Web marketing metadata, download prompt, or JSON-LD. */
export default async function MobileHome({ params }: Props) {
  const { lang } = await params;
  const [translation, seo] = await Promise.all([
    getTranslations(lang, "translation"),
    getTranslations(lang, "seo"),
  ]);

  return (
    <I18nProvider lang={lang} resources={{ translation, seo }}>
      <div className="min-h-screen">
        <OffWorkCountdown lang={lang} />
      </div>
    </I18nProvider>
  );
}
