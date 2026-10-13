// Headlines for the 3.2.2 search-results video: one line per scene, split into
// a dark half and an orange half. Reviewed 3.2.1 V4 tour lines are reused
// where they still describe the scene; the rest were written for this video
// and are listed in app-store-connect/ios/3.2.2/search-video.md for review.
import {COPY} from './creative-copy-3.2.1.mjs';

export const SCENE_KEYS=['countdown','widget','focus','records','report','leave','watch','life'];
const TOUR={countdown:0,widget:1,focus:2,records:3,report:4,leave:5};

// Lines written for 3.2.2. Records: the V4 lines described the year view in
// colour; this video shows last week on the month calendar. Watch (en, ko):
// the V4 lines repeated the widget or countdown line. Life: new scene; en and
// zh-CN come from the 3.1.9 App Preview. Shorter countdown, focus, report,
// leave and widget lines: the V4 line would have pulled the locale's shared
// headline size below the readable floor in creative-search-3.2.2.mjs.
const WRITTEN={
 en:{countdown:['Know when','you’re done.'],report:['Your month,','in review.'],watch:['On your wrist.','Closer to done.'],life:['Work,','in the bigger picture.']},
 'zh-CN':{life:['把工作，','放回人生里。']},
 'zh-TW':{records:['時間去哪，','都有跡可循。'],life:['把工作，','放回人生裡。']},
 de:{records:['Deine Tage.','Im Überblick.'],life:['Die Arbeit,','im großen Ganzen.']},
 fr:{countdown:['Voyez quand','vous finissez.'],report:['Votre mois.','Plus clair.'],records:['Vos journées.','En perspective.'],life:['Le travail,','à sa juste place.']},
 es:{focus:['Concéntrate.','Luego, descansa.'],leave:['Poco permiso.','Más descanso.'],records:['Tus días.','En perspectiva.'],life:['El trabajo,','en su justa medida.']},
 it:{report:['Il tuo mese,','più chiaro.'],leave:['Poche ferie.','Pause più lunghe.'],records:['I tuoi giorni.','In prospettiva.'],life:['Il lavoro,','nel quadro della vita.']},
 pt:{report:['Seu mês,','mais claro.'],leave:['Pouca folga.','Pausa maior.'],records:['Seus dias.','Em perspectiva.'],life:['O trabalho,','no quadro da vida.']},
 ja:{records:['毎日の記録が、','ひと目でわかる。'],life:['仕事を、','人生の中で見る。']},
 ko:{widget:['앱을 열지 않아도,','한눈에.'],records:['하루하루가,','한눈에.'],watch:['손목을 들면,','남은 시간이 보여요.'],life:['일을,','삶 속에서 바라봐요.']},
 ru:{countdown:['Всё ближе','к концу смены.'],focus:['Работа.','Потом отдых.'],leave:['Мало отпуска.','Много отдыха.'],records:['Ваши дни.','Как на ладони.'],life:['Работа —','часть большой жизни.']},
 tr:{countdown:['Her saniye,','mesai sonuna.'],records:['Günlerin.','Bir bakışta.'],life:['İşini,','hayatın içinde gör.']},
 id:{countdown:['Tiap detik,','makin dekat pulang.'],report:['Bulanmu,','lebih jelas.'],records:['Hari-harimu.','Sekilas terlihat.'],life:['Pekerjaan,','dalam gambaran hidup.']},
 vi:{records:['Từng ngày,','thật rõ.'],report:['Tháng của bạn,','rõ ràng hơn.'],leave:['Nghỉ phép ít,','nghỉ ngơi nhiều.'],life:['Công việc,','trong cả cuộc đời.']},
 th:{records:['วันทำงานของคุณ','ในแวบเดียว'],life:['งาน','ในภาพใหญ่ของชีวิต']},
 'hi-IN':{records:['आपके दिन।','एक नज़र में।'],life:['काम,','ज़िंदगी की बड़ी तस्वीर में।']},
 'mr-IN':{records:['तुमचे दिवस.','एका नजरेत.'],life:['काम,','आयुष्याच्या मोठ्या चित्रात.']},
 ar:{records:['أيامك.','في لمحة.'],life:['العمل،','ضمن صورة حياتك.']},
};

const split=lines=>lines.length>2?[lines.slice(0,-1).join(' '),lines.at(-1)]:lines;

/** [dark, accent] for a scene, and where it came from. */
export function searchLine(locale,scene){
 const own=WRITTEN[locale]?.[scene];
 if(own)return{lines:own,source:'written for 3.2.2'};
 if(scene in TOUR)return{lines:split(COPY[locale].tour[TOUR[scene]].lines),source:'3.2.1 V4 tour'};
 if(scene==='watch')return{lines:split(COPY[locale].pages[4].lines),source:'3.2.1 Watch page'};
 throw Error(`No ${scene} headline for ${locale}`);
}

// en-GB reuses en and es-MX reuses es, as in 3.2.1.
export const LOCALES=Object.keys(COPY);
export const ASC_REUSE={en:['en-US','en-GB'],es:['es-ES','es-MX']};
