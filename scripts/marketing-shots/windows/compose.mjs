// 微软商店截图：1920×1080 CSS，以 2 倍渲染成 3840×2160（商店接受的最大档，16:9）。
// 版式和 macOS 那套同源：左文右图，右边固定舞台，主窗和迷你窗都在舞台正中。
//
// 不补窗口装饰：Windows 上主窗关掉了系统标题栏，最小化 / 关闭按钮是应用自己画的，
// 已经在截图里了。窗口圆角按 Windows 11 的 8px。没有小组件那张——桌面小组件只有
// macOS 有。
//
// 19 种界面语言对应商店商品页的 19 个语言。文案用各语言在应用里的叫法（木鱼 /
// 목탁 / mõ gỗ，其余语言沿用 Woodfish），称呼跟随该语言商品页描述已有的口吻。
// 阿拉伯语整页从右往左排：文案在右、舞台在左，和应用自己在 ar 下的方向一致。

import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BRAND, brandMark, escapeHTML, fontStack } from "../brand.mjs";
import { captureHtml, flattenPng } from "../chrome.mjs";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const OUT = join(DIR, "out");
const HTML_DIR = join(tmpdir(), "off-work-shots-html");
mkdirSync(OUT, { recursive: true });
mkdirSync(HTML_DIR, { recursive: true });

