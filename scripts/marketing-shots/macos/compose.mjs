// Mac App Store 截图：1440×900 CSS，以 2 倍渲染成 2880×1800（Apple 接受的最大档，16:10）。
// 左文右图。右边是一块固定舞台，主窗、迷你窗、小组件桌面图尺寸不同，都在舞台正中。
// App Store Connect 拒收带透明通道的 PNG。
//
// 交通灯由这里画：应用在 macOS 上用覆盖式标题栏，浏览器截图里那块是空的。
//
// 17 种界面语言对应 17 个商店语言。阿拉伯语整页从右往左排：文案在右、舞台在左，
// 和应用自己在 ar 下的方向一致。

import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BRAND, brandMark, escapeHTML, fontStack } from "../brand.mjs";
import { captureHtml, flattenPng } from "../chrome.mjs";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const ASSETS = join(DIR, "assets");
const OUT = join(DIR, "out");
const HTML_DIR = join(tmpdir(), "off-work-shots-html");
mkdirSync(OUT, { recursive: true });
mkdirSync(HTML_DIR, { recursive: true });
if (existsSync(DIR)) {
  for (const name of readdirSync(DIR)) {
    if (name.startsWith("p-") && name.endsWith(".html")) rmSync(join(DIR, name));
  }
}

// 每种语言六张，顺序固定：倒计时、迷你窗、统计、班次、设置、小组件。
// 中文、日文没有空格，text-wrap: balance 会从词中间折开（「干了多 / 少」）；
// 长标题用 \n 标出语义断点。
const SHOTS = ["countdown", "mini-woodfish", "stats", "setup", "settings", "widget"];
const LINES = {
  en: [
    ["Know when your time is yours", "The time remaining, how far through you are, and what you have earned today."],
    ["Keep it on top of everything", "A floating timer you can park in any corner. Tap the woodfish while you wait."],
    ["See how your month adds up", "Days worked, hours including overtime and every woodfish knock, month by month. It all stays on your Mac."],
    ["Set your hours once", "Nine to five, twelve-hour days, or a night shift that runs past midnight."],
    ["Set it up the way you work", "Launch at login, a global shortcut, 19 languages, light and dark."],
    ["Or keep it on the desktop itself", "Small and medium widgets, on your desktop or in Notification Center. They keep counting with the app closed."],
  ],
  "zh-CN": [
    ["几点下班，心里有数", "剩余时间、已完成进度，以及今天已经挣到的钱。"],
    ["让倒计时\n浮在最上层", "可以停在屏幕任意角落。等下班的时候，还能敲敲木鱼。"],
    ["这个月干了多少，\n一眼就知道", "出勤天数、含加班的工时，还有敲过的每一下木鱼，按月记着，只存在你的 Mac 上。"],
    ["上下班时间\n只需设置一次", "朝九晚六、十二小时班，还是跨过午夜的夜班，都算得对。"],
    ["按你的工作方式来", "开机自启、全局快捷键、19 种语言，明暗主题跟随系统。"],
    ["也可以直接\n放在桌面上", "小号和中号两种小组件，放在桌面或通知中心。应用关着，倒计时照样在走。"],
  ],
  "zh-TW": [
    ["幾點下班，\n心裡有數", "剩餘時間、已完成進度，以及今天已經賺到的錢。"],
    ["讓倒數計時\n浮在最上層", "可以停在螢幕任意角落。等下班的時候，還能敲敲木魚。"],
    ["這個月做了多少，\n一眼就知道", "出勤天數、含加班的工時，還有敲過的每一下木魚，按月記著，只存在你的 Mac 上。"],
    ["上下班時間\n只需設定一次", "朝九晚六、十二小時班，還是跨過午夜的夜班，都算得對。"],
    ["照你的工作方式來", "登入時啟動、全域快速鍵、19 種語言，明暗主題跟隨系統。"],
    ["也可以直接\n放在桌面上", "小型和中型兩種小工具，放在桌面或通知中心。App 關著，倒數照樣在走。"],
  ],
  ja: [
    ["退勤まで、\nあとどれくらい", "残り時間、進み具合、今日ここまでの収入をひと目で。"],
    ["いつも一番手前に", "画面の好きな隅に置けるフローティングタイマー。待つあいだは木魚をどうぞ。"],
    ["今月の働きぶりが\nひと目でわかる", "出勤日数、残業を含む勤務時間、木魚を叩いた回数を月ごとに。記録はすべてこのMacの中に。"],
    ["勤務時間の設定は\n一度だけ", "9時から18時も、12時間勤務も、日付をまたぐ夜勤も。"],
    ["働き方に合わせて", "ログイン時に起動、グローバルショートカット、19言語、ライトとダーク。"],
    ["デスクトップにも\n置いておける", "小・中サイズのウィジェットをデスクトップや通知センターに。アプリを閉じてもカウントは続きます。"],
  ],
  ko: [
    ["퇴근까지 얼마나 남았는지", "남은 시간, 진행률, 오늘 번 돈까지 한눈에."],
    ["언제나 맨 위에", "화면 어느 구석에나 둘 수 있는 미니 타이머. 기다리는 동안 목탁도 두드려 보세요."],
    ["이번 달 근무를 한눈에", "출근 일수, 초과 근무를 포함한 근무 시간, 목탁 두드린 횟수까지 월별로. 모든 기록은 이 Mac에만 남아요."],
    ["근무 시간은 한 번만 설정", "9시부터 6시까지, 12시간 근무, 자정을 넘기는 야간 근무까지."],
    ["일하는 방식에 맞게", "로그인 시 실행, 전역 단축키, 19개 언어, 라이트와 다크 모드."],
    ["데스크탑 위에 그대로", "소형·중형 위젯을 데스크탑이나 알림 센터에. 앱을 닫아도 계속 셉니다."],
  ],
  de: [
    ["Wissen, wann Feierabend ist", "Die verbleibende Zeit, der Fortschritt und was Sie heute schon verdient haben."],
    ["Immer im Vordergrund", "Ein schwebender Timer für jede Bildschirmecke. Und zum Warten gibt es den Woodfish."],
    ["Sehen, was Ihr Monat ergibt", "Arbeitstage, Stunden inklusive Überstunden und jeder Woodfish-Schlag, Monat für Monat. Alles bleibt auf Ihrem Mac."],
    ["Arbeitszeiten einmal festlegen", "Neun bis fünf, Zwölf-Stunden-Tage oder eine Nachtschicht über Mitternacht hinaus."],
    ["So, wie Sie arbeiten", "Beim Anmelden starten, globaler Kurzbefehl, 19 Sprachen, hell und dunkel."],
    ["Oder direkt auf dem Schreibtisch", "Kleine und mittelgroße Widgets auf dem Schreibtisch oder in der Mitteilungszentrale. Sie zählen weiter, auch wenn die App geschlossen ist."],
  ],
  es: [
    ["Tu hora de salida, siempre a la vista", "El tiempo que queda, cuánto llevas y lo que has ganado hoy."],
    ["Siempre por encima de todo", "Un temporizador flotante que puedes dejar en cualquier esquina. Y mientras esperas, golpea el Woodfish."],
    ["Mira cómo cuadra tu mes", "Días trabajados, horas con horas extra y cada toque del Woodfish, mes a mes. Todo se queda en tu Mac."],
    ["Tu horario, una sola vez", "De nueve a cinco, jornadas de doce horas o un turno de noche que pasa de medianoche."],
    ["A tu manera de trabajar", "Abrir al iniciar sesión, atajo global, 19 idiomas, modo claro y oscuro."],
    ["O déjalo en el escritorio", "Widgets pequeño y mediano, en el escritorio o en el Centro de Notificaciones. Siguen contando con la app cerrada."],
  ],
  fr: [
    ["Sachez quand votre temps vous revient", "Le temps restant, votre progression et ce que vous avez gagné aujourd’hui."],
    ["Toujours au premier plan", "Un minuteur flottant à placer dans n’importe quel coin. Et pour patienter, frappez le Woodfish."],
    ["Voyez ce que donne votre mois", "Jours travaillés, heures supplémentaires comprises, et chaque frappe du Woodfish, mois par mois. Tout reste sur votre Mac."],
    ["Réglez vos horaires une fois", "De neuf à cinq, journées de douze heures ou poste de nuit qui passe minuit."],
    ["À votre façon de travailler", "Lancement à la connexion, raccourci global, 19 langues, clair et sombre."],
    ["Ou gardez-le sur le bureau", "Widgets petit et moyen, sur le bureau ou dans le Centre de notifications. Ils continuent de compter, app fermée."],
  ],
  it: [
    ["Sai quando il tempo torna tuo", "Il tempo che manca, a che punto sei e quanto hai guadagnato oggi."],
    ["Sempre in primo piano", "Un timer fluttuante da lasciare in qualsiasi angolo. E mentre aspetti, batti il Woodfish."],
    ["Guarda come va il tuo mese", "Giorni lavorati, ore con gli straordinari e ogni colpo di Woodfish, mese per mese. Tutto resta sul tuo Mac."],
    ["Imposta l’orario una volta", "Dalle nove alle cinque, turni di dodici ore o un turno di notte oltre la mezzanotte."],
    ["Come lavori tu", "Avvio all’accesso, scorciatoia globale, 19 lingue, chiaro e scuro."],
    ["Oppure tienilo sulla scrivania", "Widget piccoli e medi, sulla scrivania o nel Centro Notifiche. Continuano a contare anche ad app chiusa."],
  ],
  pt: [
    ["Saiba quando o tempo volta a ser seu", "O tempo que falta, quanto já foi e quanto você ganhou hoje."],
    ["Sempre à frente de tudo", "Um timer flutuante para deixar em qualquer canto. Enquanto espera, bata no Woodfish."],
    ["Veja como fecha o seu mês", "Dias trabalhados, horas com hora extra e cada toque no Woodfish, mês a mês. Tudo fica no seu Mac."],
    ["Defina seu horário uma vez", "Das nove às cinco, jornadas de doze horas ou um turno da noite que passa da meia-noite."],
    ["Do jeito que você trabalha", "Abrir ao iniciar sessão, atalho global, 19 idiomas, claro e escuro."],
    ["Ou deixe na mesa", "Widgets pequeno e médio, na mesa ou na Central de Notificações. Continuam contando com o app fechado."],
  ],
  ru: [
    ["Видно, когда время снова ваше", "Сколько осталось, какая часть дня позади и сколько вы уже заработали."],
    ["Поверх всех окон", "Плавающий таймер, который можно поставить в любой угол. А пока ждёте — стучите по Woodfish."],
    ["Весь месяц как на ладони", "Рабочие дни, часы с учётом переработок и каждый удар по Woodfish — по месяцам. Всё остаётся на вашем Mac."],
    ["График задаётся один раз", "С девяти до шести, смены по двенадцать часов или ночная смена после полуночи."],
    ["Под ваш ритм работы", "Запуск при входе, глобальное сочетание клавиш, 19 языков, светлая и тёмная тема."],
    ["Или прямо на рабочем столе", "Маленький и средний виджеты — на рабочем столе или в Центре уведомлений. Продолжают считать, даже когда приложение закрыто."],
  ],
  ar: [
    ["اعرف متى يعود وقتك إليك", "الوقت المتبقي، ومدى تقدمك، وما كسبته اليوم."],
    ["دائمًا فوق كل النوافذ", "مؤقت عائم تضعه في أي زاوية من الشاشة. وأثناء الانتظار، اطرق على Woodfish."],
    ["شهرك كله في لمحة", "أيام العمل، والساعات مع العمل الإضافي، وكل طرقة على Woodfish، شهرًا بعد شهر. كل ذلك يبقى على جهاز Mac."],
    ["اضبط ساعات عملك مرة واحدة", "من التاسعة إلى الخامسة، أو أيام من اثنتي عشرة ساعة، أو وردية ليلية تتجاوز منتصف الليل."],
    ["على طريقتك في العمل", "التشغيل عند تسجيل الدخول، واختصار عام، و19 لغة، ووضعان فاتح وداكن."],
    ["أو أبقه على سطح المكتب", "أدوات صغيرة ومتوسطة على سطح المكتب أو في مركز الإشعارات. تواصل العد حتى والتطبيق مغلق."],
  ],
  "hi-IN": [
    ["जानिए कब आपका समय आपका होगा", "बचा हुआ समय, कितना सफ़र तय हुआ और आज की कमाई।"],
    ["हर विंडो के ऊपर", "एक तैरता टाइमर, जिसे स्क्रीन के किसी भी कोने में रखें। इंतज़ार में Woodfish बजाते रहें।"],
    ["पूरा महीना एक नज़र में", "काम के दिन, ओवरटाइम समेत घंटे और Woodfish की हर ठोक, महीने-दर-महीने। सब कुछ आपके Mac पर ही रहता है।"],
    ["काम के घंटे बस एक बार तय करें", "नौ से पाँच, बारह घंटे की शिफ़्ट या आधी रात के पार चलने वाली नाइट शिफ़्ट।"],
    ["आपके काम करने के तरीके से", "लॉग इन पर शुरू, ग्लोबल शॉर्टकट, 19 भाषाएँ, लाइट और डार्क।"],
    ["या सीधे डेस्कटॉप पर रखें", "छोटे और मध्यम विजेट, डेस्कटॉप पर या सूचना केंद्र में। ऐप बंद होने पर भी गिनती चलती रहती है।"],
  ],
  id: [
    ["Tahu kapan jam kerja usai", "Sisa waktu, progres hari ini, dan penghasilan Anda sejauh ini."],
    ["Selalu di atas jendela lain", "Timer mengambang yang bisa Anda taruh di sudut mana saja. Sambil menunggu, ketuk Woodfish."],
    ["Lihat rekap bulan Anda", "Hari kerja, jam kerja termasuk lembur, dan setiap ketukan Woodfish, bulan demi bulan. Semuanya tetap di Mac Anda."],
    ["Atur jam kerja sekali saja", "Jam sembilan sampai lima, hari kerja dua belas jam, atau sif malam yang lewat tengah malam."],
    ["Sesuai cara Anda bekerja", "Jalankan saat masuk, pintasan global, 19 bahasa, terang dan gelap."],
    ["Atau taruh langsung di desktop", "Widget kecil dan sedang, di desktop atau Pusat Pemberitahuan. Terus menghitung meski aplikasi ditutup."],
  ],
  th: [
    ["รู้ว่าเมื่อไหร่เวลาจะเป็นของคุณ", "เวลาที่เหลือ ความคืบหน้า และรายได้ของวันนี้"],
    ["ลอยอยู่เหนือทุกหน้าต่าง", "ตัวจับเวลาแบบลอยที่วางไว้มุมไหนของจอก็ได้ ระหว่างรอก็เคาะ Woodfish ไปพลาง ๆ"],
    ["ดูภาพรวมทั้งเดือน", "วันทำงาน ชั่วโมงรวมโอที และทุกครั้งที่เคาะ Woodfish แยกตามเดือน ทุกอย่างอยู่ใน Mac ของคุณเท่านั้น"],
    ["ตั้งเวลาทำงานครั้งเดียว", "เก้าโมงถึงห้าโมง กะสิบสองชั่วโมง หรือกะดึกที่ข้ามเที่ยงคืน"],
    ["ปรับให้เข้ากับการทำงานของคุณ", "เปิดเมื่อเข้าสู่ระบบ ปุ่มลัดส่วนกลาง 19 ภาษา โหมดสว่างและมืด"],
    ["หรือวางไว้บนเดสก์ท็อป", "วิดเจ็ตขนาดเล็กและกลาง บนเดสก์ท็อปหรือในศูนย์การแจ้งเตือน นับต่อแม้ปิดแอปแล้ว"],
  ],
  tr: [
    ["Zamanın ne zaman size kalacağını bilin", "Kalan süre, ne kadar ilerlediğiniz ve bugün ne kazandığınız."],
    ["Her şeyin üstünde", "Ekranın istediğiniz köşesine koyabileceğiniz yüzen bir sayaç. Beklerken Woodfish’e vurun."],
    ["Ayınızın nasıl geçtiğini görün", "Çalışılan günler, fazla mesai dahil saatler ve Woodfish’e her vuruş, ay ay. Hepsi Mac’inizde kalır."],
    ["Mesai saatinizi bir kez ayarlayın", "Dokuz-beş, on iki saatlik günler ya da gece yarısını geçen gece vardiyası."],
    ["Çalışma şeklinize göre", "Oturum açınca başlatma, genel kısayol, 19 dil, açık ve koyu görünüm."],
    ["Ya da doğrudan masaüstünde", "Küçük ve orta boy widget’lar, masaüstünde ya da Bildirim Merkezi’nde. Uygulama kapalıyken de saymaya devam eder."],
  ],
  vi: [
    ["Biết khi nào thời gian là của bạn", "Thời gian còn lại, tiến độ và số tiền bạn đã kiếm được hôm nay."],
    ["Luôn nổi trên cùng", "Bộ hẹn giờ nổi, đặt ở góc nào trên màn hình cũng được. Trong lúc chờ, gõ mõ cho vui."],
    ["Cả tháng trong một cái nhìn", "Số ngày làm, giờ làm tính cả tăng ca và từng tiếng gõ mõ, theo từng tháng. Mọi thứ chỉ nằm trên Mac của bạn."],
    ["Đặt giờ làm một lần", "Chín giờ đến năm giờ, ca mười hai tiếng hay ca đêm qua nửa đêm."],
    ["Theo cách bạn làm việc", "Khởi chạy khi đăng nhập, phím tắt toàn cục, 19 ngôn ngữ, sáng và tối."],
    ["Hoặc đặt ngay trên màn hình nền", "Widget cỡ nhỏ và vừa, trên màn hình nền hoặc Trung tâm thông báo. Vẫn đếm dù ứng dụng đã đóng."],
  ],
};

