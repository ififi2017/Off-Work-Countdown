// Compose simulator captures into opaque App Store screenshots.
//
// Same stacking as doneat-site DeviceHero: the official frame PNG sizes the
// box, the capture sits in the screen hole, the frame stacks on top.
// iPhone hole is 75 / 66 / 75 / 66 on 1470×3000. iPad hole is 118 / 124 /
// 118 / 124 on 2300×3000. Do not punch, crop, or redraw the frame.
//
// Copy sits in a reserved band. Long localizations shrink to fit that band
// instead of pushing the device off the canvas.

import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { BRAND, brandMark, escapeHTML, fontStack } from "../brand.mjs";
import { captureHtml, flattenPng } from "../chrome.mjs";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = process.env.IOS_SHOTS_RAW_DIR || join(DIR, "raw");
const OUT = process.env.IOS_SHOTS_OUT_DIR || join(DIR, "out");
const FRAMES = join(DIR, "frames");
const HTML_DIR = join(tmpdir(), "off-work-shots-html");
const LAYOUT_PREVIEW = process.env.IOS_SHOTS_LAYOUT_PREVIEW === "1";
mkdirSync(OUT, { recursive: true });
mkdirSync(HTML_DIR, { recursive: true });
for (const name of readdirSync(DIR)) {
  if (name.startsWith("p-") && name.endsWith(".html")) rmSync(join(DIR, name));
}

const IPHONE_FRAME = join(FRAMES, "iphone-17-pro-max-deep-blue.png");
const IPAD_FRAME = join(FRAMES, "ipad-pro-m5-13-inch-space-black-portrait.png");

const IPHONE = {
  canvas: { width: 660, height: 1434, scale: 2 },
  aspect: "1470 / 3000",
  screen: {
    top: "2.2%",
    left: "5.102041%",
    width: "89.795918%",
    height: "95.6%",
    radius: "14.4% / 6.62%",
  },
};
const IPAD = {
  canvas: { width: 1032, height: 1376, scale: 2 },
  aspect: "2300 / 3000",
  screen: {
    top: "4.133333%",
    left: "5.130435%",
    width: "89.739130%",
    height: "91.733333%",
    radius: "2.91% / 2.18%",
  },
};

const SHOTS = ["timer", "widgets", "lunch", "records", "life", "focus"];

const STEMS = {
  en: "en",
  "zh-CN": "zh",
  "zh-TW": "zh-tw",
  ja: "ja",
  ko: "ko",
  de: "de",
  es: "es",
  fr: "fr",
  it: "it",
  pt: "pt",
  ru: "ru",
  ar: "ar",
  "hi-IN": "hi",
  id: "id",
  th: "th",
  tr: "tr",
  vi: "vi",
};