const COPY = {
  en: [
    {
      shot: "countdown",
      title: "Know when your time is yours",
      sub: "The time remaining, how far through you are, and what you have earned today.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Keep it on top of everything",
      sub: "A small timer you can drag anywhere, above your other windows and off the taskbar. Tap the woodfish while you wait.",
    },
    {
      shot: "stats",
      title: "See how your month adds up",
      sub: "Days worked, hours including overtime and every woodfish knock, month by month. It all stays on this PC.",
    },
    {
      shot: "setup",
      title: "Set your hours once",
      sub: "Nine to five, twelve-hour days, or a night shift that runs past midnight.",
    },
    {
      shot: "settings",
      title: "Set it up the way you work",
      sub: "Launch at startup, a global shortcut, 19 languages, light and dark.",
    },
  ],
  "zh-CN": [
    {
      shot: "countdown",
      title: "几点下班，心里有数",
      sub: "剩余时间、已完成进度，以及今天已经挣到的钱。",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "让倒计时\n浮在最上层",
      sub: "拖到屏幕任意位置，盖在其他窗口之上，也不占任务栏。等下班的时候，还能敲敲木鱼。",
    },
    {
      shot: "stats",
      title: "这个月干了多少，\n一眼就知道",
      sub: "出勤天数、含加班的工时，还有敲过的每一下木鱼，按月记着，只存在这台电脑上。",
    },
    {
      shot: "setup",
      title: "上下班时间\n只需设置一次",
      sub: "朝九晚六、十二小时班，还是跨过午夜的夜班，都算得对。",
    },
    {
      shot: "settings",
      title: "按你的工作方式来",
      sub: "开机自启、全局快捷键、19 种语言，明暗主题跟随系统。",
    },
  ],
  "zh-TW": [
    {
      shot: "countdown",
      title: "幾點下班，\n心裡有數",
      sub: "剩餘時間、已完成進度，以及今天已經賺到的錢。",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "讓倒數計時\n浮在最上層",
      sub: "拖到螢幕任意位置，蓋在其他視窗之上，也不占工作列。等下班的時候，還能敲敲木魚。",
    },
    {
      shot: "stats",
      title: "這個月做了多少，\n一眼就知道",
      sub: "出勤天數、含加班的工時，還有敲過的每一下木魚，按月記著，只存在這台電腦上。",
    },
    {
      shot: "setup",
      title: "上下班時間\n只需設定一次",
      sub: "朝九晚六、十二小時班，還是跨過午夜的夜班，都算得對。",
    },
    {
      shot: "settings",
      title: "照你的工作方式來",
      sub: "開機自動啟動、全域快速鍵、19 種語言，明暗主題跟隨系統。",
    },
  ],
  ja: [
    {
      shot: "countdown",
      title: "退勤まで、\nあとどれくらい",
      sub: "残り時間、進み具合、今日ここまでの収入をひと目で。",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "いつも一番手前に",
      sub: "画面のどこへでもドラッグでき、他のウィンドウより前に出ます。タスクバーにも並びません。待つあいだは木魚をどうぞ。",
    },
    {
      shot: "stats",
      title: "今月の働きぶりが\nひと目でわかる",
      sub: "出勤日数、残業を含む勤務時間、木魚を叩いた回数を月ごとに。記録はすべてこのPCの中に。",
    },
    {
      shot: "setup",
      title: "勤務時間の設定は\n一度だけ",
      sub: "9時から18時も、12時間勤務も、日付をまたぐ夜勤も。",
    },
    {
      shot: "settings",
      title: "働き方に合わせて",
      sub: "スタートアップで起動、グローバルショートカット、19言語、ライトとダーク。",
    },
  ],
  ko: [
    {
      shot: "countdown",
      title: "퇴근까지 얼마나 남았는지",
      sub: "남은 시간, 진행률, 오늘 번 돈까지 한눈에.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "언제나 맨 위에",
      sub: "화면 어디로든 끌어다 놓을 수 있고, 다른 창 위에 떠 있으며 작업 표시줄도 차지하지 않아요. 기다리는 동안 목탁도 두드려 보세요.",
    },
    {
      shot: "stats",
      title: "이번 달 근무를 한눈에",
      sub: "출근 일수, 초과 근무를 포함한 근무 시간, 목탁 두드린 횟수까지 월별로. 모든 기록은 이 PC에만 남아요.",
    },
    {
      shot: "setup",
      title: "근무 시간은 한 번만 설정",
      sub: "9시부터 6시까지, 12시간 근무, 자정을 넘기는 야간 근무까지.",
    },
    {
      shot: "settings",
      title: "일하는 방식에 맞게",
      sub: "시작 시 실행, 전역 단축키, 19개 언어, 라이트와 다크 모드.",
    },
  ],
  de: [
    {
      shot: "countdown",
      title: "Wissen, wann Feierabend ist",
      sub: "Die verbleibende Zeit, der Fortschritt und was Sie heute schon verdient haben.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Immer im Vordergrund",
      sub: "Ein kleiner Timer, den Sie überall hinziehen können – über Ihren Fenstern und ohne Platz in der Taskleiste. Und zum Warten gibt es den Woodfish.",
    },
    {
      shot: "stats",
      title: "Sehen, was Ihr Monat ergibt",
      sub: "Arbeitstage, Stunden inklusive Überstunden und jeder Woodfish-Schlag, Monat für Monat. Alles bleibt auf diesem PC.",
    },
    {
      shot: "setup",
      title: "Arbeitszeiten einmal festlegen",
      sub: "Neun bis fünf, Zwölf-Stunden-Tage oder eine Nachtschicht über Mitternacht hinaus.",
    },
    {
      shot: "settings",
      title: "So, wie Sie arbeiten",
      sub: "Beim Systemstart starten, globaler Kurzbefehl, 19 Sprachen, hell und dunkel.",
    },
  ],
  fr: [
    {
      shot: "countdown",
      title: "Sachez quand votre temps vous revient",
      sub: "Le temps restant, votre progression et ce que vous avez gagné aujourd’hui.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Toujours au premier plan",
      sub: "Un minuteur que vous placez où vous voulez, au-dessus de vos fenêtres et sans occuper la barre des tâches. Et pour patienter, frappez le Woodfish.",
    },
    {
      shot: "stats",
      title: "Voyez ce que donne votre mois",
      sub: "Jours travaillés, heures supplémentaires comprises, et chaque frappe du Woodfish, mois par mois. Tout reste sur ce PC.",
    },
    {
      shot: "setup",
      title: "Réglez vos horaires une fois",
      sub: "De neuf à cinq, journées de douze heures ou poste de nuit qui passe minuit.",
    },
    {
      shot: "settings",
      title: "À votre façon de travailler",
      sub: "Lancement au démarrage de Windows, raccourci global, 19 langues, clair et sombre.",
    },
  ],
  es: [
    {
      shot: "countdown",
      title: "Tu hora de salida, siempre a la vista",
      sub: "El tiempo que queda, cuánto llevas y lo que has ganado hoy.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Siempre por encima de todo",
      sub: "Un temporizador que puedes arrastrar a cualquier sitio, sobre tus ventanas y sin ocupar la barra de tareas. Y mientras esperas, golpea el Woodfish.",
    },
    {
      shot: "stats",
      title: "Mira cómo cuadra tu mes",
      sub: "Días trabajados, horas con horas extra y cada toque del Woodfish, mes a mes. Todo se queda en este PC.",
    },
    {
      shot: "setup",
      title: "Tu horario, una sola vez",
      sub: "De nueve a cinco, jornadas de doce horas o un turno de noche que pasa de medianoche.",
    },
    {
      shot: "settings",
      title: "A tu manera de trabajar",
      sub: "Inicio con Windows, atajo global, 19 idiomas, modo claro y oscuro.",
    },
  ],
  it: [
    {
      shot: "countdown",
      title: "Sai quando il tempo torna tuo",
      sub: "Il tempo che manca, a che punto sei e quanto hai guadagnato oggi.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Sempre in primo piano",
      sub: "Un timer che trascini dove vuoi, sopra le altre finestre e senza occupare la barra delle applicazioni. E mentre aspetti, batti il Woodfish.",
    },
    {
      shot: "stats",
      title: "Guarda come va il tuo mese",
      sub: "Giorni lavorati, ore con gli straordinari e ogni colpo di Woodfish, mese per mese. Tutto resta su questo PC.",
    },
    {
      shot: "setup",
      title: "Imposta l’orario una volta",
      sub: "Dalle nove alle cinque, turni di dodici ore o un turno di notte oltre la mezzanotte.",
    },
    {
      shot: "settings",
      title: "Come lavori tu",
      sub: "Avvio con Windows, scorciatoia globale, 19 lingue, chiaro e scuro.",
    },
  ],
  pt: [
    {
      shot: "countdown",
      title: "Saiba quando o tempo volta a ser seu",
      sub: "O tempo que falta, quanto já passou e quanto ganhou hoje.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Sempre à frente de tudo",
      sub: "Um temporizador que arrasta para onde quiser, por cima das outras janelas e sem ocupar a barra de tarefas. Enquanto espera, bata no Woodfish.",
    },
    {
      shot: "stats",
      title: "Veja como fecha o seu mês",
      sub: "Dias trabalhados, horas com horas extra e cada toque no Woodfish, mês a mês. Fica tudo neste PC.",
    },
    {
      shot: "setup",
      title: "Defina o seu horário uma vez",
      sub: "Das nove às cinco, jornadas de doze horas ou um turno da noite que passa da meia-noite.",
    },
    {
      shot: "settings",
      title: "À sua maneira de trabalhar",
      sub: "Iniciar com o Windows, atalho global, 19 idiomas, claro e escuro.",
    },
  ],
  ru: [
    {
      shot: "countdown",
      title: "Видно, когда время снова ваше",
      sub: "Сколько осталось, какая часть дня позади и сколько вы уже заработали.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Поверх всех окон",
      sub: "Таймер можно перетащить в любой угол: он поверх других окон и не занимает панель задач. А пока ждёте — стучите по Woodfish.",
    },
    {
      shot: "stats",
      title: "Весь месяц как на ладони",
      sub: "Рабочие дни, часы с учётом переработок и каждый удар по Woodfish — по месяцам. Всё остаётся на этом ПК.",
    },
    {
      shot: "setup",
      title: "График задаётся один раз",
      sub: "С девяти до шести, смены по двенадцать часов или ночная смена после полуночи.",
    },
    {
      shot: "settings",
      title: "Под ваш ритм работы",
      sub: "Запуск вместе с Windows, глобальное сочетание клавиш, 19 языков, светлая и тёмная тема.",
    },
  ],
  "hi-IN": [
    {
      shot: "countdown",
      title: "जानिए कब आपका समय आपका होगा",
      sub: "बचा हुआ समय, कितना सफ़र तय हुआ और आज की कमाई।",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "हर विंडो के ऊपर",
      sub: "टाइमर को स्क्रीन पर कहीं भी खींचकर रखें — बाकी विंडो के ऊपर, और टास्कबार में जगह लिए बिना। इंतज़ार में Woodfish बजाते रहें।",
    },
    {
      shot: "stats",
      title: "पूरा महीना एक नज़र में",
      sub: "काम के दिन, ओवरटाइम समेत घंटे और Woodfish की हर ठोक, महीने-दर-महीने। सब कुछ इसी PC पर रहता है।",
    },
    {
      shot: "setup",
      title: "काम के घंटे बस एक बार तय करें",
      sub: "नौ से पाँच, बारह घंटे की शिफ़्ट या आधी रात के पार चलने वाली नाइट शिफ़्ट।",
    },
    {
      shot: "settings",
      title: "आपके काम करने के तरीके से",
      sub: "Windows के साथ शुरू, ग्लोबल शॉर्टकट, 19 भाषाएँ, लाइट और डार्क।",
    },
  ],
  "mr-IN": [
    {
      shot: "countdown",
      title: "तुमचा वेळ कधी तुमचा होतो, ते कळतं",
      sub: "उरलेला वेळ, किती दिवस सरला आणि आजची कमाई.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "नेहमी सगळ्यांच्या वर",
      sub: "टायमर स्क्रीनवर कुठेही ठेवा — इतर विंडोंच्या वर, आणि टास्कबारमध्ये जागा न घेता. वाट पाहताना Woodfish वाजवा.",
    },
    {
      shot: "stats",
      title: "पूर्ण महिना एका नजरेत",
      sub: "कामाचे दिवस, ओव्हरटाइमसह तास आणि Woodfish चा प्रत्येक ठोका, महिन्यानुसार. सगळं याच PC वर राहतं.",
    },
    {
      shot: "setup",
      title: "कामाचे तास एकदाच ठरवा",
      sub: "नऊ ते पाच, बारा तासांची शिफ्ट किंवा मध्यरात्र ओलांडणारी नाइट शिफ्ट.",
    },
    {
      shot: "settings",
      title: "तुमच्या कामाच्या पद्धतीनुसार",
      sub: "Windows सोबत सुरू, ग्लोबल शॉर्टकट, 19 भाषा, लाइट आणि डार्क.",
    },
  ],
  tr: [
    {
      shot: "countdown",
      title: "Zamanın ne zaman size kalacağını bilin",
      sub: "Kalan süre, ne kadar ilerlediğiniz ve bugün ne kazandığınız.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Her şeyin üstünde",
      sub: "Ekranda istediğiniz yere sürükleyebileceğiniz bir sayaç: diğer pencerelerin üstünde durur, görev çubuğunda yer kaplamaz. Beklerken Woodfish’e vurun.",
    },
    {
      shot: "stats",
      title: "Ayınızın nasıl geçtiğini görün",
      sub: "Çalışılan günler, fazla mesai dahil saatler ve Woodfish’e her vuruş, ay ay. Hepsi bu bilgisayarda kalır.",
    },
    {
      shot: "setup",
      title: "Mesai saatinizi bir kez ayarlayın",
      sub: "Dokuz-beş, on iki saatlik günler ya da gece yarısını geçen gece vardiyası.",
    },
    {
      shot: "settings",
      title: "Çalışma şeklinize göre",
      sub: "Windows ile birlikte başlatma, genel kısayol, 19 dil, açık ve koyu görünüm.",
    },
  ],
  ar: [
    {
      shot: "countdown",
      title: "اعرف متى يعود وقتك إليك",
      sub: "الوقت المتبقي، ومدى تقدمك، وما كسبته اليوم.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "دائمًا فوق كل النوافذ",
      sub: "مؤقت يمكنك سحبه إلى أي مكان على الشاشة، فوق النوافذ الأخرى ودون أن يشغل شريط المهام. وأثناء الانتظار، اطرق على Woodfish.",
    },
    {
      shot: "stats",
      title: "شهرك كله في لمحة",
      sub: "أيام العمل، والساعات مع العمل الإضافي، وكل طرقة على Woodfish، شهرًا بعد شهر. كل ذلك يبقى على هذا الكمبيوتر.",
    },
    {
      shot: "setup",
      title: "اضبط ساعات عملك مرة واحدة",
      sub: "من التاسعة إلى الخامسة، أو أيام من اثنتي عشرة ساعة، أو وردية ليلية تتجاوز منتصف الليل.",
    },
    {
      shot: "settings",
      title: "على طريقتك في العمل",
      sub: "التشغيل مع بدء Windows، واختصار عام، و19 لغة، ووضعان فاتح وداكن.",
    },
  ],
  th: [
    {
      shot: "countdown",
      title: "รู้ว่าเมื่อไหร่เวลาจะเป็นของคุณ",
      sub: "เวลาที่เหลือ ความคืบหน้า และรายได้ของวันนี้",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "ลอยอยู่เหนือทุกหน้าต่าง",
      sub: "ลากตัวจับเวลาไปวางตรงไหนของจอก็ได้ อยู่เหนือหน้าต่างอื่นและไม่กินที่บนแถบงาน ระหว่างรอก็เคาะ Woodfish ไปพลาง ๆ",
    },
    {
      shot: "stats",
      title: "ดูภาพรวมทั้งเดือน",
      sub: "วันทำงาน ชั่วโมงรวมโอที และทุกครั้งที่เคาะ Woodfish แยกตามเดือน ทุกอย่างอยู่ในเครื่องนี้เท่านั้น",
    },
    {
      shot: "setup",
      title: "ตั้งเวลาทำงานครั้งเดียว",
      sub: "เก้าโมงถึงห้าโมง กะสิบสองชั่วโมง หรือกะดึกที่ข้ามเที่ยงคืน",
    },
    {
      shot: "settings",
      title: "ปรับให้เข้ากับการทำงานของคุณ",
      sub: "เปิดพร้อม Windows ปุ่มลัดส่วนกลาง 19 ภาษา โหมดสว่างและมืด",
    },
  ],
  id: [
    {
      shot: "countdown",
      title: "Tahu kapan jam kerja usai",
      sub: "Sisa waktu, progres hari ini, dan penghasilan Anda sejauh ini.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Selalu di atas jendela lain",
      sub: "Timer yang bisa Anda seret ke mana saja, di atas jendela lain dan tanpa memenuhi bilah tugas. Sambil menunggu, ketuk Woodfish.",
    },
    {
      shot: "stats",
      title: "Lihat rekap bulan Anda",
      sub: "Hari kerja, jam kerja termasuk lembur, dan setiap ketukan Woodfish, bulan demi bulan. Semuanya tetap di PC ini.",
    },
    {
      shot: "setup",
      title: "Atur jam kerja sekali saja",
      sub: "Jam sembilan sampai lima, hari kerja dua belas jam, atau sif malam yang lewat tengah malam.",
    },
    {
      shot: "settings",
      title: "Sesuai cara Anda bekerja",
      sub: "Jalankan bersama Windows, pintasan global, 19 bahasa, terang dan gelap.",
    },
  ],
  vi: [
    {
      shot: "countdown",
      title: "Biết khi nào thời gian là của bạn",
      sub: "Thời gian còn lại, tiến độ và số tiền bạn đã kiếm được hôm nay.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Luôn nổi trên cùng",
      sub: "Bộ hẹn giờ kéo tới đâu cũng được, nằm trên các cửa sổ khác và không chiếm chỗ trên thanh tác vụ. Trong lúc chờ, gõ mõ cho vui.",
    },
    {
      shot: "stats",
      title: "Cả tháng trong một cái nhìn",
      sub: "Số ngày làm, giờ làm tính cả tăng ca và từng tiếng gõ mõ, theo từng tháng. Mọi thứ chỉ nằm trên máy này.",
    },
    {
      shot: "setup",
      title: "Đặt giờ làm một lần",
      sub: "Chín giờ đến năm giờ, ca mười hai tiếng hay ca đêm qua nửa đêm.",
    },
    {
      shot: "settings",
      title: "Theo cách bạn làm việc",
      sub: "Khởi chạy cùng Windows, phím tắt toàn cục, 19 ngôn ngữ, sáng và tối.",
    },
  ],
  "zh-HK": [
    {
      shot: "countdown",
      title: "幾點下班，\n心裡有數",
      sub: "剩餘時間、已完成進度，以及今天已經賺到的錢。",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "讓倒數計時\n浮在最上層",
      sub: "拖到螢幕任意位置，蓋在其他視窗之上，也不佔工作列。等下班的時候，還能敲敲木魚。",
    },
    {
      shot: "stats",
      title: "這個月做了多少，\n一眼就知道",
      sub: "出勤天數、含加班的工時，還有敲過的每一下木魚，按月記著，只存在這部電腦上。",
    },
    {
      shot: "setup",
      title: "上下班時間\n只需設定一次",
      sub: "朝九晚六、十二小時班，還是跨過午夜的夜班，都算得對。",
    },
    {
      shot: "settings",
      title: "照你的工作方式來",
      sub: "開機自動啟動、全域快速鍵、19 種語言，明暗主題跟隨系統。",
    },
  ],
};