// DESKTOP_SHOTS_LANGUAGE=ja,ko 只重排其中几种语言。
const only = process.env.DESKTOP_SHOTS_LANGUAGE?.split(",").map((value) => value.trim());

function titleHTML(title) {
  return escapeHTML(title).replaceAll("\n", "<br>");
}

function dataUri(path, mime) {
  if (!existsSync(path)) {
    throw new Error(`Missing ${path}. Run npm run shots:macos:capture first.`);
  }
  return `data:${mime};base64,${readFileSync(path).toString("base64")}`;
}

function sourceUri(shot, language) {
  if (shot === "widget") {
    // 小组件是真机桌面截图，只有英文和简体中文两张素材；其余语言用英文那张。
    const own = join(ASSETS, `widget-${language}.jpg`);
    return dataUri(existsSync(own) ? own : join(ASSETS, "widget-en.jpg"), "image/jpeg");
  }
  return dataUri(join(RAW, `${language}-${shot}.png`), "image/png");
}

function page(shot, [title, sub], language) {
  const kind = shot === "mini-woodfish" ? "mini" : shot === "widget" ? "crop" : "window";
  const width = kind === "mini" ? 520 : kind === "crop" ? 620 : 488;
  const rtl = language === "ar";
  // 负字距会把阿拉伯文的连写拆开，天城文和泰文的上下标也会挤在一起。
  const tracking = ["ar", "hi-IN", "th"].includes(language) ? "0" : "-0.03em";
  const lights = kind === "window"
    ? '<div class="lights" aria-hidden="true"><i></i><i></i><i></i></div>'
    : "";

  return `<!doctype html><html lang="${language}" dir="${rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 1440px; height: 900px; overflow: hidden; }
    body {
      font-family: ${fontStack(language)};
      background:
        radial-gradient(760px 560px at ${rtl ? "22%" : "78%"} 70%, rgba(244, 90, 30, .24), transparent 58%),
        radial-gradient(520px 420px at ${rtl ? "92%" : "8%"} 12%, rgba(255, 154, 69, .10), transparent 64%),
        linear-gradient(158deg, ${BRAND.eveningStart} 0%, ${BRAND.plum} 48%, ${BRAND.eveningEnd} 100%);
      display: flex; align-items: stretch;
      padding: 0 88px;
    }
    .copy {
      flex: 0 0 520px; width: 520px;
      display: flex; flex-direction: column; justify-content: center;
      padding-inline-end: 36px;
      /* 韩文默认按音节断行，会把「얼마나」折成「얼마 / 나」；只在空格处换行。 */
      word-break: ${language === "ko" ? "keep-all" : "normal"};
    }
    .brand {
      display: inline-flex; align-items: center; gap: 10px;
      color: ${BRAND.orangeBright}; font-size: 18px; font-weight: 700; letter-spacing: .04em;
    }
    .mark { width: 26px; height: 26px; }
    .title {
      margin-top: 22px;
      font-size: 56px; font-weight: 700; line-height: 1.14; letter-spacing: ${tracking};
      color: ${BRAND.cream}; text-wrap: balance;
    }
    .sub {
      margin-top: 22px; font-size: 24px; line-height: 1.48; font-weight: 400;
      color: color-mix(in srgb, ${BRAND.cream} 64%, transparent);
      text-wrap: balance;
    }
    .stage {
      flex: 1; min-width: 0;
      display: flex; align-items: center; justify-content: center;
    }
    .shot { position: relative; width: ${width}px; }
    .shot img { display: block; width: 100%; height: auto; }
    .shot.window, .shot.crop {
      border-radius: ${kind === "crop" ? 18 : 26}px; overflow: hidden;
      box-shadow: 0 36px 72px rgba(0, 0, 0, .42), 0 8px 20px rgba(0, 0, 0, .28);
    }
    .shot.mini {
      filter: drop-shadow(0 28px 48px rgba(0, 0, 0, .38));
    }
    /* macOS 在从右往左的语言里也不镜像交通灯，始终在窗口左上角。 */
    .lights { position: absolute; top: 19px; left: 21px; display: flex; gap: 8px; z-index: 2; direction: ltr; }
    .lights i { width: 13px; height: 13px; border-radius: 50%; display: block; }
    .lights i:nth-child(1) { background: #ff5f57; }
    .lights i:nth-child(2) { background: #febc2e; }
    .lights i:nth-child(3) { background: #28c840; }
  </style></head><body>
    <div class="copy">
      <div class="brand">${brandMark(BRAND.cream)}<span dir="ltr">${BRAND.name}</span></div>
      <div class="title">${titleHTML(title)}</div>
      <div class="sub">${escapeHTML(sub)}</div>
    </div>
    <div class="stage">
      <div class="shot ${kind}">
        ${lights}
        <img src="${sourceUri(shot, language)}" alt="">
      </div>
    </div>
  </body></html>`;
}

for (const [language, cards] of Object.entries(LINES)) {
  if (only && !only.includes(language)) continue;
  for (const [index, shot] of SHOTS.entries()) {
    const name = `${language}-${String(index + 1).padStart(2, "0")}-${shot}`;
    const outFile = join(OUT, `${name}.png`);
    await captureHtml({
      html: page(shot, cards[index], language),
      htmlPath: join(HTML_DIR, `p-${name}.html`),
      width: 1440,
      height: 900,
      scale: 2,
      outFile,
    });
    flattenPng(outFile);
    console.log(`composed ${name}.png`);
  }
}

console.log("done");