const LINES = {
  en: {
    iphone: [
      ["See exactly when work ends", "Remaining time, progress, and what’s next — in one view."],
      ["Still counting on the Home Screen", "Medium, large, and Live Activities. No need to open the app."],
      ["Lunch pauses the clock", "Breaks don’t count as work. The remaining time stays honest."],
      ["See the shape of your year", "Your workdays, time, and trends in one place."],
      ["Put work in the bigger picture", "See your life and work in one view."],
      ["Make room for focused work", "Tasks, focus blocks, and breaks fit into your day."],
    ],
    ipad: [
      ["Built for the bigger screen", "Your countdown and today’s details, together."],
      ["Widgets that fill a desk", "Four sizes on the Home Screen, still counting with the app closed."],
      ["Lunch, at iPad scale", "Pause the countdown for lunch. Keep work and breaks clear."],
      ["Your year, side by side", "Workdays, time, and trends have room to tell the story."],
      ["Your working life, in view", "Life and work have room to share the same picture."],
      ["A clearer place to focus", "Tasks and focus blocks stay close to the rest of your day."],
    ],
  },
  "zh-CN": {
    iphone: [
      ["一眼看清几点下班", "还剩多久、走了多远、接下来做什么，都在这一屏。"],
      ["不用打开，也能看到", "中号、大号和灵动岛，倒计时一直在走。"],
      ["午休时，倒计时会停", "午饭不算工时，剩下的时间是准的。"],
      ["把这一年看得更清楚", "工作日、工时和趋势，都能回头看。"],
      ["把工作放进人生里看", "从出生到退休，看看时间花在哪里。"],
      ["在上班时间，留一段专注", "任务、专注时段和休息，都排在今天。"],
    ],
    ipad: [
      ["为 iPad 大屏做的", "倒计时和今天的细节，都在同一屏。"],
      ["倒计时铺在主屏幕上", "四种大小，应用关着也在走。"],
      ["午休，大屏上也停", "午休暂停进度，工作和休息分得清楚。"],
      ["把这一年展开来看", "工作日、工时和趋势，一起放进更大的画面。"],
      ["把工作放回人生里看", "从第一份工作到退休，前后的时间都看得见。"],
      ["给专注留一块清楚的地方", "任务和专注时段，和今天的其他安排放在一起。"],
    ],
  },
  "zh-TW": {
    iphone: [
      ["一眼看清幾點下班", "還剩多久、走了多遠、接下來做什麼，都在這一屏。"],
      ["不用打開，也能看到", "中型、大型和動態島，倒數一直在走。"],
      ["午休時，倒數會停", "午飯不算工時，剩下的時間是準的。"],
      ["把這一年看得更清楚", "工作日、工時和趨勢，都能回頭看。"],
      ["把工作放進人生裡看", "從出生到退休，看看時間花在哪裡。"],
      ["在上班時間，留一段專注", "任務、專注時段和休息，都排在今天。"],
    ],
    ipad: [
      ["為 iPad 大螢幕做的", "倒數和今天的細節，都在同一屏。"],
      ["倒數鋪在主畫面上", "四種大小，應用程式關著也在走。"],
      ["午休，大螢幕上也停", "午休暫停進度，工作和休息分得清楚。"],
      ["把這一年展開來看", "工作日、工時和趨勢，一起放進更大的畫面。"],
      ["把工作放回人生裡看", "從第一份工作到退休，前後的時間都看得見。"],
      ["給專注留一塊清楚的地方", "任務和專注時段，和今天的其他安排放在一起。"],
    ],
  },
  ja: {
    iphone: [
      ["退勤時刻が、はっきり見える", "残り時間、進み具合、次に何をするか。この一画面で。"],
      ["ホーム画面でも、数え続けます", "中・大ウィジェットとライブアクティビティ。アプリを開かなくていい。"],
      ["昼休みは、時計が止まる", "休憩は勤務時間に入れない。残り時間は正確。"],
      ["一年の形が、見える", "出勤日、時間、傾向を、ひとつの場所で。"],
      ["仕事を、人生の中で見る", "人生と仕事を、同じ画面で。"],
      ["集中する時間を、残す", "タスク、集中、休憩を、今日の中に置く。"],
    ],
    ipad: [
      ["大きな画面のために", "カウントダウンと今日の詳細を、並べて。"],
      ["デスクに広がるウィジェット", "4つのサイズ。アプリを閉じても数え続ける。"],
      ["昼休みも、この大きさで", "昼はカウントを止める。仕事と休憩を分けておく。"],
      ["一年を、横に広げて", "出勤日、時間、傾向が、ちゃんと語れる余白。"],
      ["働く人生を、見渡す", "人生と仕事が、同じ絵の中に。"],
      ["集中できる場所", "タスクと集中ブロックを、今日の流れのそばに。"],
    ],
  },
  ko: {
    iphone: [
      ["퇴근 시간이 한눈에", "남은 시간, 진행, 다음에 할 일. 이 화면에서."],
      ["홈 화면에서도 계속 셉니다", "중형, 대형, 실시간 현황. 앱을 열 필요 없어요."],
      ["점심시간엔 시계가 멈춰요", "휴식은 근무 시간이 아니에요. 남은 시간은 정확해요."],
      ["한 해의 모양이 보여요", "근무일, 시간, 흐름을 한곳에서."],
      ["일을 인생 안에 놓고 보기", "인생과 일을 같은 화면에서."],
      ["집중할 시간을 남겨 두기", "할 일, 집중, 휴식을 오늘 안에."],
    ],
    ipad: [
      ["더 큰 화면을 위해", "카운트다운과 오늘의 디테일을 나란히."],
      ["책상을 채우는 위젯", "네 가지 크기. 앱을 닫아도 계속 셉니다."],
      ["점심도, 이 크기에서", "점심엔 카운트를 멈춰요. 일과 휴식을 나눠 둡니다."],
      ["한 해를 펼쳐 보기", "근무일, 시간, 흐름이 들어갈 자리가 있어요."],
      ["일하는 인생을 한눈에", "인생과 일이 같은 그림 안에."],
      ["집중하기 좋은 자리", "할 일과 집중 블록을 오늘 옆에."],
    ],
  },
  de: {
    iphone: [
      ["Genau sehen, wann Feierabend ist", "Restzeit, Fortschritt und was als Nächstes kommt — in einer Ansicht."],
      ["Zählt weiter auf dem Home-Bildschirm", "Mittel, groß und Live-Aktivitäten. Die App muss nicht offen sein."],
      ["Mittag stoppt die Uhr", "Pausen zählen nicht als Arbeit. Die Restzeit bleibt ehrlich."],
      ["Dein Jahr auf einen Blick", "Arbeitstage, Zeit und Trends an einem Ort."],
      ["Arbeit im größeren Bild", "Leben und Arbeit in einer Ansicht."],
      ["Platz für fokussierte Arbeit", "Aufgaben, Fokusblöcke und Pausen passen in den Tag."],
    ],
    ipad: [
      ["Für den größeren Bildschirm", "Countdown und die Details des Tages, nebeneinander."],
      ["Widgets für den Schreibtisch", "Vier Größen. Zählt weiter, wenn die App zu ist."],
      ["Mittag, in iPad-Größe", "Pause fürs Mittagessen. Arbeit und Pause getrennt halten."],
      ["Dein Jahr, nebeneinander", "Arbeitstage, Zeit und Trends haben Platz zu erzählen."],
      ["Dein Arbeitsleben im Blick", "Leben und Arbeit teilen dasselbe Bild."],
      ["Ein klarerer Ort zum Fokussieren", "Aufgaben und Fokusblöcke bleiben nah am Rest des Tages."],
    ],
  },
  es: {
    iphone: [
      ["Mira exactamente cuándo sales", "Tiempo restante, progreso y lo que sigue, en una vista."],
      ["Sigue contando en la pantalla de inicio", "Mediano, grande y Actividades en directo. No hace falta abrir la app."],
      ["La comida pausa el reloj", "Los descansos no cuentan como trabajo. El tiempo restante es honesto."],
      ["La forma de tu año", "Días laborables, tiempo y tendencias en un solo lugar."],
      ["El trabajo en el cuadro grande", "Tu vida y tu trabajo, en una vista."],
      ["Deja sitio para concentrarte", "Tareas, bloques de foco y descansos caben en tu día."],
    ],
    ipad: [
      ["Hecha para la pantalla grande", "La cuenta atrás y el detalle del día, juntos."],
      ["Widgets que llenan el escritorio", "Cuatro tamaños. Sigue contando con la app cerrada."],
      ["La comida, a escala iPad", "Pausa la cuenta en la comida. Separa trabajo y descanso."],
      ["Tu año, lado a lado", "Días, tiempo y tendencias tienen espacio para verse."],
      ["Tu vida laboral, a la vista", "Vida y trabajo caben en la misma imagen."],
      ["Un lugar más claro para el foco", "Tareas y bloques de foco, junto al resto del día."],
    ],
  },
  fr: {
    iphone: [
      ["Voyez l’heure de sortie", "Temps restant, progression et la suite — sur un seul écran."],
      ["Ça compte encore sur l’écran d’accueil", "Moyen, grand et Activités en direct. Pas besoin d’ouvrir l’app."],
      ["Le déjeuner arrête l’horloge", "Les pauses ne comptent pas comme du travail. Le temps restant reste juste."],
      ["La forme de votre année", "Jours travaillés, temps et tendances au même endroit."],
      ["Le travail dans le reste de la vie", "La vie et le travail, sur une seule vue."],
      ["Gardez du temps pour vous concentrer", "Tâches, blocs de focus et pauses tiennent dans la journée."],
    ],
    ipad: [
      ["Pensée pour le grand écran", "Le compte à rebours et le détail du jour, ensemble."],
      ["Des widgets qui remplissent le bureau", "Quatre tailles. Ça compte encore, app fermée."],
      ["Le déjeuner, à l’échelle iPad", "Pausez le compte pour déjeuner. Gardez travail et pause distincts."],
      ["Votre année, côte à côte", "Jours, temps et tendances ont la place de se raconter."],
      ["Votre vie au travail, en vue", "La vie et le travail partagent la même image."],
      ["Un endroit plus clair pour le focus", "Tâches et blocs de focus, près du reste de la journée."],
    ],
  },
  it: {
    iphone: [
      ["Vedi esattamente quando finisci", "Tempo rimasto, avanzamento e cosa viene dopo — in una vista."],
      ["Continua a contare sulla Home", "Medio, grande e Attività in tempo reale. Non serve aprire l’app."],
      ["Il pranzo ferma l’orologio", "Le pause non contano come lavoro. Il tempo rimasto resta onesto."],
      ["La forma del tuo anno", "Giorni lavorativi, tempo e andamenti in un solo posto."],
      ["Il lavoro nel quadro più ampio", "Vita e lavoro, in una sola vista."],
      ["Lascia spazio alla concentrazione", "Compiti, blocchi di focus e pause stanno nella giornata."],
    ],
    ipad: [
      ["Pensata per lo schermo grande", "Il conto alla rovescia e i dettagli del giorno, insieme."],
      ["Widget che riempiono la scrivania", "Quattro dimensioni. Continua a contare a app chiusa."],
      ["Il pranzo, in scala iPad", "Metti in pausa il conto a pranzo. Tieni lavoro e pausa distinti."],
      ["Il tuo anno, affiancato", "Giorni, tempo e andamenti hanno spazio per raccontarsi."],
      ["La vita lavorativa, in vista", "Vita e lavoro condividono la stessa immagine."],
      ["Un posto più chiaro per il focus", "Compiti e blocchi di focus, vicino al resto della giornata."],
    ],
  },
  pt: {
    iphone: [
      ["Veja exatamente quando o expediente acaba", "Tempo restante, progresso e o que vem a seguir — numa vista."],
      ["Continua a contar na Tela de Início", "Médio, grande e Atividades ao Vivo. Não precisa abrir o app."],
      ["O almoço pausa o relógio", "Pausas não contam como trabalho. O tempo restante continua honesto."],
      ["A forma do seu ano", "Dias de trabalho, tempo e tendências num só lugar."],
      ["O trabalho no quadro maior", "Vida e trabalho, numa só vista."],
      ["Deixe espaço para o foco", "Tarefas, blocos de foco e pausas cabem no seu dia."],
    ],
    ipad: [
      ["Feito para a tela maior", "A contagem e os detalhes do dia, juntos."],
      ["Widgets que preenchem a mesa", "Quatro tamanhos. Continua a contar com o app fechado."],
      ["O almoço, em escala iPad", "Pause a contagem no almoço. Separe trabalho e pausa."],
      ["O seu ano, lado a lado", "Dias, tempo e tendências têm espaço para aparecer."],
      ["A vida no trabalho, à vista", "Vida e trabalho compartilham a mesma imagem."],
      ["Um lugar mais claro para o foco", "Tarefas e blocos de foco, perto do resto do dia."],
    ],
  },
  ru: {
    iphone: [
      ["Точно видно, когда смена кончится", "Остаток, прогресс и что дальше — на одном экране."],
      ["Считает и на домашнем экране", "Средний, большой виджет и Live Activities. Приложение открывать не нужно."],
      ["Обед останавливает часы", "Перерыв не считается работой. Оставшееся время честное."],
      ["Форма вашего года", "Рабочие дни, время и тенденции в одном месте."],
      ["Работа в более широкой картине", "Жизнь и работа — на одном экране."],
      ["Оставьте место для фокуса", "Задачи, блоки фокуса и паузы умещаются в день."],
    ],
    ipad: [
      ["Для большого экрана", "Отсчёт и детали дня — рядом."],
      ["Виджеты на весь стол", "Четыре размера. Считает и при закрытом приложении."],
      ["Обед в масштабе iPad", "Пауза на обед. Работа и отдых разделены."],
      ["Ваш год рядом", "Дням, времени и тенденциям есть где развернуться."],
      ["Рабочая жизнь на виду", "Жизнь и работа в одной картине."],
      ["Более ясное место для фокуса", "Задачи и блоки фокуса рядом с остальным днём."],
    ],
  },
  ar: {
    iphone: [
      ["اعرف متى ينتهي الدوام", "الوقت المتبقي والتقدم وما التالي — في شاشة واحدة."],
      ["العدّ مستمر على الشاشة الرئيسية", "متوسط وكبير والأنشطة المباشرة. لا حاجة لفتح التطبيق."],
      ["الغداء يوقف الساعة", "الاستراحة لا تُحتسب من العمل. الوقت المتبقي يبقى صادقًا."],
      ["شكل عامك في مكان واحد", "أيام العمل والوقت والاتجاهات معًا."],
      ["ضع العمل في صورة أكبر", "حياتك وعملك في عرض واحد."],
      ["اترك وقتًا للتركيز", "المهام وكتل التركيز والاستراحات تتسع في يومك."],
    ],
    ipad: [
      ["مصمم للشاشة الأكبر", "العدّ التنازلي وتفاصيل اليوم معًا."],
      ["ويدجات تملأ المكتب", "أربعة أحجام. يستمر العدّ والتطبيق مغلق."],
      ["الغداء بمقياس iPad", "أوقف العدّ عند الغداء. أبقِ العمل والاستراحة منفصلين."],
      ["عامك جنبًا إلى جنب", "أيام العمل والوقت والاتجاهات لها مساحة لتُروى."],
      ["حياتك العملية أمامك", "الحياة والعمل في الصورة نفسها."],
      ["مكان أوضح للتركيز", "المهام وكتل التركيز قرب بقية يومك."],
    ],
  },
  "hi-IN": {
    iphone: [
      ["साफ़ दिखे, काम कब खत्म होगा", "बचा समय, प्रगति और आगे क्या है — एक नज़र में।"],
      ["होम स्क्रीन पर भी गिनती चलती है", "मध्यम, बड़ा और लाइव ऐक्टिविटी। ऐप खोलने की ज़रूरत नहीं।"],
      ["लंच पर घड़ी रुकती है", "ब्रेक काम नहीं गिना जाता। बचा समय सही रहता है।"],
      ["अपने साल का आकार देखें", "कार्यदिवस, समय और रुझान एक जगह।"],
      ["काम को बड़ी तस्वीर में देखें", "जीवन और काम, एक ही दृश्य में।"],
      ["फोकस के लिए जगह रखें", "काम, फोकस ब्लॉक और ब्रेक आपके दिन में समाते हैं।"],
    ],
    ipad: [
      ["बड़ी स्क्रीन के लिए", "काउंटडाउन और आज की बातें, साथ-साथ।"],
      ["डेस्क भरने वाले विजेट", "चार आकार। ऐप बंद हो तो भी गिनती चलती है।"],
      ["लंच, iPad के पैमाने पर", "लंच पर काउंटडाउन रोकें। काम और ब्रेक अलग रखें।"],
      ["आपका साल, साथ-साथ", "दिन, समय और रुझान को दिखने की जगह मिलती है।"],
      ["कामकाजी जीवन नज़र में", "जीवन और काम एक ही तस्वीर में।"],
      ["फोकस के लिए साफ़ जगह", "काम और फोकस ब्लॉक, बाकी दिन के पास।"],
    ],
  },
  id: {
    iphone: [
      ["Lihat persis kapan pulang", "Sisa waktu, progres, dan langkah berikutnya — dalam satu tampilan."],
      ["Tetap menghitung di Layar Utama", "Sedang, besar, dan Live Activities. Tak perlu membuka aplikasi."],
      ["Makan siang menghentikan jam", "Istirahat tidak dihitung sebagai kerja. Sisa waktunya jujur."],
      ["Bentuk tahunmu", "Hari kerja, waktu, dan tren di satu tempat."],
      ["Kerja dalam gambar yang lebih besar", "Hidup dan kerja dalam satu tampilan."],
      ["Sisakan ruang untuk fokus", "Tugas, blok fokus, dan istirahat muat di harimu."],
    ],
    ipad: [
      ["Untuk layar yang lebih besar", "Hitung mundur dan detail hari ini, berdampingan."],
      ["Widget yang mengisi meja", "Empat ukuran. Tetap menghitung saat aplikasi tertutup."],
      ["Makan siang, skala iPad", "Jeda hitungan saat makan siang. Pisahkan kerja dan istirahat."],
      ["Tahunmu, berdampingan", "Hari, waktu, dan tren punya ruang untuk terlihat."],
      ["Hidup kerja, terlihat", "Hidup dan kerja berbagi gambar yang sama."],
      ["Tempat yang lebih jelas untuk fokus", "Tugas dan blok fokus dekat dengan sisa harimu."],
    ],
  },
  th: {
    iphone: [
      ["เห็นชัดว่าเลิกงานเมื่อไหร่", "เวลาที่เหลือ ความคืบหน้า และอะไรต่อไป — ในจอเดียว"],
      ["นับต่อบนหน้าจอโฮม", "กลาง ใหญ่ และ Live Activities ไม่ต้องเปิดแอป"],
      ["พักเที่ยง นาฬิกาหยุด", "พักไม่นับเป็นชั่วโมงทำงาน เวลาที่เหลือยังตรง"],
      ["เห็นรูปปีของคุณ", "วันทำงาน เวลา และแนวโน้ม ในที่เดียว"],
      ["วางงานไว้ในภาพใหญ่", "ชีวิตและงาน ในมุมมองเดียว"],
      ["เว้นที่ให้โฟกัส", "งาน ช่วงโฟกัส และพัก อยู่ในวันนี้"],
    ],
    ipad: [
      ["ทำเพื่อหน้าจอที่ใหญ่ขึ้น", "นับถอยหลังกับรายละเอียดของวันนี้ อยู่ด้วยกัน"],
      ["วิดเจ็ตที่เต็มโต๊ะ", "สี่ขนาด แอปปิดอยู่ก็นับต่อ"],
      ["พักเที่ยง ในสเกล iPad", "หยุดนับตอนพักเที่ยง แยกงานกับพักให้ชัด"],
      ["ปีของคุณ วางคู่กัน", "วัน เวลา และแนวโน้ม มีที่ให้เห็น"],
      ["ชีวิตการทำงาน ในสายตา", "ชีวิตและงาน อยู่ในภาพเดียวกัน"],
      ["ที่ที่โฟกัสได้ชัดขึ้น", "งานกับช่วงโฟกัส อยู่ใกล้กับวันอื่น ๆ"],
    ],
  },
  tr: {
    iphone: [
      ["Mesainin ne zaman bittiğini gör", "Kalan süre, ilerleme ve sırada ne var — tek bakışta."],
      ["Ana Ekranda saymaya devam eder", "Orta, büyük ve Canlı Etkinlikler. Uygulamayı açmana gerek yok."],
      ["Öğle arası saati durdurur", "Molalar iş sayılmaz. Kalan süre dürüst kalır."],
      ["Yılının şeklini gör", "İş günleri, süre ve eğilimler tek yerde."],
      ["İşi daha geniş resimde gör", "Hayat ve iş, tek görünümde."],
      ["Odak için yer bırak", "Görevler, odak blokları ve molalar güne sığar."],
    ],
    ipad: [
      ["Daha büyük ekran için", "Geri sayım ve günün ayrıntıları, yan yana."],
      ["Masayı dolduran widget’lar", "Dört boyut. Uygulama kapalıyken de sayar."],
      ["Öğle, iPad ölçeğinde", "Öğlede geri sayımı durdur. İş ile molayı ayır."],
      ["Yılın, yan yana", "Günlerin, sürenin ve eğilimlerin anlatacak yeri var."],
      ["Çalışma hayatın görünür", "Hayat ve iş aynı resimde."],
      ["Odak için daha net bir yer", "Görevler ve odak blokları, günün geri kalanının yanında."],
    ],
  },
  vi: {
    iphone: [
      ["Nhìn rõ giờ tan ca", "Thời gian còn lại, tiến độ và việc tiếp theo — trên một màn hình."],
      ["Vẫn đếm trên Màn hình chính", "Vừa, lớn và Live Activities. Không cần mở ứng dụng."],
      ["Nghỉ trưa thì đồng hồ dừng", "Nghỉ không tính là giờ làm. Thời gian còn lại vẫn đúng."],
      ["Hình dạng của năm bạn", "Ngày làm, thời gian và xu hướng ở một chỗ."],
      ["Đặt công việc vào bức tranh lớn", "Đời sống và công việc, trong một khung nhìn."],
      ["Chừa chỗ cho sự tập trung", "Việc, khối tập trung và nghỉ vừa trong ngày của bạn."],
    ],
    ipad: [
      ["Làm cho màn hình lớn hơn", "Đếm ngược và chi tiết hôm nay, cạnh nhau."],
      ["Tiện ích phủ kín bàn", "Bốn kích thước. Ứng dụng đóng vẫn đếm."],
      ["Nghỉ trưa, cỡ iPad", "Tạm dừng đếm lúc nghỉ trưa. Tách việc và nghỉ."],
      ["Năm của bạn, cạnh nhau", "Ngày, thời gian và xu hướng có chỗ để hiện ra."],
      ["Đời làm việc, trong tầm mắt", "Đời sống và công việc chung một bức ảnh."],
      ["Chỗ rõ hơn để tập trung", "Việc và khối tập trung, gần phần còn lại của ngày."],
    ],
  },
};

