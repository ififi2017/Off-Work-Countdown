// Editorial line breaks: never split a word to fit a poster.
import {COPY as BASE,FOOTERS} from './creative-copy.mjs';
const P=(label,title,sub)=>({label,lines:title.split('|'),sub:sub.split('|')});
const EXTRA={
 'mr-IN':['सुट्टी कधी,|कळून राहो','प्रातिनिधिक डेटा','३ मोफत शोध',['सुट्टीचे नियोजन','थोडी रजा.|मोठा विराम.','सुट्टीचे दिवस एकत्र पाहा.|कॅलेंडरवर तुमचा विराम निवडा.'],['कालावधी अहवाल','कामाचे दिवस,|अधिक स्पष्ट.','काम, ओव्हरटाइम आणि विश्रांती.|आठवडा, महिना आणि वर्षाच्या अहवालात.']],
'zh-CN':['几点下班，|心里有数。','界面为演示数据','3 次免费体验',['请假规划','把假期，|排得更完整。','请哪几天，能连休多久。|放进月历，一眼看清。'],['周期报告','忙过的日子，|慢慢看清。','工作、加班与休息，|写成你的周报、月报和年报。']],
'zh-TW':['幾點下班，|心裡有數。','畫面為示範資料','3 次免費體驗',['請假規劃','把假期，|排得更完整。','請哪幾天，能連休多久。|放進月曆，一眼看清。'],['週期報告','忙過的日子，|慢慢看清。','工作、加班與休息，|寫成你的週報、月報和年報。']],
en:['Know when|your time is yours.','Illustrative data','3 free tries',['LEAVE PLANNING','A little leave.|A longer break.','See your days off come together.|Find your break on the calendar.'],['CYCLE REPORTS','Your working days.|A clearer picture.','Work, overtime and time off.|Your week, month and year in view.']],
de:['Sieh, wann|Feierabend ist.','Beispieldaten','3 Mal kostenlos testen',['Urlaubsplanung','Wenige Urlaubstage.|Mehr freie Zeit.','Sieh freie Tage zusammen im Kalender.|Plane deine nächste Auszeit.'],['Zeitraumberichte','Deine Arbeitstage.|Klarer im Blick.','Arbeit, Überstunden und Erholung.|Deine Woche, dein Monat, dein Jahr.']],
fr:['Sachez quand|vous pourrez partir.','Données de démonstration','3 essais gratuits',['Planifier ses congés','Quelques congés.|Une vraie pause.','Réunissez vos jours de repos.|Visualisez votre pause sur le calendrier.'],['Bilans périodiques','Vos journées de travail.|Une vue plus claire.','Travail, heures supplémentaires et repos.|Votre semaine, votre mois, votre année.']],
es:['Ten claro|cuándo sales.','Datos de ejemplo','3 pruebas gratis',['Planificar vacaciones','Pocos días de permiso.|Más tiempo para ti.','Junta tus días libres.|Mira tu descanso en el calendario.'],['Informes por periodo','Tus días de trabajo.|Todo más claro.','Trabajo, horas extra y descanso.|Tu semana, tu mes y tu año.']],
it:['Sai quando|puoi staccare.','Dati dimostrativi','3 prove gratuite',['Pianifica le ferie','Pochi giorni di ferie.|Una pausa più lunga.','Riunisci i tuoi giorni liberi.|Guarda la pausa nel calendario.'],['Report periodici','I tuoi giorni di lavoro.|Un quadro più chiaro.','Lavoro, straordinari e riposo.|La tua settimana, il tuo mese, il tuo anno.']],
pt:['Saiba quando|o expediente acaba.','Dados ilustrativos','3 testes grátis',['Planejar folgas','Poucos dias de folga.|Uma pausa maior.','Veja seus dias livres juntos.|Encontre sua pausa no calendário.'],['Relatórios por período','Seus dias de trabalho.|Tudo mais claro.','Trabalho, horas extras e descanso.|Sua semana, seu mês e seu ano.']],
ja:['上がる時間が、|すぐわかる。','画面はサンプルデータです','3 回無料でお試し',['休暇プラン','少しの休暇で、|長めのひと休み。','どの日を休めば、何日つながるか。|カレンダーで、ひと目で確認。'],['期間レポート','働いた日々を、|ゆっくり見渡す。','仕事、残業、休息を振り返る。|週・月・年のレポートで。']],
ko:['퇴근이 보이면|마음이 놓여요.','화면은 예시 데이터입니다','3회 무료 체험',['휴가 계획','휴가를 조금 더해,|더 긴 쉼으로.','쉬는 날을 달력에서 한눈에.|나에게 맞는 휴가를 찾아요.'],['기간별 보고서','일한 날들을,|더 또렷하게.','근무와 초과 근무, 휴식까지.|주간·월간·연간 보고서로 봐요.']],
ru:['Знаешь, когда|можно уйти.','Демонстрационные данные','3 бесплатные попытки',['Планирование отпуска','Немного отпуска.|Больше отдыха.','Соберите выходные вместе.|Посмотрите на отдых в календаре.'],['Отчёты за период','Рабочие дни.|Ясная картина.','Работа, переработки и отдых.|Ваша неделя, месяц и год.']],
tr:['Ne zaman çıkacağını|bilirsin.','Örnek veriler','3 ücretsiz deneme',['İzin planlama','Biraz izin.|Daha uzun bir mola.','Boş günlerini bir arada gör.|Molana takvimde yer aç.'],['Dönem raporları','Çalıştığın günler.|Daha net bir bakış.','İş, fazla mesai ve dinlenme.|Haftan, ayın ve yılın bir arada.']],
id:['Tahu kapan|boleh pulang.','Data contoh','3 kali coba gratis',['Rencana cuti','Sedikit cuti.|Libur lebih panjang.','Lihat hari liburmu berdekatan.|Temukan jeda di kalender.'],['Laporan berkala','Hari-hari kerjamu.|Terlihat lebih jelas.','Kerja, lembur, dan waktu istirahat.|Dalam laporan mingguan hingga tahunan.']],
vi:['Biết chắc|giờ tan ca.','Dữ liệu minh họa','3 lần thử miễn phí',['Lên kế hoạch nghỉ','Xin nghỉ một chút.|Nghỉ ngơi lâu hơn.','Xem những ngày nghỉ liền nhau.|Tìm khoảng nghỉ trên lịch.'],['Báo cáo định kỳ','Những ngày làm việc.|Một góc nhìn rõ hơn.','Công việc, làm thêm và nghỉ ngơi.|Qua báo cáo tuần, tháng và năm.']],
th:['รู้แน่|เลิกกี่โมง','ข้อมูลตัวอย่าง','ทดลองใช้ฟรี 3 ครั้ง',['วางแผนวันลา','ลาเพิ่มอีกนิด|พักได้นานขึ้น','ดูวันหยุดต่อเนื่องในปฏิทิน|เลือกช่วงพักที่เหมาะกับคุณ'],['รายงานตามช่วงเวลา','มองวันทำงาน|ได้ชัดเจนขึ้น','งาน ล่วงเวลา และการพัก|ในรายงานสัปดาห์ เดือน และปี']],
'hi-IN':['पता रहे,|छुट्टी कब है।','उदाहरण के आँकड़े','3 बार मुफ़्त आज़माएँ',['छुट्टी की योजना','थोड़ी-सी छुट्टी।|थोड़ा लंबा आराम।','छुट्टी के दिन एक साथ देखें।|कैलेंडर में अपना आराम चुनें।'],['समयावधि की रिपोर्ट','काम के दिन।|एक साफ़ तस्वीर।','काम, ओवरटाइम और आराम।|सप्ताह, महीने और साल की रिपोर्ट में।']],
ar:['تعرف متى|ينتهي دوامك.','بيانات توضيحية','3 تجارب مجانية',['تخطيط الإجازة','إجازة قصيرة.|راحة أطول.','شاهد أيام راحتك معًا.|واختر إجازتك في التقويم.'],['تقارير الفترات','أيام عملك.|صورة أوضح.','العمل والساعات الإضافية والراحة.|في تقارير الأسبوع والشهر والسنة.']]
};
const TOUR_OPENERS={
 'mr-IN':'प्रत्येक सेकंद.|तुमच्या वेळेच्या जवळ.',
'zh-TW':'幾點下班，|一眼有數。',de:'Jede Sekunde.|Näher am Feierabend.',fr:'Chaque seconde.|Plus près de la sortie.',es:'Cada segundo.|Más cerca de salir.',it:'Ogni secondo.|Più vicino alla fine.',pt:'Cada segundo.|Mais perto de sair.',ja:'一秒ずつ。|自分の時間へ。',ko:'매초마다.|퇴근이 가까워져요.',ru:'Каждая секунда.|Ближе к концу смены.',tr:'Her saniye.|Mesai sonuna daha yakın.',id:'Setiap detik.|Makin dekat waktu pulang.',vi:'Mỗi giây.|Gần giờ tan ca hơn.',th:'ทุกวินาที|ใกล้เวลาเลิกงานอีกนิด','hi-IN':'हर सेकंड।|छुट्टी के और करीब।',ar:'كل ثانية.|تقترب نهاية دوامك.'
};
export const COPY=Object.fromEntries(Object.entries(BASE).map(([lang,b])=>{
 const [brand,note,trials,leave,report]=EXTRA[lang];
 const l=P(leave[0]+' · '+trials,leave[1],leave[2]),r=P(report[0]+' · DoneAt Plus',report[1],report[2]);
 const pages=[{label:'DoneAt',lines:b.hero,sub:b.intro.split('|')},b.pages[0],l,r,...b.pages.slice(1)];
 // Duo's widget image uses the native Home Screen preview, not an Island graphic.
 const widget={...pages[8],label:b.pages[5].label,sub:[FOOTERS[lang][1]]};
 const tour=[
  P(b.pages[0].label,b.hero.join('|'),b.intro),
  widget,pages[7],pages[6],r,l
 ];
 if(TOUR_OPENERS[lang])tour[0]={...tour[0],lines:TOUR_OPENERS[lang].split('|')};
 if(lang==='mr-IN')tour[0]={...tour[0],label:'काउंटडाउन',sub:['शिफ्ट संपायला किती वेळ उरला, एका नजरेत.']};
 if(lang==='zh-CN')tour.splice(0,6,...[
  P('倒计时','几点下班，|一眼有数。','每一秒，都更接近自己的时间。'),P('小组件','不用打开，|也能看见。','主屏幕、锁定屏幕，随时查看。'),P('专注','把这一段，|留给专注。','安排任务，让每一段时间更从容。'),P('记录','时间去哪，|都有迹可循。','从每一天，看见你的工作与休息。'),P('周期报告','忙过的日子，|慢慢看清。','工作、加班与休息，写成你的报告。'),P('请假规划','一点请假，|多一点假期。','选个方案，连休范围一眼看清。')]);
 if(lang==='en')tour.splice(0,6,...[
  P('COUNTDOWN','Every second.|Closer to your time.','See when your time is yours.'),P('WIDGETS','A glance.|And you know.','On your Home Screen and Lock Screen.'),P('FOCUS','One thing.|Your full focus.','Plan tasks. Make room to concentrate.'),P('RECORDS','Your days.|In perspective.','See your work and time off, day by day.'),P('CYCLE REPORTS','Your working days.|A clearer picture.','Work, overtime and time off, in view.'),P('LEAVE PLANNING','A little leave.|A longer break.','Choose a plan. See your days off together.')]);
 return [lang,{...b,brand:brand.split('|'),note,trials,pages,widget,tour,footer:FOOTERS[lang]}];
}));
export const SCENES=['timer','timer','leave','report','watch','calendar','records','focus','widgets','rest'];
