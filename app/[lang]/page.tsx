import { OffWorkCountdown } from '@/components/off-work-countdown';
import { Metadata } from 'next';
import { locales } from '@/i18n-config';

type Props = {
  params: { lang: string }
};

type Languages = {
  [key: string]: string;
};

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const lang = params.lang;
  
  const titles: Languages = {
    'en': 'Off Work Countdown - Work Time Management Tool',
    'zh-CN': '下班倒计时 - 高效工作时间管理工具',
    'zh-TW': '下班倒數 - 高效工作時間管理工具',
    'zh-HK': '下班倒數 - 高效工作時間管理工具',
    'ja': '退勤カウントダウン - 効率的な勤務時間管理ツール',
    'ko': '퇴근 카운트다운 - 효율적인 근무 시간 관리 도구',
    'fr': 'Compte à rebours de fin de travail - Outil de gestion du temps de travail',
    'de': 'Feierabend-Countdown - Arbeitszeitmanagement-Tool',
    'es': 'Cuenta regresiva del trabajo - Herramienta de gestión del tiempo laboral',
    'it': 'Conto alla rovescia del lavoro - Strumento di gestione del tempo lavorativo',
    'pt': 'Contagem regressiva do trabalho - Ferramenta de gestão do tempo de trabalho',
    'ru': 'Обратный отсчет до конца работы - Инструмент управления рабочим временем',
    'hi-IN': 'ऑफ वर्क काउंटडाउन - कार्य समय प्रबंधन टूल',
    'mr-IN': 'ऑफ वर्क काउंटडाउन - कार्य वेळ व्यवस्थापन साधन'
  };

  const descriptions: Languages = {
    'en': 'Track your workday progress with Off Work Countdown. Enhance workplace productivity and work-life balance with real-time countdown timer, notifications, and progress tracking.',
    'zh-CN': '使用下班倒计时追踪工作进度，提升职场效率。实时倒计时、智能提醒、进度追踪，帮助您更好地平衡工作与生活，提高时间管理能力。',
    'zh-TW': '使用下班倒數追蹤工作進度，提升職場效率。即時倒數計時、智慧提醒、進度追蹤，幫助您更好地平衡工作與生活，提高時間管理能力。',
    'zh-HK': '使用下班倒數追蹤工作進度，提升職場效率。即時倒數計時、智能提示、進度追蹤，幫助您更好地平衡工作與生活，提高時間管理能力。',
    'ja': '退勤カウントダウンで仕事の進捗を管理。リアルタイムカウントダウン、通知機能、進捗トラッキングで職場の生産性とワークライフバランスを向上させます。',
    'ko': '퇴근 카운트다운으로 업무 진행 상황을 추적하세요. 실시간 카운트다운, 알림 기능, 진행 상황 추적으로 직장 생산성과 일과 삶의 균형을 향상시킵니다.',
    'fr': 'Suivez votre progression quotidienne avec le compte à rebours de fin de travail. Améliorez la productivité et l\'équilibre travail-vie avec minuteur en temps réel, notifications et suivi des progrès.',
    'de': 'Verfolgen Sie Ihren Arbeitstag mit dem Feierabend-Countdown. Steigern Sie die Produktivität am Arbeitsplatz und die Work-Life-Balance mit Echtzeit-Timer, Benachrichtigungen und Fortschrittsverfolgung.',
    'es': 'Sigue tu progreso laboral con la cuenta regresiva del trabajo. Mejora la productividad y el equilibrio trabajo-vida con temporizador en tiempo real, notificaciones y seguimiento del progreso.',
    'it': 'Monitora il tuo progresso lavorativo con il conto alla rovescia del lavoro. Migliora la produttività sul lavoro e l\'equilibrio vita-lavoro con timer in tempo reale, notifiche e monitoraggio dei progressi.',
    'pt': 'Acompanhe seu progresso diário com a contagem regressiva do trabalho. Melhore a produtividade no trabalho e o equilíbrio trabalho-vida com timer em tempo real, notificações e acompanhamento do progresso.',
    'ru': 'Отслеживайте прогресс рабочего дня с помощью обратного отсчета. Повышайте производительность и баланс между работой и личной жизнью с помощью таймера реального времени, уведомлений и отслеживания прогресса.',
    'hi-IN': 'ऑफ वर्क काउंटडाउन के साथ अपने कार्यदिवस की प्रगति को ट्रैक करें। रीयल-टाइम काउंटडाउन टाइमर, नोटिफिकेशन और प्रगति ट्रैकिंग के साथ कार्यस्थल उत्पादकता और कार्य-जीवन संतुलन बढ़ाएं।',
    'mr-IN': 'ऑफ वर्क काउंटडाउनसह आपल्या कामाच्या दिवसाची प्रगती ट्रॅक करा। रिअल-टाइम काउंटडाउन टाइमर, सूचना आणि प्रगती ट्रॅकिंगसह कार्यस्थळ उत्पादकता आणि कार्य-जीवन संतुलन वाढवा।'
  };

  const keywords: Languages = {
    'en': 'work countdown, productivity timer, time management, workplace efficiency, work progress tracker, office timer',
    'zh-CN': '下班倒计时,工作计时器,时间管理,职场效率,工作进度追踪,办公计时器',
    'zh-TW': '下班倒數,工作計時器,時間管理,職場效率,工作進度追蹤,辦公計時器',
    'zh-HK': '下班倒數,工作計時器,時間管理,職場效率,工作進度追蹤,辦公計時器',
    'ja': '退勤カウントダウン,作業タイマー,時間管理,職場効率,作業進捗トラッカー,オフィスタイマー',
    'ko': '퇴근 카운트다운,작업 타이머,시간 관리,직장 효율성,작업 진행 추적기,사무실 타이머',
    'fr': 'compte à rebours travail,minuteur productivité,gestion temps,efficacité travail,suivi progrès,minuteur bureau',
    'de': 'Arbeitszeit-Countdown,Produktivitäts-Timer,Zeitmanagement,Arbeitsplatzeffizienz,Arbeitsfortschritt-Tracker',
    'es': 'cuenta regresiva trabajo,temporizador productividad,gestión tiempo,eficiencia laboral,seguimiento progreso',
    'it': 'conto alla rovescia lavoro,timer produttività,gestione tempo,efficienza lavoro,monitoraggio progressi',
    'pt': 'contagem regressiva trabalho,temporizador produtividade,gestão tempo,eficiência trabalho,monitoramento progresso',
    'ru': 'обратный отсчет работы,таймер продуктивности,управление временем,эффективность работы,отслеживание прогресса',
    'hi-IN': 'वर्क काउंटडाउन,प्रोडक्टिविटी टाइमर,टाइम मैनेजमेंट,वर्कप्लेस एफिशिएंसी,वर्क प्रोग्रेस ट्रैकर',
    'mr-IN': 'वर्क काउंटडाउन,प्रोडक्टिव्हिटी टाइमर,टाइम मॅनेजमेंट,वर्कप्लेस एफिशिएन्सी,वर्क प्रोग्रेस ट्रॅकर'
  };

  const languageAlternates = locales.reduce((acc: Record<string, string>, l: string) => ({
    ...acc,
    [l]: `https://off.rainif.com/${l}`
  }), {});

  return {
    title: titles[lang] || titles['en'],
    description: descriptions[lang] || descriptions['en'],
    keywords: keywords[lang] || keywords['en'],
    alternates: {
      canonical: `https://off.rainif.com/${lang}`,
      languages: languageAlternates
    },
    openGraph: {
      title: titles[lang] || titles['en'],
      description: descriptions[lang] || descriptions['en'],
      url: `https://off.rainif.com/${lang}`,
      siteName: 'Off Work Countdown',
      locale: lang,
      type: 'website',
      images: [{ 
        url: 'https://github.com/ififi2017/Off-Work-Countdown/raw/main/readme_image/demo.jpg',
        width: 1200,
        height: 630,
        alt: titles[lang] || titles['en']
      }]
    },
    twitter: {
      card: 'summary_large_image',
      title: titles[lang] || titles['en'],
      description: descriptions[lang] || descriptions['en'],
      images: ['https://github.com/ififi2017/Off-Work-Countdown/raw/main/readme_image/demo.jpg'],
    }
  };
}

export async function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

export default function Page({ params: { lang } }: Props) {
  return <OffWorkCountdown lang={lang} />;
} 