function pack(language) {
  const stem = STEMS[language];
  const lines = LINES[language];
  return {
    iphone: lines.iphone.map(([title, sub], index) => ({
      shot: SHOTS[index],
      file: `${stem}-${index + 1}.png`,
      plus: index >= 3,
      title,
      sub,
    })),
    ipad: lines.ipad.map(([title, sub], index) => ({
      shot: SHOTS[index],
      file: `${stem}-ipad-${index + 1}.png`,
      plus: index >= 3,
      title,
      sub,
    })),
  };
}

const COPY = Object.fromEntries(Object.keys(LINES).map((language) => [language, pack(language)]));

function fileUri(path) {
  if (!existsSync(path)) throw new Error(`Missing ${path}`);
  return pathToFileURL(path).href;
}

function resolveRaw(file) {
  const path = join(RAW, file);
  if (existsSync(path)) return path;
  if (LAYOUT_PREVIEW) {
    const number = file.match(/(\d)\.png$/)?.[1] ?? "1";
    const fallback = file.includes("ipad") ? `en-ipad-${number}.png` : `en-${number}.png`;
    return join(RAW, fallback);
  }
  throw new Error(`Missing ${path}`);
}

function page(card, language, platform, frameUri, sourceUri) {
  const spec = platform === "iphone" ? IPHONE : IPAD;
  const hole = spec.screen;
  const isPhone = platform === "iphone";
  const rtl = language === "ar";
  const copyMax = isPhone ? 268 : 248;
  const titleSize = isPhone ? 40 : 42;
  const subSize = isPhone ? 18 : 20;
  const tracking = language === "ar" ? "0" : "-.036em";

  return `<!doctype html><html lang="${language}" dir="${rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><style>
    * { box-sizing: border-box; }
    html, body { margin: 0; width: ${spec.canvas.width}px; height: ${spec.canvas.height}px; overflow: hidden; }
    body {
      font-family: ${fontStack(language)};
      color: ${BRAND.plum};
      background: ${BRAND.cream};
      display: flex; flex-direction: column;
    }
    .copy {
      position: relative; z-index: 3; flex: none;
      height: ${copyMax}px;
      padding: ${isPhone ? "36px 24px 0" : "32px 36px 0"};
      text-align: center;
      overflow: hidden;
    }
    .brand {
      display: inline-flex; align-items: center; gap: 8px;
      color: ${BRAND.orange}; font-size: ${isPhone ? 17 : 18}px; font-weight: 700;
    }
    .plus {
      padding: 2px 6px; border: 1px solid color-mix(in srgb, ${BRAND.orange} 60%, ${BRAND.cream});
      border-radius: 999px; font-size: .68em; font-weight: 700; letter-spacing: .02em;
    }
    .mark { width: ${isPhone ? 36 : 40}px; height: ${isPhone ? 36 : 40}px; display: block; }
    h1 {
      margin: 12px auto 0; max-width: ${isPhone ? 600 : 920}px;
      font-size: ${titleSize}px; line-height: 1.12; letter-spacing: ${tracking}; font-weight: 700;
      text-wrap: balance;
    }
    p {
      margin: 10px auto 0; max-width: ${isPhone ? 560 : 840}px;
      color: color-mix(in srgb, ${BRAND.plum} 62%, ${BRAND.cream});
      font-size: ${subSize}px; line-height: 1.4;
      text-wrap: balance;
    }
    .stage {
      position: relative; z-index: 2; flex: 1; min-height: 0;
      display: flex; justify-content: center; align-items: flex-end;
      padding: ${isPhone ? "8px 16px 32px" : "8px 24px 32px"};
    }
    .device {
      position: relative;
      width: min(${isPhone ? "88%" : "82%"}, calc(${spec.canvas.height - copyMax - 40}px * ${spec.aspect}));
      filter: drop-shadow(0 16px 24px rgba(43, 25, 53, .16));
    }
    .screen {
      position: absolute;
      top: ${hole.top}; left: ${hole.left};
      width: ${hole.width}; height: ${hole.height};
      overflow: hidden; border-radius: ${hole.radius};
    }
    .screen img {
      position: absolute; inset: 0; width: 100%; height: 100%;
      object-fit: cover; object-position: center top;
    }
    .frame {
      position: relative; z-index: 1;
      display: block; width: 100%; height: auto;
    }
  </style></head><body>
    <div class="copy" id="copy">
      <div class="brand">${brandMark(BRAND.plum)}<span>${BRAND.name}</span>${card.plus ? '<span class="plus">Plus</span>' : ""}</div>
      <h1 id="title">${escapeHTML(card.title)}</h1>
      <p id="sub">${escapeHTML(card.sub)}</p>
    </div>
    <div class="stage">
      <div class="device">
        <div class="screen"><img src="${sourceUri}" alt=""></div>
        <img class="frame" src="${frameUri}" alt="">
      </div>
    </div>
    <script>
      const copy = document.getElementById("copy");
      const title = document.getElementById("title");
      const sub = document.getElementById("sub");
      let titleSize = ${titleSize};
      let subSize = ${subSize};
      for (let i = 0; i < 18 && copy.scrollHeight > copy.clientHeight + 1; i++) {
        titleSize = Math.max(22, titleSize - 1.5);
        subSize = Math.max(13, subSize - 0.7);
        title.style.fontSize = titleSize + "px";
        sub.style.fontSize = subSize + "px";
      }
    </script>
  </body></html>`;
}