function dataUri(path) {
  if (!existsSync(path)) {
    throw new Error(`Missing ${path}. Run npm run shots:windows:capture first.`);
  }
  return `data:image/png;base64,${readFileSync(path).toString("base64")}`;
}

// DESKTOP_SHOTS_LANGUAGE=ja,ko 只重排其中几种语言。
const only = process.env.DESKTOP_SHOTS_LANGUAGE?.split(",").map((value) => value.trim());

function page(card, language) {
  const kind = card.mini ? "mini" : "window";
  const width = card.mini ? 600 : 640;
  const rtl = language === "ar";
  // 负字距会把阿拉伯文的连写拆开，天城文和泰文的上下标也会挤在一起。
  const tracking = ["ar", "hi-IN", "mr-IN", "th"].includes(language) ? "0" : "-0.03em";

  return `<!doctype html><html lang="${language}" dir="${rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 1920px; height: 1080px; overflow: hidden; }
    body {
      font-family: ${fontStack(language)};
      background:
        radial-gradient(1000px 740px at ${rtl ? "22%" : "78%"} 70%, rgba(244, 90, 30, .24), transparent 58%),
        radial-gradient(700px 560px at ${rtl ? "92%" : "8%"} 12%, rgba(255, 154, 69, .10), transparent 64%),
        linear-gradient(158deg, ${BRAND.eveningStart} 0%, ${BRAND.plum} 48%, ${BRAND.eveningEnd} 100%);
      display: flex; align-items: stretch;
      padding: 0 132px;
    }
    .copy {
      flex: 0 0 700px; width: 700px;
      display: flex; flex-direction: column; justify-content: center;
      padding-inline-end: 48px;
      /* 韩文默认按音节断行，会把「얼마나」折成「얼마 / 나」；只在空格处换行。 */
      word-break: ${language === "ko" ? "keep-all" : "normal"};
    }
    .brand {
      display: inline-flex; align-items: center; gap: 12px;
      color: ${BRAND.orangeBright}; font-size: 22px; font-weight: 700; letter-spacing: .04em;
    }
    .mark { width: 32px; height: 32px; }
    .title {
      margin-top: 28px;
      font-size: 72px; font-weight: 700; line-height: 1.12; letter-spacing: ${tracking};
      color: ${BRAND.cream}; text-wrap: balance;
    }
    .sub {
      margin-top: 28px; font-size: 30px; line-height: 1.48; font-weight: 400;
      color: color-mix(in srgb, ${BRAND.cream} 64%, transparent);
      text-wrap: balance;
    }
    .stage {
      flex: 1; min-width: 0;
      display: flex; align-items: center; justify-content: center;
    }
    .shot { position: relative; width: ${width}px; }
    .shot img { display: block; width: 100%; height: auto; }
    .shot.window {
      border-radius: 8px; overflow: hidden;
      box-shadow: 0 0 0 1px rgba(0, 0, 0, .22), 0 40px 80px rgba(0, 0, 0, .42), 0 10px 24px rgba(0, 0, 0, .28);
    }
    .shot.mini {
      filter: drop-shadow(0 32px 56px rgba(0, 0, 0, .38));
    }
  </style></head><body>
    <div class="copy">
      <div class="brand">${brandMark(BRAND.cream)}<span dir="ltr">${BRAND.name}</span></div>
      <div class="title">${escapeHTML(card.title).replaceAll("\n", "<br>")}</div>
      <div class="sub">${escapeHTML(card.sub)}</div>
    </div>
    <div class="stage">
      <div class="shot ${kind}">
        <img src="${dataUri(join(RAW, `${language}-${card.shot}.png`))}" alt="">
      </div>
    </div>
  </body></html>`;
}

for (const [language, cards] of Object.entries(COPY)) {
  if (only && !only.includes(language)) continue;
  for (const [index, card] of cards.entries()) {
    const name = `${language}-${String(index + 1).padStart(2, "0")}-${card.shot}`;
    const outFile = join(OUT, `${name}.png`);
    await captureHtml({
      html: page(card, language),
      htmlPath: join(HTML_DIR, `p-windows-${name}.html`),
      width: 1920,
      height: 1080,
      scale: 2,
      outFile,
    });
    // 商店拒收带透明通道的 PNG 这一条，微软与 Apple 一样稳妥起见都压实。
    flattenPng(outFile);
    console.log(`composed ${name}.png`);
  }
}

console.log("done");
