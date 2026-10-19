// Copy for the 3.2.3 store media: search-video headlines and the two widget
// screenshot pages. zh-CN and en were reviewed on 2026-10-19; the other
// locales are written for 3.2.3 and listed in app-store-connect/ios/3.2.3 for
// review. Platform terms follow each language's iOS wording (Home Screen,
// Lock Screen). Widgets never show salary.
import {searchLine as line322,LOCALES as LOCALES322} from './creative-copy-3.2.2.mjs';

// Search video: [dark, accent] per beat. `home` falls back to each locale's
// reviewed 3.2.2 widget line; `desk` and `lock` are new.
const WRITTEN={
 'zh-CN':{home:['不用打开，','桌面就有数。'],desk:['班表和本周，','一眼看清。'],lock:['锁屏一亮，','还剩多久。']},
 en:{home:['Your day,','on your Home Screen.'],desk:['Your shifts.','Your week.'],lock:['Wake your screen.','See what’s left.']},
 'zh-TW':{desk:['班表和本週，','一眼看清。'],lock:['螢幕一亮，','還剩多久。']},
 ja:{desk:['シフトも今週も、','ひと目で。'],lock:['画面をつければ、','あと何分。']},
 ko:{desk:['근무표와 이번 주,','한눈에.'],lock:['화면을 켜면,','남은 시간이 보여요.']},
 de:{desk:['Deine Schichten.','Deine Woche.'],lock:['Bildschirm an.','Restzeit im Blick.']},
 fr:{desk:['Vos horaires.','Votre semaine.'],lock:['Un regard.','Le temps restant.']},
 es:{desk:['Tus turnos.','Tu semana.'],lock:['Un vistazo.','Lo que te falta.']},
 it:{desk:['I tuoi turni.','La tua settimana.'],lock:['Un’occhiata.','Ecco quanto manca.']},
 pt:{desk:['Seus turnos.','Sua semana.'],lock:['Acenda a tela.','Veja quanto falta.']},
 ru:{desk:['Ваши смены.','Ваша неделя.'],lock:['Один взгляд —','сколько осталось.']},
 tr:{desk:['Vardiyaların.','Haftan.'],lock:['Ekranı aç,','kalan süreyi gör.']},
 id:{desk:['Shift-mu.','Minggumu.'],lock:['Nyalakan layar,','lihat sisa waktu.']},
 vi:{desk:['Ca làm của bạn.','Tuần của bạn.'],lock:['Bật màn hình,','biết còn bao lâu.']},
 th:{desk:['กะงานของคุณ','สัปดาห์นี้ในแวบเดียว'],lock:['เปิดหน้าจอ','ก็รู้ว่าเหลืออีกนาน']},
 'hi-IN':{desk:['आपकी शिफ़्टें।','आपका हफ़्ता।'],lock:['स्क्रीन जगाइए,','बचा समय देखिए।']},
 'mr-IN':{desk:['तुमच्या शिफ्ट्स.','तुमचा आठवडा.'],lock:['स्क्रीन सुरू करा,','उरलेला वेळ पाहा.']},
 ar:{desk:['مناوباتك.','أسبوعك.'],lock:['أضئ الشاشة،','واعرف كم تبقّى.']},
};

export const LOCALES=LOCALES322;

/** [dark, accent] for a scene, and where it came from. */
export function searchLine(locale,scene){
 const own=WRITTEN[locale]?.[scene];
 if(own)return{lines:own,source:['zh-CN','en'].includes(locale)?'reviewed for 3.2.3':'written for 3.2.3'};
 if(scene==='home')return{...line322(locale,'widget'),source:'3.2.2 widget line'};
 return line322(locale,scene);
}