if (!existsSync(IPHONE_FRAME) || !existsSync(IPAD_FRAME)) {
  throw new Error(`Official Apple frames missing in ${FRAMES}`);
}

const iphoneFrameUri = fileUri(IPHONE_FRAME);
const ipadFrameUri = fileUri(IPAD_FRAME);
const selected = process.env.IOS_SHOTS_LANGUAGE
  ? process.env.IOS_SHOTS_LANGUAGE.split(",").map((value) => value.trim())
  : Object.keys(COPY);
for (const name of readdirSync(OUT)) {
  if (!name.endsWith(".png")) continue;
  if (selected.some((language) => name.startsWith(`${language}-`))) {
    rmSync(join(OUT, name));
  }
}

for (const language of selected) {
  const platforms = COPY[language];
  if (!platforms) throw new Error(`Unknown IOS_SHOTS_LANGUAGE ${language}`);
  for (const platform of ["iphone", "ipad"]) {
    const spec = platform === "iphone" ? IPHONE : IPAD;
    const frameUri = platform === "iphone" ? iphoneFrameUri : ipadFrameUri;
    for (const [index, card] of platforms[platform].entries()) {
      const name = `${language}-${platform}-${String(index + 1).padStart(2, "0")}-${card.shot}`;
      const outFile = join(OUT, `${name}.png`);
      await captureHtml({
        html: page(card, language, platform, frameUri, fileUri(resolveRaw(card.file))),
        htmlPath: join(HTML_DIR, `p-${name}.html`),
        width: spec.canvas.width,
        height: spec.canvas.height,
        scale: spec.canvas.scale,
        outFile,
      });
      flattenPng(outFile);
      console.log(`composed ${name}.png`);
    }
  }
}

