import { OffWorkCountdown } from '@/components/off-work-countdown';

type Props = {
  params: { lang: string }
};

export default function Home({ params }: Props) {
  return (
    <div className="min-h-screen">
      <OffWorkCountdown lang={params.lang} />
    </div>
  );
} 