// Screenshot pages 3 (Home Screen) and 4 (Lock Screen and Apple Watch):
// label, headline lines (last line orange), supporting lines.
const P=(label,lines,sub)=>({label,lines:lines.split('|'),sub:sub.split('|')});
export const PAGES={
 'zh-CN':{home:P('全新小组件','不用打开，|桌面就有数。','倒计时、本周进度、班表与节假日，|多款小组件免费可用。'),lock:P('锁屏 · Apple Watch','锁屏一亮，|就知道还剩多久。','锁屏小组件、一键开始上班，|Apple Watch 也能看。')},
 en:{home:P('NEW WIDGETS','Your day,|on your Home Screen.','Countdown, week progress, shifts and holidays.|Many of them free.'),lock:P('LOCK SCREEN · APPLE WATCH','Wake your screen.|See how long is left.','Lock Screen widgets, a Start shift control|and your countdown on Apple Watch.')},
 'zh-TW':{home:P('全新小工具','不打開，|主畫面就看得到。','倒數、本週進度、班表與假日，|多款小工具免費使用。'),lock:P('鎖定畫面 · Apple Watch','螢幕一亮，|就知道還剩多久。','鎖定畫面小工具、一鍵開始上班，|Apple Watch 也看得到。')},
 ja:{home:P('新しいウィジェット','開かなくても、|ホーム画面でわかる。','カウントダウン、今週の進み具合、シフト、祝日。|多くは無料で使えます。'),lock:P('ロック画面 · Apple Watch','画面をつければ、|あと何分かわかる。','ロック画面のウィジェット、ワンタップで出勤、|Apple Watch でも確認できます。')},
 ko:{home:P('새로운 위젯','열지 않아도,|홈 화면에서 한눈에.','카운트다운, 이번 주 진행률, 근무표와 공휴일.|대부분 무료로 쓸 수 있어요.'),lock:P('잠금 화면 · Apple Watch','화면을 켜면,|남은 시간이 보여요.','잠금 화면 위젯, 탭 한 번으로 근무 시작,|Apple Watch에서도 볼 수 있어요.')},
 de:{home:P('NEUE WIDGETS','Dein Tag,|auf dem Home-Bildschirm.','Countdown, Wochenfortschritt, Schichten und Feiertage.|Viele davon kostenlos.'),lock:P('SPERRBILDSCHIRM · APPLE WATCH','Bildschirm an.|Restzeit im Blick.','Widgets auf dem Sperrbildschirm, Schichtstart per Tipp|und dein Countdown auf der Apple Watch.')},
 fr:{home:P('NOUVEAUX WIDGETS','Votre journée,|sur l’écran d’accueil.','Compte à rebours, semaine, horaires et jours fériés.|Beaucoup sont gratuits.'),lock:P('ÉCRAN VERROUILLÉ · APPLE WATCH','Un regard.|Le temps restant.','Des widgets sur l’écran verrouillé, le début de journée en un geste|et votre compte à rebours sur Apple Watch.')},
 es:{home:P('WIDGETS NUEVOS','Tu día,|en la pantalla de inicio.','Cuenta atrás, progreso semanal, turnos y festivos.|Muchos son gratis.'),lock:P('PANTALLA BLOQUEADA · APPLE WATCH','Enciende la pantalla.|Mira cuánto falta.','Widgets en la pantalla bloqueada, empieza tu turno con un toque|y tu cuenta atrás en el Apple Watch.')},
 it:{home:P('NUOVI WIDGET','La tua giornata,|sulla schermata Home.','Conto alla rovescia, settimana, turni e festività.|Molti sono gratis.'),lock:P('SCHERMATA DI BLOCCO · APPLE WATCH','Accendi lo schermo.|Vedi quanto manca.','Widget nella schermata di blocco, inizio turno con un tocco|e il conto alla rovescia su Apple Watch.')},
 pt:{home:P('NOVOS WIDGETS','Seu dia,|na Tela de Início.','Contagem regressiva, semana, escalas e feriados.|Muitos são gratuitos.'),lock:P('TELA BLOQUEADA · APPLE WATCH','Acenda a tela.|Veja quanto falta.','Widgets na Tela Bloqueada, comece o turno com um toque|e sua contagem regressiva no Apple Watch.')},
 ru:{home:P('НОВЫЕ ВИДЖЕТЫ','Ваш день —|на экране «Домой».','Обратный отсчёт, неделя, смены и праздники.|Многие — бесплатно.'),lock:P('ЭКРАН БЛОКИРОВКИ · APPLE WATCH','Взгляд на экран —|сколько осталось.','Виджеты на экране блокировки, начало смены одним касанием|и обратный отсчёт на Apple Watch.')},
 tr:{home:P('YENİ WIDGET’LAR','Günün,|ana ekranında.','Geri sayım, haftalık ilerleme, vardiyalar ve tatiller.|Çoğu ücretsiz.'),lock:P('KİLİT EKRANI · APPLE WATCH','Ekranı aç,|kalan süreyi gör.','Kilit ekranı widget’ları, tek dokunuşla mesai başlangıcı|ve Apple Watch’ta geri sayım.')},
 id:{home:P('WIDGET BARU','Harimu,|di Layar Utama.','Hitung mundur, progres minggu, shift, dan hari libur.|Banyak yang gratis.'),lock:P('LAYAR TERKUNCI · APPLE WATCH','Nyalakan layar,|lihat sisa waktu.','Widget Layar Terkunci, mulai shift dengan sekali ketuk,|dan hitung mundur di Apple Watch.')},
 vi:{home:P('TIỆN ÍCH MỚI','Ngày của bạn,|ngay trên màn hình chính.','Đếm ngược, tiến độ tuần, ca làm và ngày lễ.|Nhiều tiện ích miễn phí.'),lock:P('MÀN HÌNH KHÓA · APPLE WATCH','Bật màn hình,|biết còn bao lâu.','Tiện ích màn hình khóa, bắt đầu ca chỉ với một chạm|và đếm ngược trên Apple Watch.')},
 th:{home:P('วิดเจ็ตใหม่','วันทำงานของคุณ|บนหน้าจอโฮม','นับถอยหลัง ความคืบหน้าสัปดาห์ กะงาน และวันหยุด|หลายแบบใช้ได้ฟรี'),lock:P('หน้าจอล็อก · Apple Watch','เปิดหน้าจอ|ก็รู้ว่าเหลืออีกนาน','วิดเจ็ตหน้าจอล็อก เริ่มกะได้ในแตะเดียว|และนับถอยหลังบน Apple Watch')},
 'hi-IN':{home:P('नए विजेट','आपका दिन,|होम स्क्रीन पर।','काउंटडाउन, हफ़्ते की प्रगति, शिफ़्ट और छुट्टियाँ।|कई मुफ़्त हैं।'),lock:P('लॉक स्क्रीन · Apple Watch','स्क्रीन जगाइए,|बचा समय देखिए।','लॉक स्क्रीन विजेट, एक टैप में शिफ़्ट शुरू,|और Apple Watch पर काउंटडाउन।')},
 ar:{home:P('أدوات جديدة','يومك،|على الشاشة الرئيسية.','عدّ تنازلي، تقدّم الأسبوع، المناوبات والعطلات.|كثير منها مجاني.'),lock:P('شاشة القفل · Apple Watch','أضئ الشاشة،|واعرف كم تبقّى.','أدوات على شاشة القفل، وبدء المناوبة بلمسة،|والعدّ التنازلي على Apple Watch.')},
};
