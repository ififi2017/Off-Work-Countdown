import { OffWorkCountdown } from '@/components/off-work-countdown';

type Props = {
  params: Promise<{ lang: string }> | { lang: string }
};

export default async function Home({ params }: Props) {
  const { lang } = await params;
  return (
    <div className="min-h-screen">
      <OffWorkCountdown lang={lang} />
    </div>
  );
} 