const reviewDir = join(DIR, "review-3.1.9");
mkdirSync(reviewDir, { recursive: true });
const labels = {
  en: "English",
  "zh-CN": "简体中文",
  "zh-TW": "繁體中文",
  ja: "日本語",
  ko: "한국어",
  de: "Deutsch",
  es: "Español",
  fr: "Français",
  it: "Italiano",
  pt: "Português",
  ru: "Русский",
  ar: "العربية",
  "hi-IN": "हिन्दी",
  id: "Bahasa Indonesia",
  th: "ไทย",
  tr: "Türkçe",
  vi: "Tiếng Việt",
};
const sections = Object.keys(COPY).flatMap((language) =>
  ["iphone", "ipad"].map((platform) => {
    const shots = COPY[language][platform]
      .map((card, index) => `<li><a href="../out/${language}-${platform}-${String(index + 1).padStart(2, "0")}-${card.shot}.png">${String(index + 1).padStart(2, "0")} ${card.shot}</a></li>`)
      .join("");
    return `<section><h2>${labels[language]} · ${platform === "iphone" ? "iPhone" : "iPad"}</h2><ul>${shots}</ul></section>`;
  }),
).join("\n");
writeFileSync(join(reviewDir, "index.html"), `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>DoneAt 3.1.9 App Store screenshot review</title>
    <style>
      body { margin: 32px; background: #fff1d8; color: #2b1935; font: 16px -apple-system, BlinkMacSystemFont, sans-serif; }
      main { max-width: 2160px; margin: auto; }
      h1 { margin-bottom: 8px; }
      p { color: #5d4a65; }
      section { margin: 28px 0; }
      h2 { margin-bottom: 12px; }
      ul { display: flex; flex-wrap: wrap; gap: 8px 16px; padding: 0; }
      li { display: block; }
      a { color: #c2410c; }
    </style>
  </head>
  <body>
    <main>
      <h1>DoneAt 3.1.9 screenshots</h1>
      <p>Each set is ordered: Timer, Widgets, Lunch, Records, Life, Focus.</p>
      ${sections}
    </main>
  </body>
</html>
`);

console.log(`done: App Store screenshots are in ${OUT}`);
